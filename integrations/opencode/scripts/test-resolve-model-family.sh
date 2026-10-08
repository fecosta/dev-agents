#!/usr/bin/env bash
# test-resolve-model-family.sh — test harness for resolve-model-family.sh.
# Builds temporary SQLite DBs, seeds fixture data, and asserts resolver behavior.
# Never touches ~/.9router or the live 9Router store. Runs on bash 3.2+.
#
# JSON1 note: the resolver no longer uses sqlite JSON1 (it parses the combo array
# with a strict regex + grep), so there is no JSON1-unavailable fallback to
# exercise; a static check below asserts it stays that way.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve-model-family.sh"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

if [[ ! -x "$RESOLVER" ]]; then
  echo "FAIL: resolver not executable: $RESOLVER" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

SENTINEL="SECRET-SENTINEL-DO-NOT-PRINT"
cases_passed=0
cases_failed=0
all_out=""
out=""
rc=0

# --- helpers ------------------------------------------------------------------

fsize() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi | awk '{print $1}'; }

pass() { echo "PASS: $1"; cases_passed=$((cases_passed + 1)); }
fail() { echo "FAIL: $1"; shift; [[ $# -gt 0 ]] && echo "  $*"; cases_failed=$((cases_failed + 1)); return 0; }

SCHEMA="CREATE TABLE combos (id TEXT PRIMARY KEY, name TEXT UNIQUE NOT NULL, kind TEXT, models TEXT NOT NULL, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL);
CREATE TABLE usageHistory (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT NOT NULL, provider TEXT, model TEXT, connectionId TEXT, apiKey TEXT, endpoint TEXT, promptTokens INTEGER DEFAULT 0, completionTokens INTEGER DEFAULT 0, cost REAL DEFAULT 0, status TEXT, tokens TEXT, meta TEXT);"

mkdb() { rm -f "$1"; sqlite3 "$1" "$SCHEMA"; }
# addcombo <db> <name> <models-json>   (json must not contain single quotes)
addcombo() { sqlite3 "$1" "INSERT INTO combos VALUES ('$2','$2','','$3','t','t');"; }
# adduse <db> <id> <provider-sql> <model-sql> [status]
adduse() {
  sqlite3 "$1" "INSERT INTO usageHistory (id,timestamp,provider,model,connectionId,apiKey,endpoint,status)
    VALUES ($2,'t',$3,$4,'conn','$SENTINEL','https://example.invalid','${5:-ok}');"
}

# run <db> <args...>: sets globals out (stdout+stderr) and rc.
run() {
  local db="$1"
  shift
  rc=0
  out=$(env NINEROUTER_DB="$db" "$RESOLVER" "$@" 2>&1) || rc=$?
  all_out="${all_out}${out}"$'\n'
}

has() { [[ "$out" == *"$1"* ]]; }

# ok_case <name> <needle>...: rc must be exactly 0 and every needle present.
ok_case() {
  local name="$1" n
  shift
  if [[ $rc -ne 0 ]]; then fail "$name" "expected rc=0, got rc=$rc: $out"; return 0; fi
  for n in "$@"; do
    if ! has "$n"; then fail "$name" "missing '$n' in: $out"; return 0; fi
  done
  pass "$name"
}

# fail_case <name> <want-rc> <status> <reason> [forbidden]...: exact non-zero rc.
fail_case() {
  local name="$1" want="$2" st="$3" reason="$4" n
  shift 4
  if [[ $rc -eq 0 || $rc -ne $want ]]; then fail "$name" "expected rc=$want (non-zero), got rc=$rc: $out"; return 0; fi
  if ! has "status=$st" || ! has "reason=$reason"; then fail "$name" "expected status=$st reason=$reason, got: $out"; return 0; fi
  for n in "$@"; do
    if has "$n"; then fail "$name" "forbidden '$n' present in: $out"; return 0; fi
  done
  pass "$name"
}

# --- main fixture -------------------------------------------------------------

DB="$TMP_DIR/main.sqlite"
mkdb "$DB"
addcombo "$DB" economy  '["ocg/deepseek-v4.1-flash","ocg/glm-5.3-flash","ocg/kimi-k2.7-code"]'
addcombo "$DB" standard '["ocg/kimi-k2.7-code","cx/gpt-5.6-luna","ocg/gpt-5.6-luna","oc-dmas/gpt-5.6-luna"]'
addcombo "$DB" strong   '["cc/claude-sonnet-5-5","dmas/claude-sonnet-5-5","cx/gpt-5.6-sol","oc-dmas/gpt-5.6-sol"]'
addcombo "$DB" mixed-combo '["cc/claude-sonnet-5-5","ocg/kimi-k2.7-code"]'

adduse "$DB" 1  "'opencode-go'" "'kimi-k2.7-code'"
adduse "$DB" 2  "'opencode-go'" "'kimi-k2.7-code'"
adduse "$DB" 3  "'opencode-go'" "'kimi-k2.7-code'" error
adduse "$DB" 4  "'opencode-go'" "'deepseek-v4.1-flash'"
adduse "$DB" 10 "'claude'" "'claude-sonnet-5-5'"
adduse "$DB" 11 "'claude'" "'claude-sonnet-5-5'"
adduse "$DB" 12 "'anthropic-compatible-abc123'" "'claude-sonnet-5-5'"
adduse "$DB" 20 "'opencode-go'" "'kimi-k2.7-code'"
adduse "$DB" 21 "'claude'" "'claude-sonnet-5-5'"

cp "$DB" "$TMP_DIR/main.orig"
orig_sum=$(sha "$DB")
orig_size=$(fsize "$DB")

# --- positive cases (rc must be 0) -------------------------------------------

run "$DB" 0 9 standard
ok_case "standard resolves non-claude" status=resolved family=non-claude reviewer=review-claude models=kimi-k2.7-code providers=opencode-go usage_ids=1,2 window=0-9

run "$DB" 9 19 strong
ok_case "strong resolves claude (claude + anthropic-compatible providers)" status=resolved family=claude reviewer=review-openai models=claude-sonnet-5-5 providers=anthropic-compatible-abc123,claude usage_ids=10,11,12

run "$DB" 0 9 economy
ok_case "multiple same-family rows" status=resolved family=non-claude usage_ids=1,2,4

run "$DB" 10 19 strong
ok_case "rows at or below start-id ignored" status=resolved usage_ids=11,12
has "usage_ids=10" && fail "start-id boundary exclusive" "$out" || pass "start-id boundary exclusive"

run "$DB" 2 9 economy
ok_case "non-ok status rows ignored" status=resolved usage_ids=4

run "$DB" 0 21 strong
ok_case "unrelated models ignored" status=resolved models=claude-sonnet-5-5 usage_ids=10,11,12,21
has "kimi" && fail "unrelated models not leaked" "$out" || pass "unrelated models not leaked"

run "$DB" 0 11 strong
ok_case "rows after end-id ignored" status=resolved usage_ids=10,11 window=0-11
has "12" && fail "end-id boundary inclusive-only" "$out" || pass "end-id boundary inclusive-only"

run "$DB" 0 100 standard
ok_case "wide window includes later rows" status=resolved usage_ids=1,2,20

# --- failure cases (rc exact, non-zero) --------------------------------------

run "$DB" 19 21 mixed-combo
fail_case "mixed families ambiguous" 5 ambiguous MODEL_DETECTION_AMBIGUOUS
run "$DB" 999 1000 mixed-combo
fail_case "no matching rows" 4 failed MODEL_DETECTION_FAILED
run "$DB" 5 5 standard
fail_case "empty window (start==end) finds nothing" 4 failed MODEL_DETECTION_FAILED
run "$DB" 0 9 unknown-combo
fail_case "unknown combo" 3 failed COMBO_NOT_FOUND
run "$DB"
fail_case "missing args" 2 failed USAGE
run "$DB" 0 9
fail_case "two args (old interface)" 2 failed USAGE
run "$DB" abc 9 strong
fail_case "non-integer start" 2 failed INVALID_CHECKPOINT
run "$DB" 0 -1 strong
fail_case "negative end" 2 failed INVALID_CHECKPOINT
run "$DB" 0 "" strong
fail_case "empty end" 2 failed INVALID_CHECKPOINT
run "$DB" 10 5 strong
fail_case "invalid window end<start" 2 failed INVALID_WINDOW
run "$DB" 0 9 'evil;name'
fail_case "invalid combo name (not reflected)" 2 failed INVALID_COMBO_NAME "evil"
run "$DB" 0 9 $'a\nstatus=resolved'
fail_case "invalid combo name newline (not reflected)" 2 failed INVALID_COMBO_NAME "status=resolved"
run "$TMP_DIR/missing.sqlite" 0 9 strong
fail_case "missing DB" 2 failed DB_NOT_FOUND

# --- extra DBs ----------------------------------------------------------------

X="$TMP_DIR/x.sqlite"

mkdb "$X"
addcombo "$X" mixedcase '["CC/Claude-Sonnet-5-5"]'
adduse "$X" 1 "'Claude'" "'CLAUDE-Sonnet-5-5'"
run "$X" 0 9 mixedcase
ok_case "mixed-case claude identity" status=resolved family=claude reviewer=review-openai models=CLAUDE-Sonnet-5-5

mkdb "$X"
addcombo "$X" mixedgpt '["CX/GPT-5.6-Sol"]'
adduse "$X" 1 "'CODEX'" "'gpt-5.6-SOL'"
run "$X" 0 9 mixedgpt
ok_case "mixed-case non-claude allowlist" status=resolved family=non-claude reviewer=review-claude

mkdb "$X"
addcombo "$X" unk '["ocg/mystery-model"]'
adduse "$X" 1 "'opencode-go'" "'mystery-model'"
run "$X" 0 9 unk
fail_case "unknown family fails closed" 7 failed MODEL_FAMILY_UNKNOWN "family=non-claude"

mkdb "$X"
addcombo "$X" both '["cc/claude-gpt-hybrid"]'
adduse "$X" 1 "'claude'" "'claude-gpt-hybrid'"
run "$X" 0 9 both
fail_case "claude+allowlist both match fails closed" 7 failed MODEL_FAMILY_UNKNOWN

# Provider/model basename collision: same model name from a provider the route does not map to.
mkdb "$X"
addcombo "$X" coll '["ocg/gpt-6-luna"]'
adduse "$X" 1 "'opencode-go'" "'gpt-6-luna'"
adduse "$X" 2 "'codex'" "'gpt-6-luna'"
run "$X" 0 1 coll
ok_case "collision: exact provider row alone resolves" status=resolved providers=opencode-go usage_ids=1
run "$X" 0 9 coll
fail_case "collision: other-provider same-basename row fails" 8 failed MODEL_ATTRIBUTION_UNKNOWN
run "$X" 1 2 coll
fail_case "collision: only other-provider row fails" 8 failed MODEL_ATTRIBUTION_UNKNOWN

# Duplicate candidate basenames across routes must not weaken attribution.
mkdb "$X"
addcombo "$X" dup '["ocg/gpt-6-luna","cx/gpt-6-luna"]'
adduse "$X" 1 "'opencode-go'" "'gpt-6-luna'"
adduse "$X" 2 "'codex'" "'gpt-6-luna'"
adduse "$X" 3 "'claude'" "'gpt-6-luna'"
run "$X" 0 2 dup
ok_case "duplicate basenames: both mapped providers resolve" status=resolved providers=codex,opencode-go
run "$X" 2 3 dup
fail_case "duplicate basenames: unlisted provider still fails" 8 failed MODEL_ATTRIBUTION_UNKNOWN

mkdb "$X"
addcombo "$X" dupunm '["ocg/gpt-6-luna","zz/gpt-6-luna"]'
adduse "$X" 1 "'opencode-go'" "'gpt-6-luna'"
run "$X" 0 9 dupunm
fail_case "duplicate basenames: unmapped sibling prefix fails closed" 8 failed MODEL_ATTRIBUTION_UNKNOWN

# Attribution unavailable: unmapped prefix, NULL provider, wrong-family provider.
mkdb "$X"
addcombo "$X" unmapped '["zz/kimi-k2.7-code"]'
adduse "$X" 1 "'opencode-go'" "'kimi-k2.7-code'"
run "$X" 0 9 unmapped
fail_case "unmapped route prefix" 8 failed MODEL_ATTRIBUTION_UNKNOWN

mkdb "$X"
addcombo "$X" nullp '["ocg/kimi-k2.7-code"]'
adduse "$X" 1 NULL "'kimi-k2.7-code'"
run "$X" 0 9 nullp
fail_case "NULL provider" 8 failed MODEL_ATTRIBUTION_UNKNOWN

mkdb "$X"
addcombo "$X" wrongprov '["cc/claude-sonnet-5-5"]'
adduse "$X" 1 "'codex'" "'claude-sonnet-5-5'"
run "$X" 0 9 wrongprov
fail_case "claude model via non-claude route provider" 8 failed MODEL_ATTRIBUTION_UNKNOWN

# Combo JSON problems.
for spec in 'malformed|["ocg/kimi-k2.7-code"' 'notjson|not json' 'empty|[]' 'noslash|["kimi"]' 'badchar|["ocg/ki mi"]' 'escape|["ocg/k\\"x"]' 'nested|[["ocg/kimi"]]' 'emptystr|[""]'; do
  mkdb "$X"
  addcombo "$X" "${spec%%|*}" "${spec#*|}"
  run "$X" 0 9 "${spec%%|*}"
  fail_case "combo JSON ${spec%%|*}" 6 failed MODEL_PARSE_FAILED
done

# Unsafe provider values must never reach output.
mkdb "$X"
addcombo "$X" unsafe '["ocg/kimi-k2.7-code"]'
adduse "$X" 1 "'opencode-go'||char(10)||'status=resolved'" "'kimi-k2.7-code'"
run "$X" 0 9 unsafe
fail_case "unsafe newline provider" 9 failed UNSAFE_OUTPUT_VALUE "family=" "usage_ids="
has "status=resolved" && fail "newline injection absent" "$out" || pass "newline injection absent"
for ch in "char(13)" "char(9)" "'|'" "','" "'='" "' '" "';'" "char(0xe9)"; do
  mkdb "$X"
  addcombo "$X" unsafe '["ocg/kimi-k2.7-code"]'
  adduse "$X" 1 "'opencode-go'||$ch" "'kimi-k2.7-code'"
  run "$X" 0 9 unsafe
  fail_case "unsafe provider delimiter $ch" 9 failed UNSAFE_OUTPUT_VALUE "family="
done

# sqlite/schema/query failures.
sqlite3 "$X" "DROP TABLE usageHistory;"
run "$X" 0 9 unsafe
fail_case "missing usageHistory table" 6 failed RUNTIME_ERROR

mkdb "$X"
addcombo "$X" ok1 '["ocg/kimi-k2.7-code"]'
sqlite3 "$X" "ALTER TABLE usageHistory RENAME COLUMN status TO state;"
run "$X" 0 9 ok1
fail_case "schema drift (status column missing)" 6 failed RUNTIME_ERROR

sqlite3 "$X" "DROP TABLE combos;"
run "$X" 0 9 ok1
fail_case "missing combos table" 6 failed RUNTIME_ERROR

printf 'this is not a sqlite database\n' > "$TMP_DIR/garbage.sqlite"
run "$TMP_DIR/garbage.sqlite" 0 9 strong
fail_case "non-sqlite file" 6 failed RUNTIME_ERROR

# --- cross-cutting ------------------------------------------------------------

# No secret material in any output captured so far.
if [[ "$all_out" != *"$SENTINEL"* && "$all_out" != *apiKey* && "$all_out" != *endpoint* && "$all_out" != *connectionId* && "$all_out" != *example.invalid* ]]; then
  pass "no secrets emitted"
else
  fail "secrets leaked in output"
fi

# Read-only proof: size + checksum + byte-for-byte content of the main fixture.
if [[ "$(sha "$DB")" == "$orig_sum" && "$(fsize "$DB")" == "$orig_size" ]] && cmp -s "$DB" "$TMP_DIR/main.orig"; then
  pass "DB unchanged (size, checksum, content)"
else
  fail "DB changed during tests"
fi

# Portable helper sanity.
[[ "$(fsize "$TMP_DIR/garbage.sqlite")" == "30" ]] && pass "portable file-size helper" || fail "portable file-size helper" "got $(fsize "$TMP_DIR/garbage.sqlite")"

# set -e arithmetic compatibility: no bare ((...)) statements in harness or resolver.
if grep -nE '^[[:space:]]*\(\(' "$SELF" "$RESOLVER" >/dev/null; then
  fail "no bare (( )) arithmetic statements"
else
  pass "no bare (( )) arithmetic statements"
fi
( set -e; n=0; n=$((n + 1)); n=$((n + 1)); [[ $n -eq 2 ]] ) && pass "set -e arithmetic increment" || fail "set -e arithmetic increment"

# Resolver static checks: no write SQL, no JSON1.
if grep -vE '^[[:space:]]*#' "$RESOLVER" | grep -iE '\b(INSERT|UPDATE|DELETE|REPLACE|CREATE|DROP|ALTER|VACUUM|ATTACH)\b' >/dev/null; then
  fail "resolver contains write SQL keyword"
else
  pass "resolver contains no write SQL"
fi
if grep -vE '^[[:space:]]*#' "$RESOLVER" | grep -iE 'json_each|json_extract' >/dev/null; then
  fail "resolver depends on JSON1"
else
  pass "resolver does not depend on JSON1"
fi
grep -q -- '-readonly' "$RESOLVER" && grep -q 'query_only=1' "$RESOLVER" && pass "resolver uses -readonly and query_only" || fail "resolver read-only flags"

echo ""
echo "Results: $cases_passed passed, $cases_failed failed"
[[ $cases_failed -eq 0 ]] || exit 1
exit 0
