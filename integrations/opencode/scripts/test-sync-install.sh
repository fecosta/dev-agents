#!/usr/bin/env bash
# test-sync-install.sh — deterministic checks for sync-install.sh (v3c.2).
# Uses ONLY mktemp fixtures: a fixture "repo" holding a copy of the script under test, and a
# fixture HOME. Every invocation sets HOME to the fixture; the real ~/.config/opencode and
# ~/.9router are never read or written, and --apply never runs against the real HOME.
# bash 3.2+, no frameworks.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_UNDER_TEST="$HERE/sync-install.sh"
BASH_BIN="${BASH:-/bin/bash}"
REAL_PATH="$PATH"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/cwd"

pass=0; failn=0
ok() { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { failn=$((failn + 1)); echo "FAIL: $1"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
contains() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3')" ;; esac; }
lacks() { case "$2" in *"$3"*) bad "$1 (found '$3')" ;; *) ok "$1" ;; esac; }
hasline() { if printf '%s\n' "$2" | grep -qxF -- "$3"; then ok "$1"; else bad "$1 (no line '$3')"; fi; }
nline() { if printf '%s\n' "$2" | grep -qxF -- "$3"; then bad "$1 (unexpected line '$3')"; else ok "$1"; fi; }

SECRET_CFG="SENTINEL-CONFIG-SECRET-4d2e"
SECRET_ENV="SENTINEL-ENV-SECRET-8b1c"

MANIFEST="agents/orchestrator.md agents/doctor.md agents/sync-install.md
commands/implement-spec.md commands/route-task.md commands/review-change.md commands/split-spec.md commands/doctor.md commands/sync-install.md
scripts/review-route.sh scripts/resolve-model-family.sh scripts/doctor.sh scripts/sync-install.sh"
NMAN=13

F=""; REPO=""; HM=""; CFG=""
stub_doctor() { # <mode: pass|warn|fail|exit127|empty>
  local f="$REPO/integrations/opencode/scripts/doctor.sh"
  case "$1" in
    pass) printf '#!/bin/sh\nprintf "check=x\\nstatus=pass\\ndetail=ok\\noverall=pass\\npassed=1\\nwarnings=0\\nfailed=0\\n"\nexit 0\n' >"$f" ;;
    warn) printf '#!/bin/sh\nprintf "check=c_warn\\nstatus=warn\\ndetail=degraded thing\\noverall=warn\\npassed=0\\nwarnings=1\\nfailed=0\\n"\nexit 1\n' >"$f" ;;
    fail) printf '#!/bin/sh\nprintf "check=c_fail\\nstatus=fail\\ndetail=broken thing\\noverall=fail\\npassed=0\\nwarnings=0\\nfailed=1\\n"\nexit 2\n' >"$f" ;;
    exit127) printf '#!/bin/sh\nexit 127\n' >"$f" ;;
    empty) printf '#!/bin/sh\nexit 0\n' >"$f" ;;
  esac
  chmod 755 "$f"
}

mkfix() { # <name> [doctor mode]: fixture repo + fixture HOME with sentinels, EMPTY install
  F="$TMP/$1"; rm -rf "$F"
  REPO="$F/repo"; HM="$F/home"; CFG="$HM/.config/opencode"
  case "$F" in "$TMP"/*) ;; *) echo "fixture escaped TMP" >&2; exit 2 ;; esac
  local e
  mkdir -p "$REPO/integrations/opencode/agents" "$REPO/integrations/opencode/commands" "$REPO/integrations/opencode/scripts"
  mkdir -p "$HM/.9router/db" "$CFG"
  echo "agents contract" >"$REPO/AGENTS.md"
  for e in $MANIFEST; do
    case "$e" in
      scripts/sync-install.sh) cp "$SCRIPT_UNDER_TEST" "$REPO/integrations/opencode/$e" ;;
      *) printf 'dummy %s v1\n' "$e" >"$REPO/integrations/opencode/$e" ;;
    esac
    case "$e" in scripts/*) chmod 755 "$REPO/integrations/opencode/$e" ;; esac
  done
  stub_doctor "${2:-pass}"
  printf '{"provider":{"9router":{"options":{"apiKey":"%s"}}}}\n' "$SECRET_CFG" >"$CFG/opencode.json"
  printf 'router-sentinel-data %s\n' "$SECRET_CFG" >"$HM/.9router/db/data.sqlite"
  SYNC="$REPO/integrations/opencode/scripts/sync-install.sh"
}

install_all() { # make the install fully in sync (simulates a prior apply)
  local e m
  for e in $MANIFEST; do
    mkdir -p "$CFG/$(dirname "$e")"
    cp "$REPO/integrations/opencode/$e" "$CFG/$e"
    case "$e" in scripts/*) m=755 ;; *) m=644 ;; esac
    chmod "$m" "$CFG/$e"
  done
}

OUT=""; RC=0
run() { # args... ; runs the FIXTURE copy with HOME=fixture
  case "$SYNC" in "$TMP"/*) ;; *) echo "refusing to run non-fixture script" >&2; exit 2 ;; esac
  case "$HM" in "$TMP"/*) ;; *) echo "refusing non-fixture HOME" >&2; exit 2 ;; esac
  OUT=$(cd "$TMP/cwd" && env -i HOME="$HM" PATH="$REAL_PATH" SECRET_ENV="$SECRET_ENV" "$BASH_BIN" "$SYNC" "$@" 2>&1 </dev/null); RC=$?
}

fsum() { shasum -a 256 <"$1" | awk '{print $1}'; }
snap() { # <dir>: content hash + inode + mode listing of the whole tree (symlinks listed, not followed)
  (cd "$1" && find . -print | LC_ALL=C sort | while IFS= read -r p; do
    if [ -L "$p" ]; then echo "L $p -> $(readlink "$p")"
    elif [ -d "$p" ]; then echo "D $p $(ls -ldi "$p" | awk '{print $1, $2}')"
    else echo "F $p $(ls -li "$p" | awk '{print $1, $2}') $(fsum "$p")"; fi
  done)
}
ino() { ls -i "$1" | awk '{print $1}'; }
status_of() { printf '%s\n' "$OUT" | awk -v f="$1" '$0=="file=" f {getline; sub(/^status=/,""); print; exit}'; }
count() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p" | tail -n 1; }
files_in() { (cd "$1" && find . -type f | LC_ALL=C sort); }

echo "# script under test is the fixture copy"
mkfix t0
case "$SYNC" in "$TMP"/*) ok "script invoked from fixture, not the real checkout" ;; *) bad "script path" ;; esac

# A: clean --check
mkfix a; install_all; before=$(snap "$F")
run --check
eq "A exit 0" "$RC" 0
hasline "A sync_status=clean" "$OUT" "sync_status=clean"
eq "A in_sync=13" "$(count in_sync)" 13
eq "A tree unchanged" "$(snap "$F")" "$before"
eq "A first file status" "$(status_of agents/orchestrator.md)" in_sync

# B: missing
mkfix b; install_all; rm "$CFG/commands/route-task.md"; before=$(snap "$F")
run --check
eq "B exit 1" "$RC" 1
eq "B status missing" "$(status_of commands/route-task.md)" missing
eq "B missing=1" "$(count missing)" 1
hasline "B drift" "$OUT" "sync_status=drift"
eq "B no writes" "$(snap "$F")" "$before"

# C: different
mkfix c; install_all; echo changed >"$CFG/agents/doctor.md"; before=$(snap "$F")
run --check
eq "C exit 1" "$RC" 1
eq "C status different" "$(status_of agents/doctor.md)" different
eq "C different=1" "$(count different)" 1
eq "C no writes" "$(snap "$F")" "$before"

# D: apply missing copies only that file
mkfix d; install_all; rm "$CFG/commands/route-task.md"
i1=$(ino "$CFG/agents/doctor.md"); i2=$(ino "$CFG/scripts/doctor.sh")
run --apply
eq "D exit 0" "$RC" 0
hasline "D copied only route-task" "$OUT" "copied=commands/route-task.md"
eq "D one copied line" "$(printf '%s\n' "$OUT" | grep -c '^copied=')" 1
eq "D content" "$(fsum "$CFG/commands/route-task.md")" "$(fsum "$REPO/integrations/opencode/commands/route-task.md")"
eq "D others untouched (inode a)" "$(ino "$CFG/agents/doctor.md")" "$i1"
eq "D others untouched (inode b)" "$(ino "$CFG/scripts/doctor.sh")" "$i2"
hasline "D applied" "$OUT" "status=applied"
hasline "D doctor_overall=pass" "$OUT" "doctor_overall=pass"

# E: apply different
mkfix e; install_all; echo changed >"$CFG/agents/doctor.md"; i1=$(ino "$CFG/commands/doctor.md")
run --apply
eq "E exit 0" "$RC" 0
eq "E updated" "$(fsum "$CFG/agents/doctor.md")" "$(fsum "$REPO/integrations/opencode/agents/doctor.md")"
eq "E one copied" "$(printf '%s\n' "$OUT" | grep -c '^copied=')" 1
eq "E other untouched" "$(ino "$CFG/commands/doctor.md")" "$i1"
eq "E mode 644" "$(ls -l "$CFG/agents/doctor.md" | cut -c1-10)" "-rw-r--r--"

# F: in-sync not rewritten
mkfix f; install_all; touch -t 202001010000 "$CFG/commands/split-spec.md"
i1=$(ino "$CFG/commands/split-spec.md"); s1=$(ls -l "$CFG/commands/split-spec.md" | awk '{print $6,$7,$8}'); h1=$(fsum "$CFG/commands/split-spec.md")
echo changed >"$CFG/commands/doctor.md"
run --apply
eq "F exit 0" "$RC" 0
eq "F inode same" "$(ino "$CFG/commands/split-spec.md")" "$i1"
eq "F mtime same" "$(ls -l "$CFG/commands/split-spec.md" | awk '{print $6,$7,$8}')" "$s1"
eq "F hash same" "$(fsum "$CFG/commands/split-spec.md")" "$h1"
nline "F not listed copied" "$OUT" "copied=commands/split-spec.md"

# F2: fully in-sync apply is a no-op that still runs doctor
mkfix f2; install_all; before=$(snap "$F")
run --apply
eq "F2 exit 0" "$RC" 0
eq "F2 no copied" "$(printf '%s\n' "$OUT" | grep -c '^copied=')" 0
hasline "F2 doctor ran" "$OUT" "doctor_overall=pass"
eq "F2 tree unchanged" "$(snap "$F")" "$before"

# G: multiple differences
mkfix g; install_all; rm "$CFG/commands/route-task.md" "$CFG/scripts/review-route.sh"; echo x >"$CFG/agents/orchestrator.md"
run --check
eq "G exit 1" "$RC" 1
eq "G missing=2" "$(count missing)" 2
eq "G different=1" "$(count different)" 1
eq "G in_sync=10" "$(count in_sync)" 10
run --apply
eq "G apply exit 0" "$RC" 0
eq "G three copied" "$(printf '%s\n' "$OUT" | grep -c '^copied=')" 3
run --check
eq "G clean after" "$RC" 0

# H: source manifest file missing
mkfix h; rm "$REPO/integrations/opencode/commands/split-spec.md"; before=$(snap "$F")
run --apply
eq "H exit 2" "$RC" 2
hasline "H reason" "$OUT" "reason=SOURCE_FILE_MISSING"
eq "H nothing written" "$(snap "$F")" "$before"
mkfix h2; install_all; echo x >"$CFG/agents/doctor.md"; rm "$REPO/integrations/opencode/scripts/doctor.sh"; before=$(snap "$F")
run --apply
eq "H2 exit 2 (doctor source missing)" "$RC" 2
eq "H2 nothing written (even the differing file)" "$(snap "$F")" "$before"
mkfix h3; ln -s ../agents/doctor.md "$REPO/integrations/opencode/commands/zz"; rm "$REPO/integrations/opencode/commands/route-task.md"; ln -s ../agents/doctor.md "$REPO/integrations/opencode/commands/route-task.md"; before=$(snap "$F")
run --apply
eq "H3 symlinked source rejected" "$RC" 2
hasline "H3 reason" "$OUT" "reason=SOURCE_FILE_MISSING"
eq "H3 nothing written" "$(snap "$F")" "$before"

# I: unverified source
for miss in AGENTS.md integrations/opencode/agents/orchestrator.md; do
  mkfix i; rm "$REPO/$miss"; before=$(snap "$F")
  run --apply
  eq "I exit 2 ($miss)" "$RC" 2
  hasline "I reason ($miss)" "$OUT" "reason=SOURCE_REPOSITORY_UNVERIFIED"
  hasline "I status=failed ($miss)" "$OUT" "status=failed"
  hasline "I sync_status=failed ($miss)" "$OUT" "sync_status=failed"
  eq "I no writes ($miss)" "$(snap "$F")" "$before"
  run --check
  eq "I check exit 2 ($miss)" "$RC" 2
done
# script outside any checkout layout (like the installed copy)
mkfix i3; install_all; before=$(snap "$F")
SYNC="$CFG/scripts/sync-install.sh"; run --apply
eq "I installed copy fails closed" "$RC" 2
hasline "I installed copy reason" "$OUT" "reason=SOURCE_REPOSITORY_UNVERIFIED"
eq "I installed copy no writes" "$(snap "$F")" "$before"

# J: destination escapes
mkfix j1; install_all; mkdir "$F/outside"; rm -rf "$CFG/commands"; ln -s "$F/outside" "$CFG/commands"; echo x >"$CFG/agents/doctor.md"
before=$(snap "$F")
run --apply
eq "J1 symlinked subdir exit 2" "$RC" 2
hasline "J1 reason" "$OUT" "reason=DESTINATION_UNSAFE"
eq "J1 nothing written" "$(snap "$F")" "$before"
mkfix j2; install_all; echo secret-outside >"$F/outside.txt"; rm "$CFG/agents/doctor.md"; ln -s "$F/outside.txt" "$CFG/agents/doctor.md"; echo x >"$CFG/scripts/doctor.sh"
before=$(snap "$F")
run --apply
eq "J2 symlinked file exit 2" "$RC" 2
hasline "J2 reason" "$OUT" "reason=DESTINATION_UNSAFE"
eq "J2 nothing written" "$(snap "$F")" "$before"
eq "J2 outside file intact" "$(cat "$F/outside.txt")" "secret-outside"
run --check
eq "J2 check also fails" "$RC" 2
mkfix j3; install_all; mv "$CFG" "$F/realcfg"; ln -s "$F/realcfg" "$CFG"; echo x >"$F/realcfg/agents/doctor.md"
before=$(snap "$F")
run --apply
eq "J3 symlinked root exit 2" "$RC" 2
hasline "J3 reason" "$OUT" "reason=DESTINATION_UNSAFE"
eq "J3 nothing written" "$(snap "$F")" "$before"
mkfix j4; ln -s "$F/nowhere" "$CFG/scripts"; before=$(snap "$F")
run --apply
eq "J4 dangling symlink subdir exit 2" "$RC" 2
eq "J4 nothing written" "$(snap "$F")" "$before"

# K/L/M/W: sentinels and write boundary on an empty install
mkfix k
cfg_h=$(fsum "$CFG/opencode.json"); rt_h=$(fsum "$HM/.9router/db/data.sqlite")
echo "my private notes" >"$CFG/notes.txt"; mkdir -p "$CFG/agents"; echo "mine" >"$CFG/agents/custom.md"
run --apply
eq "K/W exit 0" "$RC" 0
eq "K opencode.json byte-identical" "$(fsum "$CFG/opencode.json")" "$cfg_h"
eq "L .9router sentinel identical" "$(fsum "$HM/.9router/db/data.sqlite")" "$rt_h"
eq "M unmanaged root file kept" "$(cat "$CFG/notes.txt")" "my private notes"
eq "M unmanaged agent kept" "$(cat "$CFG/agents/custom.md")" "mine"
want=$( (for e in $MANIFEST; do echo "./.config/opencode/$e"; done; echo ./.config/opencode/opencode.json; echo ./.config/opencode/notes.txt; echo ./.config/opencode/agents/custom.md; echo ./.9router/db/data.sqlite) | LC_ALL=C sort)
eq "W only manifest files written" "$(files_in "$HM")" "$want"
eq "W exactly 13 copied lines" "$(printf '%s\n' "$OUT" | grep -c '^copied=')" "$NMAN"
eq "W ls of dirs: only 3 dirs created" "$(cd "$CFG" && ls -d */ | LC_ALL=C sort | tr '\n' ' ')" "agents/ commands/ scripts/ "

# N: exec bits
for s in review-route resolve-model-family doctor sync-install; do
  eq "N scripts/$s.sh is 755" "$(ls -l "$CFG/scripts/$s.sh" | cut -c1-10)" "-rwxr-xr-x"
done
eq "N markdown 644" "$(ls -l "$CFG/commands/doctor.md" | cut -c1-10)" "-rw-r--r--"
mkfix n2; install_all; chmod 644 "$CFG/scripts/review-route.sh"; i1=$(ino "$CFG/scripts/review-route.sh")
run --check
eq "N2 non-exec script is drift" "$RC" 1
eq "N2 status different" "$(status_of scripts/review-route.sh)" different
hasline "N2 would_chmod" "$OUT" "would_chmod=scripts/review-route.sh"
eq "N2 check did not chmod" "$(ls -l "$CFG/scripts/review-route.sh" | cut -c1-10)" "-rw-r--r--"
run --apply
eq "N2 apply exit 0" "$RC" 0
hasline "N2 chmodded reported" "$OUT" "chmodded=scripts/review-route.sh"
eq "N2 now executable" "$(ls -l "$CFG/scripts/review-route.sh" | cut -c1-10)" "-rwxr-xr-x"
eq "N2 not rewritten" "$(ino "$CFG/scripts/review-route.sh")" "$i1"
eq "N2 no copied" "$(printf '%s\n' "$OUT" | grep -c '^copied=')" 0

# O: doctor pass
mkfix o pass
run --apply
eq "O exit 0" "$RC" 0
hasline "O status=applied" "$OUT" "status=applied"
hasline "O doctor_failed=0" "$OUT" "doctor_failed=0"
hasline "O sync_status=clean" "$OUT" "sync_status=clean"

# P/Q/R: doctor not clean
mkfix p warn
run --apply
eq "P warn exit 2" "$RC" 2
hasline "P reason" "$OUT" "reason=POST_INSTALL_DOCTOR_FAILED"
hasline "P doctor_overall=warn" "$OUT" "doctor_overall=warn"
hasline "P non-pass check shown" "$OUT" "doctor_check=c_warn"
eq "P copied list present" "$(printf '%s\n' "$OUT" | grep -c '^copied=')" "$NMAN"
nline "P not applied" "$OUT" "status=applied"
eq "P files stay (no rollback)" "$(test -f "$CFG/agents/doctor.md" && echo yes)" yes
mkfix q fail
run --apply
eq "Q fail exit 2" "$RC" 2
hasline "Q reason" "$OUT" "reason=POST_INSTALL_DOCTOR_FAILED"
hasline "Q doctor_overall=fail" "$OUT" "doctor_overall=fail"
hasline "Q doctor_failed=1" "$OUT" "doctor_failed=1"
hasline "Q check detail" "$OUT" "doctor_check_detail=broken thing"
mkfix r exit127
run --apply
eq "R doctor exit 127 -> exit 2" "$RC" 2
hasline "R reason" "$OUT" "reason=POST_INSTALL_DOCTOR_FAILED"
mkfix r2 empty
run --apply
eq "R2 doctor with no overall -> exit 2" "$RC" 2
hasline "R2 reason" "$OUT" "reason=POST_INSTALL_DOCTOR_FAILED"
mkfix r3 pass
printf '#!/bin/sh\nprintf "overall=pass\\npassed=1\\nwarnings=0\\nfailed=0\\n"\nexit 3\n' >"$REPO/integrations/opencode/scripts/doctor.sh"
run --apply
eq "R3 pass text but nonzero exit -> exit 2" "$RC" 2

# S: no-arg is read-only check
mkfix s; before=$(snap "$F")
run
eq "S no-arg exit 1 (empty install)" "$RC" 1
hasline "S mode=check" "$OUT" "mode=check"
eq "S missing=13" "$(count missing)" 13
eq "S no writes" "$(snap "$F")" "$before"
eq "S install dirs not created" "$(test -d "$CFG/agents" && echo yes || echo no)" no
eq "S cwd clean" "$(ls -A "$TMP/cwd" | wc -l | tr -d ' ')" 0

# T: usage errors
mkfix t; before=$(snap "$F")
for a in "--bogus" "apply" "--help" ""; do
  run "$a"
  eq "T exit 64 for '$a'" "$RC" 64
done
run --check --apply
eq "T two args exit 64" "$RC" 64
run --apply --apply
eq "T two args (same) exit 64" "$RC" 64
hasline "T reason USAGE" "$OUT" "reason=USAGE"
eq "T no writes" "$(snap "$F")" "$before"

# U: no secrets in output
mkfix u; install_all; echo x >"$CFG/agents/doctor.md"
run --check; all="$OUT"
run --apply; all="$all$OUT"
mkfix u2 fail
run --apply; all="$all$OUT"
lacks "U config secret not printed" "$all" "$SECRET_CFG"
lacks "U env secret not printed" "$all" "$SECRET_ENV"
lacks "U router sentinel not printed" "$all" "router-sentinel"

# V: whole-tree identical across --check (both repo and home)
mkfix v; install_all; echo x >"$CFG/agents/doctor.md"; rm "$CFG/commands/route-task.md"; before=$(snap "$F")
run --check
eq "V exit 1" "$RC" 1
eq "V tree identical" "$(snap "$F")" "$before"

# HOME invalid
mkfix hm; before=$(snap "$F")
OUT=$(cd "$TMP/cwd" && env -i PATH="$REAL_PATH" "$BASH_BIN" "$SYNC" --apply 2>&1 </dev/null); RC=$?
eq "HOME unset exit 2" "$RC" 2
hasline "HOME unset reason" "$OUT" "reason=HOME_INVALID"
OUT=$(cd "$TMP/cwd" && env -i HOME="relative/home" PATH="$REAL_PATH" "$BASH_BIN" "$SYNC" --apply 2>&1 </dev/null); RC=$?
eq "HOME relative exit 2" "$RC" 2
hasline "HOME relative reason" "$OUT" "reason=HOME_INVALID"
OUT=$(cd "$TMP/cwd" && env -i HOME="" PATH="$REAL_PATH" "$BASH_BIN" "$SYNC" --check 2>&1 </dev/null); RC=$?
eq "HOME empty exit 2" "$RC" 2
eq "HOME cases: no writes" "$(snap "$F")" "$before"
eq "HOME cases: cwd clean" "$(ls -A "$TMP/cwd" | wc -l | tr -d ' ')" 0

# No leftover temp files after success
mkfix lt; run --apply
eq "no .sync-install temp leftovers" "$(find "$HM" -name '.sync-install.*' | wc -l | tr -d ' ')" 0

# Static: helper contains no forbidden constructs
bodyfile="$SCRIPT_UNDER_TEST"
code=$(grep -v '^[[:space:]]*#' "$bodyfile")
for pat in '\bgit\b' 'rsync' 'cp -r' 'cp -R' 'sqlite' 'opencode\.json' '9router' '\brm -r'; do
  if printf '%s\n' "$code" | grep -Eq -- "$pat"; then bad "static: helper code contains /$pat/"; else ok "static: no /$pat/ in helper code"; fi
done

echo
echo "Summary: $pass passed, $failn failed"
[ "$failn" -eq 0 ]
