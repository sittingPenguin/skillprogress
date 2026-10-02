# SkillProgress

Private coaching-feedback app for school sport. Coaches film a skill, assess it against a rubric and publish feedback. Parents and (optionally) pupils follow progress. Nothing is public.

**Status:** Stage 1 of 6 (accounts, roles and school data isolation) is complete and tested. The mobile app and web portal are not built yet. See `docs/ARCHITECTURE.md` for the plan.

## What's here

```
demo/index.html  Clickable design demo (synthetic data, no backend)
supabase/
  migrations/      Database schema, access rules, audit trail, video storage rules
  seed.sql         Synthetic demo data: two fictional schools, no real children
  tests/           Access tests (69 checks) and a full-year load test
docs/
  ARCHITECTURE.md  Stack, decisions, assumptions, stages, costs
  SCHOOL_DECISIONS.md  What the school must decide before a pilot
run_tests.sh       Rebuilds a scratch database and runs every test
.env.example       Configuration names (no real values)
```

## Running the tests

Needs PostgreSQL 15 or later on your machine.

```bash
PGHOST=/tmp PGPORT=5432 PGUSER=postgres ./run_tests.sh
```

`supabase/tests/00_supabase_shim.sql` imitates the parts of Supabase the rules depend on, so the tests run on plain Postgres. Never run the shim against a real project.

## Live project

Supabase project: `ftkakywjnokhmnzxilob` (London). Pilot data only; no real pupils yet.

## Deploying the database to Supabase

1. Create a Supabase project in the **London (eu-west-2)** region.
2. Install the Supabase CLI, then run `supabase link --project-ref <your-ref>` and `supabase db push`.
3. Do **not** load `seed.sql` into a project that will hold real pupils.

## Security model in one paragraph

Every table has row-level security switched on and forced. Admins see their own school. Coaches see only pupils in the class groups they are assigned to; groups they make themselves never widen that. Parents see only children the school has linked them to, and only clips that are uploaded, unflagged and published. Private coach notes live in a separate staff-only table. Videos sit in a private bucket and are reached only through short-lived signed links, which Supabase issues only when these same rules allow it. Revoking a person or a parent link takes effect on the next request. Published rubric versions are frozen. Permission changes, publishing, exports and deletions are written to an append-only audit log that only that school's admins can read.
