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
  r=$(sed -n 's/^expected_readiness: //p' "$f" | head -n 1)
  found=0; for v in "${valid_readiness[@]}"; do [ "$v" = "$r" ] && { found=1; break; }; done
  [ "$found" -eq 1 ] && ok "$name readiness domain" || bad "$name readiness domain '$r'"
  # decision domain
  d=$(sed -n 's/^expected_decision: //p' "$f" | head -n 1)
  found=0; for v in "${valid_decisions[@]}"; do [ "$v" = "$d" ] && { found=1; break; }; done
  [ "$found" -eq 1 ] && ok "$name decision domain" || bad "$name decision domain '$d'"
  # must_not_decide does not contain expected_decision
  mn=$(sed -n 's/^must_not_decide: //p' "$f" | head -n 1)
  case ",${mn// /}," in *",$d,"*) bad "$name expected_decision in must_not_decide" ;; *) ok "$name expected_decision not in must_not_decide" ;; esac
  # ACCEPT_UNIT only with ready/ready_with_notes
  if [ "$d" = "ACCEPT_UNIT" ]; then
    if [ "$r" = "ready" ] || [ "$r" = "ready_with_notes" ]; then ok "$name ACCEPT_UNIT with readiness $r"; else bad "$name ACCEPT_UNIT with readiness $r"; fi
  fi
  # CHANGES_REQUIRED/stale/blocked review never yields ACCEPT_UNIT
  rev=$(sed -n 's/^review: //p' "$f" | head -n 1)
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
  impl=$(sed -n 's/^implementation: //p' "$f" | head -n 1)
  case "$impl" in complete|incomplete|none|unknown) ok "$name implementation domain" ;; *) bad "$name implementation domain '$impl'" ;; esac
  # doc_state domain
  ds=$(sed -n 's/^doc_state: //p' "$f" | head -n 1)
  case "$ds" in in_sync|out_of_sync|unknown) ok "$name doc_state domain" ;; *) bad "$name doc_state domain '$ds'" ;; esac
  # human_acceptance domain
  ha=$(sed -n 's/^human_acceptance: //p' "$f" | head -n 1)
  case "$ha" in recorded|not_recorded) ok "$name human_acceptance domain" ;; *) bad "$name human_acceptance domain '$ha'" ;; esac
  # next_unit domain
  nu=$(sed -n 's/^next_unit: //p' "$f" | head -n 1)
  case "$nu" in available|none|unknown) ok "$name next_unit domain" ;; *) bad "$name next_unit domain '$nu'" ;; esac
done

echo
echo "Summary: $pass passed, $failn failed"
[ "$failn" -eq 0 ]
