#!/usr/bin/env bash
# test-resolve-model-family.sh — test harness for resolve-model-family.sh.
# Builds a temporary SQLite DB, seeds fixture data, and asserts resolver behavior.
# Never touches ~/.9router or the live 9Router store.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-model-family.sh"

if [[ ! -x "$RESOLVER" ]]; then
  echo "FAIL: resolver not executable: $RESOLVER" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d)
DB="$TMP_DIR/test.sqlite"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

run_sql() {
  sqlite3 "$DB" "$1"
}

# Mirror the live schema for combos and usageHistory.
run_sql "CREATE TABLE combos (
  id TEXT PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  kind TEXT,
  models TEXT NOT NULL,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
);"

run_sql "CREATE TABLE usageHistory (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp TEXT NOT NULL,
  provider TEXT,
  model TEXT,
  connectionId TEXT,
  apiKey TEXT,
  endpoint TEXT,
  promptTokens INTEGER DEFAULT 0,
  completionTokens INTEGER DEFAULT 0,
  cost REAL DEFAULT 0,
  status TEXT,
  tokens TEXT,
  meta TEXT
);"

# Seed combos (same JSON-array-of-strings encoding as the live DB).
run_sql "INSERT INTO combos (id, name, kind, models, createdAt, updatedAt) VALUES
  ('c1', 'economy', '', '[\"ocg/deepseek-v4.1-flash\",\"ocg/glm-5.3-flash\",\"ocg/kimi-k2.7-code\"]', '2026-01-01', '2026-01-01'),
  ('c2', 'standard', '', '[\"ocg/kimi-k2.7-code\",\"cx/gpt-5.6-luna\",\"ocg/gpt-5.6-luna\",\"oc-dmas/gpt-5.6-luna\"]', '2026-01-01', '2026-01-01'),
  ('c3', 'strong', '', '[\"cc/claude-sonnet-5-5\",\"dmas/claude-sonnet-5-5\",\"cx/gpt-5.6-sol\",\"oc-dmas/gpt-5.6-sol\"]', '2026-01-01', '2026-01-01'),
  ('c4', 'mixed-combo', '', '[\"cc/claude-sonnet-5-5\",\"ocg/kimi-k2.7-code\"]', '2026-01-01', '2026-01-01');"

# Seed usageHistory. id values are explicit to make checkpoint tests predictable.
run_sql "INSERT INTO usageHistory (id, timestamp, provider, model, connectionId, apiKey, endpoint, status)
  VALUES
    (1, '2026-01-01T00:00:00Z', 'opencode-go', 'kimi-k2.7-code', 'conn-1', 'SECRET-SENTINEL-DO-NOT-PRINT', 'https://example.com', 'ok'),
    (2, '2026-01-01T00:01:00Z', 'opencode-go', 'kimi-k2.7-code', 'conn-1', 'SECRET-SENTINEL-DO-NOT-PRINT', 'https://example.com', 'ok'),
    (3, '2026-01-01T00:02:00Z', 'opencode-go', 'kimi-k2.7-code', 'conn-1', 'SECRET-SENTINEL-DO-NOT-PRINT', 'https://example.com', 'error'),
    (4, '2026-01-01T00:03:00Z', 'opencode-go', 'deepseek-v4.1-flash', 'conn-1', 'SECRET-SENTINEL-DO-NOT-PRINT', 'https://example.com', 'ok'),
    (10, '2026-01-01T01:00:00Z', 'claude', 'claude-sonnet-5-5', 'conn-2', 'SECRET-SENTINEL-DO-NOT-PRINT', 'https://example.com', 'ok'),
    (11, '2026-01-01T01:01:00Z', 'claude', 'claude-sonnet-5-5', 'conn-2', 'SECRET-SENTINEL-DO-NOT-PRINT', 'https://example.com', 'ok'),
    (12, '2026-01-01T01:02:00Z', 'dmas', 'claude-sonnet-5-5', 'conn-2', 'SECRET-SENTINEL-DO-NOT-PRINT', 'https://example.com', 'ok'),
    (20, '2026-01-01T02:00:00Z', 'opencode-go', 'kimi-k2.7-code', 'conn-3', 'SECRET-SENTINEL-DO-NOT-PRINT', 'https://example.com', 'ok'),
    (21, '2026-01-01T02:01:00Z', 'claude', 'claude-sonnet-5-5', 'conn-3', 'SECRET-SENTINEL-DO-NOT-PRINT', 'https://example.com', 'ok');"

export NINEROUTER_DB="$DB"

# Export PATH for sqlite3 as well; the resolver needs sqlite3 on PATH.
# Capture original DB checksum and bytes to prove read-only behavior.
orig_sum=$(shasum -a 256 "$DB" | awk '{print $1}')
orig_size=$(stat -f%z "$DB")

cases_passed=0
cases_failed=0

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]]
}

assert_not_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" != *"$needle"* ]]
}

run_case() {
  local name="$1"
  shift
  local out
  local rc=0
  out=$("$@" 2>&1) || rc=$?
  printf '%s' "$out"
  return $rc
}

expect_ok() {
  local name="$1"
  local expected_status="$2"
  shift 2
  local out
  local rc=0
  out=$("$@" 2>&1) || rc=$?
  if assert_contains "$out" "status=$expected_status"; then
    echo "PASS: $name"
    ((cases_passed++))
  else
    echo "FAIL: $name (rc=$rc)"
    echo "  expected status=$expected_status"
    echo "  got: $out"
    ((cases_failed++))
  fi
}

expect_fail() {
  local name="$1"
  local expected_status="$2"
  local expected_reason="$3"
  shift 3
  local out
  local rc=0
  out=$("$@" 2>&1) || rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "FAIL: $name — expected non-zero exit, got 0"
    echo "  output: $out"
    ((cases_failed++))
    return
  fi
  if assert_contains "$out" "status=$expected_status" && assert_contains "$out" "reason=$expected_reason"; then
    echo "PASS: $name"
    ((cases_passed++))
  else
    echo "FAIL: $name (rc=$rc)"
    echo "  expected status=$expected_status reason=$expected_reason"
    echo "  got: $out"
    ((cases_failed++))
  fi
}

# 1. standard combo -> non-claude from kimi-k2.7-code.
out=$("$RESOLVER" 0 standard 2>&1) || true
if assert_contains "$out" "status=resolved" &&
   assert_contains "$out" "family=non-claude" &&
   assert_contains "$out" "reviewer=review-claude" &&
   assert_contains "$out" "models=kimi-k2.7-code" &&
   assert_contains "$out" "usage_ids=1,2"; then
  echo "PASS: standard combo resolves to non-claude"
  ((cases_passed++))
else
  echo "FAIL: standard combo resolution"
  echo "  got: $out"
  ((cases_failed++))
fi

# 2. strong combo -> claude from claude-sonnet-5-5.
out=$("$RESOLVER" 9 strong 2>&1) || true
if assert_contains "$out" "status=resolved" &&
   assert_contains "$out" "family=claude" &&
   assert_contains "$out" "reviewer=review-openai" &&
   assert_contains "$out" "models=claude-sonnet-5-5" &&
   assert_contains "$out" "usage_ids=10,11,12"; then
  echo "PASS: strong combo resolves to claude"
  ((cases_passed++))
else
  echo "FAIL: strong combo resolution"
  echo "  got: $out"
  ((cases_failed++))
fi

# 3. Multiple rows same family resolve.
out=$("$RESOLVER" 0 economy 2>&1) || true
if assert_contains "$out" "status=resolved" &&
   assert_contains "$out" "family=non-claude" &&
   assert_contains "$out" "usage_ids=1,2,4"; then
  echo "PASS: multiple same-family rows resolve"
  ((cases_passed++))
else
  echo "FAIL: multiple same-family rows"
  echo "  got: $out"
  ((cases_failed++))
fi

# 4. Mixed claude + non-claude -> MODEL_DETECTION_AMBIGUOUS.
expect_fail "mixed combo ambiguous" ambiguous MODEL_DETECTION_AMBIGUOUS "$RESOLVER" 19 mixed-combo

# 5. No matching rows -> MODEL_DETECTION_FAILED.
expect_fail "no matching rows" failed MODEL_DETECTION_FAILED "$RESOLVER" 999 mixed-combo

# 6. Unknown combo -> COMBO_NOT_FOUND.
expect_fail "unknown combo" failed COMBO_NOT_FOUND "$RESOLVER" 0 unknown-combo

# 7. Rows at or below checkpoint ignored.
out=$("$RESOLVER" 10 strong 2>&1) || true
if assert_contains "$out" "status=resolved" &&
   assert_contains "$out" "usage_ids=11,12"; then
  echo "PASS: rows at or below checkpoint ignored"
  ((cases_passed++))
else
  echo "FAIL: checkpoint filtering"
  echo "  got: $out"
  ((cases_failed++))
fi

# 8. status != ok rows ignored.
out=$("$RESOLVER" 2 economy 2>&1) || true
if assert_contains "$out" "status=resolved" &&
   assert_contains "$out" "usage_ids=4"; then
  echo "PASS: non-ok status rows ignored"
  ((cases_passed++))
else
  echo "FAIL: status filtering"
  echo "  got: $out"
  ((cases_failed++))
fi

# 9. Unrelated models not in combo ignored.
out=$("$RESOLVER" 0 strong 2>&1) || true
if assert_contains "$out" "status=resolved" &&
   assert_contains "$out" "models=claude-sonnet-5-5" &&
   assert_not_contains "$out" "kimi-k2.7-code"; then
  echo "PASS: unrelated models ignored"
  ((cases_passed++))
else
  echo "FAIL: unrelated model filtering"
  echo "  got: $out"
  ((cases_failed++))
fi

# 10. No secret fields / sentinel in stdout or stderr.
out=$("$RESOLVER" 0 strong 2>&1) || true
if assert_not_contains "$out" "SECRET-SENTINEL-DO-NOT-PRINT" &&
   assert_not_contains "$out" "apiKey" &&
   assert_not_contains "$out" "endpoint" &&
   assert_not_contains "$out" "connectionId"; then
  echo "PASS: no secrets leaked"
  ((cases_passed++))
else
  echo "FAIL: secrets leaked in output"
  echo "  got: $out"
  ((cases_failed++))
fi

# 11. Invalid args: missing args.
expect_fail "missing args" failed USAGE "$RESOLVER"

# 12. Invalid args: non-integer checkpoint.
expect_fail "non-integer checkpoint" failed INVALID_CHECKPOINT "$RESOLVER" abc strong

# 13. Invalid args: negative integer checkpoint.
expect_fail "negative checkpoint" failed INVALID_CHECKPOINT "$RESOLVER" -1 strong

# 14. Missing DB.
out=$(NINEROUTER_DB="$TMP_DIR/missing.sqlite" "$RESOLVER" 0 strong 2>&1) || rc=$?
if [[ ${rc:-0} -ne 0 ]] && assert_contains "$out" "status=failed" && assert_contains "$out" "reason=DB_NOT_FOUND"; then
  echo "PASS: missing DB handled"
  ((cases_passed++))
else
  echo "FAIL: missing DB handling"
  echo "  got: $out"
  ((cases_failed++))
fi

# 15. Read-only proof: DB file unchanged.
new_sum=$(shasum -a 256 "$DB" | awk '{print $1}')
new_size=$(stat -f%z "$DB")
if [[ "$orig_sum" == "$new_sum" && "$orig_size" == "$new_size" ]]; then
  echo "PASS: DB file unchanged (read-only proof)"
  ((cases_passed++))
else
  echo "FAIL: DB file changed during tests"
  ((cases_failed++))
fi

echo ""
echo "Results: $cases_passed passed, $cases_failed failed"

if [[ $cases_failed -gt 0 ]]; then
  exit 1
fi
exit 0
