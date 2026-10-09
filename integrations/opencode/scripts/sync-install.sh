#!/usr/bin/env bash
# sync-install.sh — safe sync of the dev-agents OpenCode integration into $HOME/.config/opencode (v3c.2).
#
#   sync-install.sh [--check | --apply]       (no argument == --check)
#
# --check : read-only. Compares each manifest file with the installed copy and prints the plan.
# --apply : computes and validates the whole plan first, then copies ONLY missing/different
#           manifest files (and fixes the exec bit of manifest scripts), then runs the installed
#           doctor.sh --machine. Never prompts. No backups, no deletion, no automatic rollback.
#
# Source of truth: the checkout this script lives in. The root is derived from the script's own
# location (<root>/integrations/opencode/scripts), never from the working directory. Run from an
# installed copy (not in a checkout) it fails closed with reason=SOURCE_REPOSITORY_UNVERIFIED.
#
# Source snapshot: preflight validates every manifest source (regular, readable, non-symlink,
# physically inside the checkout) and copies its bytes into a private staging dir (mktemp -d under
# $TMPDIR or /tmp, mode 700, files 600). Checksums, drift detection and all destination writes use
# ONLY the staged copies; repository source paths are never reopened after staging. The staging dir
# is removed on EXIT/INT/TERM.
#
# Destination revalidation: immediately before every mktemp / mv / chmod the destination root, the
# managed subdirectory and the target file are re-checked (no symlink, physical path still under the
# approved root, regular file). Any change => reason=DESTINATION_UNSAFE, nothing further is written.
# ponytail: without openat/O_NOFOLLOW a check-then-act window of microseconds remains between a
# check and the following syscall; this narrows it, it does not eliminate it. Upgrade path: a helper
# using openat(O_NOFOLLOW) / renameat, or run the sync as a user nobody else can write as.
#
# Drift detection: SHA-256 of the staged source vs the installed file (shasum -a 256, else
# sha256sum). Only if neither works, POSIX cksum (CRC + size) is used and reported via
# checksum_tool=cksum. Exec-bit mismatch of a script is drift regardless of checksum.
#
# Write boundary: the explicit MANIFEST below, nothing else. Source <root>/integrations/opencode/<entry>,
# destination $HOME/.config/opencode/<entry>. No globs, no directory copies, no deletion of
# destination files. Unmanaged files and all provider/router configuration are never touched.
#
# Output: key=value lines. "mode=" then "checksum_tool=shasum|sha256sum|cksum", then per manifest entry (manifest order) "file=<rel>" followed by
# "status=in_sync|missing|different". Any other "status=" line (not right after "file=") is the
# overall result: status=applied|failed. Then: sync_status=clean|drift|failed, in_sync=N,
# different=N, missing=N. Failures: status=failed, reason=<CODE>, [detail=<text>], sync_status=failed.
# Apply adds copied=<rel>, chmodded=<rel>, doctor_* lines. Counts in apply are the post-apply state.
# A script whose content matches but is not executable counts as status=different (chmod only).
#
# Exit codes: 0 clean (check) / applied (apply) | 1 drift (check) | 2 setup, validation or
# post-install failure | 64 usage error.
# Reasons: USAGE, SOURCE_REPOSITORY_UNVERIFIED, SOURCE_FILE_MISSING, SOURCE_FILE_UNSAFE, HOME_INVALID,
#          DESTINATION_UNSAFE, COPY_FAILED, POST_INSTALL_DOCTOR_FAILED.
# Bash 3.2 compatible.

set -u
export LC_ALL=C

MANIFEST=(
  agents/orchestrator.md
  agents/doctor.md
  agents/sync-install.md
  commands/implement-spec.md
  commands/route-task.md
  commands/review-change.md
  commands/split-spec.md
  commands/doctor.md
  commands/sync-install.md
  scripts/review-route.sh
  scripts/resolve-model-family.sh
  scripts/doctor.sh
  scripts/sync-install.sh
)
SUBDIRS="agents commands scripts"

MODE=""
TMPF=""
STG=""
cleanup() {
  local m
  # own temp file only; never through a swapped (symlinked) directory
  if [ -n "$TMPF" ] && [ ! -L "$(dirname "$TMPF")" ]; then rm -f -- "$TMPF"; fi
  # Remove ONLY what this run staged: the exact manifest files, then the (empty) dirs. No recursion.
  case "$STG" in
    /?*)
      for m in "${MANIFEST[@]}"; do rm -f -- "$STG/$m"; done
      for m in $SUBDIRS; do rmdir -- "$STG/$m" 2>/dev/null; done
      rmdir -- "$STG" 2>/dev/null
      ;;
  esac
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() { # <reason> [detail] [exit]
  [ -n "$MODE" ] && printf 'mode=%s\n' "$MODE"
  printf 'status=failed\nreason=%s\n' "$1"
  [ -n "${2:-}" ] && printf 'detail=%s\n' "$2"
  printf 'sync_status=failed\n'
  exit "${3:-2}"
}

COPIED=""
CHMODDED=""
print_changes() {
  local r
  for r in $COPIED; do printf 'copied=%s\n' "$r"; done
  for r in $CHMODDED; do printf 'chmodded=%s\n' "$r"; done
}
apply_fail() { print_changes; fail "$@"; }

# TEST-ONLY hook (not part of the product interface): when DEV_AGENTS_SYNC_TEST_HOOK is an absolute
# path to an executable regular file it is run as "<hook> <phase> <manifest-entry>" with stdin
# </dev/null and all output discarded; its exit status is ignored. It gets read-only labels only
# and cannot influence decisions: every safety check runs AFTER the hook against live filesystem
# state. Phases: after_staging before_mktemp before_mv before_chmod.
run_hook() { # <phase> [manifest entry]
  local h="${DEV_AGENTS_SYNC_TEST_HOOK:-}"
  case "$h" in /*) ;; *) return 0 ;; esac
  if [ -f "$h" ] && [ -x "$h" ]; then "$h" "$1" "${2:-}" </dev/null >/dev/null 2>&1 || true; fi
  return 0
}

# --- arguments ------------------------------------------------------------------

if [ $# -gt 1 ]; then
  echo "usage: sync-install.sh [--check|--apply]" >&2
  printf 'status=failed\nreason=USAGE\nsync_status=failed\n'
  exit 64
fi
case "${1-"--check"}" in
  --check) MODE=check ;;
  --apply) MODE=apply ;;
  *)
    echo "usage: sync-install.sh [--check|--apply]" >&2
    printf 'status=failed\nreason=USAGE\nsync_status=failed\n'
    exit 64
    ;;
esac

# --- source repository (derived from this script's own location) ----------------

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)
ROOT=$(cd "$SELF_DIR/../../.." 2>/dev/null && pwd -P)
if [ -z "$SELF_DIR" ] || [ -z "$ROOT" ] || [ "$SELF_DIR" != "$ROOT/integrations/opencode/scripts" ] ||
  [ ! -f "$ROOT/AGENTS.md" ] || [ ! -f "$ROOT/integrations/opencode/agents/orchestrator.md" ] ||
  [ ! -f "$ROOT/integrations/opencode/scripts/doctor.sh" ]; then
  fail SOURCE_REPOSITORY_UNVERIFIED
fi
SRC="$ROOT/integrations/opencode"

# --- destination root -------------------------------------------------------------

case "${HOME:-}" in
  /*) ;;
  *) fail HOME_INVALID ;;
esac
[ -d "$HOME" ] || fail HOME_INVALID
DEST="$HOME/.config/opencode"
DESTPHYS=""

# --- validation helpers -----------------------------------------------------------

valid_rel() { # manifest string: relative, no empty/./.. segment, safe charset, <subdir>/<file>
  local p="$1" seg
  [[ "$p" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || return 1
  local IFS=/
  for seg in $p; do
    case "$seg" in . | ..) return 1 ;; esac
  done
  case " $SUBDIRS " in *" ${p%%/*} "*) return 0 ;; esac
  return 1
}

is_script() { case "$1" in scripts/*.sh) return 0 ;; esac; return 1; }

check_dest_dirs() { # symlink / escape checks for the destination root and the three subdirs
  local d phys physroot=""
  if [ -L "$DEST" ]; then fail DESTINATION_UNSAFE "destination root is a symlink"; fi
  if [ -e "$DEST" ] && [ ! -d "$DEST" ]; then fail DESTINATION_UNSAFE "destination root is not a directory"; fi
  [ -d "$DEST" ] && physroot=$(cd -P "$DEST" 2>/dev/null && pwd -P)
  # the physical root must not change between calls (recorded on first sight)
  if [ -n "$physroot" ]; then
    if [ -z "$DESTPHYS" ]; then DESTPHYS="$physroot"
    elif [ "$physroot" != "$DESTPHYS" ]; then apply_fail DESTINATION_UNSAFE "destination root changed"; fi
  fi
  for d in $SUBDIRS; do
    if [ -L "$DEST/$d" ]; then fail DESTINATION_UNSAFE "$d is a symlink"; fi
    if [ -e "$DEST/$d" ]; then
      [ -d "$DEST/$d" ] || fail DESTINATION_UNSAFE "$d is not a directory"
      phys=$(cd -P "$DEST/$d" 2>/dev/null && pwd -P)
      [ -n "$physroot" ] && [ "$phys" = "$physroot/$d" ] || fail DESTINATION_UNSAFE "$d resolves outside the destination root"
    fi
  done
}

# Live revalidation of ONE managed destination, run immediately before each write/chmod.
# 0 = root, subdir and target still safe: root not a symlink and physically unchanged, subdir not a
# symlink and physically DESTPHYS/<subdir>, target absent or a regular readable non-symlink file.
dest_safe() { # <manifest entry>
  local e="$1" d="${1%%/*}" physroot phys
  [ -n "$DESTPHYS" ] || return 1
  if [ -L "$DEST" ] || [ ! -d "$DEST" ]; then return 1; fi
  physroot=$(cd -P "$DEST" 2>/dev/null && pwd -P) || return 1
  [ "$physroot" = "$DESTPHYS" ] || return 1
  if [ -L "$DEST/$d" ] || [ ! -d "$DEST/$d" ]; then return 1; fi
  phys=$(cd -P "$DEST/$d" 2>/dev/null && pwd -P) || return 1
  [ "$phys" = "$DESTPHYS/$d" ] || return 1
  [ ! -L "$DEST/$e" ] || return 1
  if [ -e "$DEST/$e" ]; then
    if [ ! -f "$DEST/$e" ] || [ ! -r "$DEST/$e" ]; then return 1; fi
  fi
  return 0
}

# --- checksum tool: SHA-256 preferred, POSIX cksum only when no SHA-256 tool works -----------

CKTOOL=""
if command -v shasum >/dev/null 2>&1 && printf x | shasum -a 256 >/dev/null 2>&1; then CKTOOL=shasum
elif command -v sha256sum >/dev/null 2>&1 && printf x | sha256sum >/dev/null 2>&1; then CKTOOL=sha256sum
elif command -v cksum >/dev/null 2>&1 && printf x | cksum >/dev/null 2>&1; then CKTOOL=cksum
else fail COPY_FAILED "no checksum tool (shasum, sha256sum, cksum)"; fi

ck() { # <file>: print the comparable digest (sha-256 hex, or "crc size" for cksum); read the file once
  local out
  case "$CKTOOL" in
    shasum) out=$(shasum -a 256 2>/dev/null <"$1") || return 1 ;;
    sha256sum) out=$(sha256sum 2>/dev/null <"$1") || return 1 ;;
    *) out=$(cksum 2>/dev/null <"$1") || return 1 ;;
  esac
  set -- $out
  if [ "$CKTOOL" = cksum ]; then
    [[ "${1:-}" =~ ^[0-9]+$ && "${2:-}" =~ ^[0-9]+$ ]] || return 1
    printf '%s %s' "$1" "$2"
  else
    [[ "${1:-}" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
    printf '%s' "$1"
  fi
}

inode_of() { local o; o=$(ls -di -- "$1" 2>/dev/null) || return 1; set -- $o; printf '%s' "${1:-}"; }

# --- preflight: validate + snapshot sources (writes only to the private staging dir) ------------

TB="${TMPDIR:-/tmp}"
case "$TB" in /*) ;; *) TB=/tmp ;; esac
STG=$(mktemp -d "${TB%/}/sync-install.XXXXXX" 2>/dev/null) || { STG=""; fail COPY_FAILED "cannot create staging dir"; }
case "$STG" in /?*) ;; *) STG=""; fail COPY_FAILED "cannot create staging dir" ;; esac
chmod 700 "$STG" || fail COPY_FAILED "cannot secure staging dir"
for d in $SUBDIRS; do mkdir -m 700 "$STG/$d" 2>/dev/null || fail COPY_FAILED "cannot create staging dir"; done

N=${#MANIFEST[@]}
SUM=()
i=0
while [ "$i" -lt "$N" ]; do
  e="${MANIFEST[$i]}"
  valid_rel "$e" || fail USAGE "invalid manifest entry"
  s="$SRC/$e"
  if [ -L "$s" ] || [ ! -f "$s" ] || [ ! -r "$s" ]; then fail SOURCE_FILE_MISSING "$e"; fi
  physdir=$(cd -P "$(dirname "$s")" 2>/dev/null && pwd -P)
  [ "$physdir" = "$SRC/${e%%/*}" ] || fail SOURCE_FILE_MISSING "$e"
  ino1=$(inode_of "$s") || fail SOURCE_FILE_UNSAFE "$e"
  # snapshot: from here on only the staged copy is used
  (umask 077; cat -- "$s" 2>/dev/null >"$STG/$e") || fail SOURCE_FILE_UNSAFE "$e cannot be snapshotted"
  chmod 600 "$STG/$e" || fail SOURCE_FILE_UNSAFE "$e cannot be snapshotted"
  # best effort: the path must still be the same regular non-symlink file (staged bytes are the authority)
  ino2=$(inode_of "$s") || fail SOURCE_FILE_UNSAFE "$e changed while snapshotting"
  physdir=$(cd -P "$(dirname "$s")" 2>/dev/null && pwd -P)
  if [ -L "$s" ] || [ ! -f "$s" ] || [ "$ino1" != "$ino2" ] || [ "$physdir" != "$SRC/${e%%/*}" ]; then
    fail SOURCE_FILE_UNSAFE "$e changed while snapshotting"
  fi
  SUM[$i]=$(ck "$STG/$e") || fail COPY_FAILED "checksum of staged $e"
  i=$((i + 1))
done
run_hook after_staging

# --- destination preflight (no writes) --------------------------------------------------------

check_dest_dirs
i=0
while [ "$i" -lt "$N" ]; do
  e="${MANIFEST[$i]}"
  d="$DEST/$e"
  if [ -L "$d" ]; then fail DESTINATION_UNSAFE "$e is a symlink"; fi
  if [ -e "$d" ] && { [ ! -f "$d" ] || [ ! -r "$d" ]; }; then fail DESTINATION_UNSAFE "$e is not a readable regular file"; fi
  i=$((i + 1))
done

# --- plan -------------------------------------------------------------------------

STATUS=()
ACTION=()
n_in=0; n_diff=0; n_miss=0

compute_plan() {
  local k e d dsum
  STATUS=(); ACTION=(); n_in=0; n_diff=0; n_miss=0
  k=0
  while [ "$k" -lt "$N" ]; do
    e="${MANIFEST[$k]}"; d="$DEST/$e"
    if [ -L "$d" ]; then apply_fail DESTINATION_UNSAFE "$e is a symlink"; fi
    if [ ! -e "$d" ]; then
      STATUS[$k]=missing; ACTION[$k]=copy; n_miss=$((n_miss + 1))
    else
      if [ ! -f "$d" ] || [ ! -r "$d" ]; then apply_fail DESTINATION_UNSAFE "$e is not a readable regular file"; fi
      # fail closed: an unreadable/unchecksummable installed file is never treated as in_sync
      dsum=$(ck "$d") || apply_fail DESTINATION_UNSAFE "cannot checksum installed $e"
      if [ "$dsum" != "${SUM[$k]}" ]; then
        STATUS[$k]=different; ACTION[$k]=copy; n_diff=$((n_diff + 1))
      elif is_script "$e" && [ ! -x "$d" ]; then
        STATUS[$k]=different; ACTION[$k]=chmod; n_diff=$((n_diff + 1))
      else
        STATUS[$k]=in_sync; ACTION[$k]=none; n_in=$((n_in + 1))
      fi
    fi
    k=$((k + 1))
  done
}

print_pairs() {
  local k=0
  while [ "$k" -lt "$N" ]; do
    printf 'file=%s\nstatus=%s\n' "${MANIFEST[$k]}" "${STATUS[$k]}"
    k=$((k + 1))
  done
}

print_counts() { printf 'in_sync=%s\ndifferent=%s\nmissing=%s\n' "$n_in" "$n_diff" "$n_miss"; }

compute_plan
printf 'mode=%s\nchecksum_tool=%s\n' "$MODE" "$CKTOOL"
print_pairs

if [ "$MODE" = check ]; then
  k=0
  while [ "$k" -lt "$N" ]; do
    case "${ACTION[$k]}" in
      copy) printf 'would_copy=%s\n' "${MANIFEST[$k]}" ;;
      chmod) printf 'would_chmod=%s\n' "${MANIFEST[$k]}" ;;
    esac
    k=$((k + 1))
  done
  if [ $((n_diff + n_miss)) -eq 0 ]; then
    printf 'sync_status=clean\n'; print_counts; exit 0
  fi
  printf 'sync_status=drift\n'; print_counts; exit 1
fi

# --- apply ------------------------------------------------------------------------

# Only the three managed directories are ever created.
for d in $SUBDIRS; do
  if [ ! -d "$DEST/$d" ]; then mkdir -p "$DEST/$d" 2>/dev/null || fail COPY_FAILED "cannot create $d"; fi
done
check_dest_dirs

k=0
while [ "$k" -lt "$N" ]; do
  e="${MANIFEST[$k]}"
  sub="${e%%/*}"
  case "${ACTION[$k]}" in
    copy)
      if is_script "$e"; then perm=755; else perm=644; fi
      run_hook before_mktemp "$e"
      dest_safe "$e" || apply_fail DESTINATION_UNSAFE "$e changed during apply"
      TMPF=$(mktemp "$DEST/$sub/.sync-install.XXXXXX" 2>/dev/null) || { TMPF=""; apply_fail COPY_FAILED "$e"; }
      # the temp file must be a fresh regular non-symlink file directly inside the validated dir
      if [ -L "$TMPF" ] || [ ! -f "$TMPF" ] || [ "$(cd -P "$(dirname "$TMPF")" 2>/dev/null && pwd -P)" != "$DESTPHYS/$sub" ]; then
        apply_fail DESTINATION_UNSAFE "$e temp file"
      fi
      # bytes come ONLY from the staged snapshot
      cat -- "$STG/$e" >"$TMPF" 2>/dev/null || apply_fail COPY_FAILED "$e"
      run_hook before_mv "$e"
      dest_safe "$e" || apply_fail DESTINATION_UNSAFE "$e changed during apply"
      if [ -L "$TMPF" ] || [ ! -f "$TMPF" ]; then apply_fail DESTINATION_UNSAFE "$e temp file"; fi
      chmod "$perm" "$TMPF" 2>/dev/null || apply_fail COPY_FAILED "$e"
      # ponytail: check-then-act window remains here (no openat/renameat); see header.
      if mv -f -- "$TMPF" "$DEST/$e" 2>/dev/null; then
        TMPF=""
        COPIED="$COPIED $e"
      else
        apply_fail COPY_FAILED "$e"
      fi
      ;;
    chmod)
      run_hook before_chmod "$e"
      dest_safe "$e" || apply_fail DESTINATION_UNSAFE "$e changed during apply"
      [ -f "$DEST/$e" ] || apply_fail DESTINATION_UNSAFE "$e is not a regular file"
      chmod 755 "$DEST/$e" 2>/dev/null || apply_fail COPY_FAILED "$e"
      CHMODDED="$CHMODDED $e"
      ;;
  esac
  k=$((k + 1))
done

compute_plan
if [ $((n_diff + n_miss)) -ne 0 ]; then apply_fail COPY_FAILED "post-copy verification"; fi
print_changes

# --- post-install verification (does not duplicate any doctor check) ---------------

sanitize() { printf '%s' "$1" | tr -c 'A-Za-z0-9 ._,:;/=()@+~-' '?' | cut -c1-300; }

DOC="$DEST/scripts/doctor.sh"
doctor_fail() {
  printf 'doctor_overall=%s\n' "$(sanitize "${1:-unavailable}")"
  [ -n "${2:-}" ] && printf 'doctor_exit=%s\n' "$2"
  printf 'status=failed\nreason=POST_INSTALL_DOCTOR_FAILED\nsync_status=clean\n'
  print_counts
  exit 2
}
if [ ! -f "$DOC" ] || [ ! -x "$DOC" ]; then doctor_fail unavailable; fi

DOUT=$("$DOC" --machine 2>&1 </dev/null)
DRC=$?
dval() { printf '%s\n' "$DOUT" | sed -n "s/^$1=//p"; }
d_overall=$(dval overall); d_passed=$(dval passed); d_warn=$(dval warnings); d_failed=$(dval failed)
ok=1
[ "$DRC" -eq 0 ] || ok=0
case "$(printf '%s\n' "$DOUT" | grep -c '^overall=')" in 1) ;; *) ok=0 ;; esac
[ "$d_overall" = pass ] || ok=0
[ "$d_failed" = 0 ] || ok=0
[ "$d_warn" = 0 ] || ok=0

printf 'doctor_overall=%s\ndoctor_passed=%s\ndoctor_warnings=%s\ndoctor_failed=%s\ndoctor_exit=%s\n' \
  "$(sanitize "${d_overall:-unknown}")" "$(sanitize "${d_passed:-unknown}")" \
  "$(sanitize "${d_warn:-unknown}")" "$(sanitize "${d_failed:-unknown}")" "$DRC"

if [ "$ok" -ne 1 ]; then
  cname=""; cst=""
  printf '%s\n' "$DOUT" | head -n 400 | while IFS= read -r line; do
    case "$line" in
      check=*) cname=${line#check=}; cst="" ;;
      status=*) cst=${line#status=} ;;
      detail=*)
        if [ -n "$cname" ] && [ "$cst" != pass ]; then
          printf 'doctor_check=%s\ndoctor_check_status=%s\ndoctor_check_detail=%s\n' \
            "$(sanitize "$cname")" "$(sanitize "$cst")" "$(sanitize "${line#detail=}")"
        fi
        ;;
    esac
  done
  printf 'status=failed\nreason=POST_INSTALL_DOCTOR_FAILED\nsync_status=clean\n'
  print_counts
  exit 2
fi

printf 'status=applied\nsync_status=clean\n'
print_counts
exit 0
