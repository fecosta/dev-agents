#!/usr/bin/env bash
# resolve-model-family.sh — read-only 9Router runtime model resolver for OpenCode child sessions.
# Usage: resolve-model-family.sh <start-id> <end-id> <combo-name>
#
# Resolves the model family (claude vs non-claude) actually used in usageHistory
# rows with start-id < id <= end-id for a named combo, then maps to the
# opposite-family reviewer per policies/review-routing.md.
#
# Output: key=value lines on stdout. Every emitted provider/model value is
# validated against [A-Za-z0-9._-]+; the combo name is only echoed after the same
# validation. Failures are always status=failed|ambiguous plus a reason, exit != 0.
#
# Exit codes / reasons:
#   0  resolved (all rows claude, or all rows non-claude)
#   2  USAGE | INVALID_CHECKPOINT | INVALID_WINDOW | INVALID_COMBO_NAME |
#      SQLITE3_NOT_FOUND | DB_NOT_FOUND | DB_NOT_READABLE
#   3  COMBO_NOT_FOUND
#   4  MODEL_DETECTION_FAILED   (no matching ok rows in window)
#   5  MODEL_DETECTION_AMBIGUOUS (status=ambiguous; both families in window)
#   6  RUNTIME_ERROR (sqlite/schema/query failure) | MODEL_PARSE_FAILED
#   7  MODEL_FAMILY_UNKNOWN     (row is neither Claude nor allowlisted non-Claude)
#   8  MODEL_ATTRIBUTION_UNKNOWN (row model matches a candidate but not its route's provider)
#   9  UNSAFE_OUTPUT_VALUE
#
# Window: the caller (v3b.2) must capture start-id immediately BEFORE child
# delegation and end-id immediately AFTER child completion, so later orchestrator
# traffic is outside the window.
#
# ponytail: usageHistory has no session/correlation column, so unrelated concurrent
# traffic INSIDE the window cannot be told apart. It fails closed when attribution is
# not exact or families mix, but same-provider/same-model traffic is indistinguishable.
# Upgrade path: scope rows by a correlation id once 9Router records one.
#
# Read-only: sqlite3 -readonly + PRAGMA query_only=1, SELECT only. Reads only
# combos.name/models and usageHistory.id/provider/model/status. No JSON1 needed.

set -euo pipefail
export LC_ALL=C

readonly DB_PATH="${NINEROUTER_DB:-$HOME/.9router/db/data.sqlite}"
readonly SAFE_RE='^[A-Za-z0-9._-]+$'
readonly ENTRY_RE='^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'
readonly ARRAY_RE='^\[[[:space:]]*("[A-Za-z0-9._/-]*"[[:space:]]*(,[[:space:]]*"[A-Za-z0-9._/-]*"[[:space:]]*)*)?\]$'

fail() {
  local code="$1" reason="$2"
  echo "status=failed"
  echo "reason=$reason"
  exit "$code"
}

# Route prefix -> runtime provider glob (lowercase). Empty output = unmapped.
# Evidence (live 9Router DB, read-only, usageHistory.provider/model vs combos.models):
#   cc    -> provider "claude"       (cc/claude-sonnet-5-5 rows: claude|claude-sonnet-5-5)
#   cx    -> provider "codex"        (cx/gpt-5.6-sol rows: codex|gpt-5.6-sol)
#   ocg   -> provider "opencode-go"  (ocg/kimi-k2.7-code rows: opencode-go|kimi-k2.7-code)
#   dmas  -> "anthropic-compatible-<uuid>"      (only claude-* rows with that provider type)
#   oc-dmas -> "openai-compatible-responses-<uuid>" (only gpt-* rows with that provider type)
# The compatible-node uuid is dynamic and not derivable from the allowed columns, so
# dmas/oc-dmas match on the provider-type prefix only. Unknown prefixes stay unmapped
# and fail closed.
provider_glob() {
  case "$1" in
    cc) echo "claude" ;;
    cx) echo "codex" ;;
    ocg) echo "opencode-go" ;;
    dmas) echo "anthropic-compatible-*" ;;
    oc-dmas) echo "openai-compatible-responses-*" ;;
    *) echo "" ;;
  esac
}

lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

# --- validation ---------------------------------------------------------------

if [[ $# -ne 3 ]]; then
  echo "usage=resolve-model-family.sh <start-id> <end-id> <combo-name>" >&2
  fail 2 USAGE
fi

start_raw="$1"
end_raw="$2"
combo="$3"

int_re='^[0-9]{1,15}$'
if ! [[ "$start_raw" =~ $int_re && "$end_raw" =~ $int_re ]]; then
  echo "start-id and end-id must be non-negative integers" >&2
  fail 2 INVALID_CHECKPOINT
fi
start=$((10#$start_raw))
end=$((10#$end_raw))
if [[ $end -lt $start ]]; then
  echo "end-id must be >= start-id" >&2
  fail 2 INVALID_WINDOW
fi

if ! [[ "$combo" =~ $SAFE_RE ]]; then
  echo "combo-name must match [A-Za-z0-9._-]+" >&2
  fail 2 INVALID_COMBO_NAME
fi

command -v sqlite3 >/dev/null 2>&1 || { echo "sqlite3 not found on PATH" >&2; fail 2 SQLITE3_NOT_FOUND; }
[[ -e "$DB_PATH" ]] || { echo "Database not found: $DB_PATH" >&2; fail 2 DB_NOT_FOUND; }
[[ -r "$DB_PATH" ]] || { echo "Database not readable: $DB_PATH" >&2; fail 2 DB_NOT_READABLE; }

# --- read combo candidates ----------------------------------------------------

combo_json=$(sqlite3 -readonly "$DB_PATH" "PRAGMA query_only=1; SELECT models FROM combos WHERE name = '$combo';" 2>/dev/null) || {
  echo "Failed to query combos table" >&2
  fail 6 RUNTIME_ERROR
}

if [[ -z "$combo_json" ]]; then
  echo "status=failed"
  echo "combo=$combo"
  echo "reason=COMBO_NOT_FOUND"
  exit 3
fi

# Strict parse: JSON array of "prefix/model" strings with safe characters only.
# Escapes, nested values, or odd characters fail the whole parse (fail closed).
if ! [[ "$combo_json" =~ $ARRAY_RE ]]; then
  echo "Combo models JSON is not a plain array of safe strings" >&2
  fail 6 MODEL_PARSE_FAILED
fi

cand_prefix=()
cand_model=()
in_clause=""
sep=""
while IFS= read -r entry; do
  entry="${entry//\"/}"
  if ! [[ "$entry" =~ $ENTRY_RE ]]; then
    echo "Combo entry is not <prefix>/<model>" >&2
    fail 6 MODEL_PARSE_FAILED
  fi
  m="$(lc "${entry#*/}")"
  cand_prefix+=("$(lc "${entry%%/*}")")
  cand_model+=("$m")
  in_clause="${in_clause}${sep}'${m}'"
  sep=","
done < <(printf '%s' "$combo_json" | grep -oE '"[^"]*"' || true)

if [[ ${#cand_model[@]} -eq 0 ]]; then
  echo "Combo has no models" >&2
  fail 6 MODEL_PARSE_FAILED
fi

# --- query usageHistory -------------------------------------------------------

# Select ONLY id, provider, model. The SQL flags values outside the safe charset
# and blanks them so a hostile value can never split or inject output lines.
unsafe='GLOB '"'"'*[^A-Za-z0-9._-]*'"'"
rows=$(sqlite3 -readonly "$DB_PATH" "PRAGMA query_only=1;
SELECT id,
  (COALESCE(provider,'') $unsafe OR COALESCE(model,'') $unsafe),
  CASE WHEN COALESCE(provider,'') $unsafe THEN '' ELSE COALESCE(provider,'') END,
  CASE WHEN COALESCE(model,'') $unsafe THEN '' ELSE COALESCE(model,'') END
FROM usageHistory
WHERE id > $start AND id <= $end
  AND status = 'ok'
  AND lower(model) IN ($in_clause)
ORDER BY id ASC;" 2>/dev/null) || {
  echo "Failed to query usageHistory table" >&2
  fail 6 RUNTIME_ERROR
}

if [[ -z "$rows" ]]; then
  echo "status=failed"
  echo "combo=$combo"
  echo "reason=MODEL_DETECTION_FAILED"
  exit 4
fi

# --- attribute + classify -----------------------------------------------------

ids=""
providers=""
models=""
has_claude=0
has_non_claude=0

while IFS='|' read -r uh_id uh_unsafe uh_provider uh_model; do
  if [[ "$uh_unsafe" != "0" || ! "$uh_id" =~ $int_re ]]; then
    fail 9 UNSAFE_OUTPUT_VALUE
  fi
  p="$(lc "$uh_provider")"
  m="$(lc "$uh_model")"

  # Attribution: the row's provider must match the route of a candidate with the
  # same model. Any same-model candidate with an unmapped prefix, or no
  # provider match, means exact attribution is impossible -> fail closed.
  attributed=0
  unmapped=0
  i=0
  while [[ $i -lt ${#cand_model[@]} ]]; do
    if [[ "${cand_model[$i]}" == "$m" ]]; then
      g="$(provider_glob "${cand_prefix[$i]}")"
      if [[ -z "$g" ]]; then
        unmapped=1
      elif [[ -n "$p" && "$p" == $g ]]; then
        attributed=1
      fi
    fi
    i=$((i + 1))
  done
  if [[ $unmapped -eq 1 || $attributed -eq 0 ]]; then
    fail 8 MODEL_ATTRIBUTION_UNKNOWN
  fi

  # Family: fail closed unless exactly one side matches.
  is_claude=0
  is_non=0
  case "$p/$m" in *claude* | *anthropic*) is_claude=1 ;; esac
  case "$m" in *gpt* | *codex* | *kimi* | *deepseek* | *glm*) is_non=1 ;; esac
  if [[ $((is_claude + is_non)) -ne 1 ]]; then
    fail 7 MODEL_FAMILY_UNKNOWN
  fi
  if [[ $is_claude -eq 1 ]]; then has_claude=1; else has_non_claude=1; fi

  # Defense in depth: re-validate every value about to be emitted.
  if ! [[ "$uh_provider" =~ $SAFE_RE && "$uh_model" =~ $SAFE_RE ]]; then
    fail 9 UNSAFE_OUTPUT_VALUE
  fi
  ids="${ids}${uh_id}"$'\n'
  providers="${providers}${uh_provider}"$'\n'
  models="${models}${uh_model}"$'\n'
done <<< "$rows"

csv() { printf '%s' "$1" | sort "${2:--u}" | paste -sd ',' -; }
models_csv=$(csv "$models")
providers_csv=$(csv "$providers")
ids_csv=$(csv "$ids" -nu)

if [[ $has_claude -eq 1 && $has_non_claude -eq 1 ]]; then
  echo "status=ambiguous"
  echo "combo=$combo"
  echo "reason=MODEL_DETECTION_AMBIGUOUS"
  echo "models=$models_csv"
  echo "families=claude,non-claude"
  echo "providers=$providers_csv"
  exit 5
fi

if [[ $has_claude -eq 1 ]]; then
  family="claude"
  reviewer="review-openai"
else
  family="non-claude"
  reviewer="review-claude"
fi

echo "status=resolved"
echo "combo=$combo"
echo "window=$start-$end"
echo "family=$family"
echo "reviewer=$reviewer"
echo "models=$models_csv"
echo "providers=$providers_csv"
echo "usage_ids=$ids_csv"
exit 0
