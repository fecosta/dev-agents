#!/usr/bin/env bash
# test-doctor.sh — deterministic checks for doctor.sh (v3c.1).
# Uses ONLY temporary HOME / config / DB fixtures and stub executables; never reads or writes the
# real ~/.config/opencode or ~/.9router. Never calls an LLM. bash 3.2+, no frameworks.
# The repository files are only read (copied into fixture "installed" trees).

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
SRC="$ROOT/integrations/opencode"
DOCTOR="$HERE/doctor.sh"
BASH_BIN="${BASH:-/bin/bash}"
REAL_PATH="$PATH"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/tmpd"

pass=0; failn=0
ok() { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { failn=$((failn + 1)); echo "FAIL: $1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
contains() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3')" ;; esac; }
lacks() { case "$2" in *"$3"*) bad "$1 (found '$3')" ;; *) ok "$1" ;; esac; }

SENTINEL_CFG="SENTINEL-CONFIG-KEY-9f3a"
SENTINEL_DB="SENTINEL-DB-SECRET-77c1"

# --- fixture builders ---------------------------------------------------------

mkdb() { # <path> [omit-table]
  local db="$1" omit="${2:-}"
  rm -f "$db"; mkdir -p "$(dirname "$db")"
  sqlite3 "$db" "
CREATE TABLE apiKeys (id TEXT PRIMARY KEY, name TEXT, key TEXT);
INSERT INTO apiKeys VALUES ('k1','n','$SENTINEL_DB-apikey');
CREATE TABLE providerConnections (id TEXT PRIMARY KEY, data TEXT);
INSERT INTO providerConnections VALUES ('c1','{\"token\":\"$SENTINEL_DB-conn\"}');
CREATE TABLE settings (id TEXT PRIMARY KEY, data TEXT);
INSERT INTO settings VALUES ('s','$SENTINEL_DB-settings');
CREATE TABLE kv (k TEXT PRIMARY KEY, value TEXT);
INSERT INTO kv VALUES ('a','$SENTINEL_DB-kv');
CREATE TABLE combos (id TEXT PRIMARY KEY, name TEXT UNIQUE NOT NULL, kind TEXT, models TEXT NOT NULL, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL);
INSERT INTO combos VALUES ('strong','strong','','[\"cx/gpt-5.6-sol\"]','t','t');
CREATE TABLE usageHistory (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp TEXT NOT NULL, provider TEXT, model TEXT, connectionId TEXT, apiKey TEXT, endpoint TEXT, promptTokens INTEGER DEFAULT 0, completionTokens INTEGER DEFAULT 0, cost REAL DEFAULT 0, status TEXT, tokens TEXT, meta TEXT);
INSERT INTO usageHistory (timestamp,provider,model,apiKey,status) VALUES ('t','codex','gpt-5.6-sol','$SENTINEL_DB-usage','ok');
INSERT INTO usageHistory (timestamp,provider,model,apiKey,status) VALUES ('t','codex','gpt-5.6-sol','$SENTINEL_DB-usage','ok');" || return 1
  [ -n "$omit" ] && sqlite3 "$db" "DROP TABLE $omit;"
  return 0
}

mkconfig() { # <path>
  cat >"$1" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": { "9router": { "options": { "apiKey": "$SENTINEL_CFG", "baseURL": "http://localhost:20128/v1" } } },
  "agent": {
    "economy":  { "mode": "all", "model": "9router/economy" },
    "standard": { "mode": "all", "model": "9router/standard" },
    "strong":   { "mode": "all", "model": "9router/strong" },
    "premium":  { "mode": "all", "model": "9router/premium" },
    "review-openai": { "mode": "subagent", "model": "9router/review-openai", "tools": { "write": false, "edit": false } },
    "review-claude": { "mode": "subagent", "model": "9router/review-claude", "tools": { "write": false, "edit": false } },
    "explorer": { "mode": "subagent", "model": "9router/ocg/deepseek-v4.1-flash" }
  }
}
EOF
}

mkstubs() { # <dir>: fake opencode first on PATH
  mkdir -p "$1"
  printf '#!/bin/sh\necho "opencode v0.0.0-stub"\n' >"$1/opencode"; chmod +x "$1/opencode"
}

mkmin() { # <dir> <excluded tool>...  minimal PATH dir of symlinks (plus the fake opencode)
  local d="$1" t p x skip
  shift
  rm -rf "$d"; mkdir -p "$d"
  mkstubs "$d"
  for t in bash sh env awk sed tr cut cat head grep sort paste dirname basename mktemp rm cmp \
    shasum sha256sum cksum sleep git jq sqlite3 cp chmod mkdir find uname wc date perl; do
    skip=0
    for x in "$@"; do [ "$x" = "$t" ] && skip=1; done
    [ "$skip" = 1 ] && continue
    p=$(PATH="$REAL_PATH" command -v "$t" 2>/dev/null) && [ -n "$p" ] && ln -s "$p" "$d/$t"
  done
}

F=""  # current fixture dir
mkfix() { # <name>: healthy "installed" tree under a temp HOME
  F="$TMP/$1"
  rm -rf "$F"
  local c="$F/home/.config/opencode"
  mkdir -p "$c/agents" "$c/commands" "$c/scripts" "$F/stubs"
  cp "$SRC"/agents/*.md "$c/agents/"
  cp "$SRC"/commands/*.md "$c/commands/"
  cp "$SRC/scripts/doctor.sh" "$SRC/scripts/review-route.sh" "$SRC/scripts/resolve-model-family.sh" "$c/scripts/"
  mkconfig "$c/opencode.json"
  mkdb "$F/home/.9router/db/data.sqlite" || bad "fixture db $1"
  mkstubs "$F/stubs"
  case "$F" in "$TMP"/*) ;; *) echo "fixture escaped TMP: $F" >&2; exit 2 ;; esac
}

OUT=""; RC=0
run_doctor() { # <doctor-script> [args...]: uses $F, $PATH_OVERRIDE
  local script="$1" p
  shift
  p="${PATH_OVERRIDE:-$F/stubs:$REAL_PATH}"
  OUT=$(env -i HOME="$F/home" NINEROUTER_DB="$F/home/.9router/db/data.sqlite" PATH="$p" TMPDIR="$TMP/tmpd" \
    "$BASH_BIN" "$script" "$@" 2>&1 </dev/null); RC=$?
}
status_of() { printf '%s\n' "$OUT" | awk -F= -v n="$1" '$1=="check" {cur=($2==n)} cur && $1=="status" {print $2; exit}'; }
detail_of() { printf '%s\n' "$OUT" | awk -v n="$1" '$0=="check=" n {cur=1; next} cur && /^detail=/ {sub(/^detail=/,""); print; exit}'; }
line_of() { printf '%s\n' "$OUT" | grep -x -- "$1" >/dev/null 2>&1; }
summary_of() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p" | tail -n 1; }
expect() { # <label> <check> <status>
  eq "$1" "$(status_of "$2")" "$3"
}

# --- 0: safety guards ---------------------------------------------------------
mkfix g0
case "$F/home" in "$TMP"/*) ok "0a fixture HOME under temp dir" ;; *) bad "0a fixture HOME under temp dir" ;; esac
[ "$F/home" != "${REAL_HOME:-$HOME}" ] && ok "0b fixture HOME differs from real HOME" || bad "0b fixture HOME differs from real HOME"
[ -x "$DOCTOR" ] || { bad "0c doctor.sh executable"; }
bash -n "$DOCTOR" && ok "0d doctor.sh syntax" || bad "0d doctor.sh syntax"

# --- A: healthy ---------------------------------------------------------------
mkfix A
run_doctor "$DOCTOR" --machine
eq "A1 exit 0" "$RC" 0
eq "A2 overall=pass" "$(summary_of overall)" pass
eq "A3 failed=0" "$(summary_of failed)" 0
eq "A4 warnings=0" "$(summary_of warnings)" 0
for c in exe_sqlite3 exe_opencode installed_orchestrator installed_commands installed_scripts installed_doctor \
  orchestrator_sync command_sync review_route_sync resolver_sync config_file config_impl_agents config_review_agents \
  config_explorer db_file db_open db_combos db_usagehistory checkpoint resolver_syntax resolver_smoke_non_claude \
  resolver_smoke_claude framing_valid framing_malformed framing_trailing_blank; do
  expect "A5 $c pass" "$c" pass
done
eq "A6 checkpoint detail" "$(detail_of checkpoint)" "checkpoint start = 2"
contains "A7 opencode version stub" "$(detail_of exe_opencode)" "stub"
eq "A8 sync not skipped" "$(detail_of orchestrator_sync)" "1 file(s) match repository"
run_doctor "$DOCTOR"
eq "A9 human exit 0" "$RC" 0
contains "A10 human PASS line" "$OUT" "PASS  checkpoint  checkpoint start = 2"
contains "A11 human summary" "$OUT" "Summary: "
line_of "overall=pass" && ok "A12 overall line" || bad "A12 overall line"
run_doctor "$DOCTOR" --quiet
eq "A13 quiet exit 0" "$RC" 0
lacks "A14 quiet hides PASS lines" "$OUT" "PASS  "
contains "A15 quiet summary" "$OUT" "overall=pass"
run_doctor "$DOCTOR" --bogus
eq "A16 bad flag exit 64" "$RC" 64
eq "A17 doctor tempdir cleaned" "$(ls -A "$TMP/tmpd" | wc -l | tr -d ' ')" 0

# --- B: missing opencode.json -------------------------------------------------
mkfix B; rm "$F/home/.config/opencode/opencode.json"
run_doctor "$DOCTOR" --machine
eq "B1 exit 2" "$RC" 2
expect "B2 config_file fail" config_file fail
expect "B3 impl agents not checked (warn)" config_impl_agents warn

# --- C: missing resolver ------------------------------------------------------
mkfix C; rm "$F/home/.config/opencode/scripts/resolve-model-family.sh"
run_doctor "$DOCTOR" --machine
eq "C1 exit 2" "$RC" 2
expect "C2 installed_scripts fail" installed_scripts fail
expect "C3 resolver_sync warn" resolver_sync warn
contains "C4 hint present" "$OUT" "hint=mkdir -p ~/.config/opencode/scripts/ && cp "

# --- D: installed file differs ------------------------------------------------
mkfix D; echo "# local edit" >>"$F/home/.config/opencode/commands/implement-spec.md"
run_doctor "$DOCTOR" --machine
eq "D1 exit 1" "$RC" 1
eq "D2 overall=warn" "$(summary_of overall)" warn
expect "D3 command_sync warn" command_sync warn
contains "D4 detail" "$(detail_of command_sync)" "installed copy differs from repository"
expect "D5 orchestrator_sync still pass" orchestrator_sync pass
eq "D6 failed=0" "$(summary_of failed)" 0
mkfix D2; echo "# local edit" >>"$F/home/.config/opencode/agents/orchestrator.md"
run_doctor "$DOCTOR" --machine
expect "D7 orchestrator_sync warn" orchestrator_sync warn
mkfix D3; echo "# local edit" >>"$F/home/.config/opencode/scripts/review-route.sh"
run_doctor "$DOCTOR" --machine
expect "D8 review_route_sync warn" review_route_sync warn
mkfix D4; echo "# local edit" >>"$F/home/.config/opencode/scripts/resolve-model-family.sh"
run_doctor "$DOCTOR" --machine
expect "D9 resolver_sync warn" resolver_sync warn
mkfix D5; rm "$F/home/.config/opencode/commands/split-spec.md"
run_doctor "$DOCTOR" --machine
eq "D10 missing command => fail (exit 2)" "$RC" 2
expect "D11 installed_commands fail" installed_commands fail
expect "D12 command_sync warn" command_sync warn

# --- E: missing sqlite3 -------------------------------------------------------
mkfix E; mkmin "$F/min" sqlite3
PATH_OVERRIDE="$F/min" run_doctor "$DOCTOR" --machine
eq "E1 exit 2" "$RC" 2
expect "E2 exe_sqlite3 fail" exe_sqlite3 fail
expect "E3 db_file not checked" db_file warn
expect "E4 checkpoint not checked" checkpoint warn
# control: the minimal PATH dir is itself sufficient when sqlite3 is present
mkmin "$F/min2"
PATH_OVERRIDE="$F/min2" run_doctor "$DOCTOR" --machine
eq "E5 minimal PATH with sqlite3 is healthy" "$RC" 0

# --- F: missing DB ------------------------------------------------------------
mkfix F; rm "$F/home/.9router/db/data.sqlite"
run_doctor "$DOCTOR" --machine
eq "F1 exit 2" "$RC" 2
expect "F2 db_file fail" db_file fail
expect "F3 checkpoint not checked" checkpoint warn

# --- G/H: missing tables ------------------------------------------------------
mkfix G; mkdb "$F/home/.9router/db/data.sqlite" combos
run_doctor "$DOCTOR" --machine
eq "G1 exit 2" "$RC" 2
expect "G2 db_combos fail" db_combos fail
expect "G3 db_usagehistory pass" db_usagehistory pass
mkfix H; mkdb "$F/home/.9router/db/data.sqlite" usageHistory
run_doctor "$DOCTOR" --machine
eq "H1 exit 2" "$RC" 2
expect "H2 db_usagehistory fail" db_usagehistory fail
expect "H3 db_combos pass" db_combos pass
mkfix H4; sqlite3 "$F/home/.9router/db/data.sqlite" "ALTER TABLE combos RENAME COLUMN models TO modelz;"
run_doctor "$DOCTOR" --machine
expect "H4 missing column fails" db_combos fail
mkfix H5; echo "not a database" >"$F/home/.9router/db/data.sqlite"
run_doctor "$DOCTOR" --machine
expect "H5 corrupt DB fails" db_open fail

# --- I: checkpoint helper failure --------------------------------------------
mkfix I
printf '#!/usr/bin/env bash\necho 5\necho oops >&2\nexit 0\n' >"$F/home/.config/opencode/scripts/review-route.sh"
run_doctor "$DOCTOR" --machine
eq "I1 exit 2" "$RC" 2
expect "I2 checkpoint fail (stderr output)" checkpoint fail
mkfix I2
printf '#!/usr/bin/env bash\nprintf "5\\n\\n"\n' >"$F/home/.config/opencode/scripts/review-route.sh"
run_doctor "$DOCTOR" --machine
expect "I3 checkpoint fail (extra blank line)" checkpoint fail
mkfix I3
printf '#!/usr/bin/env bash\nexit 2\n' >"$F/home/.config/opencode/scripts/review-route.sh"
run_doctor "$DOCTOR" --machine
expect "I4 checkpoint fail (exit 2)" checkpoint fail

# --- J: resolver fixture gives wrong reviewer --------------------------------
mkfix J
cat >"$F/home/.config/opencode/scripts/resolve-model-family.sh" <<'EOF'
#!/usr/bin/env bash
printf 'status=resolved\ncombo=%s\nwindow=%s-%s\nfamily=claude\nreviewer=review-openai\nmodels=m\nproviders=p\nusage_ids=1\n' "$3" "$1" "$2"
EOF
chmod +x "$F/home/.config/opencode/scripts/resolve-model-family.sh"
run_doctor "$DOCTOR" --machine
eq "J1 exit 2" "$RC" 2
expect "J2 non-claude smoke fails" resolver_smoke_non_claude fail
expect "J3 claude smoke passes" resolver_smoke_claude pass
mkfix J2; printf '#!/usr/bin/env bash\nif then\n' >"$F/home/.config/opencode/scripts/resolve-model-family.sh"
run_doctor "$DOCTOR" --machine
expect "J4 syntax error fails" resolver_syntax fail

# --- K: review-route malformed-output handling -------------------------------
mkfix K
cat >"$F/home/.config/opencode/scripts/review-route.sh" <<'EOF'
#!/usr/bin/env bash
# lax helper: accepts anything
case "$1" in
  checkpoint) echo 2 ;;
  resolve) printf 'model_resolution=resolved\nfamily=claude\nreviewer=review-openai\nmodels=m1\nproviders=p1\n' ;;
esac
EOF
run_doctor "$DOCTOR" --machine
eq "K1 exit 2" "$RC" 2
expect "K2 framing_malformed fail" framing_malformed fail
expect "K3 framing_trailing_blank fail" framing_trailing_blank fail
expect "K4 framing_valid pass" framing_valid pass

# --- L: no repository checkout -----------------------------------------------
mkfix L
mkdir -p "$TMP/outside"; cp "$DOCTOR" "$TMP/outside/doctor.sh"
run_doctor "$TMP/outside/doctor.sh" --machine
eq "L1 exit 0" "$RC" 0
for c in orchestrator_sync command_sync review_route_sync resolver_sync doctor_sync; do
  expect "L2 $c pass" "$c" pass
  eq "L3 $c skipped" "$(detail_of "$c")" "skipped (not a dev-agents checkout)"
done
# installed copy differing does not matter outside a checkout
echo "# local edit" >>"$F/home/.config/opencode/agents/orchestrator.md"
run_doctor "$TMP/outside/doctor.sh" --machine
eq "L4 differing install still exit 0 when skipped" "$RC" 0
# a copy of doctor.sh in a checkout-lookalike with a missing orchestrator file is also "not a checkout"
mkdir -p "$TMP/fake/integrations/opencode/scripts"; cp "$DOCTOR" "$TMP/fake/integrations/opencode/scripts/doctor.sh"
run_doctor "$TMP/fake/integrations/opencode/scripts/doctor.sh" --machine
eq "L5 lookalike without orchestrator.md skipped" "$(detail_of orchestrator_sync)" "skipped (not a dev-agents checkout)"

# --- M: no secrets printed ----------------------------------------------------
mkfix M
all=""
for mode in "" "--machine" "--quiet"; do
  run_doctor "$DOCTOR" $mode; all="$all$OUT"
done
rm "$F/home/.config/opencode/opencode.json"; mkconfig "$F/home/.config/opencode/opencode.json"
sed 's#"9router/strong"#"9router/'"$SENTINEL_CFG"'"#' "$F/home/.config/opencode/opencode.json" >"$F/cfg.tmp" && mv "$F/cfg.tmp" "$F/home/.config/opencode/opencode.json"
run_doctor "$DOCTOR"; all="$all$OUT"
mkfix M2; mkdb "$F/home/.9router/db/data.sqlite" combos
run_doctor "$DOCTOR"; all="$all$OUT"
lacks "M1 no config secret in output" "$all" "$SENTINEL_CFG"
lacks "M2 no DB secret in output" "$all" "$SENTINEL_DB"
lacks "M3 no apiKey word value leak" "$all" "apiKey"

# --- N: warn-only install -----------------------------------------------------
mkfix N
rm "$F/home/.config/opencode/commands/doctor.md" "$F/home/.config/opencode/agents/doctor.md" "$F/home/.config/opencode/scripts/doctor.sh"
run_doctor "$DOCTOR" --machine
eq "N1 exit 1" "$RC" 1
eq "N2 overall=warn" "$(summary_of overall)" warn
eq "N3 failed=0" "$(summary_of failed)" 0
expect "N4 installed_doctor warn" installed_doctor warn
contains "N5 hint line" "$OUT" "hint="
run_doctor "$DOCTOR" --quiet
eq "N6 quiet exit 1" "$RC" 1
contains "N7 quiet shows WARN" "$OUT" "WARN  installed_doctor"
mkfix N2; mkmin "$F/min" jq
PATH_OVERRIDE="$F/min" run_doctor "$DOCTOR" --machine
eq "N8 missing jq => warn-only exit 1" "$RC" 1
expect "N9 config_file warn without jq" config_file warn

# --- O: single failure -> exit 2 ---------------------------------------------
mkfix O; rm "$F/home/.config/opencode/scripts/review-route.sh"
run_doctor "$DOCTOR" --machine
eq "O1 exit 2" "$RC" 2
eq "O2 overall=fail" "$(summary_of overall)" fail
case "$(summary_of failed)" in 1) ok "O3 exactly one failure" ;; *) bad "O3 exactly one failure (got $(summary_of failed))" ;; esac

# --- P: config variants -------------------------------------------------------
mkfix P
sed 's#"mode": "all", "model": "9router/premium"#"mode": "subagent", "model": "9router/premium"#' "$F/home/.config/opencode/opencode.json" >"$F/c" && mv "$F/c" "$F/home/.config/opencode/opencode.json"
run_doctor "$DOCTOR" --machine
expect "P1 impl agent wrong mode fails" config_impl_agents fail
mkfix P2
sed 's#"9router/review-claude"#"openai/x"#' "$F/home/.config/opencode/opencode.json" >"$F/c" && mv "$F/c" "$F/home/.config/opencode/opencode.json"
run_doctor "$DOCTOR" --machine
expect "P2 non-9router model fails" config_review_agents fail
mkfix P3
sed 's#"explorer": {.*#"explorer": { "mode": "primary" }#' "$F/home/.config/opencode/opencode.json" >"$F/c" && mv "$F/c" "$F/home/.config/opencode/opencode.json"
run_doctor "$DOCTOR" --machine
expect "P3 explorer not subagent warns" config_explorer warn
mkfix P4; echo '{ "model": "x" }' >"$F/home/.config/opencode/opencode.json"
run_doctor "$DOCTOR" --machine
expect "P4 missing agent key fails" config_impl_agents fail
mkfix P5; echo '{ not json' >"$F/home/.config/opencode/opencode.json"
run_doctor "$DOCTOR" --machine
expect "P5 invalid JSON fails" config_file fail
mkfix P6
cat >"$F/home/.config/opencode/opencode.json" <<'EOF'
{ "agents": {
  "economy": {"mode":"all","model":{"providerID":"9router","model":"economy"}},
  "standard": {"mode":"all","model":"9router/standard"}, "strong": {"mode":"all","model":"9router/strong"},
  "premium": {"mode":"all","model":"9router/premium"},
  "review-openai": {"mode":"subagent","model":"9router/a"}, "review-claude": {"mode":"subagent","model":"9router/b"},
  "explorer": {"mode":"subagent"} } }
EOF
run_doctor "$DOCTOR" --machine
expect "P6 V2 'agents' key with expanded model accepted" config_impl_agents pass

# --- R: read-only proof -------------------------------------------------------
snap() { # <fixture> -> deterministic digest of tree listing + file checksums
  ( cd "$1" && find . | sort && find . -type f -exec cksum {} + | sort )
}
mkfix R
before=$(snap "$F")
run_doctor "$DOCTOR" --machine; run_doctor "$DOCTOR"
run_doctor "$DOCTOR" --quiet
after=$(snap "$F")
if [ "$before" = "$after" ]; then ok "R1 fixture tree and DB unchanged"; else bad "R1 fixture tree and DB unchanged"; fi
mkfix R2; echo "# local edit" >>"$F/home/.config/opencode/agents/orchestrator.md"; rm "$F/home/.config/opencode/commands/doctor.md"
before=$(snap "$F"); run_doctor "$DOCTOR" --machine; after=$(snap "$F")
if [ "$before" = "$after" ]; then ok "R2 unchanged even when warnings/hints are produced"; else bad "R2 unchanged even when warnings/hints are produced"; fi
# static checks: every sqlite3 invocation is read-only on the live DB (or targets the temp fixture DB)
live=$(grep -v '^[[:space:]]*#' "$DOCTOR" | grep -E 'sqlite3 ' | grep -v -e '-readonly' -e 'sqlite3 --version' -e 'sqlite3 "\$FIXDB"' -e 'command -v sqlite3' -e 'sqlite3 not found' -e 'sqlite3 \$' -e 'check ' -e 'HAVE_SQLITE' -e 'sqro()' || true)
if [ -z "$live" ]; then ok "R3 every live-DB sqlite3 call is -readonly"; else bad "R3 non-readonly sqlite3 call: $live"; fi
if grep -Eqi 'apiKeys|providerConnections|settings\.data|kv\.value|SELECT[^;]*(\.key|apiKey|token)' <(grep -v '^[[:space:]]*#' "$DOCTOR" | grep -v 'apiKey,endpoint'); then
  bad "R4 doctor.sh references credential-bearing columns"
else ok "R4 doctor.sh references no credential-bearing columns"; fi
if grep -Eq '(^|[^a-z_])(rm|mv|cp|ln|chmod|tee)[[:space:]]' <(grep -v '^[[:space:]]*#' "$DOCTOR" | grep -v 'hint\|cp_hint\|fixes=\|printf .mkdir\|check ' | grep -v 'rm -rf "\$TMP"' | grep -v 'chmod +x "\$TMP/') ; then
  bad "R5 doctor.sh contains file-mutating commands outside hints/cleanup"
else ok "R5 doctor.sh mutating commands only in hints/cleanup"; fi

echo
echo "Result: $pass passed, $failn failed"
[ "$failn" -eq 0 ]
