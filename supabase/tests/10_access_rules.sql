-- Access tests. Each line signs in as a seeded person and checks what the DATABASE allows,
-- so these hold even if the app has a bug. Any failure stops the run with "FAIL".
\pset tuples_only on
\pset format unaligned

create schema t;
grant usage on schema t to authenticated, anon;
create function t.as(who text) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claims', case when who = 'anon' then '' else
    json_build_object('sub', '00000000-0000-0000-0000-0000000000' || who)::text end, false);
  return '-- signed in as ' || who;
end $$;
create function t.n(q text) returns bigint language plpgsql as $$
declare c bigint; begin execute 'select count(*) from (' || q || ') x' into c; return c; end $$;
create function t.eq(got anyelement, want anyelement, msg text) returns text language plpgsql as $$
begin
  if got is distinct from want then raise exception 'FAIL: % (got %, expected %)', msg, got, want; end if;
  return 'ok   ' || msg;
end $$;
create function t.denied(q text, msg text) returns text language plpgsql as $$
begin
  begin execute q; exception when others then return 'ok   ' || msg || '  [' || left(sqlerrm, 70) || ']'; end;
  raise exception 'FAIL: % (it was allowed)', msg;
end $$;
create function t.affected(q text) returns bigint language plpgsql as $$
declare c bigint; begin execute q; get diagnostics c = row_count; return c; end $$;
grant execute on all functions in schema t to authenticated, anon;

-- ===== Coach A, assigned to Year 8 =====
reset role; select t.as('a2'); set role authenticated;
select t.eq(t.n('select * from students'), 6::bigint, 'Year 8 coach sees the 6 Year 8 pupils only');
select t.eq(t.n($$select * from students where display_name in ('Ben W.','Sam T.')$$), 0::bigint, 'Year 8 coach cannot see a Year 9 pupil or another school''s pupil');
select t.eq(t.n('select * from clips'), 5::bigint, 'Year 8 coach sees clips for their pupils only');
select t.eq(t.n($$select * from clips where school_id = 'bbbbbbbb-0000-0000-0000-000000000000'$$), 0::bigint, 'Coach cannot read another school''s clips by id');
select t.eq(t.n('select * from schools'), 1::bigint, 'Coach sees only their own school');
select t.eq(t.n('select * from coach_notes'), 1::bigint, 'Coach can read private notes on their pupils');
select t.eq(t.n('select * from audit_log'), 0::bigint, 'Coach cannot read the audit log');
select t.eq(t.n($$select * from storage.objects where bucket_id = 'clips'$$), 5::bigint, 'Coach can fetch video files for their pupils only');
select t.denied($$insert into students (school_id, display_name) values ('aaaaaaaa-0000-0000-0000-000000000000','New pupil')$$, 'Coach cannot create pupil records directly');
select t.denied($$select register_clip('99000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000007','50000000-0000-0000-0000-000000000001','2026-10-02')$$, 'Coach cannot record a clip for a pupil outside their classes');
select t.denied($$insert into storage.objects (bucket_id, name) values ('clips','aaaaaaaa-0000-0000-0000-000000000000/20000000-0000-0000-0000-000000000007/70000000-0000-0000-0000-000000000006.mp4')$$, 'Coach cannot upload video into another class''s pupil folder');
select t.denied($$update clips set school_id = 'bbbbbbbb-0000-0000-0000-000000000000' where id = '70000000-0000-0000-0000-000000000003'$$, 'A clip cannot be moved to another school');
select t.denied($$update clips set student_id = '20000000-0000-0000-0000-000000000002' where id = '70000000-0000-0000-0000-000000000003'$$, 'A clip cannot be reassigned to another pupil');
select t.denied($$update assessments set status = 'published' where clip_id = '70000000-0000-0000-0000-000000000004'$$, 'A flagged clip (other pupils visible) cannot be published');
select t.denied($$update assessments set scores = '{"balance":9}' where clip_id = '70000000-0000-0000-0000-000000000005'$$, 'Rubric levels outside the scale are rejected');
select t.denied($$update assessments set scores = '{"speed":2}' where clip_id = '70000000-0000-0000-0000-000000000005'$$, 'Criteria that are not in the rubric are rejected');
select t.eq(t.affected($$update rubric_versions set levels = '["A","B"]' where id = '60000000-0000-0000-0000-000000000002'$$), 0::bigint, 'Coach cannot edit rubrics');

-- Retried uploads do not create duplicates
select t.eq((select id from register_clip('99000000-0000-0000-0000-0000000000aa','20000000-0000-0000-0000-000000000003','50000000-0000-0000-0000-000000000002','2026-10-02','Partner passing')) =
            (select id from register_clip('99000000-0000-0000-0000-0000000000aa','20000000-0000-0000-0000-000000000003','50000000-0000-0000-0000-000000000002','2026-10-02','Partner passing')), true, 'Retrying an upload returns the same clip');
select t.eq(t.n($$select * from clips where upload_id = '99000000-0000-0000-0000-0000000000aa'$$), 1::bigint, 'Retrying an upload leaves exactly one clip record');
select t.denied($$select register_clip('99000000-0000-0000-0000-0000000000ab','20000000-0000-0000-0000-000000000003','50000000-0000-0000-0000-000000000002','2030-01-01')$$, 'Recording dates in the future are rejected');

-- Coach-made groups organise pupils but never widen access
insert into groups (id, school_id, name, kind, created_by) values ('30000000-0000-0000-0000-0000000000f1','aaaaaaaa-0000-0000-0000-000000000000','Tuesday club','coach','00000000-0000-0000-0000-0000000000a2');
select t.eq(t.affected($$insert into group_members (group_id, student_id, school_id) values ('30000000-0000-0000-0000-0000000000f1','20000000-0000-0000-0000-000000000006','aaaaaaaa-0000-0000-0000-000000000000')$$), 1::bigint, 'Coach can add their own pupil to their own group');
select t.denied($$insert into group_members (group_id, student_id, school_id) values ('30000000-0000-0000-0000-0000000000f1','20000000-0000-0000-0000-000000000007','aaaaaaaa-0000-0000-0000-000000000000')$$, 'Coach cannot add a pupil from another class to their group');
select t.denied($$insert into groups (school_id, name, kind, created_by) values ('aaaaaaaa-0000-0000-0000-000000000000','Fake class','class','00000000-0000-0000-0000-0000000000a2')$$, 'Coach cannot create a class group (that would widen access)');

-- ===== Coach A, Year 9 only =====
reset role; select t.as('a3'); set role authenticated;
select t.eq(t.n('select * from students'), 1::bigint, 'Year 9 coach sees only Ben');
select t.eq(t.n($$select * from clips where student_id = '20000000-0000-0000-0000-000000000001'$$), 0::bigint, 'Year 9 coach cannot see Ava''s clips');
select t.eq(t.n('select * from groups'), 1::bigint, 'Coach cannot see another coach''s private groups');

-- ===== Ava's parent =====
reset role; select t.as('a4'); set role authenticated;
select t.eq(t.n('select * from students'), 1::bigint, 'Parent sees only their own child');
select t.eq(t.n('select * from clips'), 3::bigint, 'Parent sees only Ava''s published clips');
select t.eq(t.n($$select * from assessments where status <> 'published'$$), 0::bigint, 'Parent never sees draft assessments');
select t.eq(t.n('select * from coach_notes'), 0::bigint, 'Parent never sees private coach notes');
select t.eq(t.n('select * from clip_moments'), 2::bigint, 'Parent sees timestamped comments on published clips only');
select t.eq(t.n('select * from goals'), 2::bigint, 'Parent sees published goals only');
select t.eq(t.n($$select * from storage.objects where bucket_id = 'clips'$$), 3::bigint, 'Parent can fetch only Ava''s published video files');
select t.eq(t.n('select * from school_members'), 1::bigint, 'Parent sees only their own membership');
select t.eq(t.n('select * from audit_log'), 0::bigint, 'Parent cannot read the audit log');
select t.eq(t.affected($$update assessments set feedback = 'hacked'$$), 0::bigint, 'Parent cannot change feedback');
select t.denied($$insert into guardian_links (school_id, student_id, guardian_member_id) values ('aaaaaaaa-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-0000000000a4')$$, 'Parent cannot link themselves to another child');
select t.denied($$select accept_guardian_invitation('not-a-real-token')$$, 'Guessing an invitation code does not work');
select t.denied($$insert into clips (school_id, student_id, skill_id, upload_id, recorded_on, created_by) values ('aaaaaaaa-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001',gen_random_uuid(),'2026-10-01','00000000-0000-0000-0000-0000000000a4')$$, 'Parent cannot upload clips');

-- ===== Leo's parent: Leo's only clip is a flagged draft =====
reset role; select t.as('a5'); set role authenticated;
select t.eq(t.n('select * from clips'), 0::bigint, 'Flagged draft clips are invisible to the family');
select t.eq(t.n('select * from clip_moments'), 0::bigint, 'Draft comments are invisible to the family');

-- ===== Other school's parent and an anonymous visitor =====
reset role; select t.as('b3'); set role authenticated;
select t.eq(t.n($$select * from clips where school_id = 'aaaaaaaa-0000-0000-0000-000000000000'$$), 0::bigint, 'Parent at another school cannot see this school''s clips');
select t.eq(t.n('select * from students'), 1::bigint, 'Parent at another school sees only their own child');
reset role; select t.as('anon'); set role anon;
select t.denied('select * from clips', 'Signed-out visitors cannot read clips');
select t.denied('select * from students', 'Signed-out visitors cannot read pupils');

-- ===== Pupil login is off until the school switches it on =====
reset role; select t.as('a6'); set role authenticated;
select t.eq(t.n('select * from clips'), 0::bigint, 'Pupil login sees nothing while pupil access is off');
reset role; select t.as('a1'); set role authenticated;
update schools set student_access_enabled = true where id = 'aaaaaaaa-0000-0000-0000-000000000000';
reset role; select t.as('a6'); set role authenticated;
select t.eq(t.n('select * from clips'), 3::bigint, 'Pupil sees their own published clips once the school allows it');
select t.eq(t.n('select * from coach_notes'), 0::bigint, 'Pupil never sees private coach notes');

-- ===== Admin A =====
reset role; select t.as('a1'); set role authenticated;
select t.eq(t.n('select * from students'), 7::bigint, 'Admin sees every pupil in their school only');
select t.denied($$insert into students (school_id, display_name) values ('bbbbbbbb-0000-0000-0000-000000000000','Planted pupil')$$, 'Admin cannot add pupils to another school');
select t.eq(t.n($$select * from audit_log where school_id = 'bbbbbbbb-0000-0000-0000-000000000000'$$), 0::bigint, 'Admin cannot read another school''s audit log');
select t.denied($$update rubric_versions set levels = '["A","B"]' where id = '60000000-0000-0000-0000-000000000002'$$, 'Published rubric versions are frozen, even for admins');
select t.eq((export_student_data('20000000-0000-0000-0000-000000000001')->'clips' ->> 0) is not null, true, 'Admin can export a pupil''s data');
select t.eq(jsonb_array_length(export_student_data('20000000-0000-0000-0000-000000000001')->'assessments'), 3, 'Export includes each assessment with its rubric');
select t.denied($$select export_student_data('20000000-0000-0000-0000-0000000000b1')$$, 'Admin cannot export another school''s pupil');

-- Invitation flow: the school invites a parent for one named pupil
select set_config('test.token', create_guardian_invitation('20000000-0000-0000-0000-000000000003', 'Priya''s parent'), false) is not null as invited \gset
reset role; select t.as('a2'); set role authenticated;
select t.denied($$select create_guardian_invitation('20000000-0000-0000-0000-000000000003','x')$$, 'Coaches cannot invite parents');
reset role; select t.as('c1'); set role authenticated;
select t.eq(t.n('select * from students'), 0::bigint, 'A new parent sees nothing before accepting an invite');
select t.eq(accept_guardian_invitation(current_setting('test.token')), '20000000-0000-0000-0000-000000000003'::uuid, 'A new parent can accept a valid invitation');
select t.eq(t.n('select display_name from students'), 1::bigint, 'After accepting, the parent sees exactly that pupil');
reset role; select t.as('a5'); set role authenticated;
select t.denied($$select accept_guardian_invitation(current_setting('test.token'))$$, 'An invitation cannot be used twice');

-- Review a flagged clip, then publish it
reset role; select t.as('a2'); set role authenticated;
update clips set restricted = false where id = '70000000-0000-0000-0000-000000000004';
update assessments set feedback = 'Great effort, Leo.', status = 'published' where clip_id = '70000000-0000-0000-0000-000000000004';
reset role; select t.as('a5'); set role authenticated;
select t.eq(t.n('select * from clips'), 1::bigint, 'After review and publishing, Leo''s parent sees the clip');

-- Revocation takes effect immediately
reset role; select t.as('a1'); set role authenticated;
update guardian_links set status = 'revoked' where guardian_member_id = '10000000-0000-0000-0000-0000000000a4';
reset role; select t.as('a4'); set role authenticated;
select t.eq(t.n('select * from clips'), 0::bigint, 'A revoked parent loses access at once');
select t.eq(t.n($$select * from storage.objects where bucket_id = 'clips'$$), 0::bigint, 'A revoked parent cannot fetch video files');
reset role; select t.as('a1'); set role authenticated;
update school_members set status = 'revoked' where id = '10000000-0000-0000-0000-0000000000a2';
reset role; select t.as('a2'); set role authenticated;
select t.eq(t.n('select * from students'), 0::bigint, 'A revoked coach loses access at once');

-- Audit trail
reset role; select t.as('a1'); set role authenticated;
select t.eq(t.n($$select * from audit_log where action in ('guardian.revoked','member.revoked','guardian.invited','clip.flag_cleared','student.exported','school.settings_changed')$$) >= 6, true, 'Permission changes, publishing, exports and settings are recorded');
select t.eq(t.n($$select * from audit_log where details::text ilike '%hacked%' or details::text ilike '%PRIVATE%'$$), 0::bigint, 'The audit log never stores feedback or private notes');
select t.denied('delete from audit_log', 'Nobody can delete audit entries');

-- Retention: a scheduled job soft-deletes clips past the school's retention period
reset role;
update schools set clip_retention_days = 100 where id = 'aaaaaaaa-0000-0000-0000-000000000000';
select t.eq((select count(*) from app.expire_clips()), 1::bigint, 'Retention job expires only clips older than the school''s setting');
select t.as('a6'); set role authenticated;
select t.eq(t.n('select * from clips'), 2::bigint, 'Expired clips disappear for families');
reset role;
