#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../helpers.sh"

echo ""
printf "${BOLD}E2E: dev sb reset${RESET}\n"

# Entry state (left by 02-db-migrate-seed):
#   - Supabase running (restarted at end of 02)
#   - Migrations 20260101000000, 20260418000001, 20260420000000 applied
#   - supabase_seeds.applied_seeds contains 001_sample.sql + 002_sample.sql
#   - _test_init has 3 rows
#   - Shared worktree's supabase/seeds/ has 002_sample.sql

SHARED_WT="$WORKTREE_BASE/supabase"

# ── Pre-check: data is present ───────────────────────────────────────

header "pre-check: seed data present before reset"
assert "_test_init has rows" test "$(db_count _test_init)" -gt 0
assert "002_sample in registry" db_seed_exists "002_sample.sql"

# ── dev sb reset — wipes + re-migrates + re-seeds ────────────────────

header "dev sb reset — full cycle"
cd "$WORKTREE_BASE/main"
EXIT_CODE=0
OUTPUT=$(bash "$SCRIPTS_DIR/dev-supabase.sh" reset 2>&1) || EXIT_CODE=$?
if [ "$EXIT_CODE" != "0" ]; then
  printf "${DIM}reset output:${RESET}\n%s\n" "$OUTPUT" >&2
fi
assert_exit_code "exits 0" "0" "$EXIT_CODE"

# After reset: migrations re-applied, seeds re-applied.
assert "baseline migration re-applied" db_version_exists "20260101000000"
assert "_migrate_test table still exists" db_table_exists "_migrate_test"
assert "seed registry re-populated" db_seed_exists "002_sample.sql"
# 002_sample.sql inserts 2 rows
assert_eq "_test_init has exactly 2 rows (fresh seed)" "2" "$(db_count _test_init)"

# ── reset from feature worktree operates on shared ───────────────────

header "dev sb reset — from feature worktree"
cd "$WORKTREE_BASE/feat-gamma"

# Re-insert a sentinel row in the SHARED DB
db_query "INSERT INTO public._test_init DEFAULT VALUES;" >/dev/null || true
ROWS_BEFORE=$(db_count _test_init)

EXIT_CODE=0
OUTPUT=$(bash "$SCRIPTS_DIR/dev-supabase.sh" reset 2>&1) || EXIT_CODE=$?
if [ "$EXIT_CODE" != "0" ]; then
  printf "${DIM}reset #2 output:${RESET}\n%s\n" "$OUTPUT" >&2
fi
assert_exit_code "exits 0" "0" "$EXIT_CODE"

ROWS_AFTER=$(db_count _test_init)
# Post-reset seed state again: exactly 2 rows (from 002_sample.sql).
assert_eq "shared DB reset (back to seed state)" "2" "$ROWS_AFTER"

print_results
