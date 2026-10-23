#!/usr/bin/env bash
# test-review-route.sh — deterministic checks for v3b.2 (review-route.sh + orchestrator instructions).
# Cases A-L. Uses temp SQLite DBs and stub resolvers only; never touches ~/.9router.
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

# Normalize extracted YAML frontmatter for stable comparison: strip trailing
# whitespace only (spaces, tabs, CR). Leading whitespace is preserved because
# YAML indentation is significant. This is textual normalization, not a full
# YAML parse, so it ignores only trailing-whitespace-only differences.
norm_fm() { sed -e 's/[[:space:]]*$//'; }

DB="$TMP/t.sqlite"
sqlite3 "$DB" "CREATE TABLE usageHistory (id INTEGER PRIMARY KEY AUTOINCREMENT, provider TEXT, model TEXT, apiKey TEXT, status TEXT);
INSERT INTO usageHistory(provider,model,apiKey,status) VALUES ('codex','gpt-5.6-sol','SECRET','ok'),('codex','gpt-5.6-sol','SECRET','ok'),('codex','gpt-5.6-sol','SECRET','ok');"

stub() { # stub <name> <stdout> <exit>
  printf '#!/usr/bin/env bash\nprintf "%%b" %q\nexit %s\n' "$2" "$3" > "$TMP/$1"; chmod +x "$TMP/$1"; echo "$TMP/$1"
}
route() { # route <resolver> -> sets out, rc
  out=$(NINEROUTER_DB="$DB" DEV_AGENTS_RESOLVER="$1" "$RR" resolve 3 5 strong 2>/dev/null); rc=$?
}
route_err() { # route_err <resolver> -> sets out, err, rc
  local efile="$TMP/route_err_$$"
  out=$(NINEROUTER_DB="$DB" DEV_AGENTS_RESOLVER="$1" "$RR" resolve 3 5 strong 2>"$efile"); rc=$?
  err=$(cat "$efile"); rm -f "$efile"
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

# --- D-G: resolver failure states and schema tightening => blocked with a fixed reason, no reviewer/family
blocked_case() { # id reason stdout exit
  route "$(stub "s_$1" "$3" "$4")"
  eq "$1 rc" "$rc" 3
  has_line "$1 status" "status=REVIEW_BLOCKED_MODEL_RESOLUTION"
  has_line "$1 reason" "reason=$2"
  case "$out" in *reviewer=*|*family=*) bad "$1 leaked reviewer/family" ;; *) ok "$1 no reviewer/family" ;; esac
}
# leak_check <id> <resolver> <expected_rc>: assert TMPDIR is honored and the temp file is removed
# on both success and blocked exit paths, and that stderr is empty.
check_no_leak() {
  local ldir="$TMP/leak_$1" efile="$TMP/leak_err_$1"
  mkdir -p "$ldir"
  out=$(TMPDIR="$ldir" NINEROUTER_DB="$DB" DEV_AGENTS_RESOLVER="$2" "$RR" resolve 3 5 strong 2>"$efile"); rc=$?
  err=$(cat "$efile"); rm -f "$efile"
  eq "$1 rc" "$rc" "$3"
  [[ -z "$err" ]] && ok "$1 stderr empty" || bad "$1 stderr not empty: $err"
  if [[ -n $(find "$ldir" -mindepth 1 -print -quit) ]]; then bad "$1 temp file leaked"; else ok "$1 no temp leak"; fi
}
# resolved_out <family> <reviewer> [extra "k=v\n" to append]; build one valid resolved body
res() { printf 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=%s\nreviewer=%s\nmodels=m1\nproviders=p1\nusage_ids=4,5\n%b' "$1" "$2" "${3:-}"; }
# same body, but with no terminating newline (framing tests)
res_noterm() { printf 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=%s\nreviewer=%s\nmodels=m1\nproviders=p1\nusage_ids=4,5%b' "$1" "$2" "${3:-}"; }
AMBIG='status=ambiguous\ncombo=strong\nreason=MODEL_DETECTION_AMBIGUOUS\nmodels=a,b\nfamilies=claude,non-claude\nproviders=x,y\n'

# 13: documented ambiguous schema
blocked_case D MODEL_DETECTION_AMBIGUOUS "$AMBIG" 5
blocked_case D2 RESOLVER_OUTPUT_INVALID "$AMBIG" 0
blocked_case D3 RESOLVER_OUTPUT_INVALID "${AMBIG}extra=1\n" 5
blocked_case D4 RESOLVER_OUTPUT_INVALID 'status=ambiguous\ncombo=strong\nreason=MODEL_DETECTION_AMBIGUOUS\nmodels=a,b\nproviders=x,y\n' 5
blocked_case D5 RESOLVER_OUTPUT_INVALID 'status=ambiguous\ncombo=other\nreason=MODEL_DETECTION_AMBIGUOUS\nmodels=a,b\nfamilies=claude,non-claude\nproviders=x,y\n' 5
blocked_case D6 RESOLVER_OUTPUT_INVALID 'status=ambiguous\ncombo=strong\nreason=MODEL_DETECTION_AMBIGUOUS\nmodels=a,b\nfamilies=claude\nproviders=x,y\n' 5
blocked_case D7 RESOLVER_OUTPUT_INVALID "${AMBIG}family=claude\n" 5
# 11: status/reason and exit-code mismatches
blocked_case D8 RESOLVER_OUTPUT_INVALID 'status=ambiguous\ncombo=strong\nreason=MODEL_FAMILY_UNKNOWN\nmodels=a,b\nfamilies=claude,non-claude\nproviders=x,y\n' 5
blocked_case D9 RESOLVER_OUTPUT_INVALID 'status=failed\nreason=MODEL_DETECTION_AMBIGUOUS\n' 5
blocked_case D10 RESOLVER_OUTPUT_INVALID 'status=failed\ncombo=strong\nreason=MODEL_DETECTION_AMBIGUOUS\nmodels=a,b\nfamilies=claude,non-claude\nproviders=x,y\n' 5
blocked_case D11 RESOLVER_OUTPUT_INVALID 'status=failed\nreason=MODEL_FAMILY_UNKNOWN\n' 8
blocked_case D12 RESOLVER_OUTPUT_INVALID 'status=failed\nreason=MODEL_FAMILY_UNKNOWN\n' 0
blocked_case D13 RESOLVER_OUTPUT_INVALID 'status=resolved\nreason=MODEL_FAMILY_UNKNOWN\n' 7

# 12: each documented failed status/reason => blocked with that reason (documented exit code)
blocked_case E MODEL_FAMILY_UNKNOWN 'status=failed\nreason=MODEL_FAMILY_UNKNOWN\n' 7
blocked_case F MODEL_ATTRIBUTION_UNKNOWN 'status=failed\nreason=MODEL_ATTRIBUTION_UNKNOWN\n' 8
blocked_case F2 MODEL_DETECTION_FAILED 'status=failed\ncombo=strong\nreason=MODEL_DETECTION_FAILED\n' 4
blocked_case F3 UNSAFE_OUTPUT_VALUE 'status=failed\nreason=UNSAFE_OUTPUT_VALUE\n' 9
blocked_case F4 RUNTIME_ERROR 'status=failed\nreason=RUNTIME_ERROR\n' 6
blocked_case F4b MODEL_PARSE_FAILED 'status=failed\nreason=MODEL_PARSE_FAILED\n' 6
blocked_case F4c COMBO_NOT_FOUND 'status=failed\ncombo=strong\nreason=COMBO_NOT_FOUND\n' 3
for r in USAGE INVALID_CHECKPOINT INVALID_WINDOW INVALID_COMBO_NAME SQLITE3_NOT_FOUND DB_NOT_FOUND DB_NOT_READABLE; do
  blocked_case "F4-$r" "$r" "status=failed\nreason=$r\n" 2
done
# failed-schema violations: missing/extra combo, wrong combo, wrong exit code, extra key
blocked_case F4d RESOLVER_OUTPUT_INVALID 'status=failed\nreason=COMBO_NOT_FOUND\n' 3
blocked_case F4e RESOLVER_OUTPUT_INVALID 'status=failed\ncombo=strong\nreason=MODEL_FAMILY_UNKNOWN\n' 7
blocked_case F4f RESOLVER_OUTPUT_INVALID 'status=failed\ncombo=other\nreason=MODEL_DETECTION_FAILED\n' 4
blocked_case F4g RESOLVER_OUTPUT_INVALID 'status=failed\nreason=USAGE\n' 3
blocked_case F4h RESOLVER_OUTPUT_INVALID 'status=failed\nreason=RUNTIME_ERROR\nextra=1\n' 6
blocked_case F4i RESOLVER_OUTPUT_INVALID 'status=failed\nreason=RUNTIME_ERROR\nreason=RUNTIME_ERROR\n' 6
blocked_case F4j RESOLVER_OUTPUT_INVALID 'status=failed\nreason=RUNTIME_ERROR\nfamily=claude\n' 6
# 9/10: undocumented status or reason
blocked_case F5 RESOLVER_OUTPUT_INVALID 'garbage without keys\n' 0
blocked_case F6 RESOLVER_OUTPUT_INVALID '' 0
blocked_case F7 RESOLVER_OUTPUT_INVALID 'status=failed\n' 6
blocked_case F7b RESOLVER_OUTPUT_INVALID 'status=banana\nreason=SOME_CODE\n' 6
blocked_case F7c RESOLVER_OUTPUT_INVALID 'status=banana\nreason=SOME_CODE\n' 0
blocked_case F7d RESOLVER_OUTPUT_INVALID 'status=failed\nreason=SOME_CODE\n' 6
blocked_case F7e RESOLVER_OUTPUT_INVALID 'status=failed\nreason=SOME_CODE\n' 2
blocked_case F7f RESOLVER_OUTPUT_INVALID 'status=failed\nreason=$(id)\n' 6

# 6/7/8: resolved exact schema (each case = a valid body with exactly one defect)
blocked_case F8 RESOLVER_OUTPUT_INVALID "$(res claude review-openai)" 6
blocked_case F8b RESOLVER_OUTPUT_INVALID "$(res claude review-openai)" 5
blocked_case F9 RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nreviewer=review-claude\nmodels=m\nproviders=p\nusage_ids=4\n' 0
blocked_case F9b RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nmodels=m\nproviders=p\nusage_ids=4\n' 0
blocked_case F9c RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nproviders=p1\nusage_ids=4\n' 0
blocked_case F9d RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m1\nusage_ids=4\n' 0
blocked_case F9e RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m1\nproviders=p1\n' 0
blocked_case F9f RESOLVER_OUTPUT_INVALID 'status=resolved\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m1\nproviders=p1\nusage_ids=4\n' 0
blocked_case F9g RESOLVER_OUTPUT_INVALID 'combo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m1\nproviders=p1\nusage_ids=4\n' 0
blocked_case F9h RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nfamily=claude\nreviewer=review-openai\nmodels=m1\nproviders=p1\nusage_ids=4\n' 0
blocked_case F10 RESOLVER_OUTPUT_INVALID "$(res claude review-openai 'extra=1\n')" 0
blocked_case F10b RESOLVER_OUTPUT_INVALID "$(res claude review-openai 'families=claude,non-claude\n')" 0
blocked_case F10c RESOLVER_OUTPUT_INVALID "$(res claude review-openai 'reason=MODEL_FAMILY_UNKNOWN\n')" 0
blocked_case F11 RESOLVER_OUTPUT_INVALID "$(res claude review-openai 'family=claude\n')" 0
blocked_case F11b RESOLVER_OUTPUT_INVALID "$(res claude review-openai 'status=resolved\n')" 0
blocked_case F11c RESOLVER_OUTPUT_INVALID "$(res claude review-openai 'reviewer=review-openai\n')" 0
blocked_case F11d RESOLVER_OUTPUT_INVALID "$(res claude review-openai 'models=m1\n')" 0
blocked_case F11e RESOLVER_OUTPUT_INVALID "$(res claude review-openai 'usage_ids=4\n')" 0
blocked_case F12 RESOLVER_OUTPUT_INVALID "$(res martian review-openai)" 0
blocked_case F13 RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=9-9\nfamily=claude\nreviewer=review-openai\nmodels=m\nproviders=p\nusage_ids=4\n' 0
blocked_case F13b RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=premium\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m\nproviders=p\nusage_ids=4\n' 0
blocked_case F13c RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m\nproviders=p\nusage_ids=a,b\n' 0
blocked_case F13d RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=\nproviders=p\nusage_ids=4\n' 0
blocked_case F13e RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m\nproviders=p\nusage_ids=\n' 0
blocked_case F13f RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m\nproviders=p\nusage_ids=4\nnot a kv line\n' 0
route "$TMP/does-not-exist"; eq F14 "$rc" 3; has_line F15 "reason=RESOLVER_UNAVAILABLE"
# window normalization: leading zeros in the request still match the resolver's numeric window
out=$(NINEROUTER_DB="$DB" DEV_AGENTS_RESOLVER="$(stub s_norm "$(res claude review-openai)" 0)" "$RR" resolve 003 005 strong 2>/dev/null); eq F16 "$?" 0

# --- FR: resolver stdout framing (blank-line detection)
# A: exactly one trailing newline (the normal case) => resolved
route "$(stub s_fra 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m1\nproviders=p1\nusage_ids=4,5\n' 0)"
eq FR1 "$rc" 0; has_line FR1a "model_resolution=resolved"; has_line FR1b "family=claude"; has_line FR1c "reviewer=review-openai"
# B: no trailing newline => resolved (final unterminated line is accepted)
route "$(stub s_frb "$(res_noterm claude review-openai)" 0)"
eq FR2 "$rc" 0; has_line FR2a "model_resolution=resolved"; has_line FR2b "family=claude"; has_line FR2c "reviewer=review-openai"
# C/D: extra trailing blank lines => RESOLVER_OUTPUT_INVALID
blocked_case FR3 RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m1\nproviders=p1\nusage_ids=4,5\n\n' 0
blocked_case FR4 RESOLVER_OUTPUT_INVALID 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m1\nproviders=p1\nusage_ids=4,5\n\n\n' 0
# E: leading blank line => RESOLVER_OUTPUT_INVALID
blocked_case FR5 RESOLVER_OUTPUT_INVALID '\nstatus=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m1\nproviders=p1\nusage_ids=4,5\n' 0
# F: blank line between records => RESOLVER_OUTPUT_INVALID
blocked_case FR6 RESOLVER_OUTPUT_INVALID 'status=resolved\n\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m1\nproviders=p1\nusage_ids=4,5\n' 0
# G: CRLF line endings => RESOLVER_OUTPUT_INVALID
blocked_case FR7 RESOLVER_OUTPUT_INVALID 'status=resolved\r\ncombo=strong\r\nwindow=3-5\r\nfamily=claude\r\nreviewer=review-openai\r\nmodels=m1\r\nproviders=p1\r\nusage_ids=4,5\r\n' 0
# H: reordered keys => accepted (keyset is sorted before comparison)
route "$(stub s_frh 'reviewer=review-openai\nfamily=claude\nmodels=m1\nproviders=p1\nusage_ids=4,5\ncombo=strong\nwindow=3-5\nstatus=resolved\n' 0)"
eq FR8 "$rc" 0; has_line FR8a "model_resolution=resolved"; has_line FR8b "family=claude"; has_line FR8c "reviewer=review-openai"
# framing also enforced for non-resolved statuses
blocked_case FR9 RESOLVER_OUTPUT_INVALID "${AMBIG}\n" 5
blocked_case FR10 RESOLVER_OUTPUT_INVALID 'status=failed\nreason=MODEL_FAMILY_UNKNOWN\n\n' 7
# temp-file cleanup on success and on blocked exit
check_no_leak FR11 "$(stub s_frok "$(res claude review-openai)" 0)" 0
check_no_leak FR12 "$(stub s_frbad 'status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m1\nproviders=p1\nusage_ids=4,5\n\n' 0)" 3
# positive stderr check on a normal success path (no TMPDIR override)
route_err "$(stub s_frok_stderr "$(res claude review-openai)" 0)"
eq FR13 "$rc" 0
[[ -z "$err" ]] && ok "FR13 stderr empty" || bad "FR13 stderr not empty: $err"

# 16: family/reviewer mismatch => fail closed
blocked_case G1 RESOLVER_OUTPUT_INVALID "$(res claude review-claude)" 0
blocked_case G2 RESOLVER_OUTPUT_INVALID "$(res non-claude review-openai)" 0

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
# --- 1/2: checkpoint failures always stop (behavior above; instructions below)
# Start failure: helper prints no integer (checked in ck_fail H1-H7); instructions must have no escape hatch.
for f in "$ORCH" "$CMD" "$README"; do
  n=$(basename "$f")
  for phrase in "certainly trivial" "Start checkpoint: unavailable" "skipped (not needed)" "End checkpoint: unavailable" "continue under the not-required path" "may proceed" "unless the start checkpoint"; do
    hasnot "K $n no exception text: $phrase" "$f" "$phrase"
  done
  has "K $n START_CHECKPOINT_FAILED" "$f" "START_CHECKPOINT_FAILED"
  has "K $n END_CHECKPOINT_FAILED" "$f" "END_CHECKPOINT_FAILED"
  has "K $n setup blocked" "$f" "Review/runtime setup: blocked"
  has "K $n model resolution blocked" "$f" "Model resolution: blocked"
  has "K $n end blocked status" "$f" "Independent review: REVIEW_BLOCKED_MODEL_RESOLUTION"
done
has K1 "$ORCH" "no valid start checkpoint => no implementation delegation"
has K2 "$ORCH" "launch none of economy/standard/strong/premium"
has K3 "$ORCH" "regardless of what the review decision would have been"
has K4 "$CMD" "launch none of economy/standard/strong/premium"
has K5 "$CMD" "stop blocked regardless of the eventual review decision"
# Not-required skip text exists only on the path reached after valid start and end checkpoints.
has K6 "$ORCH" "Only reached with a valid start_id and end_id"
# The end-checkpoint failure state is blocked, never a not-required success: helper never yields an id on failure.
out=$(NINEROUTER_DB="$TMP/missing.sqlite" "$RR" checkpoint end 2>/dev/null); rc=$?
eq K7 "$rc" 2
case "$out" in *status=failed*END_CHECKPOINT_FAILED*) ok "K8 end failure is END_CHECKPOINT_FAILED" ;; *) bad "K8 (got: $out)" ;; esac
out=$(NINEROUTER_DB="$TMP/missing.sqlite" "$RR" checkpoint start 2>/dev/null); rc=$?
eq K9 "$rc" 2
case "$out" in *START_CHECKPOINT_FAILED*) ok "K10 start failure is START_CHECKPOINT_FAILED" ;; *) bad "K10 (got: $out)" ;; esac

# --- 3/4/5: helper-resolution rule, executed from the block in orchestrator.md
BLOCK=$(awk '/^ *# helper-resolution$/{f=1} f&&/^ *```$/{exit} f{sub(/^ +/,""); print}' "$ORCH")
if [[ -n "$BLOCK" && "$BLOCK" == *'REVIEW_ROUTE_HELPER_UNAVAILABLE'* ]]; then ok "L0 helper-resolution block extracted"; else bad "L0 cannot extract helper-resolution block"; fi
export GIT_CEILING_DIRECTORIES="$TMP"
fake_helper() { mkdir -p "$(dirname "$1")"; printf '#!/usr/bin/env bash\necho fake\n' > "$1"; chmod +x "$1"; }
run_block() { # run_block <home> <cwd> -> sets bout, brc
  bout=$(cd "$2" && HOME="$1" bash -c "$BLOCK"$'\n''echo "RR=$RR"' 2>/dev/null); brc=$?
}
# 3: installed layout, cwd outside any repo
L3="$TMP/l3"; mkdir -p "$L3/home" "$L3/cwd"
fake_helper "$L3/home/.config/opencode/scripts/review-route.sh"
run_block "$L3/home" "$L3/cwd"
eq L3a "$brc" 0; eq L3b "$bout" "RR=$L3/home/.config/opencode/scripts/review-route.sh"
# installed non-executable helper is not used
chmod -x "$L3/home/.config/opencode/scripts/review-route.sh"
run_block "$L3/home" "$L3/cwd"
eq L3c "$brc" 1; eq L3d "$bout" "REVIEW_ROUTE_HELPER_UNAVAILABLE"
# 4: repo-local fallback (marker present), no installed helper
L4="$TMP/l4"; mkdir -p "$L4/home" "$L4/repo/integrations/opencode/agents" "$L4/repo/sub/dir"
git -C "$L4/repo" init -q
: > "$L4/repo/integrations/opencode/agents/orchestrator.md"
fake_helper "$L4/repo/integrations/opencode/scripts/review-route.sh"
run_block "$L4/home" "$L4/repo/sub/dir"
want="RR=$(cd "$L4/repo" && git rev-parse --show-toplevel)/integrations/opencode/scripts/review-route.sh"
eq L4a "$brc" 0; eq L4b "$bout" "$want"
# installed helper wins over the repo-local one
fake_helper "$L4/home/.config/opencode/scripts/review-route.sh"
run_block "$L4/home" "$L4/repo"
eq L4c "$bout" "RR=$L4/home/.config/opencode/scripts/review-route.sh"
# 5: no helper anywhere
L5="$TMP/l5"; mkdir -p "$L5/home" "$L5/cwd"
run_block "$L5/home" "$L5/cwd"
eq L5a "$brc" 1; eq L5b "$bout" "REVIEW_ROUTE_HELPER_UNAVAILABLE"
# repo without the dev-agents marker must not be used even if it holds an executable helper
mkdir -p "$L5/repo"; git -C "$L5/repo" init -q
fake_helper "$L5/repo/integrations/opencode/scripts/review-route.sh"
run_block "$L5/home" "$L5/repo"
eq L5c "$brc" 1; eq L5d "$bout" "REVIEW_ROUTE_HELPER_UNAVAILABLE"
# repo with the marker but a non-executable helper
mkdir -p "$L5/repo2/integrations/opencode/agents" "$L5/repo2/integrations/opencode/scripts"; git -C "$L5/repo2" init -q
: > "$L5/repo2/integrations/opencode/agents/orchestrator.md"; : > "$L5/repo2/integrations/opencode/scripts/review-route.sh"
run_block "$L5/home" "$L5/repo2"
eq L5e "$brc" 1; eq L5f "$bout" "REVIEW_ROUTE_HELPER_UNAVAILABLE"
# cwd directly in a plain directory containing only the relative path (no git): not used
mkdir -p "$L5/plain"; fake_helper "$L5/plain/integrations/opencode/scripts/review-route.sh"
run_block "$L5/home" "$L5/plain"
eq L5g "$brc" 1
unset GIT_CEILING_DIRECTORIES
# README states the same rule as the runtime block
ORDER_LINE=$(grep -F 'Order: (1) the installed' "$ORCH" | sed -e 's/^ *//' -e 's/ If neither is executable.*//')
if [[ -n "$ORDER_LINE" ]] && grep -qF -- "$ORDER_LINE" "$README"; then ok "L6 README lookup text matches orchestrator.md"; else bad "L6 README lookup text differs from orchestrator.md"; fi
# the command refers to the rule, does not restate paths
hasnot L7 "$CMD" "~/.config/opencode"
hasnot L8 "$CMD" "integrations/opencode/scripts/review-route.sh"
has L9 "$CMD" "helper-resolution block"
has L10 "$ORCH" '"$RR" resolve'
hasnot L11 "$ORCH" "RESOLVER_UNAVAILABLE if the helper itself"
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

# --- V: orchestrator completion verification checkpoint (static wording)
for f in "$ORCH" "$CMD"; do
  n=$(basename "$f")
  has "V1 $n step exists" "$f" "ompletion verification"
  has "V2 $n after end checkpoint, before review decision" "$f" "after the end checkpoint and before the review decision"
  has "V3 $n VERIFIED" "$f" "VERIFIED"
  has "V4 $n PARTIALLY_VERIFIED" "$f" "PARTIALLY_VERIFIED"
  has "V5 $n FAILED" "$f" "FAILED"
  has "V6 $n not verified complete" "$f" "NOT verified complete"
  has "V7 $n FAILED stops before review decision" "$f" "stop before the review decision"
  has "V8 $n read-only" "$f" "read-only (no edits"
  has "V9 $n not independent review" "$f" "not independent review"
  has "V10 $n git show --stat" "$f" "git show --stat"
  has "V11 $n report field verification" "$f" "Orchestrator verification"
  has "V12 $n report field unverified" "$f" "Unverified requirements"
done
has V13 "$ORCH" "Order: child returns -> END CHECKPOINT -> completion verification -> review decision"
has V14 "$ORCH" "never call it complete or successful"
has V15 "$ORCH" "no reviewer, no automatic remediation, no re-delegation"
has V16 "$ORCH" "Never accept a \"tests passed\" claim as verified without evidence"
has V17 "$CMD" "never say complete or successful"
has V18 "$README" "Completion verification"
has V19 "$README" "Orchestrator verification"
hasnot V20 "$ORCH" "Continue to normal completion"

# --- W: relationship/ordering invariants (verification step, FAILED -> NOT_REACHED, PARTIALLY_VERIFIED)
PORT="$ROOT/commands/implement-spec.md"
AGENTS="$ROOT/AGENTS.md"
lnum() { grep -nF -- "$2" "$1" | head -1 | cut -d: -f1; }                   # first line number of a phrase
stepn() { sed -n "s/^\([0-9][0-9]*\)\. $2.*/\1/p" "$1" | head -1; }         # leading step number of a numbered line
lineof() { grep -F -- "$2" "$1" | head -1; }                                 # first line containing a phrase
block() { awk -v h="$2" 'index($0,h)==1{f=1;next} f&&/^```/{c++; if(c==2)exit; next} f&&c==1' "$1"; }  # fenced block after heading
lt3() { [[ -n "$1" && -n "$2" && -n "$3" && "$1" -lt "$2" && "$2" -lt "$3" ]]; }
orch_order() { lt3 "$(lnum "$1" "END CHECKPOINT (mandatory)")" "$(lnum "$1" "Completion verification (mandatory")" "$(lnum "$1" "Review decision:")"; }
cmd_order() { lt3 "$(stepn "$1" "END CHECKPOINT")" "$(stepn "$1" "Completion verification")" "$(stepn "$1" "Decide whether independent review")"; }
port_order() { lt3 "$(stepn "$1" "Produce an implementation handoff")" "$(stepn "$1" "Verify completion read-only")" "$(stepn "$1" "If review is required")"; }
contains_all() { local t="$1"; shift; local k; for k in "$@"; do [[ "$t" == *"$k"* ]] || return 1; done; }

# ordering: end checkpoint < verification < review decision
orch_order "$ORCH" && ok "W1 ORCH order end checkpoint < verification < review decision" || bad "W1 ORCH order"
cmd_order "$CMD" && ok "W2 CMD order end checkpoint < verification < review decision" || bad "W2 CMD order"
port_order "$PORT" && ok "W3 portable order handoff < verification < review" || bad "W3 portable order"

# mutation self-check: the ordering assertions must fail when verification moves after the review decision
sed 's/^12\. Completion verification/14. Completion verification/' "$CMD" > "$TMP/cmd_mut"
cmd_order "$TMP/cmd_mut" && bad "W4 mutation (CMD verification moved) not detected" || ok "W4 mutation detected (CMD)"
sed 's/^Completion verification (mandatory/Zompletion verification (mandatory/' "$ORCH" > "$TMP/orch_mut"
orch_order "$TMP/orch_mut" && bad "W5 mutation (ORCH heading removed) not detected" || ok "W5 mutation detected (ORCH heading removed)"
# genuine ORCH ordering mutation: move Review decision before END CHECKPOINT
awk '
  { lines[NR] = $0 }
  /^Review decision:/ { rd_line = NR }
  /END CHECKPOINT \(mandatory\)/ { end_line = NR }
  END {
    for (i = 1; i <= NR; i++) {
      if (i == rd_line) continue
      if (i == end_line) print "Review decision:"
      print lines[i]
    }
  }
' "$ORCH" > "$TMP/orch_mut_order"
if cmp -s "$ORCH" "$TMP/orch_mut_order"; then bad "W5b mutation produced an identical file"; else ok "W5b mutation file differs from original"; fi
orch_order "$TMP/orch_mut_order" && bad "W5b mutation (ORCH order inverted) not detected" || ok "W5b mutation detected (ORCH order inverted)"

# FAILED -> NOT_REACHED review fields, within each file's FAILED description
of=$(lineof "$ORCH" "When Orchestrator verification is FAILED, the review decision is never evaluated")
contains_all "$of" "NOT_REACHED" "Review required" "Review decision reason" "Model resolution" "Reviewer" "Verdict" && ok "W6 ORCH FAILED text -> NOT_REACHED review fields" || bad "W6 ORCH FAILED text"
cf=$(lineof "$CMD" "Result is exactly one of")
contains_all "$cf" "FAILED" "NOT_REACHED" "Review required" "Review decision reason" "Model resolution" "Reviewer" "Verdict" "without evaluating review need" && ok "W7 CMD FAILED text -> NOT_REACHED review fields" || bad "W7 CMD FAILED text"
has W8 "$ORCH" "Start checkpoint and End checkpoint stay reported"
fb=$(block "$ORCH" "Example, failed")
contains_all "$fb" "Orchestrator verification: FAILED" "Review required: NOT_REACHED" "Review decision reason: NOT_REACHED" "Model resolution: NOT_REACHED" "Independent review: NOT_REACHED" && ok "W10 ORCH FAILED example NOT_REACHED fields" || bad "W10 ORCH FAILED example"
if printf '%s\n' "$fb" | grep -qiE 'complete|successful'; then bad "W11 FAILED example claims complete/successful"; else ok "W11 FAILED example has no complete/successful claim"; fi
if printf '%s\n' "$fb" | grep -qE '^(Reviewer|Verdict): *(PASS|PASS_WITH_NOTES|CHANGES_REQUIRED|review-)'; then bad "W12 FAILED example has real Reviewer/Verdict"; else ok "W12 FAILED example has no real Reviewer/Verdict"; fi
if printf '%s\n' "$fb" | grep -qE '^(Reviewer|Verdict):'; then bad "W13 FAILED example has Reviewer/Verdict lines"; else ok "W13 FAILED example has no Reviewer/Verdict lines"; fi

# PARTIALLY_VERIFIED: only VERIFIED may be complete/successful, on every terminal path
r=$(lineof "$ORCH" "Final report, on every terminal path")
contains_all "$r" "review not required" "REVIEW_BLOCKED_MODEL_RESOLUTION" "PASS" "only when Orchestrator verification is VERIFIED" "never upgrades PARTIALLY_VERIFIED" "never upgrades verification status" "never complete" && ok "W14 ORCH terminal-path rule" || bad "W14 ORCH terminal-path rule"
r=$(lineof "$CMD" "On every terminal path")
contains_all "$r" "review not required" "REVIEW_BLOCKED_MODEL_RESOLUTION" "PASS" "only when Orchestrator verification is VERIFIED" "never upgrades PARTIALLY_VERIFIED" "never upgrades verification status" "never complete" && ok "W15 CMD terminal-path rule" || bad "W15 CMD terminal-path rule"
r=$(lineof "$PORT" "Only \`VERIFIED\` may be called complete")
contains_all "$r" "review not required" "review blocked" "PASS" "never upgrades verification status" && ok "W16 portable terminal-path rule" || bad "W16 portable terminal-path rule"
pb=$(block "$ORCH" "Example, partially verified")
contains_all "$pb" "PARTIALLY_VERIFIED" "NOT verified complete" && ok "W17 PARTIALLY_VERIFIED example says NOT verified complete" || bad "W17 PARTIALLY_VERIFIED example"
if printf '%s\n' "$pb" | grep -q 'Verdict: PASS'; then bad "W18 PARTIALLY_VERIFIED example pairs with PASS"; else ok "W18 PARTIALLY_VERIFIED example has no PASS verdict"; fi
# no example block pairs PARTIALLY_VERIFIED with complete/successful outside "NOT verified complete"
w19=ok
while IFS= read -r h; do
  b=$(block "$ORCH" "$h")
  if [[ "$b" == *PARTIALLY_VERIFIED* ]] && printf '%s\n' "$b" | sed 's/NOT verified complete//g' | grep -qiE 'complete|successful'; then w19="bad"; fi
done < <(grep '^Example,' "$ORCH")
[[ $w19 == ok ]] && ok "W19 no example pairs PARTIALLY_VERIFIED with complete/successful" || bad "W19 example pairs PARTIALLY_VERIFIED with complete/successful"

# portable workflow: verification step content
ps=$(lineof "$PORT" "Verify completion read-only")
contains_all "$ps" "validation" "unverified" "scope and acceptance" "not independent review" "NOT verified complete" "NOT_REACHED" "VERIFIED" "PARTIALLY_VERIFIED" "FAILED" "never accept \"tests passed\" without evidence" "re-run cheap read-only validation" "commit SHA" "git status" && ok "W20 portable verification step content" || bad "W20 portable verification step content"
has W21 "$PORT" "report every unverified requirement"

# cross-file consistency: statuses and NOT_REACHED everywhere
for f in "$AGENTS" "$ORCH" "$CMD" "$PORT" "$README"; do
  n=$(basename "$(dirname "$f")")/$(basename "$f")
  for k in VERIFIED PARTIALLY_VERIFIED FAILED NOT_REACHED; do has "W22 $n: $k" "$f" "$k"; done
done

# --- U: U2 OpenCode remediation loop (Supervised Execution v1)
for f in "$ORCH" "$CMD"; do
  n=$(basename "$f")
  has "U1 $n one attempt" "$f" "at most one automatic remediation cycle"
  has "U2 $n eligibility gate" "$f" "eligible only when"
  has "U3 $n ineligible stops" "$f" "If any finding is ineligible"
  has "U4 $n no partial remediation" "$f" "do not partially remediate"
  has "U5 $n treat uncertain as ineligible" "$f" "missing, ambiguous, or uncertain eligibility"
  has "U6 $n fresh remediation checkpoints" "$f" "rem_start_id"
  has "U7 $n fresh end checkpoint" "$f" "rem_end_id"
  has "U8 $n resolve from remediation checkpoints" "$f" "resolve <rem_start_id> <rem_end_id>"
  has "U9 $n no family fallback" "$f" "do not fall back to the initial implementation family"
  has "U10 $n second CHANGES_REQUIRED stops" "$f" "do not start a second remediation cycle"
  has "U11 $n SC-9 agent re-evaluates" "$f" "re-evaluate the eligibility"
  has "U12 $n SC-9 agent rejects stops" "$f" "make no changes"
  has "U13 $n validation before remediation commit" "$f" "validation before commit"
  has "U14 $n completion verification before re-review" "$f" "before any re-review"
  has "U15 $n fresh re-review session" "$f" "fresh child session against the final commit"
  has "U16 $n counter no reset" "$f" "do not reset it through delegation"
done
# U2-specific fields appear in the orchestrator report list.
for k in "Remediation attempt count" "Remediation start checkpoint" "Remediation end checkpoint" "Remediation model family" "Re-reviewer" "Re-review verdict" "Findings resolved" "Findings unresolved" "Required human decision" "Recommended next action"; do
  has "U17 orchestrator report: $k" "$ORCH" "$k"
done
# The command file reports the same remediation fields.
has "U18 command remediation report" "$CMD" "Remediation attempt count"
has "U19 command re-review verdict" "$CMD" "Re-review verdict"

# --- U3: finding ledger, focused re-review, and concise final report
for f in "$ORCH" "$CMD"; do
  n=$(basename "$f")
  has "U3-1 $n ledger defined" "$f" "Finding ledger (session-local):"
  has "U3-2 $n ledger id format" "$f" "R<cycle>-<n>"
  has "U3-3 $n ledger lifecycle" "$f" "OPEN → REMEDIATED → VERIFIED → CLOSED"
  has "U3-4 $n stable identity" "$f" "stable across cycles"
  has "U3-5 $n no persistent ledger" "$f" "No database or persistent service"
  has "U3-6 $n Phase A I10 mapping" "$f" "Phase A I10"
  has "U3-7 $n status OPEN recorded" "$f" "status \`OPEN\`"
  has "U3-8 $n REMEDIATED status" "$f" "REMEDIATED"
  has "U3-9 $n VERIFIED status" "$f" "VERIFIED"
  has "U3-10 $n CLOSED status" "$f" "CLOSED"
  has "U3-11 $n new re-review finding IDs" "$f" "R2-<n>"
  has "U3-12 $n not re-checked unresolved" "$f" "not re-check"
  has "U3-13 $n focused re-review distinct" "$f" "distinct review cycle"
  has "U3-14 $n final commit scope" "$f" "initial implementation + remediation"
  has "U3-15 $n re-review validation evidence" "$f" "validation evidence for the remediation"
  has "U3-16 $n independent verification" "$f" "independently verify"
  has "U3-17 $n concise final report" "$f" "Supervised Execution Report:"
  has "U3-18 $n final report on terminal paths" "$f" "on every terminal path"
  has "U3-19 $n findings resolved field" "$f" "Findings resolved:"
  has "U3-20 $n findings unresolved field" "$f" "Findings unresolved:"
  has "U3-21 $n required human decision field" "$f" "Required human decision:"
  has "U3-22 $n recommended next action field" "$f" "Recommended next action:"
  has "U3-23 $n no second remediation" "$f" "do not start a second remediation cycle"
  has "U3-24 $n SC-9 no commit no re-review" "$f" "no commit is made and no re-review is launched"
  has "U3-25 $n SC-9 report IDs and reasons" "$f" "finding IDs and reasons"
  has "U3-26 $n fresh opposite-family re-review provenance" "$f" "remediation agent's actual runtime family"
done
has "U3-27 review template finding IDs" "$ROOT/templates/review-report.md" "R<cycle>-<n>"
has "U3-28 review template prior findings" "$ROOT/templates/review-report.md" "Prior findings status"
has "U3-29 review template not re-checked" "$ROOT/templates/review-report.md" "not re-checked"
has "U3-30 review routing focused re-review" "$ROOT/policies/review-routing.md" "Focused re-review after remediation"
has "U3-31 review routing final commit" "$ROOT/policies/review-routing.md" "final commit"
has "U3-32 review routing ledger ID" "$ROOT/policies/review-routing.md" "ledger ID"

# --- README wording corrected
hasnot R1 "$README" "keeps later orchestrator traffic out of the window"
hasnot R2 "$README" "Traffic after \`end-id\` (including the orchestrator's own) is excluded"
hasnot R3 "$README" "integration comes later"
has R4 "$README" "REVIEW_BLOCKED_MODEL_RESOLUTION"
has R5 "$README" "correlation id"

# --- P: orchestrator permissions front matter unchanged vs the v3b.1 baseline commit (526df80)
# Normalize: strip trailing whitespace only; preserve leading indentation.
head_fm=$(git -C "$ROOT" show 526df80:integrations/opencode/agents/orchestrator.md 2>/dev/null | awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' | norm_fm)
cur_fm=$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' "$ORCH" | norm_fm)
if [[ -z "$head_fm" ]]; then bad "P1 cannot read baseline front matter"; else eq P1 "$cur_fm" "$head_fm"; fi

# Regression tests for the frontmatter comparison helper.
awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' "$ORCH" > "$TMP/fm_base"

# P2: trailing-whitespace-only differences are ignored.
sed -e 's/$/    /' "$TMP/fm_base" > "$TMP/fm_ws"
if [[ "$(norm_fm < "$TMP/fm_base")" == "$(norm_fm < "$TMP/fm_ws")" ]]; then ok "P2 trailing whitespace ignored"; else bad "P2 trailing whitespace ignored"; fi

# P3: a real permission change is still detected.
awk '/resource: review-claude/{seen=1} seen && /effect: allow/{sub("allow","deny"); seen=0} {print}' "$TMP/fm_base" > "$TMP/fm_perm"
if [[ "$(norm_fm < "$TMP/fm_base")" != "$(norm_fm < "$TMP/fm_perm")" ]]; then ok "P3 permission change detected"; else bad "P3 permission change detected"; fi

# P4: a mode/model value change is still detected.
sed -e 's/^mode: primary$/mode: subagent/' "$TMP/fm_base" > "$TMP/fm_mode"
if [[ "$(norm_fm < "$TMP/fm_base")" != "$(norm_fm < "$TMP/fm_mode")" ]]; then ok "P4 mode change detected"; else bad "P4 mode change detected"; fi

# P5: an indentation-only change is still detected (leading whitespace is protected).
sed -e 's/^permissions:$/  permissions:/' "$TMP/fm_base" > "$TMP/fm_indent"
if [[ "$(norm_fm < "$TMP/fm_base")" != "$(norm_fm < "$TMP/fm_indent")" ]]; then ok "P5 indentation change detected"; else bad "P5 indentation change detected"; fi

echo "passed=$pass failed=$failn"
[[ $failn -eq 0 ]]
