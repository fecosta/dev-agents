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

# decide_evidence_reuse <evidence_command> <current_command> <result> <label>
#                     <evidence_commit> <final_commit>
#                     <evidence_scope> <current_scope> [dependency_surface_file]
#                     [tool_version] [current_tool_version]
#                     [env_fingerprint] [current_env_fingerprint]
# Prints "reused <reason>" or "stale <reason>".
decide_evidence_reuse() {
  local evidence_command="$1" current_command="$2" result="$3" label="$4"
  local evidence="$5" final="$6"
  local evidence_scope="$7" current_scope="$8"
  local dep_surface="${9:-}"
  local evidence_tool="${10:-}" current_tool="${11:-}"
  local evidence_env="${12:-}" current_env="${13:-}"

  # Evidence must be complete and trustworthy.
  case "$result" in
    passed) ;;
    partial|not_run|unknown|failed*) echo "stale result=$result"; return ;;
    *) echo "stale unknown_result=$result"; return ;;
  esac

  case "$label" in
    "[observed]") ;;
    *) echo "stale label=$label (not [observed])"; return ;;
  esac

  # Command identity and declared scope must be unchanged.
  if [ "$evidence_command" != "$current_command" ]; then
    echo "stale command changed from '$evidence_command' to '$current_command'"
    return
  fi
  if [ "$evidence_scope" != "$current_scope" ]; then
    echo "stale scope declaration changed from '$evidence_scope' to '$current_scope'"
    return
  fi

  # Tool version and relevant environment must be established and unchanged.
  # Empty fingerprints are indeterminate and fail closed.
  if [ -z "$evidence_tool" ] || [ -z "$current_tool" ]; then
    echo "stale tool_version indeterminate"
    return
  fi
  if [ "$evidence_tool" != "$current_tool" ]; then
    echo "stale tool_version changed from '$evidence_tool' to '$current_tool'"
    return
  fi
  if [ -z "$evidence_env" ] || [ -z "$current_env" ]; then
    echo "stale env_fingerprint indeterminate"
    return
  fi
  if [ "$evidence_env" != "$current_env" ]; then
    echo "stale env_fingerprint changed from '$evidence_env' to '$current_env'"
    return
  fi

  if ! evidence_commit_is_ancestor "$evidence" "$final"; then
    echo "stale evidence_commit=$evidence is not an ancestor of final_commit=$final"
    return
  fi

  if scope_intersects_changes "$evidence" "$final" "$current_scope" "$dep_surface"; then
    if [ -z "$current_scope" ]; then
      echo "stale scope=repository-wide and files changed after $evidence"
    else
      echo "stale scope file or dependency surface changed after $evidence"
    fi
    return
  fi

  echo "reused command='$current_command' scope_unchanged since $evidence"
}
