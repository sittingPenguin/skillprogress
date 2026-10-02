-- SYNTHETIC DEMO DATA ONLY. Fictional schools and pupils; no real children.
-- Fixed ids make the access tests readable:
--   ...a1 admin A   ...a2 coach A (Year 8)   ...a3 coach A (Year 9)   ...a4 parent of Ava
--   ...a5 parent of Leo   ...a6 Ava's own pupil login   ...b1 admin B   ...b2 coach B   ...b3 parent B

insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-0000000000a1','admin@hollinspark.example'),
 ('00000000-0000-0000-0000-0000000000a2','hughes@hollinspark.example'),
 ('00000000-0000-0000-0000-0000000000a3','patel@hollinspark.example'),
 ('00000000-0000-0000-0000-0000000000a4','parent.ava@example.com'),
 ('00000000-0000-0000-0000-0000000000a5','parent.leo@example.com'),
 ('00000000-0000-0000-0000-0000000000a6','ava.pupil@hollinspark.example'),
 ('00000000-0000-0000-0000-0000000000b1','admin@riverside.example'),
 ('00000000-0000-0000-0000-0000000000b2','coach@riverside.example'),
 ('00000000-0000-0000-0000-0000000000b3','parent.sam@example.com'),
 ('00000000-0000-0000-0000-0000000000c1','new.parent@example.com');

insert into public.schools (id, name) values
 ('aaaaaaaa-0000-0000-0000-000000000000','Hollins Park Academy (demo)'),
 ('bbbbbbbb-0000-0000-0000-000000000000','Riverside High (demo)');

insert into public.school_members (id, school_id, user_id, role, display_name) values
 ('10000000-0000-0000-0000-0000000000a1','aaaaaaaa-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000000a1','admin','Mrs Okafor'),
 ('10000000-0000-0000-0000-0000000000a2','aaaaaaaa-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000000a2','coach','Ms Hughes'),
 ('10000000-0000-0000-0000-0000000000a3','aaaaaaaa-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000000a3','coach','Mr Patel'),
 ('10000000-0000-0000-0000-0000000000a4','aaaaaaaa-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000000a4','guardian','Sam M.'),
 ('10000000-0000-0000-0000-0000000000a5','aaaaaaaa-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000000a5','guardian','Jo K.'),
 ('10000000-0000-0000-0000-0000000000a6','aaaaaaaa-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000000a6','student','Ava M.'),
 ('10000000-0000-0000-0000-0000000000b1','bbbbbbbb-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000000b1','admin','Mr Reid'),
 ('10000000-0000-0000-0000-0000000000b2','bbbbbbbb-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000000b2','coach','Miss Shah'),
 ('10000000-0000-0000-0000-0000000000b3','bbbbbbbb-0000-0000-0000-000000000000','00000000-0000-0000-0000-0000000000b3','guardian','Alex T.');

insert into public.students (id, school_id, display_name, year_group, account_member_id) values
 ('20000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000000','Ava M.','Year 8','10000000-0000-0000-0000-0000000000a6'),
 ('20000000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000000','Leo K.','Year 8',null),
 ('20000000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000000','Priya S.','Year 8',null),
 ('20000000-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000000','Noah T.','Year 8',null),
 ('20000000-0000-0000-0000-000000000005','aaaaaaaa-0000-0000-0000-000000000000','Isla R.','Year 8',null),
 ('20000000-0000-0000-0000-000000000006','aaaaaaaa-0000-0000-0000-000000000000','Zara O.','Year 8',null),
 ('20000000-0000-0000-0000-000000000007','aaaaaaaa-0000-0000-0000-000000000000','Ben W.','Year 9',null),
 ('20000000-0000-0000-0000-0000000000b1','bbbbbbbb-0000-0000-0000-000000000000','Sam T.','Year 8',null);

insert into public.guardian_links (school_id, student_id, guardian_member_id) values
 ('aaaaaaaa-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-0000000000a4'),
 ('aaaaaaaa-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-0000000000a5'),
 ('bbbbbbbb-0000-0000-0000-000000000000','20000000-0000-0000-0000-0000000000b1','10000000-0000-0000-0000-0000000000b3');

insert into public.groups (id, school_id, name, kind, created_by) values
 ('30000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000000','Year 8 Netball Club','class','00000000-0000-0000-0000-0000000000a1'),
 ('30000000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000000','Year 9 Netball','class','00000000-0000-0000-0000-0000000000a1'),
 ('30000000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000000','Shooting squad','coach','00000000-0000-0000-0000-0000000000a2'),
 ('30000000-0000-0000-0000-0000000000b1','bbbbbbbb-0000-0000-0000-000000000000','Year 8 Netball','class','00000000-0000-0000-0000-0000000000b1');
insert into public.group_coaches (group_id, coach_member_id, school_id) values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-0000000000a2','aaaaaaaa-0000-0000-0000-000000000000'),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-0000000000a3','aaaaaaaa-0000-0000-0000-000000000000'),
 ('30000000-0000-0000-0000-0000000000b1','10000000-0000-0000-0000-0000000000b2','bbbbbbbb-0000-0000-0000-000000000000');
insert into public.group_members (group_id, student_id, school_id)
 select '30000000-0000-0000-0000-000000000001', id, school_id from public.students where year_group = 'Year 8' and school_id = 'aaaaaaaa-0000-0000-0000-000000000000';
insert into public.group_members (group_id, student_id, school_id) values
 ('30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000007','aaaaaaaa-0000-0000-0000-000000000000'),
 ('30000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000000'),
 ('30000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000005','aaaaaaaa-0000-0000-0000-000000000000'),
 ('30000000-0000-0000-0000-0000000000b1','20000000-0000-0000-0000-0000000000b1','bbbbbbbb-0000-0000-0000-000000000000');

-- Netball, three skills, versioned rubrics
insert into public.sports (id, school_id, name) values
 ('40000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000000','Netball'),
 ('40000000-0000-0000-0000-0000000000b1','bbbbbbbb-0000-0000-0000-000000000000','Netball');
insert into public.skills (id, school_id, sport_id, name, recording_tip) values
 ('50000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000000','40000000-0000-0000-0000-000000000001','Shooting','Film from the side at hip height, about 4 m away'),
 ('50000000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000000','40000000-0000-0000-0000-000000000001','Chest pass','Film side-on, both partners in shot'),
 ('50000000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000000','40000000-0000-0000-0000-000000000001','Pivot footwork','Film from the front, feet in shot'),
 ('50000000-0000-0000-0000-0000000000b1','bbbbbbbb-0000-0000-0000-000000000000','40000000-0000-0000-0000-0000000000b1','Shooting',null);

insert into public.rubric_versions (id, school_id, skill_id, version, levels, criteria, published_at) values
 ('60000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000000','50000000-0000-0000-0000-000000000001',1,
  '["Working towards","Meeting","Exceeding"]',
  '[{"key":"stance","name":"Stance","descriptors":["Feet together or uneven","Feet hip-width, mostly steady","Stable, balanced stance every shot"]},
    {"key":"release","name":"Release","descriptors":["Ball pushed from the chest","Ball released above the head","High, controlled release with a flick"]}]', '2026-04-20'),
 ('60000000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000000','50000000-0000-0000-0000-000000000001',2,
  '["Emerging","Developing","Secure","Excelling"]',
  '[{"key":"balance","name":"Balance","descriptors":["Wobbles or steps after the shot","Mostly steady, small sway at release","Steady base, weight even on both feet","Fully balanced from set-up to landing"]},
    {"key":"position","name":"Positioning","descriptors":["Ball held in front of the face or to one side","Ball above the head but elbows flare out","Ball above the forehead, elbows under the ball","Same high release point on every shot"]},
    {"key":"timing","name":"Timing","descriptors":["Knees and arms move separately","Some knee bend, but arms start early","Knees bend, then arms extend in one rhythm","Smooth, repeatable rhythm under pressure"]},
    {"key":"follow","name":"Follow-through","descriptors":["Arms drop straight after release","Short wrist flick","Wrists flick, fingers point at the ring","Holds the follow-through until the ball lands"]}]', '2026-09-01'),
 ('60000000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000000','50000000-0000-0000-0000-000000000002',1,
  '["Emerging","Developing","Secure","Excelling"]',
  '[{"key":"stance","name":"Stance","descriptors":["Feet together, upright","Feet apart, little knee bend","Staggered stance, knees soft","Balanced and ready to move after the pass"]},
    {"key":"hands","name":"Hand shape","descriptors":["Palms flat behind the ball","Hands to the sides, thumbs apart","W-shape, thumbs behind the ball","Clean W-shape on every catch and pass"]},
    {"key":"step","name":"Step and push","descriptors":["No step into the pass","Step and push happen separately","Steps in as arms push","Powerful, accurate step-and-push to chest height"]},
    {"key":"follow","name":"Follow-through","descriptors":["Arms stop at the chest","Arms extend part way","Arms fully extend, thumbs point down","Full extension, thumbs down, eyes on the target"]}]', '2026-09-01'),
 ('60000000-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000000','50000000-0000-0000-0000-000000000003',1,
  '["Emerging","Developing","Secure","Excelling"]',
  '[{"key":"land","name":"Landing","descriptors":["Lands off balance","Lands on one foot, wobbles","Two-foot or one-two landing, balanced","Controlled landing at speed"]},
    {"key":"pivot","name":"Pivot","descriptors":["Landing foot moves","Pivots but foot drags","Pivots cleanly on the ball of the foot","Pivots both ways under pressure"]}]', '2026-09-01'),
 ('60000000-0000-0000-0000-0000000000b1','bbbbbbbb-0000-0000-0000-000000000000','50000000-0000-0000-0000-0000000000b1',1,
  '["Emerging","Developing","Secure","Excelling"]',
  '[{"key":"balance","name":"Balance","descriptors":["a","b","c","d"]}]', '2026-09-01');

-- Clips (storage paths point at placeholder files; no real video)
insert into public.clips (id, school_id, student_id, skill_id, upload_id, recorded_on, uploaded_at, upload_status, storage_path, duration_ms, drill, restricted, restricted_reason, created_by) values
 ('70000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001','2026-05-14','2026-05-14 15:30','ready','aaaaaaaa-0000-0000-0000-000000000000/20000000-0000-0000-0000-000000000001/70000000-0000-0000-0000-000000000001.mp4',4000,'Free shooting',false,null,'00000000-0000-0000-0000-0000000000a2'),
 ('70000000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000002','2026-09-12','2026-09-13 08:41','ready','aaaaaaaa-0000-0000-0000-000000000000/20000000-0000-0000-0000-000000000001/70000000-0000-0000-0000-000000000002.mp4',4000,'5 shots from the top of the circle',false,null,'00000000-0000-0000-0000-0000000000a2'),
 ('70000000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000003','2026-09-26','2026-09-26 16:05','ready','aaaaaaaa-0000-0000-0000-000000000000/20000000-0000-0000-0000-000000000001/70000000-0000-0000-0000-000000000003.mp4',4000,'5 shots from the top of the circle',false,null,'00000000-0000-0000-0000-0000000000a2'),
 ('70000000-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000002','50000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000004','2026-10-01','2026-10-01 16:42','ready','aaaaaaaa-0000-0000-0000-000000000000/20000000-0000-0000-0000-000000000002/70000000-0000-0000-0000-000000000004.mp4',4000,'5 shots from the top of the circle',true,'Two other pupils visible','00000000-0000-0000-0000-0000000000a2'),
 ('70000000-0000-0000-0000-000000000005','aaaaaaaa-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000004','50000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000005','2026-09-30','2026-09-30 16:10','ready','aaaaaaaa-0000-0000-0000-000000000000/20000000-0000-0000-0000-000000000004/70000000-0000-0000-0000-000000000005.mp4',4000,null,false,null,'00000000-0000-0000-0000-0000000000a2'),
 ('70000000-0000-0000-0000-000000000006','aaaaaaaa-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000007','50000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000006','2026-09-26','2026-09-26 16:20','ready','aaaaaaaa-0000-0000-0000-000000000000/20000000-0000-0000-0000-000000000007/70000000-0000-0000-0000-000000000006.mp4',4000,null,false,null,'00000000-0000-0000-0000-0000000000a3'),
 ('70000000-0000-0000-0000-0000000000b1','bbbbbbbb-0000-0000-0000-000000000000','20000000-0000-0000-0000-0000000000b1','50000000-0000-0000-0000-0000000000b1','71000000-0000-0000-0000-0000000000b1','2026-09-26','2026-09-26 16:20','ready','bbbbbbbb-0000-0000-0000-000000000000/20000000-0000-0000-0000-0000000000b1/70000000-0000-0000-0000-0000000000b1.mp4',4000,null,false,null,'00000000-0000-0000-0000-0000000000b2');

insert into storage.objects (bucket_id, name) select 'clips', storage_path from public.clips;

insert into public.assessments (id, school_id, clip_id, rubric_version_id, scores, feedback, strengths, to_improve, next_goal, status, author_id) values
 ('80000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000000','70000000-0000-0000-0000-000000000001','60000000-0000-0000-0000-000000000001','{"stance":1,"release":2}','First netball session filmed. Great enthusiasm!','Enthusiasm','Stance','Feet hip-width apart','published','00000000-0000-0000-0000-0000000000a2'),
 ('80000000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000000','70000000-0000-0000-0000-000000000002','60000000-0000-0000-0000-000000000002','{"balance":2,"position":1,"timing":2,"follow":1}','A brave start, Ava. We will work on bending your knees first.','Confident, quick set-up','Knee bend and arm position','Bend your knees before you shoot','published','00000000-0000-0000-0000-0000000000a2'),
 ('80000000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000000','70000000-0000-0000-0000-000000000003','60000000-0000-0000-0000-000000000002','{"balance":3,"position":3,"timing":3,"follow":2}','Big step forward today, Ava. You bent your knees before every shot.','Knee bend and rhythm','Hold your arms up after release','Hold your follow-through until the ball lands','published','00000000-0000-0000-0000-0000000000a2'),
 ('80000000-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000000','70000000-0000-0000-0000-000000000004','60000000-0000-0000-0000-000000000002','{"balance":2,"position":2}',null,null,null,null,'draft','00000000-0000-0000-0000-0000000000a2'),
 ('80000000-0000-0000-0000-000000000005','aaaaaaaa-0000-0000-0000-000000000000','70000000-0000-0000-0000-000000000005','60000000-0000-0000-0000-000000000002','{"balance":3,"position":3,"timing":2}','Really controlled set-up, Noah.',null,null,null,'draft','00000000-0000-0000-0000-0000000000a2'),
 ('80000000-0000-0000-0000-000000000006','aaaaaaaa-0000-0000-0000-000000000000','70000000-0000-0000-0000-000000000006','60000000-0000-0000-0000-000000000002','{"balance":3}','Good start, Ben.',null,null,null,'published','00000000-0000-0000-0000-0000000000a3'),
 ('80000000-0000-0000-0000-0000000000b1','bbbbbbbb-0000-0000-0000-000000000000','70000000-0000-0000-0000-0000000000b1','60000000-0000-0000-0000-0000000000b1','{"balance":2}','Nice work, Sam.',null,null,null,'published','00000000-0000-0000-0000-0000000000b2');

insert into public.clip_moments (school_id, clip_id, at_ms, body, author_id) values
 ('aaaaaaaa-0000-0000-0000-000000000000','70000000-0000-0000-0000-000000000003',850,'Nice deep knee bend','00000000-0000-0000-0000-0000000000a2'),
 ('aaaaaaaa-0000-0000-0000-000000000000','70000000-0000-0000-0000-000000000003',1450,'Elbows under the ball now','00000000-0000-0000-0000-0000000000a2'),
 ('aaaaaaaa-0000-0000-0000-000000000000','70000000-0000-0000-0000-000000000004',1200,'Draft comment on Leo','00000000-0000-0000-0000-0000000000a2');

insert into public.coach_notes (school_id, clip_id, body, author_id) values
 ('aaaaaaaa-0000-0000-0000-000000000000','70000000-0000-0000-0000-000000000003','PRIVATE: tired by the end of the session.','00000000-0000-0000-0000-0000000000a2');

insert into public.goals (school_id, student_id, skill_id, text, status, published, clip_id, set_on, closed_on, created_by) values
 ('aaaaaaaa-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001','Hold your follow-through until the ball lands','in_progress',true,'70000000-0000-0000-0000-000000000003','2026-09-26',null,'00000000-0000-0000-0000-0000000000a2'),
 ('aaaaaaaa-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001','Bend your knees before you shoot','achieved',true,'70000000-0000-0000-0000-000000000003','2026-09-12','2026-09-26','00000000-0000-0000-0000-0000000000a2'),
 ('aaaaaaaa-0000-0000-0000-000000000000','20000000-0000-0000-0000-000000000001','50000000-0000-0000-0000-000000000001','DRAFT goal not yet shared','in_progress',false,null,'2026-10-01',null,'00000000-0000-0000-0000-0000000000a2');
