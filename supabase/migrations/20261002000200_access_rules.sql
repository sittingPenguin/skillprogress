-- SkillProgress access rules (row-level security)
-- Helpers live in the private "app" schema, which the public API does not expose.
-- Every helper checks that the caller's membership is ACTIVE, so revoking a member
-- or a guardian link removes access on the very next request.

create schema if not exists app;
revoke all on schema app from public;
grant usage on schema app to authenticated, service_role;

create or replace function app.try_uuid(t text) returns uuid language plpgsql immutable as $$
begin return t::uuid; exception when others then return null; end $$;

-- The caller's active membership id for a school and set of roles (null if none).
create or replace function app.member_id(p_school uuid, p_roles public.member_role[])
returns uuid language sql stable security definer set search_path = '' as $$
  select m.id from public.school_members m
  where m.school_id = p_school and m.user_id = auth.uid()
    and m.status = 'active' and m.role = any (p_roles)
  limit 1
$$;

create or replace function app.is_member(p_school uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select app.member_id(p_school, array['admin','coach','guardian','student']::public.member_role[]) is not null
$$;
create or replace function app.is_admin(p_school uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select app.member_id(p_school, array['admin']::public.member_role[]) is not null
$$;
create or replace function app.is_staff(p_school uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select app.member_id(p_school, array['admin','coach']::public.member_role[]) is not null
$$;

-- Staff visibility: admins see every pupil in their school; coaches see pupils in
-- the CLASS groups they are assigned to. Coach-made groups never widen access.
create or replace function app.staff_sees_student(p_student uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.students s
    where s.id = p_student and (
      app.is_admin(s.school_id)
      or (s.archived_at is null and exists (
        select 1 from public.group_members gm
        join public.groups g on g.id = gm.group_id and g.kind = 'class'
        join public.group_coaches gc on gc.group_id = g.id
        where gm.student_id = s.id
          and gc.coach_member_id = app.member_id(s.school_id, array['coach']::public.member_role[])
      ))
    )
  )
$$;

-- Family visibility: an active guardian link, or the pupil's own login when the school allows it.
create or replace function app.family_sees_student(p_student uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.students s
    where s.id = p_student and s.archived_at is null and (
      exists (
        select 1 from public.guardian_links gl
        join public.school_members m on m.id = gl.guardian_member_id
        where gl.student_id = s.id and gl.status = 'active'
          and m.user_id = auth.uid() and m.status = 'active' and m.role = 'guardian'
      )
      or exists (
        select 1 from public.school_members m
        join public.schools sc on sc.id = s.school_id
        where m.id = s.account_member_id and m.user_id = auth.uid()
          and m.status = 'active' and m.role = 'student' and sc.student_access_enabled
      )
    )
  )
$$;

-- A clip is visible to the family only once it is uploaded, not flagged, not deleted
-- and its assessment has been published.
create or replace function app.family_sees_clip(p_clip uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.clips c
    join public.assessments a on a.clip_id = c.id and a.status = 'published'
    where c.id = p_clip and c.deleted_at is null and not c.restricted
      and c.upload_status = 'ready' and app.family_sees_student(c.student_id)
  )
$$;

create or replace function app.staff_sees_clip(p_clip uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.clips c where c.id = p_clip
    and (c.deleted_at is null or app.is_admin(c.school_id)) and app.staff_sees_student(c.student_id))
$$;


-- Set-based versions for policies. Postgres evaluates "x in (select f())" ONCE per query,
-- instead of once per row, which keeps feeds fast at tens of thousands of clips.
create or replace function app.my_school_ids(p_roles public.member_role[]) returns setof uuid
language sql stable security definer set search_path = '' as $$
  select m.school_id from public.school_members m
  where m.user_id = auth.uid() and m.status = 'active' and m.role = any (p_roles)
$$;
create or replace function app.admin_school_ids() returns setof uuid language sql stable security definer set search_path = '' as $$
  select app.my_school_ids(array['admin']::public.member_role[]) $$;
create or replace function app.staff_school_ids() returns setof uuid language sql stable security definer set search_path = '' as $$
  select app.my_school_ids(array['admin','coach']::public.member_role[]) $$;
create or replace function app.member_school_ids() returns setof uuid language sql stable security definer set search_path = '' as $$
  select app.my_school_ids(array['admin','coach','guardian','student']::public.member_role[]) $$;

create or replace function app.staff_student_ids() returns setof uuid language sql stable security definer set search_path = '' as $$
  select s.id from public.students s where s.school_id in (select app.admin_school_ids())
  union
  select gm.student_id
  from public.school_members m
  join public.group_coaches gc on gc.coach_member_id = m.id
  join public.groups g on g.id = gc.group_id and g.kind = 'class'
  join public.group_members gm on gm.group_id = g.id
  join public.students s on s.id = gm.student_id and s.archived_at is null
  where m.user_id = auth.uid() and m.status = 'active' and m.role = 'coach'
$$;

create or replace function app.family_student_ids() returns setof uuid language sql stable security definer set search_path = '' as $$
  select gl.student_id
  from public.school_members m
  join public.guardian_links gl on gl.guardian_member_id = m.id and gl.status = 'active'
  join public.students s on s.id = gl.student_id and s.archived_at is null
  where m.user_id = auth.uid() and m.status = 'active' and m.role = 'guardian'
  union
  select s.id
  from public.school_members m
  join public.students s on s.account_member_id = m.id and s.archived_at is null
  join public.schools sc on sc.id = s.school_id and sc.student_access_enabled
  where m.user_id = auth.uid() and m.status = 'active' and m.role = 'student'
$$;

create or replace function app.staff_clip_ids() returns setof uuid language sql stable security definer set search_path = '' as $$
  select c.id from public.clips c
  where c.student_id in (select app.staff_student_ids())
    and (c.deleted_at is null or c.school_id in (select app.admin_school_ids()))
$$;

create or replace function app.family_clip_ids() returns setof uuid language sql stable security definer set search_path = '' as $$
  select c.id from public.clips c
  join public.assessments a on a.clip_id = c.id and a.status = 'published'
  where c.student_id in (select app.family_student_ids())
    and c.deleted_at is null and not c.restricted and c.upload_status = 'ready'
$$;

-- Switch RLS on everywhere ----------------------------------------------------------------
do $$ declare t text; begin
  foreach t in array array['schools','school_members','students','guardian_links','guardian_invitations',
    'groups','group_members','group_coaches','sports','skills','rubric_versions','clips','assessments',
    'clip_moments','coach_notes','goals','data_requests','audit_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;
revoke insert, update, delete on public.audit_log from authenticated;

-- Schools
create policy schools_read on public.schools for select to authenticated using ((id in (select app.member_school_ids())));
create policy schools_admin_update on public.schools for update to authenticated using ((id in (select app.admin_school_ids()))) with check ((id in (select app.admin_school_ids())));

-- Members: you see your own memberships; admins manage their school's.
create policy members_read on public.school_members for select to authenticated
  using (user_id = auth.uid() or (school_id in (select app.admin_school_ids())));
create policy members_admin_insert on public.school_members for insert to authenticated with check ((school_id in (select app.admin_school_ids())));
create policy members_admin_update on public.school_members for update to authenticated
  using ((school_id in (select app.admin_school_ids()))) with check ((school_id in (select app.admin_school_ids())));
create policy members_admin_delete on public.school_members for delete to authenticated using ((school_id in (select app.admin_school_ids())));

-- Students
create policy students_read on public.students for select to authenticated
  using ((id in (select app.staff_student_ids())) or (id in (select app.family_student_ids())));
create policy students_admin_write on public.students for insert to authenticated with check ((school_id in (select app.admin_school_ids())));
create policy students_admin_update on public.students for update to authenticated
  using ((school_id in (select app.admin_school_ids()))) with check ((school_id in (select app.admin_school_ids())));
create policy students_admin_delete on public.students for delete to authenticated using ((school_id in (select app.admin_school_ids())));

-- Guardian links and invitations: admins only (guardians can see their own links).
create policy glinks_read on public.guardian_links for select to authenticated using (
  (school_id in (select app.admin_school_ids())) or exists (select 1 from public.school_members m
    where m.id = guardian_member_id and m.user_id = auth.uid()));
create policy glinks_admin_insert on public.guardian_links for insert to authenticated with check ((school_id in (select app.admin_school_ids())));
create policy glinks_admin_update on public.guardian_links for update to authenticated
  using ((school_id in (select app.admin_school_ids()))) with check ((school_id in (select app.admin_school_ids())));
create policy ginv_admin on public.guardian_invitations for all to authenticated
  using ((school_id in (select app.admin_school_ids()))) with check ((school_id in (select app.admin_school_ids())));

-- Groups: class groups are admin-managed; coaches can make their own organising groups.
create policy groups_read on public.groups for select to authenticated using (
  (school_id in (select app.admin_school_ids()))
  or (kind = 'class' and exists (select 1 from public.group_coaches gc where gc.group_id = groups.id
        and gc.coach_member_id = app.member_id(school_id, array['coach']::public.member_role[])))
  or (kind = 'coach' and created_by = auth.uid() and (school_id in (select app.staff_school_ids()))));
create policy groups_insert on public.groups for insert to authenticated with check (
  created_by = auth.uid() and ((school_id in (select app.admin_school_ids())) or (kind = 'coach' and (school_id in (select app.staff_school_ids())))));
create policy groups_update on public.groups for update to authenticated
  using ((school_id in (select app.admin_school_ids())) or (kind = 'coach' and created_by = auth.uid() and (school_id in (select app.staff_school_ids()))))
  with check ((school_id in (select app.admin_school_ids())) or (kind = 'coach' and created_by = auth.uid() and (school_id in (select app.staff_school_ids()))));
create policy groups_delete on public.groups for delete to authenticated
  using ((school_id in (select app.admin_school_ids())) or (kind = 'coach' and created_by = auth.uid() and (school_id in (select app.staff_school_ids()))));

create policy gmembers_read on public.group_members for select to authenticated
  using ((student_id in (select app.staff_student_ids())) and exists (select 1 from public.groups g where g.id = group_id));
create policy gmembers_write on public.group_members for insert to authenticated with check (exists (
  select 1 from public.groups g where g.id = group_id and (
    (g.school_id in (select app.admin_school_ids()))
    or (g.kind = 'coach' and g.created_by = auth.uid() and (student_id in (select app.staff_student_ids()))))));
create policy gmembers_delete on public.group_members for delete to authenticated using (exists (
  select 1 from public.groups g where g.id = group_id and (
    (g.school_id in (select app.admin_school_ids())) or (g.kind = 'coach' and g.created_by = auth.uid() and (g.school_id in (select app.staff_school_ids()))))));

create policy gcoaches_read on public.group_coaches for select to authenticated using ((school_id in (select app.staff_school_ids())));
create policy gcoaches_admin on public.group_coaches for insert to authenticated with check ((school_id in (select app.admin_school_ids())));
create policy gcoaches_admin_del on public.group_coaches for delete to authenticated using ((school_id in (select app.admin_school_ids())));

-- Sports, skills, rubrics: readable by anyone in the school; written by admins.
create policy sports_read on public.sports for select to authenticated using ((school_id in (select app.member_school_ids())));
create policy sports_admin on public.sports for insert to authenticated with check ((school_id in (select app.admin_school_ids())));
create policy sports_admin_u on public.sports for update to authenticated using ((school_id in (select app.admin_school_ids()))) with check ((school_id in (select app.admin_school_ids())));
create policy skills_read on public.skills for select to authenticated using ((school_id in (select app.member_school_ids())));
create policy skills_admin on public.skills for insert to authenticated with check ((school_id in (select app.admin_school_ids())));
create policy skills_admin_u on public.skills for update to authenticated using ((school_id in (select app.admin_school_ids()))) with check ((school_id in (select app.admin_school_ids())));
create policy rubrics_read on public.rubric_versions for select to authenticated
  using ((school_id in (select app.member_school_ids())) and (published_at is not null or (school_id in (select app.admin_school_ids()))));
create policy rubrics_admin on public.rubric_versions for insert to authenticated with check ((school_id in (select app.admin_school_ids())));
create policy rubrics_admin_u on public.rubric_versions for update to authenticated using ((school_id in (select app.admin_school_ids()))) with check ((school_id in (select app.admin_school_ids())));
create policy rubrics_admin_d on public.rubric_versions for delete to authenticated using ((school_id in (select app.admin_school_ids())));

-- Clips
create policy clips_read on public.clips for select to authenticated
  using (((student_id in (select app.staff_student_ids())) and (deleted_at is null or (school_id in (select app.admin_school_ids()))))
         or (id in (select app.family_clip_ids())));
create policy clips_insert on public.clips for insert to authenticated
  with check (created_by = auth.uid() and (school_id in (select app.staff_school_ids())) and (student_id in (select app.staff_student_ids())));
create policy clips_update on public.clips for update to authenticated
  using ((student_id in (select app.staff_student_ids())) and deleted_at is null)
  with check ((student_id in (select app.staff_student_ids())));

-- Assessments: staff edit; families read published only.
create policy assess_read on public.assessments for select to authenticated using (
  (clip_id in (select app.staff_clip_ids())) or (status = 'published' and (clip_id in (select app.family_clip_ids()))));
create policy assess_insert on public.assessments for insert to authenticated
  with check (author_id = auth.uid() and (clip_id in (select app.staff_clip_ids())));
create policy assess_update on public.assessments for update to authenticated
  using ((clip_id in (select app.staff_clip_ids()))) with check ((clip_id in (select app.staff_clip_ids())));

-- Timestamped moments follow the assessment's visibility.
create policy moments_read on public.clip_moments for select to authenticated
  using ((clip_id in (select app.staff_clip_ids())) or (clip_id in (select app.family_clip_ids())));
create policy moments_write on public.clip_moments for insert to authenticated
  with check (author_id = auth.uid() and (clip_id in (select app.staff_clip_ids())));
create policy moments_update on public.clip_moments for update to authenticated
  using ((clip_id in (select app.staff_clip_ids()))) with check ((clip_id in (select app.staff_clip_ids())));
create policy moments_delete on public.clip_moments for delete to authenticated using ((clip_id in (select app.staff_clip_ids())));

-- Private coach notes: staff only, never families or pupils.
create policy notes_staff on public.coach_notes for all to authenticated
  using ((clip_id in (select app.staff_clip_ids()))) with check ((clip_id in (select app.staff_clip_ids())) and author_id = auth.uid());

-- Goals
create policy goals_read on public.goals for select to authenticated
  using ((student_id in (select app.staff_student_ids())) or (published and (student_id in (select app.family_student_ids()))));
create policy goals_insert on public.goals for insert to authenticated
  with check (created_by = auth.uid() and (student_id in (select app.staff_student_ids())));
create policy goals_update on public.goals for update to authenticated
  using ((student_id in (select app.staff_student_ids()))) with check ((student_id in (select app.staff_student_ids())));

-- Data requests and audit log: admins only.
create policy dreq_admin on public.data_requests for all to authenticated
  using ((school_id in (select app.admin_school_ids()))) with check ((school_id in (select app.admin_school_ids())) and requested_by = auth.uid());
create policy audit_admin_read on public.audit_log for select to authenticated using ((school_id in (select app.admin_school_ids())));
