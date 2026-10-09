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

F=""; REPO=""; HM=""; CFG=""; HOOK=""; RUNPATH="$REAL_PATH"
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
  HOOK=""; RUNPATH="$REAL_PATH"
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
  OUT=$(cd "$TMP/cwd" && env -i HOME="$HM" PATH="$RUNPATH" SECRET_ENV="$SECRET_ENV" ${HOOK:+"DEV_AGENTS_SYNC_TEST_HOOK=$HOOK"} "$BASH_BIN" "$SYNC" "$@" 2>&1 </dev/null); RC=$?
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

# --- v3c.2 hardening: post-preflight races, staging, checksum tool ---------------------------
# The script's test-only hook (DEV_AGENTS_SYNC_TEST_HOOK) runs "<hook> <phase> <entry>" right before
# each revalidation+operation, so a swap done by the hook is exercised by the live recheck.
mkhook() { # <name> <sh body; $1=phase $2=entry>: sets HOOK to an absolute executable fixture script
  HOOK="$F/hook-$1.sh"
  printf '#!/bin/sh\n%s\n' "$2" >"$HOOK"; chmod 755 "$HOOK"
}

# R1: hook invocation rules
mkfix hk1; install_all; echo x >"$CFG/agents/doctor.md"
mkhook log "echo \"\$1 \$2\" >>\"$F/hook.log\"; echo status=hooked; echo reason=HOOKED; exit 3"
run --apply
eq "R1 exit 0 (hook exit status ignored)" "$RC" 0
lacks "R1 hook stdout not in output" "$OUT" "hooked"
hasline "R1 after_staging fired" "$(cat "$F/hook.log")" "after_staging "
hasline "R1 before_mktemp fired" "$(cat "$F/hook.log")" "before_mktemp agents/doctor.md"
hasline "R1 before_mv fired" "$(cat "$F/hook.log")" "before_mv agents/doctor.md"
nline "R1 before_chmod not fired (no chmod action)" "$(cat "$F/hook.log")" "before_chmod agents/doctor.md"
mkfix hk2; echo x >/dev/null
mkhook log "echo \"\$1\" >>\"$F/hook.log\""
HOOK=""; run --apply
eq "R1 unset: hook not invoked" "$(test -e "$F/hook.log" && echo yes || echo no)" no
mkhook log "echo \"\$1\" >>\"$F/hook.log\""; chmod 644 "$HOOK"
run --apply
eq "R1 non-executable: hook not invoked" "$(test -e "$F/hook.log" && echo yes || echo no)" no
eq "R1 non-executable: apply still ok" "$RC" 0
mkfix hk3
printf '#!/bin/sh\necho "$1" >>"%s/hook.log"\n' "$F" >"$F/relhook.sh"; chmod 755 "$F/relhook.sh"
HOOK="relhook.sh"; cp "$F/relhook.sh" "$TMP/cwd/relhook.sh"
run --apply
rm -f "$TMP/cwd/relhook.sh"
eq "R1 relative path: hook not invoked" "$(test -e "$F/hook.log" && echo yes || echo no)" no
eq "R1 relative path: apply still ok" "$RC" 0

# R2 (finding A): destination subdir swapped to a symlink after validation, before mktemp / before mv
for ph in before_mktemp before_mv; do
  mkfix ra_$ph; install_all; echo changed >"$CFG/commands/route-task.md"
  mkdir "$F/outside"; echo precious >"$F/outside/route-task.md"; echo keep >"$F/outside/other.txt"
  mkhook swap "[ \"\$1\" = $ph ] && [ \"\$2\" = commands/route-task.md ] && mv \"$CFG/commands\" \"$F/moved-commands\" && ln -s \"$F/outside\" \"$CFG/commands\"; exit 0"
  ob=$(snap "$F/outside")
  run --apply
  eq "R2 $ph exit 2" "$RC" 2
  hasline "R2 $ph DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
  hasline "R2 $ph status=failed" "$OUT" "status=failed"
  eq "R2 $ph outside byte-identical (no new files)" "$(snap "$F/outside")" "$ob"
  eq "R2 $ph symlink not followed (still link)" "$(test -L "$CFG/commands" && echo yes)" yes
  nline "R2 $ph nothing reported copied" "$OUT" "copied=commands/route-task.md"
done

# R3 (finding B): managed destination file swapped to a symlink before the replacing mv
mkfix rb; install_all; echo changed >"$CFG/agents/doctor.md"; echo external >"$F/outside.txt"; chmod 600 "$F/outside.txt"
mkhook swap "[ \"\$1\" = before_mv ] && [ \"\$2\" = agents/doctor.md ] && rm -f \"$CFG/agents/doctor.md\" && ln -s \"$F/outside.txt\" \"$CFG/agents/doctor.md\"; exit 0"
oh=$(fsum "$F/outside.txt")
run --apply
eq "R3 exit 2" "$RC" 2
hasline "R3 DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
eq "R3 external target content untouched" "$(fsum "$F/outside.txt")" "$oh"
eq "R3 external target mode untouched" "$(ls -l "$F/outside.txt" | cut -c1-10)" "-rw-------"
eq "R3 dest still the symlink (not replaced through)" "$(test -L "$CFG/agents/doctor.md" && echo yes)" yes
eq "R3 temp file cleaned up" "$(find "$CFG" -name '.sync-install.*' | wc -l | tr -d ' ')" 0

# R4 (finding C): chmod-only action; destination swapped to a symlink before chmod
mkfix rc; install_all; chmod 644 "$CFG/scripts/review-route.sh"
echo "external script" >"$F/outside.sh"; chmod 644 "$F/outside.sh"
mkhook swap "[ \"\$1\" = before_chmod ] && [ \"\$2\" = scripts/review-route.sh ] && rm -f \"$CFG/scripts/review-route.sh\" && ln -s \"$F/outside.sh\" \"$CFG/scripts/review-route.sh\"; exit 0"
oh=$(fsum "$F/outside.sh")
run --check
hasline "R4 plan has would_chmod" "$OUT" "would_chmod=scripts/review-route.sh"
run --apply
eq "R4 exit 2" "$RC" 2
hasline "R4 DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
eq "R4 external mode unchanged" "$(ls -l "$F/outside.sh" | cut -c1-10)" "-rw-r--r--"
eq "R4 external content unchanged" "$(fsum "$F/outside.sh")" "$oh"
nline "R4 not reported chmodded" "$OUT" "chmodded=scripts/review-route.sh"

# R5: earlier work is still reported when a later swap aborts (apply_fail prints copied=)
mkfix rd; install_all; echo c1 >"$CFG/agents/doctor.md"; echo c2 >"$CFG/commands/route-task.md"; mkdir "$F/outside"
mkhook swap "[ \"\$1\" = before_mktemp ] && [ \"\$2\" = commands/route-task.md ] && mv \"$CFG/commands\" \"$F/moved\" && ln -s \"$F/outside\" \"$CFG/commands\"; exit 0"
run --apply
eq "R5 exit 2" "$RC" 2
hasline "R5 earlier copy reported" "$OUT" "copied=agents/doctor.md"
eq "R5 outside empty" "$(ls -A "$F/outside" | wc -l | tr -d ' ')" 0

# R6 (finding D): repo source path swapped to a symlink/external file after the snapshot
mkfix re; echo "EXTERNAL-DATA" >"$F/external.md"
mkhook swap "[ \"\$1\" = after_staging ] && rm -f \"$REPO/integrations/opencode/commands/route-task.md\" && ln -s \"$F/external.md\" \"$REPO/integrations/opencode/commands/route-task.md\"; exit 0"
run --apply
eq "R6 exit 0" "$RC" 0
eq "R6 installed = staged original" "$(cat "$CFG/commands/route-task.md")" "dummy commands/route-task.md v1"
eq "R6 installed file is a regular file" "$(test -f "$CFG/commands/route-task.md" && test ! -L "$CFG/commands/route-task.md" && echo yes)" yes
eq "R6 external data never installed" "$(grep -rl EXTERNAL-DATA "$CFG" | wc -l | tr -d ' ')" 0

# R7 (finding E): repo source bytes mutated after the snapshot
mkfix rf
mkhook mut "[ \"\$1\" = after_staging ] && echo MUTATED >\"$REPO/integrations/opencode/agents/orchestrator.md\" && echo MUTATED >\"$REPO/integrations/opencode/commands/route-task.md\"; exit 0"
run --apply
eq "R7 exit 0" "$RC" 0
eq "R7 agents bytes = staged original" "$(cat "$CFG/agents/orchestrator.md")" "dummy agents/orchestrator.md v1"
eq "R7 commands bytes = staged original" "$(cat "$CFG/commands/route-task.md")" "dummy commands/route-task.md v1"
eq "R7 no MUTATED installed" "$(grep -rl MUTATED "$CFG" | wc -l | tr -d ' ')" 0
mkfix rf2; install_all
mkhook mut "[ \"\$1\" = after_staging ] && echo MUTATED >\"$REPO/integrations/opencode/agents/orchestrator.md\"; exit 0"
run --check
eq "R7 check: drift decided from staged copy (clean)" "$RC" 0

# R8: staging dir removed, in every outcome
tcount() { find "$1" -maxdepth 1 -name 'sync-install.*' | wc -l | tr -d ' '; }
mkfix rs; mkdir "$F/tmpd"
OUT=$(cd "$TMP/cwd" && env -i HOME="$HM" PATH="$REAL_PATH" TMPDIR="$F/tmpd" "$BASH_BIN" "$SYNC" --apply 2>&1 </dev/null); RC=$?
eq "R8 apply ok with TMPDIR" "$RC" 0
eq "R8 staging removed after apply" "$(tcount "$F/tmpd")" 0
OUT=$(cd "$TMP/cwd" && env -i HOME="$HM" PATH="$REAL_PATH" TMPDIR="$F/tmpd" "$BASH_BIN" "$SYNC" --check 2>&1 </dev/null); RC=$?
eq "R8 staging removed after check" "$(tcount "$F/tmpd")" 0
mkfix rs2; mkdir "$F/tmpd"; rm "$REPO/integrations/opencode/commands/split-spec.md"
OUT=$(cd "$TMP/cwd" && env -i HOME="$HM" PATH="$REAL_PATH" TMPDIR="$F/tmpd" "$BASH_BIN" "$SYNC" --apply 2>&1 </dev/null); RC=$?
eq "R8 failing run exits 2" "$RC" 2
eq "R8 staging removed after failure" "$(tcount "$F/tmpd")" 0
mkfix rs3; mkdir "$F/tmpd"; install_all; echo x >"$CFG/agents/doctor.md"
mkhook st "[ \"\$1\" = after_staging ] && ls \"$F/tmpd\"/sync-install.*/agents >\"$F/stg.list\"; stat -f %Lp \"$F/tmpd\"/sync-install.* >\"$F/stg.mode\" 2>/dev/null || stat -c %a \"$F\"/tmpd/sync-install.* >\"$F/stg.mode\"; exit 0"
OUT=$(cd "$TMP/cwd" && env -i HOME="$HM" PATH="$REAL_PATH" TMPDIR="$F/tmpd" DEV_AGENTS_SYNC_TEST_HOOK="$HOOK" "$BASH_BIN" "$SYNC" --check 2>&1 </dev/null); RC=$?
contains "R8 staged snapshot holds managed files" "$(cat "$F/stg.list")" "doctor.md"
eq "R8 staging dir mode 700" "$(cat "$F/stg.mode")" 700

# R9 (finding 3): checksum tool selection through PATH only
mkbin() { # <dir> <shasum|sha256sum|none>: restricted PATH dir; shasum/sha256sum are logging wrappers
  local d="$1" t real
  mkdir -p "$d"
  for t in dirname mktemp mkdir chmod cat rm rmdir mv ls tr cut sed grep head cksum stat; do
    real=$(PATH="$REAL_PATH" command -v "$t") && ln -sf "$real" "$d/$t"
  done
  real=$(PATH="$REAL_PATH" command -v shasum)
  case "$2" in
    shasum) printf '#!/bin/sh\necho "shasum $*" >>"%s/tool.log"\nexec "%s" "$@"\n' "$F" "$real" >"$d/shasum"; chmod 755 "$d/shasum" ;;
    sha256sum) printf '#!/bin/sh\necho "sha256sum $*" >>"%s/tool.log"\nexec "%s" -a 256 "$@"\n' "$F" "$real" >"$d/sha256sum"; chmod 755 "$d/sha256sum" ;;
  esac
}
mkfix ck1; install_all; mkbin "$F/bin1" shasum; mkbin "$F/bin1b" sha256sum
RUNPATH="$F/bin1"; run --check
eq "R9 shasum clean" "$RC" 0
hasline "R9 checksum_tool=shasum" "$OUT" "checksum_tool=shasum"
contains "R9 shasum invoked with -a 256" "$(cat "$F/tool.log")" "shasum -a 256"
# both present: shasum wins
cp "$F/bin1b/sha256sum" "$F/bin1/sha256sum"; rm -f "$F/tool.log"; run --check
hasline "R9 shasum preferred over sha256sum" "$OUT" "checksum_tool=shasum"
lacks "R9 sha256sum not invoked when shasum works" "$(cat "$F/tool.log")" "sha256sum"
# sha256sum fallback
rm -f "$F/tool.log"; RUNPATH="$F/bin1b"; run --check
eq "R9 sha256sum fallback clean" "$RC" 0
hasline "R9 checksum_tool=sha256sum" "$OUT" "checksum_tool=sha256sum"
contains "R9 sha256sum invoked" "$(cat "$F/tool.log")" "sha256sum"
echo changed >"$CFG/agents/doctor.md"; run --check
eq "R9 sha256sum detects drift" "$RC" 1
eq "R9 sha256sum drift status" "$(status_of agents/doctor.md)" different
# cksum fallback only when neither exists
mkbin "$F/bin2" none; RUNPATH="$F/bin2"; run --check
hasline "R9 checksum_tool=cksum" "$OUT" "checksum_tool=cksum"
eq "R9 cksum detects drift" "$RC" 1
eq "R9 cksum drift status" "$(status_of agents/doctor.md)" different
eq "R9 cksum others in_sync" "$(count in_sync)" 12
cp "$REPO/integrations/opencode/agents/doctor.md" "$CFG/agents/doctor.md"; run --check
eq "R9 cksum clean when identical" "$RC" 0
printf 'dummy agents/doctor.md v2\n' >"$CFG/agents/doctor.md"; run --check
eq "R9 cksum detects same-length-class change" "$(status_of agents/doctor.md)" different
cp "$REPO/integrations/opencode/agents/doctor.md" "$CFG/agents/doctor.md"
chmod 644 "$CFG/scripts/doctor.sh"; run --check
eq "R9 exec-bit drift independent of checksum" "$(status_of scripts/doctor.sh)" different
hasline "R9 would_chmod under cksum" "$OUT" "would_chmod=scripts/doctor.sh"
RUNPATH="$F/bin2"; run --apply
eq "R9 apply works under restricted PATH (cksum)" "$RC" 0
eq "R9 chmod applied" "$(ls -l "$CFG/scripts/doctor.sh" | cut -c1-10)" "-rwxr-xr-x"
mkfix ck2; mkbin "$F/bin3" sha256sum; RUNPATH="$F/bin3"; run --apply
eq "R9 full apply under sha256sum-only PATH" "$RC" 0
eq "R9 installed bytes match" "$(fsum "$CFG/agents/doctor.md")" "$(fsum "$REPO/integrations/opencode/agents/doctor.md")"
# unreadable installed file => fail closed, never in_sync
mkfix ck3; install_all; chmod 000 "$CFG/agents/doctor.md"; run --check
chmod 644 "$CFG/agents/doctor.md"
eq "R9 unreadable installed file fails closed" "$RC" 2
hasline "R9 unreadable => DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"

# --- v3c.2 round 2: directory creation, temp file, staged integrity, cleanup (deterministic hooks) ---
hookraw() { HOOK="$F/hook-raw.sh"; { echo '#!/bin/sh'; cat; } >"$HOOK"; chmod 755 "$HOOK"; } # body on stdin (unquoted heredoc)
nfiles() { find "$1" -mindepth 1 | wc -l | tr -d ' '; }

# S1 (HIGH 1): directory creation is revalidated, one level at a time
mkfix s1a; mkdir "$F/outside"
hookraw <<H
[ "\$1" = before_mkdir ] && [ "\$2" = agents ] && ln -s "$F/outside" "$CFG/agents"
exit 0
H
run --apply
eq "S1a subdir appears as symlink: exit 2" "$RC" 2
hasline "S1a DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
eq "S1a outside unchanged" "$(nfiles "$F/outside")" 0
eq "S1a nothing installed" "$(find "$HM" -name '*.md' | wc -l | tr -d ' ')" 0
mkfix s1b; mkdir "$F/outside"
hookraw <<H
[ "\$1" = before_mkdir ] && [ "\$2" = commands ] && mv "$CFG" "$F/movedcfg" && ln -s "$F/outside" "$CFG"
exit 0
H
run --apply
eq "S1b root swapped for symlink: exit 2" "$RC" 2
hasline "S1b DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
eq "S1b outside unchanged" "$(nfiles "$F/outside")" 0
eq "S1b no later subdir created in moved root" "$(test -e "$F/movedcfg/commands" && echo yes || echo no)" no
mkfix s1c; mkdir "$F/outside"; rm -rf "$HM/.config"
hookraw <<H
[ "\$1" = before_mkdir ] && [ "\$2" = .config ] && ln -s "$F/outside" "$HM/.config"
exit 0
H
run --apply
eq "S1c .config appears as symlink: exit 2" "$RC" 2
hasline "S1c DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
eq "S1c outside unchanged" "$(nfiles "$F/outside")" 0
mkfix s1d; mkdir "$F/outside"; rm -rf "$HM/.config"
hookraw <<H
[ "\$1" = before_mkdir ] && [ "\$2" = opencode ] && mv "$HM/.config" "$F/oldcfg" && ln -s "$F/outside" "$HM/.config"
exit 0
H
run --apply
eq "S1d .config swapped for symlink after validation: exit 2" "$RC" 2
hasline "S1d DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
eq "S1d outside unchanged (no mkdir through link)" "$(nfiles "$F/outside")" 0
mkfix s1e; rm -rf "$HM/.config"
hookraw <<H
[ "\$1" = before_mkdir ] && [ "\$2" = opencode ] && mv "$HM/.config" "$F/oldcfg" && mkdir "$HM/.config"
exit 0
H
run --apply
eq "S1e .config replaced by another dir: exit 2" "$RC" 2
hasline "S1e DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
eq "S1e replacement .config left empty" "$(nfiles "$HM/.config")" 0
mkfix s1f; rm -rf "$HM/.config"
hookraw <<H
[ "\$1" = before_mkdir ] && [ "\$2" = agents ] && mv "$HM/.config" "$F/oldcfg" && ln -s "$F/oldcfg" "$HM/.config"
exit 0
H
run --apply
eq "S1f ancestor swapped after root creation: exit 2" "$RC" 2
hasline "S1f DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
eq "S1f nothing installed" "$(find "$F/oldcfg" -name '*.md' | wc -l | tr -d ' ')" 0
mkfix s1g; rm -rf "$HM/.config"; run --apply
eq "S1g clean creation of root and subdirs" "$RC" 0
eq "S1g root created" "$(test -d "$CFG/scripts" && echo yes)" yes

# S2 (HIGH 2): validation immediately before mv; swaps in before_mv never reach mv
mkfix s2a; install_all; echo changed >"$CFG/agents/doctor.md"
hookraw <<H
[ "\$1" = before_mv ] && [ "\$2" = agents/doctor.md ] && rm -f "$CFG/agents/doctor.md" && mkdir "$CFG/agents/doctor.md"
exit 0
H
run --apply
eq "S2a file->directory swap: exit 2" "$RC" 2
hasline "S2a DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
eq "S2a destination stayed a directory" "$(test -d "$CFG/agents/doctor.md" && echo yes)" yes
eq "S2a nothing placed inside it" "$(nfiles "$CFG/agents/doctor.md")" 0
mkfix s2b; install_all; echo changed >"$CFG/agents/doctor.md"
hookraw <<H
[ "\$1" = before_mv ] && [ "\$2" = agents/doctor.md ] && mv "$CFG/agents" "$F/oldagents" && mkdir "$CFG/agents"
exit 0
H
run --apply
eq "S2b directory swap: exit 2" "$RC" 2
hasline "S2b DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
eq "S2b new directory untouched" "$(nfiles "$CFG/agents")" 0
mkfix s2c; install_all; echo changed >"$CFG/agents/doctor.md"
hookraw <<H
[ "\$1" = before_mv ] && [ "\$2" = agents/doctor.md ] && echo OTHER >"$CFG/agents/doctor.new" && mv "$CFG/agents/doctor.new" "$CFG/agents/doctor.md"
exit 0
H
run --apply
eq "S2c regular file replaced (new identity): exit 2" "$RC" 2
hasline "S2c DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
eq "S2c replacement not overwritten" "$(cat "$CFG/agents/doctor.md")" OTHER
mkfix s2d; install_all; echo changed >"$CFG/agents/doctor.md"; mkdir "$F/outside"
hookraw <<H
[ "\$1" = before_mv ] && [ "\$2" = agents/doctor.md ] && mv "$CFG" "$F/movedcfg" && ln -s "$F/movedcfg" "$CFG"
exit 0
H
run --apply
eq "S2d root swapped for symlink at mv: exit 2" "$RC" 2
hasline "S2d DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
eq "S2d old content kept" "$(cat "$F/movedcfg/agents/doctor.md")" changed
# chmod-only: replaced by a new regular file (identity change) before chmod
mkfix s2e; install_all; chmod 644 "$CFG/scripts/review-route.sh"
hookraw <<H
[ "\$1" = before_chmod ] && [ "\$2" = scripts/review-route.sh ] && cp "$CFG/scripts/review-route.sh" "$CFG/scripts/rr.new" && mv "$CFG/scripts/rr.new" "$CFG/scripts/review-route.sh"
exit 0
H
run --apply
eq "S2e chmod target identity changed: exit 2" "$RC" 2
hasline "S2e DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
eq "S2e replacement not chmodded" "$(ls -l "$CFG/scripts/review-route.sh" | cut -c1-10)" "-rw-r--r--"

# S3 (HIGH 3): temp file swapped to a symlink before the write / before the chmod
for ph in before_tmp_write before_tmp_chmod; do
  mkfix s3_$ph; install_all; echo changed >"$CFG/commands/route-task.md"
  echo precious >"$F/outside.txt"; chmod 600 "$F/outside.txt"; oh=$(fsum "$F/outside.txt")
  hookraw <<H
[ "\$1" = $ph ] && [ "\$2" = commands/route-task.md ] || exit 0
for t in "$CFG"/commands/.sync-install.*; do rm -f "\$t"; ln -s "$F/outside.txt" "\$t"; done
exit 0
H
  run --apply
  eq "S3 $ph exit 2" "$RC" 2
  hasline "S3 $ph DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
  eq "S3 $ph external content untouched" "$(fsum "$F/outside.txt")" "$oh"
  eq "S3 $ph external mode untouched" "$(ls -l "$F/outside.txt" | cut -c1-10)" "-rw-------"
  eq "S3 $ph destination file not replaced" "$(cat "$CFG/commands/route-task.md")" changed
  nline "S3 $ph nothing reported copied" "$OUT" "copied=commands/route-task.md"
done

# S4 (HIGH 4): staged snapshot is the source of truth and is verified right before it is read
mkfix s4a; mkdir "$F/tmpd"
hookraw <<H
[ "\$1" = before_stage_read ] && [ "\$2" = agents/doctor.md ] || exit 0
for s in "$F"/tmpd/sync-install.*/agents/doctor.md; do echo TAMPERED >>"\$s"; done
exit 0
H
OUT=$(cd "$TMP/cwd" && env -i HOME="$HM" PATH="$REAL_PATH" TMPDIR="$F/tmpd" DEV_AGENTS_SYNC_TEST_HOOK="$HOOK" "$BASH_BIN" "$SYNC" --apply 2>&1 </dev/null); RC=$?
eq "S4a tampered staged bytes: exit 2" "$RC" 2
hasline "S4a SOURCE_FILE_UNSAFE" "$OUT" "reason=SOURCE_FILE_UNSAFE"
eq "S4a tampered bytes never installed" "$(grep -rl TAMPERED "$HM" | wc -l | tr -d ' ')" 0
eq "S4a no destination file for that item" "$(test -e "$CFG/agents/doctor.md" && echo yes || echo no)" no
eq "S4a staging removed" "$(tcount "$F/tmpd")" 0
mkfix s4b; mkdir "$F/tmpd"
hookraw <<H
[ "\$1" = before_stage_read ] && [ "\$2" = agents/doctor.md ] || exit 0
for s in "$F"/tmpd/sync-install.*/agents/doctor.md; do cp "\$s" "\$s.new" && mv "\$s.new" "\$s"; done
exit 0
H
OUT=$(cd "$TMP/cwd" && env -i HOME="$HM" PATH="$REAL_PATH" TMPDIR="$F/tmpd" DEV_AGENTS_SYNC_TEST_HOOK="$HOOK" "$BASH_BIN" "$SYNC" --apply 2>&1 </dev/null); RC=$?
eq "S4b staged file replaced (same bytes, new identity): exit 2" "$RC" 2
hasline "S4b SOURCE_FILE_UNSAFE" "$OUT" "reason=SOURCE_FILE_UNSAFE"
mkfix s4c; mkdir "$F/tmpd"; echo "EXTERNAL-STAGED" >"$F/ext.md"
hookraw <<H
[ "\$1" = before_stage_read ] && [ "\$2" = agents/doctor.md ] || exit 0
for s in "$F"/tmpd/sync-install.*/agents/doctor.md; do rm -f "\$s"; ln -s "$F/ext.md" "\$s"; done
exit 0
H
OUT=$(cd "$TMP/cwd" && env -i HOME="$HM" PATH="$REAL_PATH" TMPDIR="$F/tmpd" DEV_AGENTS_SYNC_TEST_HOOK="$HOOK" "$BASH_BIN" "$SYNC" --apply 2>&1 </dev/null); RC=$?
eq "S4c staged symlink swap: exit 2" "$RC" 2
hasline "S4c SOURCE_FILE_UNSAFE" "$OUT" "reason=SOURCE_FILE_UNSAFE"
eq "S4c external bytes never installed" "$(grep -rl EXTERNAL-STAGED "$HM" | wc -l | tr -d ' ')" 0
eq "S4c external file intact" "$(cat "$F/ext.md")" "EXTERNAL-STAGED"
mkfix s4d; mkdir "$F/tmpd"
hookraw <<H
[ "\$1" = before_stage_read ] && [ "\$2" = agents/doctor.md ] || exit 0
for s in "$F"/tmpd/sync-install.*; do mv "\$s" "\$s.old" && mkdir "\$s"; done
exit 0
H
OUT=$(cd "$TMP/cwd" && env -i HOME="$HM" PATH="$REAL_PATH" TMPDIR="$F/tmpd" DEV_AGENTS_SYNC_TEST_HOOK="$HOOK" "$BASH_BIN" "$SYNC" --apply 2>&1 </dev/null); RC=$?
eq "S4d staging root swapped: exit 2" "$RC" 2
hasline "S4d SOURCE_FILE_UNSAFE" "$OUT" "reason=SOURCE_FILE_UNSAFE"

# S5 (MEDIUM 5): cleanup never deletes foreign files and never changes the exit code
mkfix s5a; install_all; echo changed >"$CFG/agents/doctor.md"; echo external >"$F/outside.txt"
hookraw <<H
case "\$1" in
  before_mv) rm -f "$CFG/agents/doctor.md" && ln -s "$F/outside.txt" "$CFG/agents/doctor.md" ;;
  before_cleanup) for t in "$CFG"/agents/.sync-install.*; do echo FOREIGN >"$F/repl" && mv "$F/repl" "\$t"; done ;;
esac
exit 0
H
run --apply
eq "S5a exit stays 2" "$RC" 2
hasline "S5a DESTINATION_UNSAFE" "$OUT" "reason=DESTINATION_UNSAFE"
eq "S5a unrelated file at the temp path survives cleanup" "$(cat "$CFG"/agents/.sync-install.* 2>/dev/null)" FOREIGN
mkfix s5b; install_all; echo changed >"$CFG/agents/doctor.md"; echo external >"$F/outside.txt"; chmod 600 "$F/outside.txt"; oh=$(fsum "$F/outside.txt")
hookraw <<H
case "\$1" in
  before_mv) rm -f "$CFG/agents/doctor.md" && ln -s "$F/outside.txt" "$CFG/agents/doctor.md" ;;
  before_cleanup) for t in "$CFG"/agents/.sync-install.*; do rm -f "\$t"; ln -s "$F/outside.txt" "\$t"; done ;;
esac
exit 0
H
run --apply
eq "S5b exit stays 2" "$RC" 2
eq "S5b symlink target not deleted" "$(test -f "$F/outside.txt" && echo yes)" yes
eq "S5b symlink target content untouched" "$(fsum "$F/outside.txt")" "$oh"
eq "S5b symlink target mode untouched" "$(ls -l "$F/outside.txt" | cut -c1-10)" "-rw-------"
eq "S5b symlink left in place (not followed, not removed)" "$(for t in "$CFG"/agents/.sync-install.*; do test -L "$t" && echo link; done)" link
# a swapped staged file / staging root is not removed through the swap either
mkfix s5c; mkdir "$F/tmpd"; echo changed >"$CFG/x" 2>/dev/null; install_all; echo changed >"$CFG/agents/doctor.md"
hookraw <<H
case "\$1" in
  before_mv) rm -f "$CFG/agents/doctor.md" && ln -s "$F/ext.md" "$CFG/agents/doctor.md" ;;
  before_cleanup) for s in "$F"/tmpd/sync-install.*/commands/doctor.md; do echo FOREIGN >"$F/repl" && mv "$F/repl" "\$s"; done ;;
esac
exit 0
H
echo ext >"$F/ext.md"
OUT=$(cd "$TMP/cwd" && env -i HOME="$HM" PATH="$REAL_PATH" TMPDIR="$F/tmpd" DEV_AGENTS_SYNC_TEST_HOOK="$HOOK" "$BASH_BIN" "$SYNC" --apply 2>&1 </dev/null); RC=$?
eq "S5c exit stays 2" "$RC" 2
eq "S5c foreign file in staging survives cleanup" "$(cat "$F"/tmpd/sync-install.*/commands/doctor.md 2>/dev/null)" FOREIGN
# cleanup trouble must not change the exit code (staging tree removed from under the script)
mkfix s5d; mkdir "$F/tmpd"
hookraw <<H
[ "\$1" = before_cleanup ] && { for s in "$F"/tmpd/sync-install.*; do find "\$s" -type f -exec rm -f {} + ; find "\$s" -depth -type d -exec rmdir {} + ; done; }
exit 0
H
OUT=$(cd "$TMP/cwd" && env -i HOME="$HM" PATH="$REAL_PATH" TMPDIR="$F/tmpd" DEV_AGENTS_SYNC_TEST_HOOK="$HOOK" "$BASH_BIN" "$SYNC" --apply 2>&1 </dev/null); RC=$?
eq "S5d success exit 0 survives cleanup trouble" "$RC" 0

# S6: hook labels and the exact per-file order
mkfix s6; install_all; echo x >"$CFG/agents/doctor.md"; chmod 644 "$CFG/scripts/review-route.sh"; rm -rf "$CFG/commands"
mkhook log "echo \"\$1 \$2\" >>\"$F/hook.log\""
run --apply
eq "S6 exit 0" "$RC" 0
for lb in after_staging before_mkdir before_mktemp before_tmp_write before_tmp_chmod before_mv before_chmod before_stage_read before_cleanup; do
  contains "S6 label $lb fired" "$(cat "$F/hook.log")" "$lb"
done
eq "S6 per-file order" "$(grep ' agents/doctor.md$' "$F/hook.log" | awk '{printf "%s ", $1}')" "before_mktemp before_tmp_write before_stage_read before_tmp_chmod before_mv "
eq "S6 mkdir hook precedes every mktemp" "$(awk '$1=="before_mkdir"{m=NR} $1=="before_mktemp"&&!f{f=NR} END{print (m<f)?"ok":"bad"}' "$F/hook.log")" ok

# Static: after staging, repository source paths are never reopened
post=$(sed -n '/^run_hook after_staging$/,$p' "$SCRIPT_UNDER_TEST" | grep -v '^[[:space:]]*#')
if printf '%s\n' "$post" | grep -Eq '\$SRC|\$ROOT|\$SELF_DIR'; then bad "static: repo source referenced after staging"; else ok "static: no repo source reference after staging"; fi
if printf '%s\n' "$post" | grep -q dest_safe; then ok "static: post-staging section located"; else bad "static: post-staging section not found"; fi
if grep -v '^[[:space:]]*#' "$SCRIPT_UNDER_TEST" | grep -q 'cmp '; then bad "static: cmp still used"; else ok "static: cmp not used for drift"; fi

# Static: helper contains no forbidden constructs
bodyfile="$SCRIPT_UNDER_TEST"
code=$(grep -v '^[[:space:]]*#' "$bodyfile")
if printf '%s\n' "$code" | grep -Eq 'mkdir( +-[a-z]*)* *-p|mkdir +-[A-Za-z]*p'; then bad "static: mkdir -p used"; else ok "static: no mkdir -p"; fi
if printf '%s\n' "$code" | grep -Eq 'rm +-[A-Za-z]*[rR]'; then bad "static: recursive rm used"; else ok "static: no recursive rm"; fi
for lb in after_staging before_mkdir before_mktemp before_tmp_write before_tmp_chmod before_mv before_chmod before_stage_read before_cleanup; do
  if printf '%s\n' "$code" | grep -q "run_hook $lb"; then ok "static: hook $lb present"; else bad "static: hook $lb missing"; fi
done
# the mv is directly preceded by its two validators (only comments/variable work in between)
mvblk=$(printf '%s\n' "$code" | grep -B2 'mv -f -- "\$TMPF"' | head -n 2)
if printf '%s\n' "$mvblk" | sed -n 1p | grep -q 'dest_safe' && printf '%s\n' "$mvblk" | sed -n 2p | grep -q 'file_ok'; then ok "static: mv directly preceded by dest and temp validation"; else bad "static: mv validation order"; fi
for pat in '\bgit\b' 'rsync' 'cp -r' 'cp -R' 'sqlite' 'opencode\.json' '9router' '\brm -r'; do
  if printf '%s\n' "$code" | grep -Eq -- "$pat"; then bad "static: helper code contains /$pat/"; else ok "static: no /$pat/ in helper code"; fi
done

echo
echo "Summary: $pass passed, $failn failed"
[ "$failn" -eq 0 ]
