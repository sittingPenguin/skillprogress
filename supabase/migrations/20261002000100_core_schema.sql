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
