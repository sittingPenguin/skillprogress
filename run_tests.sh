#!/usr/bin/env bash
# Rebuilds a scratch database from the migrations and runs the access tests.
set -euo pipefail
cd "$(dirname "$0")"
PSQL="psql -h ${PGHOST:-/tmp} -p ${PGPORT:-5433} -U ${PGUSER:-postgres} -v ON_ERROR_STOP=1 -q"
$PSQL -d postgres -c "drop database if exists sp_test" -c "create database sp_test"
$PSQL -d sp_test -f supabase/tests/00_supabase_shim.sql
for f in supabase/migrations/*.sql; do $PSQL -d sp_test -f "$f"; done
$PSQL -d sp_test -f supabase/seed.sql
for f in supabase/tests/[1-9]*.sql; do echo "== $f"; $PSQL -d sp_test -f "$f"; done
echo "All tests passed."
