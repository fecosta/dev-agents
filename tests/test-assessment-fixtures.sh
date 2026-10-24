#!/usr/bin/env bash
# test-assessment-fixtures.sh — verify Phase A assessment fixtures against the state contract.
# bash 3.2+, no frameworks.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXDIR="$HERE/../examples/assessment"

pass=0; failn=0
ok() { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { failn=$((failn + 1)); echo "FAIL: $1"; }

required_keys=(fixture basis scenario assessed_commit implementation review validation environments acceptance findings conflicts doc_state human_acceptance next_unit expected_readiness expected_decision rules must_not_decide)
valid_readiness=(blocked not_ready needs_human_decision ready_with_notes ready)
valid_decisions=(ACCEPT_UNIT REMEDIATE_FINDINGS VERIFY_FURTHER INVESTIGATE_FAILURE RECONCILE_DOCS PREPARE_NEXT_UNIT REQUEST_HUMAN_DECISION)

value_of() { sed -n "s/^$1: //p" "$2" | head -n 1; }

items_of() {
  local line="$(value_of "$1" "$2")"
  [ "$line" = "none" ] && return
  local IFS=';'; for item in $line; do
    item="${item# }"; item="${item% }"
    [ -n "$item" ] && echo "$item"
  done
}

cap=0
set_cap() { [ "$1" -gt "$cap" ] && cap="$1"; }

derive_readiness() {
  local f="$1" x k v
  cap=0

  local assessed_commit="$(value_of assessed_commit "$f")"
  [ "$assessed_commit" = "unknown" ] && set_cap 4

  local implementation="$(value_of implementation "$f")"
  case "$implementation" in
    incomplete|none) set_cap 3 ;;
    unknown) set_cap 4 ;;
  esac

  local review="$(value_of review "$f")"
  local review_state=""
  case "$review" in
    PASS@*|PASS_WITH_NOTES@*|CHANGES_REQUIRED@*)
      local rc="${review#*@}"
      local rv="${review%%@*}"
      if [ "$rc" = "$assessed_commit" ]; then review_state="$rv"; else review_state="stale"; fi
      ;;
    not_required*) review_state="not_required" ;;
    pending*) review_state="pending" ;;
    blocked*) review_state="$review" ;;
    stale) review_state="stale" ;;
    unknown|*) review_state="unknown" ;;
  esac
  case "$review_state" in
    PASS|not_required) : ;;
    PASS_WITH_NOTES) set_cap 1 ;;
    CHANGES_REQUIRED) set_cap 3 ;;
    pending|stale|blocked*|unknown) set_cap 4 ;;
  esac

  while IFS='=' read -r k v; do
    case "$v" in
      passed) : ;;
      failed*|partial|not_run) set_cap 3 ;;
      unknown|*) set_cap 4 ;;
    esac
  done < <(items_of validation "$f")

  while IFS='=' read -r k v; do
    case "$v" in
      verified|not_applicable) : ;;
      pending|failed*) set_cap 3 ;;
      unknown|*) set_cap 4 ;;
    esac
  done < <(items_of environments "$f")

  while IFS='=' read -r k v; do
    case "$v" in
      met) : ;;
      unverified|not_met) set_cap 3 ;;
      needs_human_decision) set_cap 2 ;;
      unknown|*) set_cap 4 ;;
    esac
  done < <(items_of acceptance "$f")

  while IFS='=' read -r x v; do
    local status="${v%%/*}" sev="${v##*/}"
    case "$status" in
      resolved) : ;;
      open)
        case "$sev" in
          blocking|unknown) set_cap 3 ;;
          non-blocking) set_cap 1 ;;
          *) set_cap 4 ;;
        esac
        ;;
      unknown|*) set_cap 4 ;;
    esac
  done < <(items_of findings "$f")

  while IFS='=' read -r k v; do
    case "$v" in
      resolved_by_authority) : ;;
      unresolved|*) set_cap 4 ;;
    esac
  done < <(items_of conflicts "$f")

  local doc_state="$(value_of doc_state "$f")"
  [ "$doc_state" = "out_of_sync" ] && set_cap 1

  case "$cap" in
    4) echo "blocked" ;;
    3) echo "not_ready" ;;
    2) echo "needs_human_decision" ;;
    1) echo "ready_with_notes" ;;
    *) echo "ready" ;;
  esac
}

derive_decision() {
  local f="$1"
  local readiness="$(derive_readiness "$f")"
  local implementation="$(value_of implementation "$f")"
  local review="$(value_of review "$f")"
  local doc_state="$(value_of doc_state "$f")"
  local human_acceptance="$(value_of human_acceptance "$f")"
  local next_unit="$(value_of next_unit "$f")"

  local has_unresolved=0
  while IFS='=' read -r k v; do
    case "$v" in unresolved|*) has_unresolved=1; break ;; esac
  done < <(items_of conflicts "$f")
  [ "$has_unresolved" -eq 1 ] && { echo "REQUEST_HUMAN_DECISION"; return; }

  case "$review" in
    blocked*) { echo "REQUEST_HUMAN_DECISION"; return; } ;;
  esac

  case "$implementation" in
    incomplete|none) { echo "REQUEST_HUMAN_DECISION"; return; } ;;
  esac

  [ "$readiness" = "blocked" ] && { echo "VERIFY_FURTHER"; return; }

  local item k v
  while IFS='=' read -r k v; do
    [ "$v" = "failed(unexplained)" ] && { echo "INVESTIGATE_FAILURE"; return; }
  done < <(items_of validation "$f")
  while IFS='=' read -r k v; do
    [ "$v" = "failed(unexplained)" ] && { echo "INVESTIGATE_FAILURE"; return; }
  done < <(items_of environments "$f")

  case "$review" in
    CHANGES_REQUIRED*) { echo "REMEDIATE_FINDINGS"; return; } ;;
  esac

  while IFS='=' read -r k v; do
    case "$v" in met|*) : ;; esac
  done < <(items_of acceptance "$f")
  while IFS='=' read -r k v; do
    [ "$v" = "not_met" ] && { echo "REMEDIATE_FINDINGS"; return; }
  done < <(items_of acceptance "$f")

  local has_open_blocking=0
  while IFS='=' read -r x v; do
    local status="${v%%/*}" sev="${v##*/}"
    [ "$status" = "open" ] && { case "$sev" in blocking|unknown) has_open_blocking=1 ;; esac; }
  done < <(items_of findings "$f")
  [ "$has_open_blocking" -eq 1 ] && { echo "REMEDIATE_FINDINGS"; return; }

  while IFS='=' read -r k v; do
    case "$v" in failed\(identified:*\)) { echo "REMEDIATE_FINDINGS"; return; } ;; esac
  done < <(items_of validation "$f")
  while IFS='=' read -r k v; do
    case "$v" in failed\(identified:*\)) { echo "REMEDIATE_FINDINGS"; return; } ;; esac
  done < <(items_of environments "$f")

  while IFS='=' read -r k v; do
    case "$v" in partial|not_run) { echo "VERIFY_FURTHER"; return; } ;; esac
  done < <(items_of validation "$f")
  while IFS='=' read -r k v; do
    [ "$v" = "pending" ] && { echo "VERIFY_FURTHER"; return; }
  done < <(items_of environments "$f")
  while IFS='=' read -r k v; do
    [ "$v" = "unverified" ] && { echo "VERIFY_FURTHER"; return; }
  done < <(items_of acceptance "$f")

  while IFS='=' read -r k v; do
    [ "$v" = "needs_human_decision" ] && { echo "REQUEST_HUMAN_DECISION"; return; }
  done < <(items_of acceptance "$f")

  [ "$doc_state" = "out_of_sync" ] && { echo "RECONCILE_DOCS"; return; }

  case "$readiness" in
    ready|ready_with_notes)
      if [ "$human_acceptance" = "not_recorded" ]; then
        echo "ACCEPT_UNIT"; return
      elif [ "$human_acceptance" = "recorded" ] && [ "$next_unit" = "available" ]; then
        echo "PREPARE_NEXT_UNIT"; return
      else
        echo "REQUEST_HUMAN_DECISION"; return
      fi
      ;;
  esac

  echo "REQUEST_HUMAN_DECISION"
}

valid_validation_status() {
  case "$1" in
    passed|failed\(unexplained\)|failed\(identified:application\)|failed\(identified:test-fixture\)|failed\(identified:infrastructure\)|failed\(identified:environment\)|failed\(identified:other\)|partial|not_run|unknown) return 0 ;;
    *) return 1 ;;
  esac
}

valid_environment_status() {
  case "$1" in
    verified|pending|failed\(unexplained\)|failed\(identified:application\)|failed\(identified:test-fixture\)|failed\(identified:infrastructure\)|failed\(identified:environment\)|failed\(identified:other\)|not_applicable|unknown) return 0 ;;
    *) return 1 ;;
  esac
}

for f in "$FIXDIR"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  # required keys
  for k in "${required_keys[@]}"; do
    if ! grep -qE "^$k:" "$f"; then bad "$name missing key $k"; else ok "$name has key $k"; fi
  done
  # basis label
  if grep -qE '^basis: assumption-based fixture \(not a historical record\)' "$f"; then ok "$name basis label"; else bad "$name basis label"; fi
  # readiness domain
  r=$(value_of expected_readiness "$f")
  found=0; for v in "${valid_readiness[@]}"; do [ "$v" = "$r" ] && { found=1; break; }; done
  [ "$found" -eq 1 ] && ok "$name readiness domain" || bad "$name readiness domain '$r'"
  # decision domain
  d=$(value_of expected_decision "$f")
  found=0; for v in "${valid_decisions[@]}"; do [ "$v" = "$d" ] && { found=1; break; }; done
  [ "$found" -eq 1 ] && ok "$name decision domain" || bad "$name decision domain '$d'"
  # must_not_decide does not contain expected_decision
  mn=$(value_of must_not_decide "$f")
  case ",${mn// /}," in *",$d,"*) bad "$name expected_decision in must_not_decide" ;; *) ok "$name expected_decision not in must_not_decide" ;; esac
  # ACCEPT_UNIT only with ready/ready_with_notes
  if [ "$d" = "ACCEPT_UNIT" ]; then
    if [ "$r" = "ready" ] || [ "$r" = "ready_with_notes" ]; then ok "$name ACCEPT_UNIT with readiness $r"; else bad "$name ACCEPT_UNIT with readiness $r"; fi
  fi
  # CHANGES_REQUIRED/stale/blocked review never yields ACCEPT_UNIT
  rev=$(value_of review "$f")
  if [ "$d" = "ACCEPT_UNIT" ]; then
    case "$rev" in
      CHANGES_REQUIRED*|stale|blocked*) bad "$name ACCEPT_UNIT with bad review '$rev'" ;;
      *) ok "$name ACCEPT_UNIT review ok" ;;
    esac
  fi
  # review value basic sanity
  case "$rev" in
    PASS@*|PASS_WITH_NOTES@*|CHANGES_REQUIRED@*|not_required@*|pending@*|stale|blocked\(*\)@*|unknown) ok "$name review format" ;;
    *) bad "$name review format '$rev'" ;;
  esac
  # implementation domain
  impl=$(value_of implementation "$f")
  case "$impl" in complete|incomplete|none|unknown) ok "$name implementation domain" ;; *) bad "$name implementation domain '$impl'" ;; esac
  # doc_state domain
  ds=$(value_of doc_state "$f")
  case "$ds" in in_sync|out_of_sync|unknown) ok "$name doc_state domain" ;; *) bad "$name doc_state domain '$ds'" ;; esac
  # human_acceptance domain
  ha=$(value_of human_acceptance "$f")
  case "$ha" in recorded|not_recorded) ok "$name human_acceptance domain" ;; *) bad "$name human_acceptance domain '$ha'" ;; esac
  # next_unit domain
  nu=$(value_of next_unit "$f")
  case "$nu" in available|none|unknown) ok "$name next_unit domain" ;; *) bad "$name next_unit domain '$nu'" ;; esac

  # validation domain
  bad_val=0
  while IFS='=' read -r k v; do
    valid_validation_status "$v" || { bad_val=1; break; }
  done < <(items_of validation "$f")
  [ "$bad_val" -eq 0 ] && ok "$name validation domain" || bad "$name validation domain"

  # environment domain
  bad_env=0
  while IFS='=' read -r k v; do
    valid_environment_status "$v" || { bad_env=1; break; }
  done < <(items_of environments "$f")
  [ "$bad_env" -eq 0 ] && ok "$name environment domain" || bad "$name environment domain"

  # acceptance domain
  bad_ac=0
  while IFS='=' read -r k v; do
    case "$v" in met|unverified|not_met|needs_human_decision|unknown) : ;; *) bad_ac=1; break ;; esac
  done < <(items_of acceptance "$f")
  [ "$bad_ac" -eq 0 ] && ok "$name acceptance domain" || bad "$name acceptance domain"

  # findings domain
  bad_fi=0
  while IFS='=' read -r x v; do
    _status="${v%%/*}" _sev="${v##*/}"
    case "$_status" in open|resolved|unknown) : ;; *) bad_fi=1; break ;; esac
    case "$_sev" in blocking|non-blocking|unknown) : ;; *) bad_fi=1; break ;; esac
  done < <(items_of findings "$f")
  [ "$bad_fi" -eq 0 ] && ok "$name findings domain" || bad "$name findings domain"

  # conflicts domain
  bad_co=0
  while IFS='=' read -r k v; do
    case "$v" in resolved_by_authority|unresolved) : ;; *) bad_co=1; break ;; esac
  done < <(items_of conflicts "$f")
  [ "$bad_co" -eq 0 ] && ok "$name conflicts domain" || bad "$name conflicts domain"

  # derived readiness matches expected
  derived_r=$(derive_readiness "$f")
  if [ "$derived_r" = "$r" ]; then ok "$name derived readiness $derived_r"; else bad "$name derived readiness $derived_r (expected $r)"; fi

  # derived decision matches expected
  derived_d=$(derive_decision "$f")
  if [ "$derived_d" = "$d" ]; then ok "$name derived decision $derived_d"; else bad "$name derived decision $derived_d (expected $d)"; fi
done

echo
echo "Summary: $pass passed, $failn failed"
[ "$failn" -eq 0 ]
