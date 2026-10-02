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
