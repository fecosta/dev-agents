#!/usr/bin/env bash
# validation-efficiency.sh — reusable helpers for declared-scope evidence reuse.
# This is a library; source it from tests. It requires a Git repository as CWD.

# evidence_commit_is_ancestor <evidence_commit> <final_commit>
evidence_commit_is_ancestor() {
  git merge-base --is-ancestor "$1" "$2" 2>/dev/null
}

# scope_matches_path <scope_spec> <path>
# scope_spec: space-separated list of files/globs (e.g. "src/*.py tests/").
# A glob with a trailing slash matches paths inside that directory.
scope_matches_path() {
  local spec="$1" p="$2" s
  for s in $spec; do
    case "$s" in
      */) case "$p" in "$s"*|*/"${s%/}"/*) return 0 ;; esac ;;
      *\**) case "$p" in $s) return 0 ;; esac ;;
      *) [ "$p" = "$s" ] && return 0 ;;
    esac
  done
  return 1
}

# scope_intersects_changes <evidence_commit> <final_commit> <scope_spec> [dependency_surface_file]
# Returns 0 (true) if the scope intersects changed files or the dependency surface changed.
scope_intersects_changes() {
  local evidence="$1" final="$2" scope="$3" dep_surface="${4:-}"
  # Empty scope means repository-wide coverage.
  if [ -z "$scope" ]; then
    local count
    count=$(git diff --name-only "$evidence" "$final" 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -gt 0 ]
    return
  fi
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if scope_matches_path "$scope" "$p"; then return 0; fi
  done < <(git diff --name-only "$evidence" "$final" 2>/dev/null)
  if [ -n "$dep_surface" ] && git diff --quiet "$evidence" "$final" -- "$dep_surface" 2>/dev/null; then
    : # dependency surface unchanged
  elif [ -n "$dep_surface" ]; then
    return 0
  fi
  return 1
}

# decide_evidence_reuse <command> <result> <evidence_commit> <final_commit> <scope_spec> [dependency_surface_file]
# Prints "reused <reason>" or "stale <reason>".
decide_evidence_reuse() {
  local cmd="$1" result="$2" evidence="$3" final="$4" scope="$5" dep_surface="${6:-}"
  case "$result" in
    passed) ;;
    partial|not_run|unknown|failed*) echo "stale result=$result"; return ;;
    *) echo "stale unknown_result=$result"; return ;;
  esac
  if ! evidence_commit_is_ancestor "$evidence" "$final"; then
    echo "stale evidence_commit=$evidence is not an ancestor of final_commit=$final"
    return
  fi
  if scope_intersects_changes "$evidence" "$final" "$scope" "$dep_surface"; then
    if [ -z "$scope" ]; then
      echo "stale scope=repository-wide and files changed after $evidence"
    else
      echo "stale scope file or dependency surface changed after $evidence"
    fi
    return
  fi
  echo "reused command='$cmd' scope_unchanged since $evidence"
}
