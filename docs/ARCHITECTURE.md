# SkillProgress architecture and plan

## Stack

| Part | Choice | Why |
|---|---|---|
| Phone and tablet app | React Native with Expo (TypeScript) | One codebase for Android, iPhone and iPad. `expo-camera` records, `expo-video` plays back with variable speed, and Expo's cloud build service (EAS) builds iPhone versions without a Mac. Strong screen-reader and dynamic-text support. Same language as the web portal. |
| Parent and admin portal | Next.js (TypeScript) | Works on phone and desktop browsers and shares types and data code with the app. |
| Database, logins, files | Supabase, London region | Postgres with row-level security, so access rules are enforced by the database itself. Built-in email/password and magic-link logins. Private storage with resumable (TUS) uploads and signed links. Managed backups. |
| Notifications | Expo push notifications | The message carries no pupil details ("A new update is ready"). Opening it requires sign-in. |
| Scheduled jobs | Supabase cron calling an Edge Function | Nightly retention clean-up deletes expired video files. |

Flutter was the other serious option. Expo won on two things: one language across app and web, and building iPhone versions without owning a Mac.

## How the key requirements are met

- **School isolation:** every row carries `school_id`. Composite foreign keys stop a row from pointing across schools, and every access rule is scoped to the caller's active memberships. Tested.
- **Parents can't claim a child:** access comes only from a school-created link, or from a single-use invitation for one named pupil that expires after 7 days. The token is stored hashed. Tested.
- **Drafts and private notes:** families see only published assessments on unflagged clips. Private notes are a separate table that families can't query. Tested.
- **Upload retries:** the phone generates an `upload_id` before the first attempt, and `register_clip` returns the existing clip on a retry. The video uses Supabase's resumable upload, so it continues from where it stopped. Tested.
- **Recording date:** `recorded_on` is separate from `uploaded_at`.
- **Rubric history:** published rubric versions can't be edited or deleted, and each assessment points at the exact version it used. The app compares scores only when two clips share a rubric version, and never adds criteria together into one score.
- **Clips showing other children:** a flag blocks publishing at database level until a coach clears it. Clearing it records who reviewed the clip and when.
- **Revocation:** every rule checks for active status, so revoking a person or a parent link takes effect on the next request. Tested.
- **Audit:** an append-only log records membership and role changes, parent linking and revocation, publishing and unpublishing, flags, exports, data requests and settings. Only that school's admins can read it, and it never stores feedback or notes.
- **Retention:** each school sets a retention period (30–3,650 days, default 400). A nightly job removes expired clips. Tested.
- **Scale:** tested with 400 pupils and about 94,000 clips (roughly three years). The slowest feed query took 0.12 s.

## Stages

1. **Accounts, roles, school isolation.** Done: schema, access rules, audit, storage rules, 69 tests, load test.
2. **Pupil profiles and video recording/upload** in the app.
3. **Assessments, timestamped comments, goals, publishing.**
4. **Progress timeline and side-by-side comparison.**
5. **Parent portal and admin tools:** invites, revocation, rubrics, retention, exports, deletion.
6. **Security check, accessibility, pilot readiness.** Includes testing on real Android and iPhone devices.

## Assumptions (change any of these)

- One school, netball, and three skills (shooting, chest pass, pivot footwork) for the pilot.
- Pupil records hold a display name (first name and initial) and a year group only.
- Parents sign in with email (a magic link or a password).
- Pupil logins stay off until the school turns them on.
- Clips are 720p, about 10 seconds, and about 15 MB after compression on the phone.

## Running costs

The main cost is video. Assuming 400 pupils filmed twice a week for 39 weeks, with each clip watched about three times:

- About 31,000 clips and 470 GB of storage by the end of the first year.
- About 1.4 TB of video downloaded over the year.
- Roughly £25–£60 a month on Supabase's Pro plan by the end of year one, rising with storage if nothing is deleted.

These are estimates and need checking against current Supabase pricing. Retention is the main way to control cost.

Fixed costs are an Apple Developer account at $99 a year and a Google Play account at $25 once.

## Not in version 1

Automatic AI scoring, public sharing, leaderboards, payments, messaging, and connections to the school's management information system. No pupil videos are ever used to train AI.
