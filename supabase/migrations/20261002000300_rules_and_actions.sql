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
