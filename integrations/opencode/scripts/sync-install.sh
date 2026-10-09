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
# $TMPDIR or /tmp, mode 700, files 600). For every staged file the checksum, device:inode identity
# and physical parent are recorded, plus the identity of the staging root. Drift detection and all
# destination writes use ONLY the staged copies; repository source paths are never reopened after
# staging. Immediately before a staged file is read for a destination write, the staging root, the
# staged file (regular, non-symlink, same identity, same parent) and its checksum are re-verified;
# any mismatch => reason=SOURCE_FILE_UNSAFE and nothing from that item is written. The checksum of
# the finished temp file is compared with the staged checksum before the final mv, so the installed
# bytes are exactly the validated bytes.
#
# Destination revalidation: every directory creation, mktemp, write, chmod and mv is preceded by a
# live check (no symlink, physical path as recorded, same device:inode identity). Missing
# directories are created ONE LEVEL at a time with a plain mkdir (never a recursive create) and
# are re-resolved physically right after creation. Any change => reason=DESTINATION_UNSAFE,
# nothing further is written. Replacement sequence per file:
#   mktemp -> before_tmp_write -> before_stage_read -> verify dest + temp + staged -> write
#   -> before_tmp_chmod -> verify dest + temp -> chmod temp -> verify temp bytes (checksum)
#   -> before_mv -> verify dest root, dir, existing file, temp -> mv   (nothing in between)
# Cleanup removes the temp file only if it is still a regular non-symlink file with the identity
# and parent recorded at creation, and removes only the exact staged files this run created, never
# recursively; a cleanup problem never changes the exit code.
# ponytail: without openat/O_NOFOLLOW/renameat a check-then-act window of microseconds remains
# between a check and the following syscall (also for the write redirection, chmod, mv and the rm
# in cleanup); this narrows it, it does not eliminate it. Upgrade path: a helper using
# openat(O_NOFOLLOW) / renameat, or run the sync as a user nobody else can write as.
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
TMPF=""; TMPID=""; TMPPAR=""   # current temp file, its device:inode identity, its physical parent
STG=""; STGP=""; STGID=""      # staging dir (as created), physical path, identity
SUM=()                         # staged checksum per manifest index
SID=()                         # staged file identity per manifest index
DFID=()                        # installed file identity per manifest index at plan time ("" = absent)
DESTPHYS=""; DESTID=""
DID_agents=""; DID_commands=""; DID_scripts=""
HOMEPHYS=""; HOMEID=""

# TEST-ONLY hook (not part of the product interface): when DEV_AGENTS_SYNC_TEST_HOOK is an absolute
# path to an executable regular file it is run as "<hook> <phase> <manifest-entry>" with stdin
# </dev/null and all output discarded; its exit status is ignored. It gets read-only labels only
# and cannot influence decisions: every safety check runs AFTER the hook against live filesystem
# state. Phases: after_staging before_mkdir before_mktemp before_tmp_write before_stage_read
# before_tmp_chmod before_mv before_chmod before_cleanup.
run_hook() { # <phase> [manifest entry]
  local h="${DEV_AGENTS_SYNC_TEST_HOOK:-}"
  case "$h" in /*) ;; *) return 0 ;; esac
  if [ -f "$h" ] && [ -x "$h" ]; then "$h" "$1" "${2:-}" </dev/null >/dev/null 2>&1 || true; fi
  return 0
}

# --- filesystem identity helpers -------------------------------------------------------------

phys_of() { (cd -P -- "$1" 2>/dev/null && pwd -P); }

# device:inode of the path itself (a symlink is not followed). GNU stat first: BSD/macOS stat rejects
# -c, while GNU stat accepts -f (filesystem mode) and would print unrelated numbers.
ident_of() { # <path>
  local o
  if o=$(stat -c '%d:%i' -- "$1" 2>/dev/null) && [[ "$o" =~ ^[0-9]+:[0-9]+$ ]]; then printf '%s' "$o"; return 0; fi
  if o=$(stat -f '%d:%i' -- "$1" 2>/dev/null) && [[ "$o" =~ ^[0-9]+:[0-9]+$ ]]; then printf '%s' "$o"; return 0; fi
  return 1
}

# regular, non-symlink file, physically inside <parent>, with identity <id> (empty id never matches)
file_ok() { # <path> <expected physical parent> <identity>
  local p="$1" par="$2" id="$3" pp cur
  [ -n "$id" ] || return 1
  [ ! -L "$p" ] || return 1
  [ -f "$p" ] || return 1
  pp=$(phys_of "$(dirname "$p")") || return 1
  [ "$pp" = "$par" ] || return 1
  cur=$(ident_of "$p") || return 1
  [ "$cur" = "$id" ]
}

stg_root_ok() {
  local p i
  [ -n "$STGP" ] && [ -n "$STGID" ] || return 1
  [ ! -L "$STGP" ] && [ -d "$STGP" ] || return 1
  p=$(phys_of "$STGP") || return 1
  [ "$p" = "$STGP" ] || return 1
  i=$(ident_of "$STGP") || return 1
  [ "$i" = "$STGID" ]
}

# --- cleanup: identity-checked, non-recursive, never changes the exit code ---------------------

cleanup() {
  local rc=$? k e m
  trap - EXIT
  if [ -n "$TMPF" ] || [ -n "$STGP" ]; then run_hook before_cleanup; fi
  # own temp file only: same parent, still a regular non-symlink file, same identity as at creation
  if [ -n "$TMPF" ] && file_ok "$TMPF" "$TMPPAR" "$TMPID"; then rm -f -- "$TMPF" 2>/dev/null; fi
  # Remove ONLY what this run staged: the exact manifest files (each verified), then the (empty) dirs.
  if stg_root_ok; then
    k=0
    while [ "$k" -lt "${#MANIFEST[@]}" ]; do
      e="${MANIFEST[$k]}"
      if file_ok "$STGP/$e" "$STGP/${e%%/*}" "${SID[$k]:-}"; then rm -f -- "$STGP/$e" 2>/dev/null; fi
      k=$((k + 1))
    done
    for m in $SUBDIRS; do rmdir -- "$STGP/$m" 2>/dev/null; done
    rmdir -- "$STGP" 2>/dev/null
  fi
  exit "$rc"
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
unsafe() { apply_fail DESTINATION_UNSAFE "$1"; }

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
# Without a device:inode tool no identity can be proven: fail closed (also in --check).
HOMEPHYS=$(phys_of "$HOME") || fail HOME_INVALID
HOMEID=$(ident_of "$HOMEPHYS") || fail COPY_FAILED "no file identity tool (stat -c or stat -f)"

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

get_did() { case "$1" in agents) printf '%s' "$DID_agents" ;; commands) printf '%s' "$DID_commands" ;; scripts) printf '%s' "$DID_scripts" ;; esac; }
set_did() { case "$1" in agents) DID_agents="$2" ;; commands) DID_commands="$2" ;; scripts) DID_scripts="$2" ;; esac; }

# Preflight (no writes): records the physical root + identity and the identity of each EXISTING
# managed subdir. An absent subdir keeps an empty identity, meaning "must still be absent".
check_dest_dirs() {
  local d phys physroot="" id
  if [ -L "$DEST" ]; then fail DESTINATION_UNSAFE "destination root is a symlink"; fi
  if [ -e "$DEST" ] && [ ! -d "$DEST" ]; then fail DESTINATION_UNSAFE "destination root is not a directory"; fi
  if [ -d "$DEST" ]; then
    physroot=$(phys_of "$DEST") || fail DESTINATION_UNSAFE "destination root unreadable"
    DESTID=$(ident_of "$DEST") || fail DESTINATION_UNSAFE "cannot identify destination root"
    DESTPHYS="$physroot"
  fi
  for d in $SUBDIRS; do
    if [ -L "$DEST/$d" ]; then fail DESTINATION_UNSAFE "$d is a symlink"; fi
    if [ -e "$DEST/$d" ]; then
      [ -d "$DEST/$d" ] || fail DESTINATION_UNSAFE "$d is not a directory"
      phys=$(phys_of "$DEST/$d")
      [ -n "$physroot" ] && [ "$phys" = "$physroot/$d" ] || fail DESTINATION_UNSAFE "$d resolves outside the destination root"
      id=$(ident_of "$DEST/$d") || fail DESTINATION_UNSAFE "cannot identify $d"
      set_did "$d" "$id"
    fi
  done
}

# Live revalidation (apply). Each returns 0 only if the object is exactly what was recorded.
home_ok() {
  local p i
  [ -d "$HOME" ] || return 1
  p=$(phys_of "$HOME") || return 1
  [ "$p" = "$HOMEPHYS" ] || return 1
  i=$(ident_of "$HOMEPHYS") || return 1
  [ "$i" = "$HOMEID" ]
}

root_ok() {
  local p i
  [ -n "$DESTPHYS" ] && [ -n "$DESTID" ] || return 1
  [ ! -L "$DEST" ] && [ -d "$DEST" ] || return 1
  p=$(phys_of "$DEST") || return 1
  [ "$p" = "$DESTPHYS" ] || return 1
  i=$(ident_of "$DEST") || return 1
  [ "$i" = "$DESTID" ]
}

dir_ok() { # <subdir>: root ok, subdir not a symlink, physically DESTPHYS/<subdir>, identity as recorded
  local d="$1" p i
  root_ok || return 1
  [ ! -L "$DEST/$d" ] && [ -d "$DEST/$d" ] || return 1
  p=$(phys_of "$DEST/$d") || return 1
  [ "$p" = "$DESTPHYS/$d" ] || return 1
  i=$(ident_of "$DEST/$d") || return 1
  [ "$i" = "$(get_did "$d")" ]
}

# One managed destination (root, dir, target) by manifest index. The target must be exactly what the
# plan saw: absent stays absent; a present regular file keeps its device:inode identity.
dest_safe() { # <manifest index>
  local k="$1" e d fid cur
  e="${MANIFEST[$k]}"; d="${e%%/*}"; fid="${DFID[$k]:-}"
  dir_ok "$d" || return 1
  [ ! -L "$DEST/$e" ] || return 1
  if [ -z "$fid" ]; then
    [ ! -e "$DEST/$e" ] || return 1
  else
    [ -f "$DEST/$e" ] && [ -r "$DEST/$e" ] || return 1
    cur=$(ident_of "$DEST/$e") || return 1
    [ "$cur" = "$fid" ] || return 1
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

# Staged copy still exactly what preflight recorded: staging root identity, regular non-symlink file,
# same parent and identity, same checksum (same CKTOOL).
stage_ok() { # <manifest index>
  local k="$1" e s
  e="${MANIFEST[$k]}"
  stg_root_ok || return 1
  file_ok "$STGP/$e" "$STGP/${e%%/*}" "${SID[$k]:-}" || return 1
  s=$(ck "$STGP/$e") || return 1
  [ "$s" = "${SUM[$k]:-}" ]
}

# --- preflight: validate + snapshot sources (writes only to the private staging dir) ------------

stg_abort() { rmdir -- "$STG" 2>/dev/null; fail COPY_FAILED "$1"; }
TB="${TMPDIR:-/tmp}"
case "$TB" in /*) ;; *) TB=/tmp ;; esac
STG=$(mktemp -d "${TB%/}/sync-install.XXXXXX" 2>/dev/null) || { STG=""; fail COPY_FAILED "cannot create staging dir"; }
case "$STG" in /?*) ;; *) STG=""; fail COPY_FAILED "cannot create staging dir" ;; esac
if [ -L "$STG" ]; then stg_abort "staging dir is a symlink"; fi
p=$(phys_of "$STG") || stg_abort "cannot resolve staging dir"
id=$(ident_of "$p") || stg_abort "cannot identify staging dir"
STGP="$p"; STGID="$id"
chmod 700 "$STGP" || fail COPY_FAILED "cannot secure staging dir"
for d in $SUBDIRS; do mkdir -m 700 "$STGP/$d" 2>/dev/null || fail COPY_FAILED "cannot create staging dir"; done

N=${#MANIFEST[@]}
i=0
while [ "$i" -lt "$N" ]; do
  e="${MANIFEST[$i]}"
  valid_rel "$e" || fail USAGE "invalid manifest entry"
  s="$SRC/$e"
  if [ -L "$s" ] || [ ! -f "$s" ] || [ ! -r "$s" ]; then fail SOURCE_FILE_MISSING "$e"; fi
  physdir=$(phys_of "$(dirname "$s")")
  [ "$physdir" = "$SRC/${e%%/*}" ] || fail SOURCE_FILE_MISSING "$e"
  ino1=$(ident_of "$s") || fail SOURCE_FILE_UNSAFE "$e"
  # snapshot: from here on only the staged copy is used
  (umask 077; cat -- "$s" 2>/dev/null >"$STGP/$e") || fail SOURCE_FILE_UNSAFE "$e cannot be snapshotted"
  # identity recorded first so cleanup can remove this file even if a later step fails
  SID[$i]=$(ident_of "$STGP/$e") || fail SOURCE_FILE_UNSAFE "$e staged identity"
  chmod 600 "$STGP/$e" || fail SOURCE_FILE_UNSAFE "$e cannot be snapshotted"
  # best effort: the path must still be the same regular non-symlink file (staged bytes are the authority)
  ino2=$(ident_of "$s") || fail SOURCE_FILE_UNSAFE "$e changed while snapshotting"
  physdir=$(phys_of "$(dirname "$s")")
  if [ -L "$s" ] || [ ! -f "$s" ] || [ "$ino1" != "$ino2" ] || [ "$physdir" != "$SRC/${e%%/*}" ]; then
    fail SOURCE_FILE_UNSAFE "$e changed while snapshotting"
  fi
  # record the staged file's identity and checksum: from here the staged copy is the source of truth
  SUM[$i]=$(ck "$STGP/$e") || fail COPY_FAILED "checksum of staged $e"
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
  STATUS=(); ACTION=(); DFID=(); n_in=0; n_diff=0; n_miss=0
  k=0
  while [ "$k" -lt "$N" ]; do
    e="${MANIFEST[$k]}"; d="$DEST/$e"
    DFID[$k]=""
    if [ -L "$d" ]; then apply_fail DESTINATION_UNSAFE "$e is a symlink"; fi
    if [ ! -e "$d" ]; then
      STATUS[$k]=missing; ACTION[$k]=copy; n_miss=$((n_miss + 1))
    else
      if [ ! -f "$d" ] || [ ! -r "$d" ]; then apply_fail DESTINATION_UNSAFE "$e is not a readable regular file"; fi
      # fail closed: an unreadable/unchecksummable installed file is never treated as in_sync
      dsum=$(ck "$d") || apply_fail DESTINATION_UNSAFE "cannot checksum installed $e"
      DFID[$k]=$(ident_of "$d") || apply_fail DESTINATION_UNSAFE "cannot identify installed $e"
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

# mkdir of exactly ONE level. A failure because the path now exists is a race (unsafe), not a copy error.
mk1() { # <abs path>
  if mkdir -- "$1" 2>/dev/null; then return 0; fi
  if [ -e "$1" ] || [ -L "$1" ]; then unsafe "$1 appeared during apply"; fi
  apply_fail COPY_FAILED "cannot create directory"
}

# $HOME/.config/opencode absent: create it one level at a time, each step revalidated.
ensure_dest_root() {
  local base="${HOMEPHYS%/}" cfg="$HOME/.config" p i cid
  run_hook before_mkdir .config
  home_ok || unsafe "home directory changed"
  if [ -L "$cfg" ]; then unsafe ".config is a symlink"; fi
  if [ ! -e "$cfg" ]; then mk1 "$cfg"; fi
  if [ -L "$cfg" ] || [ ! -d "$cfg" ]; then unsafe ".config is not a plain directory"; fi
  p=$(phys_of "$cfg") || unsafe ".config unreadable"
  [ "$p" = "$base/.config" ] || unsafe ".config resolves elsewhere"
  cid=$(ident_of "$p") || unsafe ".config cannot be identified"

  run_hook before_mkdir opencode
  home_ok || unsafe "home directory changed"
  if [ -L "$cfg" ] || [ ! -d "$cfg" ]; then unsafe ".config changed"; fi
  p=$(phys_of "$cfg") || unsafe ".config unreadable"
  [ "$p" = "$base/.config" ] || unsafe ".config changed"
  i=$(ident_of "$p") || unsafe ".config cannot be identified"
  [ "$i" = "$cid" ] || unsafe ".config changed"
  if [ -e "$DEST" ] || [ -L "$DEST" ]; then unsafe "destination root appeared during apply"; fi
  mk1 "$DEST"
  if [ -L "$DEST" ] || [ ! -d "$DEST" ]; then unsafe "destination root is not a plain directory"; fi
  p=$(phys_of "$DEST") || unsafe "destination root unreadable"
  [ "$p" = "$base/.config/opencode" ] || unsafe "destination root resolves elsewhere"
  DESTPHYS="$p"
  DESTID=$(ident_of "$p") || unsafe "destination root cannot be identified"
}

if [ -z "$DESTPHYS" ]; then ensure_dest_root; fi

# Only the three managed directories are ever created, one at a time, with a plain mkdir.
for d in $SUBDIRS; do
  run_hook before_mkdir "$d"
  root_ok || unsafe "destination root changed"
  if [ -z "$(get_did "$d")" ]; then
    # absent at validation time: it must still be absent
    if [ -e "$DEST/$d" ] || [ -L "$DEST/$d" ]; then unsafe "$d appeared during apply"; fi
    mk1 "$DEST/$d"
    if [ -L "$DEST/$d" ] || [ ! -d "$DEST/$d" ]; then unsafe "$d is not a plain directory"; fi
    p=$(phys_of "$DEST/$d") || unsafe "$d unreadable"
    [ "$p" = "$DESTPHYS/$d" ] || unsafe "$d resolves outside the destination root"
    id=$(ident_of "$p") || unsafe "$d cannot be identified"
    set_did "$d" "$id"
  else
    dir_ok "$d" || unsafe "$d changed during apply"
  fi
done

k=0
while [ "$k" -lt "$N" ]; do
  e="${MANIFEST[$k]}"
  sub="${e%%/*}"
  case "${ACTION[$k]}" in
    copy)
      if is_script "$e"; then perm=755; else perm=644; fi
      run_hook before_mktemp "$e"
      dest_safe "$k" || unsafe "$e changed during apply"
      TMPF=$(mktemp "$DEST/$sub/.sync-install.XXXXXX" 2>/dev/null) || { TMPF=""; apply_fail COPY_FAILED "$e"; }
      # record what was created (physical parent + identity) so cleanup and every later step can
      # prove it is still the same file; then it must be a fresh regular file in the validated dir
      TMPPAR=$(phys_of "$(dirname "$TMPF")") || TMPPAR=""
      TMPID=$(ident_of "$TMPF") || TMPID=""
      [ -n "$TMPPAR" ] && [ -n "$TMPID" ] || apply_fail COPY_FAILED "$e temp file"
      file_ok "$TMPF" "$DESTPHYS/$sub" "$TMPID" || unsafe "$e temp file"
      # write: both hooks first, then ALL checks, then the write itself (bytes come ONLY from the staged copy)
      run_hook before_tmp_write "$e"
      run_hook before_stage_read "$e"
      dest_safe "$k" || unsafe "$e changed during apply"
      file_ok "$TMPF" "$DESTPHYS/$sub" "$TMPID" || unsafe "$e temp file changed"
      # staged check LAST so it is the check closest to the read; the temp checksum below proves the bytes
      stage_ok "$k" || apply_fail SOURCE_FILE_UNSAFE "$e staged copy changed"
      # ponytail: the shell opens $TMPF for writing (follows symlinks) one step after the check above.
      cat -- "$STGP/$e" >"$TMPF" 2>/dev/null || apply_fail COPY_FAILED "$e"
      # mode is set on the temp file BEFORE the final validation, so no command sits between it and mv
      run_hook before_tmp_chmod "$e"
      dest_safe "$k" || unsafe "$e changed during apply"
      file_ok "$TMPF" "$DESTPHYS/$sub" "$TMPID" || unsafe "$e temp file changed"
      chmod "$perm" "$TMPF" 2>/dev/null || apply_fail COPY_FAILED "$e"
      # the finished temp file must hold exactly the validated staged bytes
      file_ok "$TMPF" "$DESTPHYS/$sub" "$TMPID" || unsafe "$e temp file changed"
      tsum=$(ck "$TMPF") || apply_fail COPY_FAILED "checksum of temp $e"
      [ "$tsum" = "${SUM[$k]}" ] || apply_fail SOURCE_FILE_UNSAFE "$e bytes differ from the validated staged copy"
      # final validation, then mv immediately: only shell-local work in between
      run_hook before_mv "$e"
      dest_safe "$k" || unsafe "$e changed during apply"
      file_ok "$TMPF" "$DESTPHYS/$sub" "$TMPID" || unsafe "$e temp file changed"
      # ponytail: check-then-act window remains here (no openat/renameat); see header.
      if mv -f -- "$TMPF" "$DEST/$e" 2>/dev/null; then
        TMPF=""; TMPID=""; TMPPAR=""
        COPIED="$COPIED $e"
      else
        apply_fail COPY_FAILED "$e"
      fi
      ;;
    chmod)
      run_hook before_chmod "$e"
      dest_safe "$k" || unsafe "$e changed during apply"
      # ponytail: chmod follows a symlink swapped in after the check above; narrowed, not eliminated.
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
