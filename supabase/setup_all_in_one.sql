-- SkillProgress database setup (stage 1). Paste the whole file into Supabase > SQL Editor and press Run.
-- Contains no demo data and no pupil information.

-- ===== 20261002000100_core_schema.sql =====
-- SkillProgress core schema
-- Every school-owned row carries school_id. Child tables use composite foreign keys
-- (id, school_id) so a row can never point at a parent in another school.

create extension if not exists pgcrypto;

create type public.member_role as enum ('admin', 'coach', 'guardian', 'student');
create type public.access_status as enum ('active', 'revoked');
create type public.content_status as enum ('draft', 'published');
create type public.goal_status as enum ('in_progress', 'achieved', 'replaced');
create type public.clip_upload_status as enum ('uploading', 'ready', 'failed');
create type public.group_kind as enum ('class', 'coach');
create type public.request_kind as enum ('export', 'deletion');
create type public.request_status as enum ('received', 'in_progress', 'completed', 'rejected');

-- Schools -------------------------------------------------------------------
create table public.schools (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(name) between 2 and 120),
  clip_retention_days integer not null default 400 check (clip_retention_days between 30 and 3650),
  student_access_enabled boolean not null default false,
  created_at timestamptz not null default now()
);

-- People and roles ------------------------------------------------------------
-- One login can hold several memberships (e.g. a teacher who is also a parent).
create table public.school_members (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.member_role not null,
  display_name text not null check (length(display_name) between 1 and 80),
  status public.access_status not null default 'active',
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (school_id, user_id, role),
  unique (id, school_id)
);
create index on public.school_members (user_id) where status = 'active';

-- Pupils: deliberately minimal personal data. No date of birth, no address, no photo.
create table public.students (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  display_name text not null check (length(display_name) between 1 and 60),
  year_group text check (length(year_group) <= 20),
  account_member_id uuid,           -- optional pupil login, school-controlled
  created_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (id, school_id),
  foreign key (account_member_id, school_id) references public.school_members(id, school_id) on delete set null (account_member_id)
);
create index on public.students (school_id);

-- Guardian access is only ever created by the school (directly or via a single-use invite).
create table public.guardian_links (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  student_id uuid not null,
  guardian_member_id uuid not null,
  status public.access_status not null default 'active',
  approved_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (student_id, guardian_member_id),
  foreign key (student_id, school_id) references public.students(id, school_id) on delete cascade,
  foreign key (guardian_member_id, school_id) references public.school_members(id, school_id) on delete cascade
);
create index on public.guardian_links (guardian_member_id) where status = 'active';

create table public.guardian_invitations (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  student_id uuid not null,
  guardian_display_name text not null,
  token_hash text not null unique,          -- sha256 of the token; the token itself is never stored
  expires_at timestamptz not null default now() + interval '7 days',
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  accepted_by uuid references auth.users(id),
  accepted_at timestamptz,
  cancelled_at timestamptz,
  foreign key (student_id, school_id) references public.students(id, school_id) on delete cascade
);

-- Groups ----------------------------------------------------------------------
-- 'class' groups are managed by admins and decide which pupils a coach can see.
-- 'coach' groups are a coach's own way of organising pupils they can already see.
create table public.groups (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  name text not null check (length(name) between 1 and 40),
  kind public.group_kind not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (id, school_id)
);
create table public.group_members (
  group_id uuid not null,
  student_id uuid not null,
  school_id uuid not null,
  primary key (group_id, student_id),
  foreign key (group_id, school_id) references public.groups(id, school_id) on delete cascade,
  foreign key (student_id, school_id) references public.students(id, school_id) on delete cascade
);
create index on public.group_members (student_id);
create table public.group_coaches (
  group_id uuid not null,
  coach_member_id uuid not null,
  school_id uuid not null,
  primary key (group_id, coach_member_id),
  foreign key (group_id, school_id) references public.groups(id, school_id) on delete cascade,
  foreign key (coach_member_id, school_id) references public.school_members(id, school_id) on delete cascade
);
create index on public.group_coaches (coach_member_id);

-- Sports, skills and versioned rubrics ---------------------------------------------
create table public.sports (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id) on delete cascade,
  name text not null,
  unique (school_id, name),
  unique (id, school_id)
);
create table public.skills (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  sport_id uuid not null,
  name text not null,
  recording_tip text,          -- e.g. "Film from the side, hip height, 4 m away"
  unique (sport_id, name),
  unique (id, school_id),
  foreign key (sport_id, school_id) references public.sports(id, school_id) on delete cascade
);
-- A rubric version is frozen once published, so old assessments keep their meaning.
create table public.rubric_versions (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  skill_id uuid not null,
  version integer not null check (version > 0),
  levels jsonb not null,       -- ["Emerging","Developing","Secure","Excelling"]
  criteria jsonb not null,     -- [{"key":"balance","name":"Balance","descriptors":[...one per level]}]
  published_at timestamptz,
  created_at timestamptz not null default now(),
  unique (skill_id, version),
  unique (id, school_id),
  foreign key (skill_id, school_id) references public.skills(id, school_id) on delete cascade,
  check (jsonb_typeof(levels) = 'array' and jsonb_array_length(levels) between 2 and 6),
  check (jsonb_typeof(criteria) = 'array' and jsonb_array_length(criteria) between 1 and 10)
);

-- Clips -----------------------------------------------------------------------------
create table public.clips (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  student_id uuid not null,
  skill_id uuid not null,
  upload_id uuid not null,             -- generated on the device; retries reuse it, so no duplicates
  recorded_on date not null,           -- when it was filmed (separate from upload time)
  uploaded_at timestamptz not null default now(),
  upload_status public.clip_upload_status not null default 'uploading',
  storage_path text,                   -- {school_id}/{student_id}/{clip_id}.mp4 in the private bucket
  duration_ms integer check (duration_ms between 0 and 600000),
  drill text check (length(drill) <= 120),
  restricted boolean not null default false,   -- other children visible: blocks publication
  restricted_reason text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_by uuid not null references auth.users(id),
  deleted_at timestamptz,
  unique (school_id, upload_id),
  unique (id, school_id),
  foreign key (student_id, school_id) references public.students(id, school_id) on delete cascade,
  foreign key (skill_id, school_id) references public.skills(id, school_id)
);
create index on public.clips (student_id, skill_id, recorded_on);

-- Family-facing assessment. Private notes live in their own staff-only table.
create table public.assessments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  clip_id uuid not null unique,
  rubric_version_id uuid not null,
  scores jsonb not null default '{}'::jsonb,   -- {"balance":3,"position":2}
  feedback text check (length(feedback) <= 2000),
  strengths text check (length(strengths) <= 500),
  to_improve text check (length(to_improve) <= 500),
  next_goal text check (length(next_goal) <= 300),
  status public.content_status not null default 'draft',
  published_at timestamptz,
  published_by uuid references auth.users(id),
  author_id uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  unique (id, school_id),
  foreign key (clip_id, school_id) references public.clips(id, school_id) on delete cascade,
  foreign key (rubric_version_id, school_id) references public.rubric_versions(id, school_id)
);

create table public.clip_moments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  clip_id uuid not null,
  at_ms integer not null check (at_ms >= 0),
  body text not null check (length(body) between 1 and 300),
  author_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (clip_id, school_id) references public.clips(id, school_id) on delete cascade
);
create index on public.clip_moments (clip_id);

create table public.coach_notes (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  clip_id uuid not null,
  body text not null check (length(body) <= 2000),
  author_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (clip_id, school_id) references public.clips(id, school_id) on delete cascade
);

create table public.goals (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  student_id uuid not null,
  skill_id uuid,
  text text not null check (length(text) between 1 and 300),
  status public.goal_status not null default 'in_progress',
  notes text check (length(notes) <= 1000),
  clip_id uuid,
  published boolean not null default false,
  set_on date not null default current_date,
  closed_on date,
  created_by uuid not null references auth.users(id),
  foreign key (student_id, school_id) references public.students(id, school_id) on delete cascade,
  foreign key (skill_id, school_id) references public.skills(id, school_id),
  foreign key (clip_id, school_id) references public.clips(id, school_id) on delete set null (clip_id)
);
create index on public.goals (student_id);

-- Admin: data requests and audit ------------------------------------------------------
create table public.data_requests (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null,
  student_id uuid not null,
  kind public.request_kind not null,
  status public.request_status not null default 'received',
  notes text,
  requested_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  foreign key (student_id, school_id) references public.students(id, school_id) on delete cascade
);

-- Append-only. Readable by that school's admins only. Never holds feedback text or notes.
create table public.audit_log (
  id bigint generated always as identity primary key,
  school_id uuid not null references public.schools(id) on delete cascade,
  actor_id uuid,
  action text not null,
  entity text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  at timestamptz not null default now()
);
create index on public.audit_log (school_id, at desc);

-- ===== 20261002000200_access_rules.sql =====
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

-- ===== 20261002000300_rules_and_actions.sql =====
-- Integrity rules, audit trail and school actions (invites, idempotent clip creation, export, retention)

-- Audit helper --------------------------------------------------------------------------
create or replace function app.audit(p_school uuid, p_action text, p_entity text, p_id uuid, p_details jsonb default '{}')
returns void language sql security definer set search_path = '' as $$
  insert into public.audit_log (school_id, actor_id, action, entity, entity_id, details)
  values (p_school, auth.uid(), p_action, p_entity, p_id, coalesce(p_details, '{}'::jsonb))
$$;

-- Columns that must never change after creation ----------------------------------------
create or replace function app.lock_identity_columns() returns trigger language plpgsql as $$
declare o jsonb := to_jsonb(old); n jsonb := to_jsonb(new); col text;
begin
  foreach col in array array['school_id','student_id','user_id','clip_id'] loop
    if o ? col and (n->col) is distinct from (o->col) then
      raise exception '% cannot be changed', col using errcode = '42501';
    end if;
  end loop;
  return new;
end $$;
do $$ declare t text; begin
  foreach t in array array['school_members','students','guardian_links','groups','clips','assessments','coach_notes','goals','rubric_versions','data_requests'] loop
    execute format('create trigger lock_ids before update on public.%I for each row execute function app.lock_identity_columns()', t);
  end loop;
end $$;

-- Rubric versions are frozen once published --------------------------------------------------
create or replace function app.rubric_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    if old.published_at is not null then raise exception 'Published rubric versions cannot be deleted'; end if;
    return old;
  end if;
  if old.published_at is not null and (new.levels, new.criteria, new.version, new.skill_id, new.published_at)
       is distinct from (old.levels, old.criteria, old.version, old.skill_id, old.published_at) then
    raise exception 'Published rubric versions cannot be changed. Create a new version instead.';
  end if;
  if new.published_at is not null and old.published_at is null then
    perform app.audit(new.school_id, 'rubric.published', 'rubric_version', new.id, jsonb_build_object('version', new.version));
  end if;
  return new;
end $$;
create trigger rubric_guard before update or delete on public.rubric_versions for each row execute function app.rubric_guard();

-- Assessments: validate scores and guard publication ------------------------------------------
create or replace function app.assessment_guard() returns trigger language plpgsql security definer set search_path = '' as $$
declare c record; r record; k text; v jsonb; n_levels int;
begin
  select * into c from public.clips where id = new.clip_id;
  select * into r from public.rubric_versions where id = new.rubric_version_id;
  if r.published_at is null then raise exception 'Use a published rubric version'; end if;
  if r.skill_id <> c.skill_id then raise exception 'Rubric does not belong to this clip''s skill'; end if;
  if tg_op = 'UPDATE' and new.rubric_version_id <> old.rubric_version_id and old.status = 'published' then
    raise exception 'A published assessment keeps its original rubric version';
  end if;
  n_levels := jsonb_array_length(r.levels);
  for k, v in select * from jsonb_each(new.scores) loop
    if not exists (select 1 from jsonb_array_elements(r.criteria) e where e->>'key' = k) then
      raise exception 'Unknown rubric criterion: %', k;
    end if;
    if jsonb_typeof(v) <> 'number' or (v::text)::int not between 1 and n_levels then
      raise exception 'Level for % must be between 1 and %', k, n_levels;
    end if;
  end loop;
  new.updated_at := now();
  if new.status = 'published' then
    if c.restricted then raise exception 'This clip is flagged (other pupils visible). Review it before publishing.' using errcode = '42501'; end if;
    if c.deleted_at is not null or c.upload_status <> 'ready' then raise exception 'Only uploaded clips can be published'; end if;
    if tg_op = 'INSERT' or old.status <> 'published' then
      new.published_at := now(); new.published_by := auth.uid();
      perform app.audit(new.school_id, 'assessment.published', 'assessment', new.id, jsonb_build_object('clip_id', new.clip_id));
    end if;
  elsif tg_op = 'UPDATE' and old.status = 'published' then
    perform app.audit(new.school_id, 'assessment.unpublished', 'assessment', new.id, jsonb_build_object('clip_id', new.clip_id));
  end if;
  return new;
end $$;
create trigger assessment_guard before insert or update on public.assessments for each row execute function app.assessment_guard();

-- Clips: flag/review trail and soft deletion ------------------------------------------------------
create or replace function app.clip_guard() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.restricted is distinct from old.restricted then
    if new.restricted then
      perform app.audit(new.school_id, 'clip.flagged', 'clip', new.id, jsonb_build_object('reason', new.restricted_reason));
    else
      new.reviewed_by := auth.uid(); new.reviewed_at := now();
      perform app.audit(new.school_id, 'clip.flag_cleared', 'clip', new.id, '{}');
    end if;
  end if;
  if new.deleted_at is not null and old.deleted_at is null then
    perform app.audit(new.school_id, 'clip.deleted', 'clip', new.id, '{}');
  end if;
  return new;
end $$;
create trigger clip_guard before update on public.clips for each row execute function app.clip_guard();

-- Generic audit for permission changes -------------------------------------------------------------
create or replace function app.audit_row() returns trigger language plpgsql security definer set search_path = '' as $$
declare r jsonb := to_jsonb(coalesce(new, old)); o jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
        act text; d jsonb := '{}'; eid uuid;
begin
  if tg_table_name = 'school_members' then
    eid := (r->>'id')::uuid; d := jsonb_build_object('role', r->>'role');
    if tg_op = 'INSERT' then act := 'member.added';
    elsif tg_op = 'DELETE' then act := 'member.removed';
    elsif r->>'status' <> o->>'status' then act := 'member.' || (r->>'status');
    elsif r->>'role' <> o->>'role' then act := 'member.role_changed'; end if;
  elsif tg_table_name = 'guardian_links' then
    eid := (r->>'id')::uuid; d := jsonb_build_object('student_id', r->>'student_id');
    if tg_op = 'INSERT' then act := 'guardian.linked';
    elsif r->>'status' <> o->>'status' then act := 'guardian.' || (r->>'status'); end if;
  elsif tg_table_name = 'group_coaches' then
    eid := (r->>'coach_member_id')::uuid; d := jsonb_build_object('group_id', r->>'group_id');
    act := case when tg_op = 'INSERT' then 'coach.assigned' else 'coach.unassigned' end;
  elsif tg_table_name = 'data_requests' then
    eid := (r->>'id')::uuid; d := jsonb_build_object('student_id', r->>'student_id');
    if tg_op = 'INSERT' then act := 'data_request.' || (r->>'kind');
    elsif r->>'status' <> o->>'status' then act := 'data_request.' || (r->>'status'); end if;
  end if;
  if act is not null then perform app.audit((r->>'school_id')::uuid, act, tg_table_name, eid, d); end if;
  return coalesce(new, old);
end $$;
-- schools has no school_id column; give it a dedicated wrapper
create or replace function app.audit_school() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform app.audit(new.id, 'school.settings_changed', 'school', new.id,
    jsonb_build_object('retention_days', new.clip_retention_days, 'student_access', new.student_access_enabled));
  return new;
end $$;
create trigger audit_members after insert or update or delete on public.school_members for each row execute function app.audit_row();
create trigger audit_glinks after insert or update on public.guardian_links for each row execute function app.audit_row();
create trigger audit_gcoaches after insert or delete on public.group_coaches for each row execute function app.audit_row();
create trigger audit_dreq after insert or update on public.data_requests for each row execute function app.audit_row();
create trigger audit_school after update on public.schools for each row execute function app.audit_school();

-- Stamp revocation times
create or replace function app.stamp_revoked() returns trigger language plpgsql as $$
begin
  if new.status = 'revoked' and old.status <> 'revoked' then new.revoked_at := now(); end if;
  if new.status = 'active' and old.status = 'revoked' then new.revoked_at := null; end if;
  return new;
end $$;
create trigger stamp_revoked before update on public.school_members for each row execute function app.stamp_revoked();
create trigger stamp_revoked before update on public.guardian_links for each row execute function app.stamp_revoked();

-- ============================== Actions (called from the app) ==============================

-- Admin creates a single-use invite for ONE named pupil. Returns the token to send to the parent.
create or replace function public.create_guardian_invitation(p_student uuid, p_guardian_name text)
returns text language plpgsql security definer set search_path = '' as $$
declare s record; tok text;
begin
  select * into s from public.students where id = p_student;
  if s.id is null or not app.is_admin(s.school_id) then raise exception 'Not allowed' using errcode = '42501'; end if;
  tok := encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.guardian_invitations (school_id, student_id, guardian_display_name, token_hash, created_by)
  values (s.school_id, s.id, p_guardian_name, encode(extensions.digest(tok, 'sha256'), 'hex'), auth.uid());
  perform app.audit(s.school_id, 'guardian.invited', 'student', s.id, '{}');
  return tok;
end $$;

-- A signed-in parent redeems the invite. Knowing a pupil's name or email is not enough.
create or replace function public.accept_guardian_invitation(p_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare inv record; mid uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select * into inv from public.guardian_invitations
   where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') for update;
  if inv.id is null or inv.accepted_at is not null or inv.cancelled_at is not null or inv.expires_at < now() then
    raise exception 'This invitation is not valid. Ask the school for a new one.' using errcode = '42501';
  end if;
  insert into public.school_members (school_id, user_id, role, display_name)
  values (inv.school_id, auth.uid(), 'guardian', inv.guardian_display_name)
  on conflict (school_id, user_id, role) do update set status = 'active'
  returning id into mid;
  insert into public.guardian_links (school_id, student_id, guardian_member_id, approved_by)
  values (inv.school_id, inv.student_id, mid, inv.created_by)
  on conflict (student_id, guardian_member_id) do update set status = 'active', approved_by = excluded.approved_by;
  update public.guardian_invitations set accepted_by = auth.uid(), accepted_at = now() where id = inv.id;
  return inv.student_id;
end $$;

-- Create (or, on retry, return) a clip record. The device's upload_id makes retries safe.
create or replace function public.register_clip(p_upload_id uuid, p_student uuid, p_skill uuid, p_recorded_on date, p_drill text default null)
returns public.clips language plpgsql security invoker set search_path = '' as $$
declare s record; c public.clips;
begin
  select * into s from public.students where id = p_student;
  if s.id is null then raise exception 'Pupil not found' using errcode = '42501'; end if;
  if p_recorded_on > current_date + 1 then raise exception 'Recording date is in the future'; end if;
  select * into c from public.clips where school_id = s.school_id and upload_id = p_upload_id;
  if c.id is not null then return c; end if;
  insert into public.clips (school_id, student_id, skill_id, upload_id, recorded_on, drill, created_by)
  values (s.school_id, s.id, p_skill, p_upload_id, p_recorded_on, p_drill, auth.uid())
  on conflict (school_id, upload_id) do nothing
  returning * into c;
  if c.id is null then select * into c from public.clips where school_id = s.school_id and upload_id = p_upload_id; end if;
  update public.clips set storage_path = s.school_id || '/' || s.id || '/' || c.id || '.mp4' where id = c.id returning * into c;
  return c;
end $$;

-- Admin export of everything held about one pupil (fulfils a subject access request).
create or replace function public.export_student_data(p_student uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s record; out jsonb;
begin
  select * into s from public.students where id = p_student;
  if s.id is null or not app.is_admin(s.school_id) then raise exception 'Not allowed' using errcode = '42501'; end if;
  select jsonb_build_object(
    'exported_at', now(),
    'student', to_jsonb(s) - 'account_member_id',
    'groups', (select coalesce(jsonb_agg(g.name), '[]') from public.group_members gm join public.groups g on g.id = gm.group_id where gm.student_id = s.id and g.kind = 'class'),
    'clips', (select coalesce(jsonb_agg(to_jsonb(c) - 'created_by' - 'reviewed_by' order by c.recorded_on), '[]') from public.clips c where c.student_id = s.id),
    'assessments', (select coalesce(jsonb_agg(jsonb_build_object('clip_id', a.clip_id, 'rubric', to_jsonb(r) - 'school_id', 'scores', a.scores,
        'feedback', a.feedback, 'strengths', a.strengths, 'to_improve', a.to_improve, 'next_goal', a.next_goal, 'status', a.status, 'published_at', a.published_at)), '[]')
        from public.assessments a join public.clips c on c.id = a.clip_id join public.rubric_versions r on r.id = a.rubric_version_id where c.student_id = s.id),
    'moments', (select coalesce(jsonb_agg(jsonb_build_object('clip_id', m.clip_id, 'at_ms', m.at_ms, 'body', m.body)), '[]') from public.clip_moments m join public.clips c on c.id = m.clip_id where c.student_id = s.id),
    'coach_notes', (select coalesce(jsonb_agg(jsonb_build_object('clip_id', n.clip_id, 'body', n.body, 'created_at', n.created_at)), '[]') from public.coach_notes n join public.clips c on c.id = n.clip_id where c.student_id = s.id),
    'goals', (select coalesce(jsonb_agg(to_jsonb(g) - 'created_by' - 'school_id'), '[]') from public.goals g where g.student_id = s.id)
  ) into out;
  perform app.audit(s.school_id, 'student.exported', 'student', s.id, '{}');
  return out;
end $$;

-- Retention: soft-delete clips past the school's retention period and return the storage
-- paths so the scheduled cleanup job can delete the video files. Service role only.
create or replace function app.expire_clips() returns table (clip_id uuid, storage_path text)
language plpgsql security definer set search_path = '' as $$
begin
  return query
  update public.clips c set deleted_at = now()
  from public.schools sc
  where sc.id = c.school_id and c.deleted_at is null
    and c.recorded_on < current_date - sc.clip_retention_days
  returning c.id, c.storage_path;
end $$;
revoke all on function app.expire_clips() from public, authenticated;
grant execute on function app.expire_clips() to service_role;

revoke all on function public.create_guardian_invitation(uuid, text), public.accept_guardian_invitation(text),
  public.register_clip(uuid, uuid, uuid, date, text), public.export_student_data(uuid) from public, anon;
grant execute on function public.create_guardian_invitation(uuid, text), public.accept_guardian_invitation(text),
  public.register_clip(uuid, uuid, uuid, date, text), public.export_student_data(uuid) to authenticated;

-- ===== 20261002000400_video_storage.sql =====
-- Private video bucket. Files are stored as {school_id}/{student_id}/{clip_id}.mp4
-- There are no public URLs: the app asks for short-lived signed links, which Supabase
-- only issues when these policies allow the caller to read the file.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('clips', 'clips', false, 209715200, array['video/mp4', 'video/quicktime'])
on conflict (id) do update set public = false;

create or replace function app.clip_from_path(p_name text) returns uuid language sql immutable as $$
  select app.try_uuid(split_part((string_to_array(p_name, '/'))[3], '.', 1))
$$;

create policy clips_upload on storage.objects for insert to authenticated with check (
  bucket_id = 'clips' and exists (
    select 1 from public.clips c
    where c.id = app.clip_from_path(name)
      and c.school_id = app.try_uuid((storage.foldername(name))[1])
      and c.student_id = app.try_uuid((storage.foldername(name))[2])
      and c.deleted_at is null
      and c.student_id in (select app.staff_student_ids())));

-- Resumable uploads need update permission on the same object.
create policy clips_upload_resume on storage.objects for update to authenticated
  using (bucket_id = 'clips' and app.clip_from_path(name) in (select app.staff_clip_ids()))
  with check (bucket_id = 'clips' and app.clip_from_path(name) in (select app.staff_clip_ids()));

create policy clips_view on storage.objects for select to authenticated using (
  bucket_id = 'clips' and (app.clip_from_path(name) in (select app.staff_clip_ids()) or app.clip_from_path(name) in (select app.family_clip_ids())));

create policy clips_admin_delete on storage.objects for delete to authenticated using (
  bucket_id = 'clips' and app.try_uuid((storage.foldername(name))[1]) in (select app.admin_school_ids()));
