-- SkillProgress pilot setup: one school, one netball class, made-up pupils, two test logins.
-- BEFORE running: in Supabase go to Authentication > Users > Add user > Create new user and create
--   coach@skillprogress.test   (tick "Auto Confirm User")
--   parent@skillprogress.test  (tick "Auto Confirm User")
-- Then paste this whole file into SQL Editor and press Run. Safe to run more than once.
-- All pupils below are fictional. Do not add real pupils until the school has signed off.

do $$
declare
  v_school uuid; v_sport uuid; v_shoot uuid; v_pass uuid; v_pivot uuid; v_class uuid;
  v_coach_user uuid; v_parent_user uuid; v_coach_member uuid; v_parent_member uuid; v_ava uuid;
begin
  select id into v_coach_user from auth.users where email = 'coach@skillprogress.test';
  select id into v_parent_user from auth.users where email = 'parent@skillprogress.test';
  if v_coach_user is null or v_parent_user is null then
    raise exception 'Create coach@skillprogress.test and parent@skillprogress.test in Authentication > Users first.';
  end if;

  select id into v_school from public.schools where name = 'Pilot School (demo)';
  if v_school is null then
    insert into public.schools (name) values ('Pilot School (demo)') returning id into v_school;
  end if;

  -- The coach test login is also the school admin, so it can test admin features later.
  insert into public.school_members (school_id, user_id, role, display_name) values
    (v_school, v_coach_user, 'admin', 'Test Admin'),
    (v_school, v_coach_user, 'coach', 'Ms Hughes (test)')
  on conflict (school_id, user_id, role) do nothing;
  select id into v_coach_member from public.school_members where school_id = v_school and user_id = v_coach_user and role = 'coach';

  insert into public.school_members (school_id, user_id, role, display_name)
  values (v_school, v_parent_user, 'guardian', 'Test Parent')
  on conflict (school_id, user_id, role) do nothing;
  select id into v_parent_member from public.school_members where school_id = v_school and user_id = v_parent_user and role = 'guardian';

  -- Sport, skills and rubrics
  insert into public.sports (school_id, name) values (v_school, 'Netball') on conflict (school_id, name) do nothing;
  select id into v_sport from public.sports where school_id = v_school and name = 'Netball';
  insert into public.skills (school_id, sport_id, name, recording_tip) values
    (v_school, v_sport, 'Shooting', 'Film from the side at hip height, about 4 m away'),
    (v_school, v_sport, 'Chest pass', 'Film side-on with both partners in shot'),
    (v_school, v_sport, 'Pivot footwork', 'Film from the front with feet in shot')
  on conflict (sport_id, name) do nothing;
  select id into v_shoot from public.skills where sport_id = v_sport and name = 'Shooting';
  select id into v_pass from public.skills where sport_id = v_sport and name = 'Chest pass';
  select id into v_pivot from public.skills where sport_id = v_sport and name = 'Pivot footwork';

  insert into public.rubric_versions (school_id, skill_id, version, levels, criteria, published_at) values
   (v_school, v_shoot, 1, '["Emerging","Developing","Secure","Excelling"]',
    '[{"key":"balance","name":"Balance","descriptors":["Wobbles or steps after the shot","Mostly steady, small sway at release","Steady base, weight even on both feet","Fully balanced from set-up to landing"]},
      {"key":"position","name":"Positioning","descriptors":["Ball held in front of the face or to one side","Ball above the head but elbows flare out","Ball above the forehead, elbows under the ball","Same high release point on every shot"]},
      {"key":"timing","name":"Timing","descriptors":["Knees and arms move separately","Some knee bend, but arms start early","Knees bend, then arms extend in one rhythm","Smooth, repeatable rhythm under pressure"]},
      {"key":"follow","name":"Follow-through","descriptors":["Arms drop straight after release","Short wrist flick","Wrists flick, fingers point at the ring","Holds the follow-through until the ball lands"]}]', now()),
   (v_school, v_pass, 1, '["Emerging","Developing","Secure","Excelling"]',
    '[{"key":"stance","name":"Stance","descriptors":["Feet together, upright","Feet apart, little knee bend","Staggered stance, knees soft","Balanced and ready to move after the pass"]},
      {"key":"hands","name":"Hand shape","descriptors":["Palms flat behind the ball","Hands to the sides, thumbs apart","W-shape, thumbs behind the ball","Clean W-shape on every catch and pass"]},
      {"key":"step","name":"Step and push","descriptors":["No step into the pass","Step and push happen separately","Steps in as arms push","Powerful, accurate step-and-push to chest height"]},
      {"key":"follow","name":"Follow-through","descriptors":["Arms stop at the chest","Arms extend part way","Arms fully extend, thumbs point down","Full extension, thumbs down, eyes on the target"]}]', now()),
   (v_school, v_pivot, 1, '["Emerging","Developing","Secure","Excelling"]',
    '[{"key":"land","name":"Landing","descriptors":["Lands off balance","Lands on one foot, wobbles","Two-foot or one-two landing, balanced","Controlled landing at speed"]},
      {"key":"pivot","name":"Pivot","descriptors":["Landing foot moves","Pivots but foot drags","Pivots cleanly on the ball of the foot","Pivots both ways under pressure"]}]', now())
  on conflict (skill_id, version) do nothing;

  -- Class group, coach assignment and fictional pupils
  select id into v_class from public.groups where school_id = v_school and name = 'Year 8 Netball Club';
  if v_class is null then
    insert into public.groups (school_id, name, kind, created_by) values (v_school, 'Year 8 Netball Club', 'class', v_coach_user) returning id into v_class;
  end if;
  insert into public.group_coaches (group_id, coach_member_id, school_id) values (v_class, v_coach_member, v_school) on conflict do nothing;

  insert into public.students (school_id, display_name, year_group)
  select v_school, n, 'Year 8' from unnest(array['Ava M.','Leo K.','Priya S.','Noah T.','Isla R.','Zara O.','Ben W.','Maya P.']) n
  where not exists (select 1 from public.students s where s.school_id = v_school and s.display_name = n);
  insert into public.group_members (group_id, student_id, school_id)
  select v_class, s.id, v_school from public.students s where s.school_id = v_school on conflict do nothing;

  -- The test parent is linked to Ava only.
  select id into v_ava from public.students where school_id = v_school and display_name = 'Ava M.';
  insert into public.guardian_links (school_id, student_id, guardian_member_id, approved_by)
  values (v_school, v_ava, v_parent_member, v_coach_user) on conflict (student_id, guardian_member_id) do nothing;
end $$;

select 'Pilot school ready: ' || count(*) || ' pupils' as result
from public.students s join public.schools sc on sc.id = s.school_id where sc.name = 'Pilot School (demo)';
