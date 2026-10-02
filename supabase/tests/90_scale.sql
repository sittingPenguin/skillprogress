-- Load test: 400 pupils, ~31,000 clips (a full school year at 2 clips per pupil per week).
\pset tuples_only on
reset role;
insert into students (id, school_id, display_name, year_group)
select gen_random_uuid(), 'aaaaaaaa-0000-0000-0000-000000000000', 'Pupil ' || g, 'Year ' || (7 + g % 5) from generate_series(1, 400) g;
insert into group_members (group_id, student_id, school_id)
select '30000000-0000-0000-0000-000000000002', id, school_id from students where display_name like 'Pupil %' and year_group = 'Year 9';
insert into clips (school_id, student_id, skill_id, upload_id, recorded_on, upload_status, created_by)
select s.school_id, s.id, '50000000-0000-0000-0000-000000000001', gen_random_uuid(), date '2025-09-01' + (w * 7), 'ready', '00000000-0000-0000-0000-0000000000a3'
from students s cross join generate_series(0, 38) w cross join generate_series(1, 2) k where s.display_name like 'Pupil %';
insert into assessments (school_id, clip_id, rubric_version_id, scores, status, author_id)
select c.school_id, c.id, '60000000-0000-0000-0000-000000000002', '{"balance":3}', 'published', '00000000-0000-0000-0000-0000000000a3'
from clips c join students s on s.id = c.student_id where s.display_name like 'Pupil %';
insert into school_members (id, school_id, user_id, role, display_name) values ('10000000-0000-0000-0000-0000000000d1','aaaaaaaa-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000000c1','guardian','Load parent') on conflict do nothing;
insert into guardian_links (school_id, student_id, guardian_member_id)
select school_id, id, (select id from school_members where user_id = '00000000-0000-0000-0000-0000000000c1' and role='guardian') from students where display_name = 'Pupil 10';
analyze;
select 'clips in table: ' || count(*) from clips;
