#!/usr/bin/env bash
# review-route.sh — read-only helper for the OpenCode orchestrator (v3b.2).
#
#   review-route.sh checkpoint <start|end>
#       Prints COALESCE(MAX(id),0) of 9Router usageHistory (one integer, exit 0).
#       On any failure prints "status=failed" + "reason=<START|END>_CHECKPOINT_FAILED", exit 2.
#   review-route.sh resolve <start-id> <end-id> <capability-alias>
#       Runs resolve-model-family.sh, strictly validates its output, and prints either
#         model_resolution=resolved family= reviewer= models= providers=      (exit 0)
#         model_resolution=blocked status=REVIEW_BLOCKED_MODEL_RESOLUTION reason=<REASON>  (exit 3)
#       Family classification stays in the resolver; this only checks that the output is
#       well formed and that family and reviewer agree (claude -> review-openai,
#       non-claude -> review-claude). Anything else fails closed. No guessing.
#
# Env: NINEROUTER_DB (default ~/.9router/db/data.sqlite). DEV_AGENTS_RESOLVER overrides the
# resolver path (tests only).
# SQL: only SELECT COALESCE(MAX(id),0) FROM usageHistory, opened -readonly + query_only.
# bash 3.2+, no dependencies beyond sqlite3.

set -u
export LC_ALL=C

DB_PATH="${NINEROUTER_DB:-$HOME/.9router/db/data.sqlite}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="${DEV_AGENTS_RESOLVER:-$HERE/resolve-model-family.sh}"
INT_RE='^[0-9]{1,15}$'

blocked() {
  echo "model_resolution=blocked"
  echo "status=REVIEW_BLOCKED_MODEL_RESOLUTION"
  echo "reason=$1"
  exit 3
}

checkpoint() {
  local label="$1" reason out
  case "$label" in
    start) reason=START_CHECKPOINT_FAILED ;;
    end) reason=END_CHECKPOINT_FAILED ;;
    *) echo "usage: review-route.sh checkpoint <start|end>" >&2; exit 64 ;;
  esac
  cp_fail() { echo "status=failed"; echo "reason=$reason"; exit 2; }
  command -v sqlite3 >/dev/null 2>&1 || cp_fail
  [[ -f "$DB_PATH" && -r "$DB_PATH" ]] || cp_fail
  out=$(sqlite3 -init /dev/null -batch -list -noheader -readonly "$DB_PATH" \
    ".timeout 2000" "PRAGMA query_only=1;" \
    "SELECT COALESCE(MAX(id),0) FROM usageHistory;" 2>/dev/null) || cp_fail
  [[ "$out" =~ $INT_RE ]] || cp_fail
  echo "$out"
}

resolve() {
  [[ $# -eq 3 ]] || { echo "usage: review-route.sh resolve <start-id> <end-id> <alias>" >&2; exit 64; }
  local start="$1" end="$2" alias="$3"
  [[ "$start" =~ $INT_RE && "$end" =~ $INT_RE ]] || blocked INVALID_CHECKPOINT
  [[ $((10#$end)) -ge $((10#$start)) ]] || blocked INVALID_WINDOW
  [[ -x "$RESOLVER" && -f "$RESOLVER" ]] || blocked RESOLVER_UNAVAILABLE

  local out rc
  out=$("$RESOLVER" "$start" "$end" "$alias" 2>/dev/null)
  rc=$?

  # Strict parse: only key=value lines, known keys, no duplicates, safe characters.
  local status="" combo="" window="" family="" families="" reviewer="" models="" providers="" usage_ids="" reason=""
  local seen=" " line key val
  while IFS= read -r line; do
    [[ "$line" =~ ^([a-z_]+)=([A-Za-z0-9._,-]*)$ ]] || blocked RESOLVER_OUTPUT_INVALID
    key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    case "$seen" in *" $key "*) blocked RESOLVER_OUTPUT_INVALID ;; esac
    seen="$seen$key "
    case "$key" in
      status) status="$val" ;;
      combo) combo="$val" ;;
      window) window="$val" ;;
      family) family="$val" ;;
      families) families="$val" ;;
      reviewer) reviewer="$val" ;;
      models) models="$val" ;;
      providers) providers="$val" ;;
      usage_ids) usage_ids="$val" ;;
      reason) reason="$val" ;;
      *) blocked RESOLVER_OUTPUT_INVALID ;;
    esac
  done <<< "$out"

  if [[ $rc -ne 0 ]]; then
    # Non-success: surface the resolver's own stable reason; never a family.
    if [[ "$status" != "resolved" && -z "$family" && -z "$reviewer" && "$reason" =~ ^[A-Z][A-Z0-9_]{0,63}$ ]]; then
      blocked "$reason"
    fi
    blocked RESOLVER_OUTPUT_INVALID
  fi

  [[ "$status" == "resolved" && -z "$reason" ]] || blocked RESOLVER_OUTPUT_INVALID
  [[ "$combo" == "$alias" && "$window" == "$((10#$start))-$((10#$end))" ]] || blocked RESOLVER_OUTPUT_INVALID
  [[ -n "$models" && -n "$providers" ]] || blocked RESOLVER_OUTPUT_INVALID
  case "$family/$reviewer" in
    claude/review-openai | non-claude/review-claude) ;;
    *) blocked RESOLVER_OUTPUT_INVALID ;;
  esac

  echo "model_resolution=resolved"
  echo "family=$family"
  echo "reviewer=$reviewer"
  echo "models=$models"
  echo "providers=$providers"
}

case "${1:-}" in
  checkpoint) [[ $# -eq 2 ]] || { echo "usage: review-route.sh checkpoint <start|end>" >&2; exit 64; }; checkpoint "$2" ;;
  resolve) shift; resolve "$@" ;;
  *) echo "usage: review-route.sh checkpoint <start|end> | resolve <start-id> <end-id> <alias>" >&2; exit 64 ;;
esac
