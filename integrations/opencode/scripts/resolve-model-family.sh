#!/usr/bin/env bash
# resolve-model-family.sh — read-only 9Router runtime model resolver for OpenCode child sessions.
# Usage: resolve-model-family.sh <checkpoint-id> <combo-name>
#
# Resolves the model family (claude vs non-claude) actually used in usageHistory
# rows after the given checkpoint for a named combo, then maps to the opposite-family
# reviewer per policies/review-routing.md.
#
# Exit codes:
#   0  resolved (all claude or all non-claude)
#   1  generic / usage error
#   2  USAGE / validation error
#   3  combo not found
#   4  model detection failed (no matching ok rows)
#   5  model detection ambiguous (mixed families)
#   6  runtime / sqlite error
#
# ponytail: This resolver cannot distinguish usage rows from unrelated concurrent
# sessions that happen to use the same combo models after the checkpoint. The caller
# should capture a fresh checkpoint immediately before delegating to the child session.
# Upgrade path: scope rows by a session/correlation id once 9Router records one.

set -euo pipefail

readonly DB_PATH="${NINEROUTER_DB:-$HOME/.9router/db/data.sqlite}"

# --- validation ---------------------------------------------------------------

usage_error() {
  echo "status=failed"
  echo "reason=USAGE"
  echo "usage=resolve-model-family.sh <checkpoint-id> <combo-name>" >&2
  exit 2
}

fail() {
  local code="$1" reason="$2"
  echo "status=failed"
  echo "reason=$reason"
  exit "$code"
}

if [[ $# -ne 2 ]]; then
  usage_error
fi

readonly checkpoint_raw="$1"
readonly combo="$2"

if [[ -z "$checkpoint_raw" || "$checkpoint_raw" =~ [^0-9] ]]; then
  echo "status=failed"
  echo "reason=INVALID_CHECKPOINT"
  echo "Invalid checkpoint-id: must be a non-negative integer" >&2
  exit 2
fi
readonly checkpoint="$checkpoint_raw"

if [[ -z "$combo" || ! "$combo" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "status=failed"
  echo "combo=$combo"
  echo "reason=INVALID_COMBO_NAME"
  echo "Invalid combo-name: must match [A-Za-z0-9._-]+" >&2
  exit 2
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "status=failed"
  echo "reason=SQLITE3_NOT_FOUND"
  echo "sqlite3 not found on PATH" >&2
  exit 2
fi

if [[ ! -e "$DB_PATH" ]]; then
  echo "status=failed"
  echo "reason=DB_NOT_FOUND"
  echo "Database not found: $DB_PATH" >&2
  exit 2
fi

if [[ ! -r "$DB_PATH" ]]; then
  echo "status=failed"
  echo "reason=DB_NOT_READABLE"
  echo "Database not readable: $DB_PATH" >&2
  exit 2
fi

# --- helpers ------------------------------------------------------------------

# Quote a string for safe inclusion in a single-quoted SQL literal.
sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

# Test whether sqlite3 supports JSON1 (json_each).
has_json1() {
  sqlite3 -readonly "$DB_PATH" "SELECT value FROM json_each('[\"a\"]') LIMIT 1;" >/dev/null 2>&1
}

# Extract candidate model names (portion after the last '/') from a JSON array of
# "provider/model" strings. Outputs one model per line.
parse_candidate_models() {
  local json="$1"
  local entries
  if has_json1; then
    # JSON1 path: extract the raw provider/model entries.
    entries=$(sqlite3 -readonly "$DB_PATH" "SELECT value FROM json_each('$(sql_quote "$json")');")
  else
    # Fallback path: extract all quoted strings.
    entries=$(printf '%s' "$json" | grep -oE '"[^"]*"' | tr -d '"')
  fi
  # Take the portion after the last '/' for each entry.
  printf '%s\n' "$entries" | sed 's/.*\///'
}

# --- read combo candidates ----------------------------------------------------

combo_models_json=$(sqlite3 -readonly "$DB_PATH" "PRAGMA query_only=1; SELECT models FROM combos WHERE name = '$(sql_quote "$combo")';") || {
  echo "status=failed"
  echo "reason=RUNTIME_ERROR"
  echo "Failed to query combos table" >&2
  exit 6
}

if [[ -z "$combo_models_json" ]]; then
  echo "status=failed"
  echo "combo=$combo"
  echo "reason=COMBO_NOT_FOUND"
  exit 3
fi

candidate_models=()
while IFS= read -r line; do
  [[ -n "$line" ]] && candidate_models+=("$line")
done < <(parse_candidate_models "$combo_models_json")

if [[ ${#candidate_models[@]} -eq 0 ]]; then
  echo "status=failed"
  echo "combo=$combo"
  echo "reason=MODEL_PARSE_FAILED"
  echo "Could not parse combo models JSON" >&2
  exit 6
fi

# Build IN clause for candidate models.
in_clause=""
sep=""
for m in "${candidate_models[@]}"; do
  in_clause="${in_clause}${sep}'$(sql_quote "$m")'"
  sep=","
done

# --- query usageHistory -------------------------------------------------------

# Strictly read-only: -readonly on the CLI plus query_only PRAGMA.
# Select ONLY id, provider, model — never credential-bearing columns.
# ponytail: If 9Router later adds a session/correlation column, scope rows by it
# here to eliminate concurrent-session ambiguity.
rows=$(sqlite3 -readonly "$DB_PATH" "PRAGMA query_only=1;
SELECT id, provider, model
FROM usageHistory
WHERE id > $(sql_quote "$checkpoint")
  AND status = 'ok'
  AND model IN ($in_clause)
ORDER BY id ASC;") || {
  echo "status=failed"
  echo "reason=RUNTIME_ERROR"
  echo "Failed to query usageHistory table" >&2
  exit 6
}

if [[ -z "$rows" ]]; then
  echo "status=failed"
  echo "combo=$combo"
  echo "reason=MODEL_DETECTION_FAILED"
  exit 4
fi

# --- classify families --------------------------------------------------------

usage_ids=()
providers=()
models=()
has_claude=0
has_non_claude=0

while IFS='|' read -r uh_id uh_provider uh_model; do
  usage_ids+=("$uh_id")
  providers+=("$uh_provider")
  models+=("$uh_model")
  if [[ "$uh_model" == claude-* ]]; then
    has_claude=1
  else
    has_non_claude=1
  fi
done <<< "$rows"

models_csv=$(printf '%s\n' "${models[@]}" | sort -u | paste -sd ',' -)
providers_csv=$(printf '%s\n' "${providers[@]}" | sort -u | paste -sd ',' -)
usage_ids_csv=$(printf '%s\n' "${usage_ids[@]}" | sort -n -u | paste -sd ',' -)

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
echo "family=$family"
echo "reviewer=$reviewer"
echo "models=$models_csv"
echo "providers=$providers_csv"
echo "usage_ids=$usage_ids_csv"
exit 0
