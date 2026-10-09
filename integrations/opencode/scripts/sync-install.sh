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
# Write boundary: the explicit MANIFEST below, nothing else. Source <root>/integrations/opencode/<entry>,
# destination $HOME/.config/opencode/<entry>. No globs, no directory copies, no deletion of
# destination files. Unmanaged files and all provider/router configuration are never touched.
#
# Output: key=value lines. Per manifest entry (manifest order) "file=<rel>" followed by
# "status=in_sync|missing|different". Any other "status=" line (not right after "file=") is the
# overall result: status=applied|failed. Then: sync_status=clean|drift|failed, in_sync=N,
# different=N, missing=N. Failures: status=failed, reason=<CODE>, [detail=<text>], sync_status=failed.
# Apply adds copied=<rel>, chmodded=<rel>, doctor_* lines. Counts in apply are the post-apply state.
# A script whose content matches but is not executable counts as status=different (chmod only).
#
# Exit codes: 0 clean (check) / applied (apply) | 1 drift (check) | 2 setup, validation or
# post-install failure | 64 usage error.
# Reasons: USAGE, SOURCE_REPOSITORY_UNVERIFIED, SOURCE_FILE_MISSING, HOME_INVALID,
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
cleanup() { if [ -n "$TMPF" ]; then rm -f -- "$TMPF"; fi; }
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
  for d in $SUBDIRS; do
    if [ -L "$DEST/$d" ]; then fail DESTINATION_UNSAFE "$d is a symlink"; fi
    if [ -e "$DEST/$d" ]; then
      [ -d "$DEST/$d" ] || fail DESTINATION_UNSAFE "$d is not a directory"
      phys=$(cd -P "$DEST/$d" 2>/dev/null && pwd -P)
      [ -n "$physroot" ] && [ "$phys" = "$physroot/$d" ] || fail DESTINATION_UNSAFE "$d resolves outside the destination root"
    fi
  done
}

# --- preflight (no writes) --------------------------------------------------------

N=${#MANIFEST[@]}
i=0
while [ "$i" -lt "$N" ]; do
  e="${MANIFEST[$i]}"
  valid_rel "$e" || fail USAGE "invalid manifest entry"
  s="$SRC/$e"
  if [ -L "$s" ] || [ ! -f "$s" ] || [ ! -r "$s" ]; then fail SOURCE_FILE_MISSING "$e"; fi
  physdir=$(cd -P "$(dirname "$s")" 2>/dev/null && pwd -P)
  [ "$physdir" = "$SRC/${e%%/*}" ] || fail SOURCE_FILE_MISSING "$e"
  i=$((i + 1))
done

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
  local k e d
  STATUS=(); ACTION=(); n_in=0; n_diff=0; n_miss=0
  k=0
  while [ "$k" -lt "$N" ]; do
    e="${MANIFEST[$k]}"; d="$DEST/$e"
    if [ ! -e "$d" ]; then
      STATUS[$k]=missing; ACTION[$k]=copy; n_miss=$((n_miss + 1))
    elif ! cmp -s "$SRC/$e" "$d"; then
      STATUS[$k]=different; ACTION[$k]=copy; n_diff=$((n_diff + 1))
    elif is_script "$e" && [ ! -x "$d" ]; then
      STATUS[$k]=different; ACTION[$k]=chmod; n_diff=$((n_diff + 1))
    else
      STATUS[$k]=in_sync; ACTION[$k]=none; n_in=$((n_in + 1))
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
printf 'mode=%s\n' "$MODE"
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

COPIED=""
CHMODDED=""
print_changes() {
  local r
  for r in $COPIED; do printf 'copied=%s\n' "$r"; done
  for r in $CHMODDED; do printf 'chmodded=%s\n' "$r"; done
}
apply_fail() { print_changes; fail "$@"; }

# Only the three managed directories are ever created.
for d in $SUBDIRS; do
  if [ ! -d "$DEST/$d" ]; then mkdir -p "$DEST/$d" 2>/dev/null || fail COPY_FAILED "cannot create $d"; fi
done
check_dest_dirs

k=0
while [ "$k" -lt "$N" ]; do
  e="${MANIFEST[$k]}"
  case "${ACTION[$k]}" in
    copy)
      if is_script "$e"; then perm=755; else perm=644; fi
      TMPF=$(mktemp "$DEST/$(dirname "$e")/.sync-install.XXXXXX" 2>/dev/null) || { TMPF=""; apply_fail COPY_FAILED "$e"; }
      if cat "$SRC/$e" >"$TMPF" 2>/dev/null && chmod "$perm" "$TMPF" && mv -f "$TMPF" "$DEST/$e"; then
        TMPF=""
        COPIED="$COPIED $e"
      else
        apply_fail COPY_FAILED "$e"
      fi
      ;;
    chmod)
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
