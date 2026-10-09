#!/usr/bin/env bash
# doctor.sh — read-only health check for the dev-agents OpenCode orchestration install (v3c.1).
#
#   doctor.sh [--machine] [--quiet] [-h|--help]
#
# Strictly read-only: it never installs, repairs, copies or edits anything, never writes to
# Git, the OpenCode config or the 9Router DB, and never calls an LLM. It only reads files,
# opens the 9Router DB with sqlite3 -readonly + PRAGMA query_only=1 (metadata and
# COALESCE(MAX(id),0) only; no credential-bearing column is ever selected), and exercises the
# INSTALLED helper scripts against throw-away fixtures in a mktemp dir (removed on exit).
# Fix commands are printed as plain-text hints only; they are never executed.
#
# Output (default): one line per check "PASS|WARN|FAIL  <name>  <detail>" (hints indented below
# non-pass checks), a human "Summary:" line, then the stable lines
#   overall=pass|warn|fail  passed=N  warnings=N  failed=N     (one per line)
# --machine : machine lines only. Per check: check=<name> status=pass|warn|fail detail=<text>
#             and zero or more hint=<text> (non-pass only), each on its own line, then the
#             summary lines. Split a line at the first "=".
# --quiet   : only non-pass checks (with hints) plus the summary; combines with --machine.
#
# Exit codes: 0 all checks PASS | 1 at least one WARN, no FAIL | 2 at least one FAIL
#             64 usage error. A check that was skipped (see "skip" below) counts as PASS.
#
# Severity: FAIL = the installed orchestration cannot work. WARN = degraded, stale or
# unverifiable. Dependent checks whose prerequisite already failed report WARN "not checked".
# Skip: the four *_sync checks (+ doctor_sync) compare installed files with the repository only
# when this script runs from a dev-agents checkout (<root>/integrations/opencode/scripts and
# <root>/integrations/opencode/agents/orchestrator.md exist). Otherwise they report
# status=pass detail="skipped (not a dev-agents checkout)".
#
# Env: HOME (config dir is $HOME/.config/opencode), NINEROUTER_DB (default
# $HOME/.9router/db/data.sqlite). Needs bash 3.2+; sqlite3, jq (optional), shasum/sha256sum/cksum.

set -u
export LC_ALL=C

MACHINE=0
QUIET=0
usage() { echo "usage: doctor.sh [--machine] [--quiet]" ; }
for arg in "$@"; do
  case "$arg" in
    --machine) MACHINE=1 ;;
    --quiet) QUIET=1 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
  esac
done

CFG="$HOME/.config/opencode"
DB="${NINEROUTER_DB:-$HOME/.9router/db/data.sqlite}"
INT_RE='^[0-9]{1,15}$'

TMP=$(mktemp -d "${TMPDIR:-/tmp}/doctor.XXXXXX") || { echo "overall=fail"; echo "detail=mktemp failed" >&2; exit 2; }
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=""
cand=$(cd "$SELF_DIR/../../.." 2>/dev/null && pwd)
if [ -n "$cand" ] && [ "$SELF_DIR" = "$cand/integrations/opencode/scripts" ] &&
  [ -f "$cand/integrations/opencode/agents/orchestrator.md" ]; then
  REPO="$cand"
fi

# --- reporting ----------------------------------------------------------------

passed=0; warnings=0; failed=0

# Details are restricted to a conservative charset; hints are plain-text commands that only
# lose control characters (they are built from fixed text and local paths, never from file
# contents, DB rows or config values).
sanitize() { printf '%s' "$1" | tr -c "A-Za-z0-9 ._,:;/=()@+~'\"-" '?' | cut -c1-300; }
sanitize_hint() { printf '%s' "$1" | tr -d '\000-\037' | cut -c1-600; }

# check <name> <pass|warn|fail> <detail> [hint...]   (hints are shown for non-pass only)
check() {
  local name="$1" st="$2" detail label h
  detail=$(sanitize "$3")
  shift 3
  case "$st" in
    pass) passed=$((passed + 1)); label=PASS ;;
    warn) warnings=$((warnings + 1)); label=WARN ;;
    *) failed=$((failed + 1)); label=FAIL; st=fail ;;
  esac
  if [ "$QUIET" = 1 ] && [ "$st" = pass ]; then return 0; fi
  if [ "$MACHINE" = 1 ]; then
    printf 'check=%s\nstatus=%s\ndetail=%s\n' "$name" "$st" "$detail"
    if [ "$st" != pass ]; then for h in "$@"; do printf 'hint=%s\n' "$(sanitize_hint "$h")"; done; fi
  else
    printf '%-4s  %s  %s\n' "$label" "$name" "$detail"
    if [ "$st" != pass ]; then for h in "$@"; do printf '      hint: %s\n' "$(sanitize_hint "$h")"; done; fi
  fi
}

notchecked() { check "$1" warn "not checked: $2"; } # <name> <reason>

# Run a command with a time limit: timed <secs> <outfile> cmd...
timed() {
  local secs="$1" out="$2" pid wd rc
  shift 2
  "$@" >"$out" 2>&1 </dev/null &
  pid=$!
  ( sleep "$secs"; kill "$pid" ) >/dev/null 2>&1 &
  wd=$!
  wait "$pid" 2>/dev/null; rc=$?
  kill "$wd" >/dev/null 2>&1
  wait "$wd" >/dev/null 2>&1
  return "$rc"
} 2>/dev/null

fsum() { # portable deterministic checksum of one file
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 <"$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum <"$1" | awk '{print $1}'
  else cksum <"$1" | awk '{print $1 "-" $2}'; fi
}

# Hint source dir: absolute inside a checkout, else a placeholder.
if [ -n "$REPO" ]; then SRC="$REPO/integrations/opencode"; else SRC="<dev-agents-checkout>/integrations/opencode"; fi
cp_hint() { # <rel path under integrations/opencode>
  local rel="$1" dir
  dir="~/.config/opencode/$(dirname "$rel")/"
  printf 'mkdir -p %s && cp "%s/%s" %s' "$dir" "$SRC" "$rel" "$dir"
}

# --- a. executables -----------------------------------------------------------

if command -v bash >/dev/null 2>&1; then
  check exe_bash pass "bash ${BASH_VERSION:-unknown}"
else
  check exe_bash fail "bash not found on PATH"
fi

HAVE_SQLITE=0
if command -v sqlite3 >/dev/null 2>&1; then
  HAVE_SQLITE=1
  v=$(sqlite3 --version 2>/dev/null | awk '{print $1; exit}')
  check exe_sqlite3 pass "sqlite3 ${v:-unknown}"
else
  check exe_sqlite3 fail "sqlite3 not found on PATH" "install sqlite3 with your package manager (it is required by the checkpoint helper and resolver)"
fi

if command -v git >/dev/null 2>&1; then
  v=$(git --version 2>/dev/null | head -n 1)
  check exe_git pass "${v:-git version unknown}"
else
  check exe_git warn "git not found on PATH (delegated implementation agents need it to commit)" "install git with your package manager"
fi

if command -v opencode >/dev/null 2>&1; then
  if timed 10 "$TMP/oc.ver" opencode --version; then
    v=$(head -n 1 "$TMP/oc.ver")
    check exe_opencode pass "${v:-version unknown}"
  else
    check exe_opencode warn "opencode found but --version failed or timed out"
  fi
else
  check exe_opencode fail "opencode not found on PATH" "install OpenCode (https://opencode.ai/v2/docs/)"
fi

# --- b. installed files -------------------------------------------------------

file_problem() { # <path> <need-exec 0|1> -> prints problem text or nothing
  if [ ! -f "$1" ]; then echo "missing"
  elif [ ! -r "$1" ]; then echo "unreadable"
  elif [ "$2" = 1 ] && [ ! -x "$1" ]; then echo "not executable"; fi
}

installed_group() { # <check-name> <severity fail|warn> <need-exec> <rel>...
  local name="$1" sev="$2" nx="$3" rel p problems="" hints="" n=0 fixes=""
  shift 3
  for rel in "$@"; do
    n=$((n + 1))
    p=$(file_problem "$CFG/$rel" "$nx")
    if [ -n "$p" ]; then
      problems="$problems${problems:+, }$rel $p"
      case "$p" in
        "not executable") fixes="${fixes}${fixes:+; }chmod +x ~/.config/opencode/$rel" ;;
        unreadable) fixes="${fixes}${fixes:+; }chmod u+r ~/.config/opencode/$rel" ;;
        *) fixes="${fixes}${fixes:+; }$(cp_hint "$rel")" ;;
      esac
    fi
  done
  if [ -z "$problems" ]; then check "$name" pass "$n file(s) present"
  else check "$name" "$sev" "$problems" "$fixes"; fi
}

installed_group installed_orchestrator fail 0 agents/orchestrator.md
installed_group installed_commands fail 0 commands/implement-spec.md commands/route-task.md commands/review-change.md commands/split-spec.md
installed_group installed_scripts fail 1 scripts/review-route.sh scripts/resolve-model-family.sh
# optional: the doctor itself and its command/agent are a convenience, so missing = WARN
doctor_files="commands/doctor.md agents/doctor.md"
problems=""; fixes=""
for rel in $doctor_files; do
  p=$(file_problem "$CFG/$rel" 0)
  if [ -n "$p" ]; then problems="$problems${problems:+, }$rel $p"; fixes="${fixes}${fixes:+; }$(cp_hint "$rel")"; fi
done
p=$(file_problem "$CFG/scripts/doctor.sh" 1)
if [ -n "$p" ]; then problems="$problems${problems:+, }scripts/doctor.sh $p"; fixes="${fixes}${fixes:+; }$(cp_hint scripts/doctor.sh)"; fi
if [ -z "$problems" ]; then check installed_doctor pass "doctor command, agent and script present"
else check installed_doctor warn "$problems" "$fixes"; fi

# --- c. stale installs (checkout only) ---------------------------------------

sync_check() { # <check-name> <rel>...
  local name="$1" rel r i a b diff="" miss="" fixes="" n=0
  shift
  for rel in "$@"; do
    r="$REPO/integrations/opencode/$rel"; i="$CFG/$rel"
    [ -f "$r" ] || continue
    n=$((n + 1))
    if [ ! -f "$i" ] || [ ! -r "$i" ]; then
      miss="$miss${miss:+, }$rel"; fixes="${fixes}${fixes:+; }$(cp_hint "$rel")"
    else
      a=$(fsum "$r"); b=$(fsum "$i")
      if [ "$a" != "$b" ]; then diff="$diff${diff:+, }$rel"; fixes="${fixes}${fixes:+; }$(cp_hint "$rel")"; fi
    fi
  done
  if [ -n "$diff$miss" ]; then
    check "$name" warn "${diff:+installed copy differs from repository: $diff}${diff:+${miss:+; }}${miss:+missing in install: $miss}" "$fixes"
  else
    check "$name" pass "$n file(s) match repository"
  fi
}

if [ -n "$REPO" ]; then
  cmds=""
  for f in "$REPO"/integrations/opencode/commands/*.md; do
    [ -f "$f" ] && cmds="$cmds commands/$(basename "$f")"
  done
  sync_check orchestrator_sync agents/orchestrator.md
  sync_check command_sync $cmds
  sync_check review_route_sync scripts/review-route.sh
  sync_check resolver_sync scripts/resolve-model-family.sh
  sync_check doctor_sync scripts/doctor.sh agents/doctor.md
else
  for n in orchestrator_sync command_sync review_route_sync resolver_sync doctor_sync; do
    check "$n" pass "skipped (not a dev-agents checkout)"
  done
fi

# --- d. OpenCode config (read-only) ------------------------------------------

CFG_JSON="$CFG/opencode.json"
CFG_INFO=""
CFG_OK=0
cfg_hint="edit ~/.config/opencode/opencode.json: economy/standard/strong/premium need mode \"all\"; review-openai/review-claude/explorer need mode \"subagent\"; models should be 9router/<alias> (see integrations/opencode/README.md)"
if [ ! -f "$CFG_JSON" ]; then
  extra=""; [ -f "$CFG/opencode.jsonc" ] && extra=" (opencode.jsonc exists but only opencode.json is checked)"
  check config_file fail "opencode.json not found$extra" "$cfg_hint"
elif [ ! -r "$CFG_JSON" ]; then
  check config_file fail "opencode.json not readable" "chmod u+r ~/.config/opencode/opencode.json"
elif ! command -v jq >/dev/null 2>&1; then
  check config_file warn "jq not found; opencode.json exists but agent settings were not validated" "install jq with your package manager"
else
  # Emits only "<alias> <present> <mode> <9router?>" tokens; model strings and every other
  # field (provider keys etc.) are never output.
  CFG_INFO=$(jq -r '
    def agent($n): ((.agents? // null) | if type == "object" then .[$n] else null end)
      // ((.agent? // null) | if type == "object" then .[$n] else null end);
    def present($n): agent($n) | type == "object";
    def mode($n): agent($n) | if type == "object" then (.mode // "") else "" end
      | if IN("all", "subagent", "primary") then . else "other" end;
    def m9($n): agent($n) | if type == "object" then
        (.model as $m | if ($m | type) == "string" then ($m | startswith("9router/") and length > 8)
                        elif ($m | type) == "object" then
                          ($m.providerID == "9router" and ($m.model | type) == "string" and ($m.model | length) > 0)
                        else false end)
      else false end;
    if type != "object" then "invalid"
    else ("economy","standard","strong","premium","review-openai","review-claude","explorer") as $n
      | "\($n) \(present($n)) \(mode($n)) \(m9($n))" end' "$CFG_JSON" 2>/dev/null)
  if [ $? -ne 0 ] || [ -z "$CFG_INFO" ]; then
    check config_file fail "opencode.json is not valid JSON" "fix the JSON syntax in ~/.config/opencode/opencode.json (jq . ~/.config/opencode/opencode.json shows the error)"
  elif [ "$CFG_INFO" = invalid ]; then
    check config_file fail "opencode.json top level is not an object" "$cfg_hint"
  else
    CFG_OK=1
    check config_file pass "opencode.json valid"
  fi
fi

cfg_agents() { # <check-name> <fail|warn> <expected-mode> <need-9router 0|1> <alias>...
  local name="$1" sev="$2" want="$3" need9="$4" a line present mode m9 problems="" n=0
  shift 4
  for a in "$@"; do
    n=$((n + 1))
    line=$(printf '%s\n' "$CFG_INFO" | awk -v n="$a" '$1 == n {print $2, $3, $4}')
    read -r present mode m9 <<EOF
$line
EOF
    if [ "${present:-}" != true ]; then problems="$problems${problems:+, }$a missing"; continue; fi
    [ "$mode" = "$want" ] || problems="$problems${problems:+, }$a mode=$mode (want $want)"
    [ "$need9" = 0 ] || [ "$m9" = true ] || problems="$problems${problems:+, }$a model is not 9router/*"
  done
  if [ -z "$problems" ]; then check "$name" pass "$n agent(s) ok (mode=$want$([ "$need9" = 1 ] && echo ', 9router model'))"
  else check "$name" "$sev" "$problems" "$cfg_hint"; fi
}

if [ "$CFG_OK" = 1 ]; then
  cfg_agents config_impl_agents fail all 1 economy standard strong premium
  cfg_agents config_review_agents fail subagent 1 review-openai review-claude
  cfg_agents config_explorer warn subagent 0 explorer
else
  for n in config_impl_agents config_review_agents config_explorer; do
    notchecked "$n" "opencode.json unavailable or not validated"
  done
fi

# --- e. 9Router DB (metadata only) -------------------------------------------

sqro() { # <sql> ; prints rows; rc = sqlite3 rc
  sqlite3 -init /dev/null -batch -list -noheader -readonly "$DB" ".timeout 2000" "PRAGMA query_only=1;" "$1" 2>/dev/null </dev/null
}

DB_OK=0
db_hint="start 9Router once so it creates its DB, or set NINEROUTER_DB to the DB path (default ~/.9router/db/data.sqlite)"
if [ "$HAVE_SQLITE" = 0 ]; then
  for n in db_file db_open db_combos db_usagehistory; do notchecked "$n" "sqlite3 not found"; done
elif [ ! -f "$DB" ]; then
  check db_file fail "9Router DB not found: $DB" "$db_hint"
  for n in db_open db_combos db_usagehistory; do notchecked "$n" "DB file missing"; done
elif [ ! -r "$DB" ]; then
  check db_file fail "9Router DB not readable: $DB" "chmod u+r on the DB file"
  for n in db_open db_combos db_usagehistory; do notchecked "$n" "DB file unreadable"; done
else
  check db_file pass "$DB"
  n=$(sqro "SELECT count(*) FROM sqlite_master;")
  if [ $? -ne 0 ] || ! [[ "$n" =~ $INT_RE ]]; then
    check db_open fail "cannot open DB read-only as SQLite" "check that $DB is a valid SQLite file not locked by another process"
    for n in db_combos db_usagehistory; do notchecked "$n" "DB cannot be opened"; done
  else
    DB_OK=1
    check db_open pass "opens read-only (query_only=1)"
    db_table() { # <check-name> <table> <col>...
      local name="$1" tbl="$2" cols c missing=""
      shift 2
      cols=$(sqro "PRAGMA table_info($tbl);" | awk -F'|' '{print $2}')
      if [ -z "$cols" ]; then check "$name" fail "table $tbl missing" "$db_hint"; return 0; fi
      for c in "$@"; do printf '%s\n' "$cols" | grep -qx -- "$c" || missing="$missing${missing:+, }$c"; done
      if [ -n "$missing" ]; then check "$name" fail "table $tbl lacks column(s): $missing" "$db_hint"
      else check "$name" pass "$tbl has $*"; fi
    }
    db_table db_combos combos name models
    db_table db_usagehistory usageHistory id provider model status
  fi
fi

# --- f. checkpoint helper -----------------------------------------------------

RR="$CFG/scripts/review-route.sh"
RESOLVER="$CFG/scripts/resolve-model-family.sh"
RR_OK=0; [ -f "$RR" ] && [ -x "$RR" ] && RR_OK=1
RES_OK=0; [ -f "$RESOLVER" ] && [ -x "$RESOLVER" ] && RES_OK=1

if [ "$RR_OK" = 0 ]; then notchecked checkpoint "installed review-route.sh missing or not executable"
elif [ "$DB_OK" = 0 ]; then notchecked checkpoint "DB not usable"
else
  NINEROUTER_DB="$DB" "$RR" checkpoint start >"$TMP/cp.out" 2>"$TMP/cp.err" </dev/null
  rc=$?
  out=$(cat "$TMP/cp.out")
  if [ $rc -eq 0 ] && [[ "$out" =~ $INT_RE ]] && [ ! -s "$TMP/cp.err" ] &&
    printf '%s\n' "$out" | cmp -s - "$TMP/cp.out"; then
    check checkpoint pass "checkpoint start = $out"
  else
    check checkpoint fail "review-route.sh checkpoint start failed (rc=$rc, want one integer on stdout and empty stderr)" "reinstall helper: $(cp_hint scripts/review-route.sh)"
  fi
fi

# --- g. resolver --------------------------------------------------------------

if [ "$RES_OK" = 0 ]; then
  notchecked resolver_syntax "installed resolve-model-family.sh missing or not executable"
elif bash -n "$RESOLVER" 2>/dev/null; then
  check resolver_syntax pass "bash -n ok"
else
  check resolver_syntax fail "bash -n failed on installed resolver" "reinstall resolver: $(cp_hint scripts/resolve-model-family.sh)"
fi

FIXDB="$TMP/fixture.sqlite"
FIX_OK=0
if [ "$HAVE_SQLITE" = 1 ]; then
  if sqlite3 "$FIXDB" "
CREATE TABLE combos (id TEXT PRIMARY KEY, name TEXT UNIQUE NOT NULL, kind TEXT, models TEXT NOT NULL, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL);
CREATE TABLE usageHistory (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT NOT NULL, provider TEXT, model TEXT, connectionId TEXT, apiKey TEXT, endpoint TEXT, promptTokens INTEGER DEFAULT 0, completionTokens INTEGER DEFAULT 0, cost REAL DEFAULT 0, status TEXT, tokens TEXT, meta TEXT);
INSERT INTO combos VALUES ('doctor-non-claude','doctor-non-claude','','[\"cx/gpt-5.6-sol\"]','t','t');
INSERT INTO combos VALUES ('doctor-claude','doctor-claude','','[\"cc/claude-sonnet-5-5\"]','t','t');
INSERT INTO usageHistory (id,timestamp,provider,model,status) VALUES (1,'t','codex','gpt-5.6-sol','ok');
INSERT INTO usageHistory (id,timestamp,provider,model,status) VALUES (2,'t','claude','claude-sonnet-5-5','ok');" >/dev/null 2>&1 </dev/null; then
    FIX_OK=1
  fi
fi

# Strict validator for the resolver's "resolved" output, mirroring review-route.sh's resolved
# schema (it deliberately does NOT call the installed review-route.sh, so a lax helper cannot
# make the smoke look healthy). <file> holds the raw stdout capture (a file, not command
# substitution, so trailing-newline/blank-line framing is preserved). Sets SMOKE_WHY to a fixed
# reason string (never resolver text). Framing: one key=value per line, no blank lines, no CRLF,
# a missing final newline is accepted.
smoke_valid() { # <file> <rc> <combo> <family> <reviewer>
  local f="$1" rc="$2" combo="$3" fam="$4" rev="$5"
  local status="" c="" window="" family="" reviewer="" models="" providers="" usage_ids=""
  local seen=" " line key val keyset
  local list_re='^[A-Za-z0-9._-]+(,[A-Za-z0-9._-]+)*$' ids_re='^[0-9]+(,[0-9]+)*$'
  SMOKE_WHY=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || { SMOKE_WHY="blank line"; return 1; }
    [[ "$line" =~ ^([a-z_]+)=([A-Za-z0-9._,-]*)$ ]] || { SMOKE_WHY="malformed line"; return 1; }
    key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    case "$seen" in *" $key "*) SMOKE_WHY="duplicate key"; return 1 ;; esac
    seen="$seen$key "
    case "$key" in
      status) status="$val" ;;
      combo) c="$val" ;;
      window) window="$val" ;;
      family) family="$val" ;;
      reviewer) reviewer="$val" ;;
      models) models="$val" ;;
      providers) providers="$val" ;;
      usage_ids) usage_ids="$val" ;;
      *) SMOKE_WHY="unexpected key"; return 1 ;;
    esac
  done <"$f"
  keyset=$(printf '%s\n' $seen | sort | paste -sd, -)
  [ "$rc" -eq 0 ] || { SMOKE_WHY="exit code $rc"; return 1; }
  [ "$keyset" = "combo,family,models,providers,reviewer,status,usage_ids,window" ] || { SMOKE_WHY="key set mismatch"; return 1; }
  [ "$status" = resolved ] || { SMOKE_WHY="status not resolved"; return 1; }
  [ "$c" = "$combo" ] || { SMOKE_WHY="combo mismatch"; return 1; }
  [ "$window" = "0-2" ] || { SMOKE_WHY="window mismatch"; return 1; }
  [[ "$models" =~ $list_re && "$providers" =~ $list_re ]] || { SMOKE_WHY="models/providers invalid"; return 1; }
  [[ "$usage_ids" =~ $ids_re ]] || { SMOKE_WHY="usage_ids invalid"; return 1; }
  case "$family/$reviewer" in
    claude/review-openai | non-claude/review-claude) ;;
    *) SMOKE_WHY="family/reviewer contradictory"; return 1 ;;
  esac
  [ "$family" = "$fam" ] && [ "$reviewer" = "$rev" ] || { SMOKE_WHY="unexpected family/reviewer"; return 1; }
  return 0
}

resolver_smoke() { # <check-name> <combo> <family> <reviewer>
  local name="$1" combo="$2" fam="$3" rev="$4" rc
  if [ "$RES_OK" = 0 ] || [ "$FIX_OK" = 0 ]; then notchecked "$name" "resolver or fixture DB unavailable"; return 0; fi
  NINEROUTER_DB="$FIXDB" "$RESOLVER" 0 2 "$combo" >"$TMP/smoke.out" 2>/dev/null </dev/null; rc=$?
  if smoke_valid "$TMP/smoke.out" "$rc" "$combo" "$fam" "$rev"; then
    check "$name" pass "fixture resolved family=$fam reviewer=$rev"
  else
    check "$name" fail "fixture resolver output invalid ($SMOKE_WHY; rc=$rc; want family=$fam reviewer=$rev)" "reinstall resolver: $(cp_hint scripts/resolve-model-family.sh)"
  fi
}
resolver_smoke resolver_smoke_non_claude doctor-non-claude non-claude review-claude
resolver_smoke resolver_smoke_claude doctor-claude claude review-openai

# --- h. review-route framing --------------------------------------------------
# The installed review-route.sh itself is exercised in place; only the resolver it calls is
# replaced, via its DEV_AGENTS_RESOLVER override, by stub scripts in $TMP; NINEROUTER_DB points at
# the throw-away fixture DB (resolve never reads the DB itself, the stub ignores it).

GOOD='status=resolved\ncombo=strong\nwindow=3-5\nfamily=claude\nreviewer=review-openai\nmodels=m1\nproviders=p1\nusage_ids=4,5\n'
mkstub() { # <file> <printf-format body>
  printf '#!/usr/bin/env bash\nprintf "%s"\nexit 0\n' "$2" >"$TMP/$1"
  chmod +x "$TMP/$1"
}
mkstub stub_good "$GOOD"
mkstub stub_blank "${GOOD}\\n"
mkstub stub_garbage "status=resolved\\nthis is not key value\\n"

framing() { # <check-name> <stub> <valid|reject>
  local name="$1" stub="$2" want="$3" out rc
  if [ "$RR_OK" = 0 ]; then notchecked "$name" "installed review-route.sh missing or not executable"; return 0; fi
  out=$(NINEROUTER_DB="$FIXDB" DEV_AGENTS_RESOLVER="$TMP/$stub" "$RR" resolve 3 5 strong 2>/dev/null </dev/null); rc=$?
  if [ "$want" = valid ]; then
    if [ $rc -eq 0 ] && printf '%s\n' "$out" | grep -qx "model_resolution=resolved" &&
      printf '%s\n' "$out" | grep -qx "family=claude" && printf '%s\n' "$out" | grep -qx "reviewer=review-openai"; then
      check "$name" pass "valid resolver output accepted"
    else
      check "$name" fail "valid resolver output not accepted (rc=$rc)" "reinstall helper: $(cp_hint scripts/review-route.sh)"
    fi
  else
    if [ $rc -eq 3 ] && printf '%s\n' "$out" | grep -qx "reason=RESOLVER_OUTPUT_INVALID"; then
      check "$name" pass "invalid resolver output rejected (RESOLVER_OUTPUT_INVALID)"
    else
      check "$name" fail "invalid resolver output not rejected with RESOLVER_OUTPUT_INVALID (rc=$rc)" "reinstall helper: $(cp_hint scripts/review-route.sh)"
    fi
  fi
}
framing framing_valid stub_good valid
framing framing_malformed stub_garbage reject
framing framing_trailing_blank stub_blank reject

# --- summary ------------------------------------------------------------------

if [ "$failed" -gt 0 ]; then overall=fail; rc=2
elif [ "$warnings" -gt 0 ]; then overall=warn; rc=1
else overall=pass; rc=0; fi

if [ "$MACHINE" = 0 ]; then
  printf '\nSummary: %s passed, %s warning(s), %s failed\n' "$passed" "$warnings" "$failed"
fi
printf 'overall=%s\npassed=%s\nwarnings=%s\nfailed=%s\n' "$overall" "$passed" "$warnings" "$failed"
exit "$rc"
