#!/usr/bin/env bash
# test-review-route.sh — deterministic checks for v3b.2 (review-route.sh + orchestrator instructions).
# Cases A-J. Uses temp SQLite DBs and stub resolvers only; never touches ~/.9router.
# bash 3.2+, no frameworks.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
RR="$HERE/review-route.sh"
ORCH="$ROOT/integrations/opencode/agents/orchestrator.md"
CMD="$ROOT/integrations/opencode/commands/implement-spec.md"
README="$ROOT/integrations/opencode/README.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"   # a stray default-DB lookup can never reach the real store
mkdir -p "$HOME"

pass=0; failn=0
ok() { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { failn=$((failn + 1)); echo "FAIL: $1"; }
eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
has() { if grep -qF -- "$3" "$2"; then ok "$1"; else bad "$1 (missing: $3)"; fi; }
hasnot() { if grep -qF -- "$3" "$2"; then bad "$1 (found: $3)"; else ok "$1"; fi; }

DB="$TMP/t.sqlite"
sqlite3 "$DB" "CREATE TABLE usageHistory (id INTEGER PRIMARY KEY AUTOINCREMENT, provider TEXT, model TEXT, apiKey TEXT, status TEXT);
INSERT INTO usageHistory(provider,model,apiKey,status) VALUES ('codex','gpt-5.6-sol','SECRET','ok'),('codex','gpt-5.6-sol','SECRET','ok'),('codex','gpt-5.6-sol','SECRET','ok');"

stub() { # stub <name> <stdout> <exit>
  printf '#!/usr/bin/env bash\nprintf "%%b" %q\nexit %s\n' "$2" "$3" > "$TMP/$1"; chmod +x "$TMP/$1"; echo "$TMP/$1"
}
route() { # route <resolver> -> sets out, rc
  out=$(NINEROUTER_DB="$DB" DEV_AGENTS_RESOLVER="$1" "$RR" resolve 3 5 strong 2>/dev/null); rc=$?
}
RES_OK='status=resolved\ncombo=strong\nwindow=3-5\nfamily=%s\nreviewer=%s\nmodels=m1\nproviders=p1\nusage_ids=4,5\n'

# --- A: review not required => resolution skipped, no reviewer (instruction contract)
has A1 "$ORCH" "Model resolution: skipped (independent review not required)"
has A2 "$CMD" "Model resolution: skipped (independent review not required)"
has A3 "$ORCH" "If review is not required: skip model resolution"
has A4 "$ORCH" "state no family"

# --- B: claude => review-openai
route "$(stub s_claude "$(printf "$RES_OK" claude review-openai)" 0)"
eq B1 "$rc" 0
has_line() { printf '%s\n' "$out" | grep -qxF -- "$2" && ok "$1" || bad "$1 (missing line $2 in: $out)"; }
has_line B2 "model_resolution=resolved"; has_line B3 "family=claude"; has_line B4 "reviewer=review-openai"
has_line B5 "models=m1"; has_line B6 "providers=p1"

# --- C: non-claude => review-claude
route "$(stub s_non "$(printf "$RES_OK" non-claude review-claude)" 0)"
eq C1 "$rc" 0
has_line C2 "family=non-claude"; has_line C3 "reviewer=review-claude"

# --- D/E/F: resolver failure states => blocked with reason, no reviewer/family in output
blocked_case() { # id reason stdout exit
  route "$(stub "s_$1" "$3" "$4")"
  eq "$1 rc" "$rc" 3
  has_line "$1 status" "status=REVIEW_BLOCKED_MODEL_RESOLUTION"
  has_line "$1 reason" "reason=$2"
  case "$out" in *reviewer=*|*family=*) bad "$1 leaked reviewer/family" ;; *) ok "$1 no reviewer/family" ;; esac
}
blocked_case D MODEL_DETECTION_AMBIGUOUS 'status=ambiguous\ncombo=strong\nreason=MODEL_DETECTION_AMBIGUOUS\nmodels=a,b\nfamilies=claude,non-claude\nproviders=x,y\n' 5
blocked_case E MODEL_FAMILY_UNKNOWN 'status=failed\nreason=MODEL_FAMILY_UNKNOWN\n' 7
blocked_case F MODEL_ATTRIBUTION_UNKNOWN 'status=failed\nreason=MODEL_ATTRIBUTION_UNKNOWN\n' 8
blocked_case F2 MODEL_DETECTION_FAILED 'status=failed\ncombo=strong\nreason=MODEL_DETECTION_FAILED\n' 4
blocked_case F3 UNSAFE_OUTPUT_VALUE 'status=failed\nreason=UNSAFE_OUTPUT_VALUE\n' 9
blocked_case F4 RUNTIME_ERROR 'status=failed\nreason=RUNTIME_ERROR\n' 6
blocked_case F5 RESOLVER_OUTPUT_INVALID 'garbage without keys\n' 0
blocked_case F6 RESOLVER_OUTPUT_INVALID '' 0
blocked_case F7 RESOLVER_OUTPUT_INVALID 'status=failed\n' 6
blocked_case F8 RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m\nproviders=p\n' 6
blocked_case F9 RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nreviewer=review-claude\nmodels=m\nproviders=p\n' 0
blocked_case F10 RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m\nproviders=p\nextra=1\n' 0
blocked_case F11 RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nfamily=claude\nreviewer=review-openai\nmodels=m\nproviders=p\n' 0
blocked_case F12 RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=martian\nreviewer=review-openai\nmodels=m\nproviders=p\n' 0
blocked_case F13 RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=9-9\nfamily=claude\nreviewer=review-openai\nmodels=m\nproviders=p\n' 0
route "$TMP/does-not-exist"; eq F14 "$rc" 3; has_line F15 "reason=RESOLVER_UNAVAILABLE"

# --- G: family/reviewer mismatch => fail closed
blocked_case G1 RESOLVER_OUTPUT_INVALID "$(printf "$RES_OK" claude review-claude)" 0
blocked_case G2 RESOLVER_OUTPUT_INVALID "$(printf "$RES_OK" non-claude review-openai)" 0

# --- window validation in resolve
out=$(DEV_AGENTS_RESOLVER="$(stub s_claude2 "$(printf "$RES_OK" claude review-openai)" 0)" "$RR" resolve 5 3 strong); eq G3 "$?" 3
out=$(DEV_AGENTS_RESOLVER="$(stub s_claude3 "$(printf "$RES_OK" claude review-openai)" 0)" "$RR" resolve x 3 strong); eq G4 "$?" 3

# --- real resolver on a temp DB end to end (routing comes from the resolver, not this test)
sqlite3 "$DB" "CREATE TABLE combos (id TEXT PRIMARY KEY, name TEXT UNIQUE NOT NULL, kind TEXT, models TEXT NOT NULL, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL);
INSERT INTO combos VALUES ('1','strong',NULL,'[\"cx/gpt-5.6-sol\",\"cc/claude-sonnet-5-5\"]','t','t');"
out=$(NINEROUTER_DB="$DB" "$RR" resolve 0 3 strong 2>/dev/null); rc=$?
eq G5 "$rc" 0; has_line G6 "family=non-claude"; has_line G7 "reviewer=review-claude"
sqlite3 "$DB" "INSERT INTO usageHistory(provider,model,apiKey,status) VALUES ('claude','claude-sonnet-5-5','SECRET','ok');"
out=$(NINEROUTER_DB="$DB" "$RR" resolve 0 4 strong 2>/dev/null); rc=$?
eq G8 "$rc" 3; has_line G9 "reason=MODEL_DETECTION_AMBIGUOUS"
case "$out" in *SECRET*) bad "G10 secret leaked" ;; *) ok "G10 no secret in output" ;; esac

# --- checkpoint success + H: checkpoint failures => no fallback
out=$(NINEROUTER_DB="$DB" "$RR" checkpoint start 2>&1); rc=$?
eq H0 "$rc" 0; eq H0b "$out" 4
ck_fail() { # id label env-db
  out=$(NINEROUTER_DB="$3" "$RR" checkpoint "$2" 2>/dev/null); rc=$?
  eq "$1 rc" "$rc" 2
  case "$out" in *status=failed*"reason=$(printf '%s' "$2" | tr a-z A-Z)_CHECKPOINT_FAILED"*) ok "$1 reason" ;; *) bad "$1 reason (got: $out)" ;; esac
  case "$out" in *[0-9]*) bad "$1 emitted a number" ;; *) ok "$1 no id emitted" ;; esac
}
ck_fail H1 start "$TMP/missing.sqlite"
ck_fail H2 end "$TMP/missing.sqlite"
echo "not a database" > "$TMP/garbage.sqlite"; ck_fail H3 start "$TMP/garbage.sqlite"
sqlite3 "$TMP/nousage.sqlite" "CREATE TABLE other(x);"; ck_fail H4 end "$TMP/nousage.sqlite"
cp "$DB" "$TMP/unread.sqlite"; chmod 000 "$TMP/unread.sqlite"
if [[ -r "$TMP/unread.sqlite" ]]; then ok "H5 skipped (running as a user that can read mode 000)"; else ck_fail H5 start "$TMP/unread.sqlite"; fi
mkdir -p "$TMP/bin"; printf '#!/usr/bin/env bash\necho "not-an-int"\n' > "$TMP/bin/sqlite3"; chmod +x "$TMP/bin/sqlite3"
out=$(PATH="$TMP/bin:$PATH" NINEROUTER_DB="$DB" "$RR" checkpoint start 2>/dev/null); rc=$?
eq H6 "$rc" 2
printf '#!/usr/bin/env bash\necho 5\necho extra\n' > "$TMP/bin/sqlite3"
out=$(PATH="$TMP/bin:$PATH" NINEROUTER_DB="$DB" "$RR" checkpoint end 2>/dev/null); rc=$?
eq H7 "$rc" 2
has H8 "$ORCH" "do NOT delegate"
has H9 "$ORCH" "END_CHECKPOINT_FAILED"
has H10 "$CMD" "START_CHECKPOINT_FAILED"
# checkpoint SQL is read-only and touches nothing else
has H11 "$RR" 'SELECT COALESCE(MAX(id),0) FROM usageHistory;'
has H12 "$RR" '-init /dev/null -batch -list -noheader -readonly'
hasnot H13 "$RR" 'apiKey'
hasnot H14 "$RR" 'INSERT'

# --- I: v3a semantics preserved
for f in "$ORCH" "$CMD"; do
  n=$(basename "$f")
  has "I1 $n fresh" "$f" "fresh"
  has "I2 $n read-only" "$f" "read-only"
  has "I3 $n verdict" "$f" "PASS_WITH_NOTES"
  has "I4 $n no auto-fix" "$f" "Do not automatically"
  has "I5 $n no push" "$f" "push, merge"
  has "I6 $n no self-report" "$f" "self-report"
  has "I7 $n blocked status" "$f" "REVIEW_BLOCKED_MODEL_RESOLUTION"
  has "I8 $n no infer" "$f" "ever infer"
done
has I9 "$CMD" "Do not use \`REVIEW_BLOCKED_MODEL_UNKNOWN\` here"
has I10 "$ORCH" "Do not use REVIEW_BLOCKED_MODEL_UNKNOWN for resolver failures"
has I11 "$ORCH" "Do not subtract, filter, or guess"

# --- J: report template
for f in "$ORCH" "$CMD"; do
  n=$(basename "$f")
  for k in "Review decision reason" "Start checkpoint" "End checkpoint" "Model resolution" "Model resolution reason" "Actual family" "Reviewer" "Verdict"; do
    has "J $n: $k" "$f" "$k"
  done
done
has J2 "$ORCH" "Start checkpoint: 2801"
has J3 "$ORCH" "End checkpoint: 2812"
has J4 "$ORCH" "Actual models and providers: kimi-k2.7-code"
has J5 "$ORCH" "Actual family: non-claude"
has J6 "$ORCH" "Reviewer: review-claude"
has J7 "$ORCH" "Verdict: PASS"
has J8 "$ORCH" "Model resolution reason: MODEL_DETECTION_AMBIGUOUS"
has J9 "$ORCH" "Independent review: REVIEW_BLOCKED_MODEL_RESOLUTION"

# --- README wording corrected
hasnot R1 "$README" "keeps later orchestrator traffic out of the window"
hasnot R2 "$README" "Traffic after \`end-id\` (including the orchestrator's own) is excluded"
hasnot R3 "$README" "integration comes later"
has R4 "$README" "REVIEW_BLOCKED_MODEL_RESOLUTION"
has R5 "$README" "correlation id"

# --- orchestrator permissions front matter unchanged vs the v3b.1 baseline commit (526df80)
head_fm=$(git -C "$ROOT" show 526df80:integrations/opencode/agents/orchestrator.md 2>/dev/null | awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f')
cur_fm=$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' "$ORCH")
if [[ -z "$head_fm" ]]; then bad "P1 cannot read baseline front matter"; else eq P1 "$cur_fm" "$head_fm"; fi

echo "passed=$pass failed=$failn"
[[ $failn -eq 0 ]]
