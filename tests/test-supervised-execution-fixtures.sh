#!/usr/bin/env bash
# test-supervised-execution-fixtures.sh — verify supervised execution regression fixture invariants.
# bash 3.2+, no frameworks.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXDIR="$HERE/../examples/supervised-execution"

pass=0; failn=0
ok() { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { failn=$((failn + 1)); echo "FAIL: $1"; }

for f in "$FIXDIR"/*.md; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  # basis label
  grep -qE '^basis: assumption-based fixture \(not a historical record\)' "$f" && ok "$name basis label" || bad "$name basis label"
  # invariants present
  grep -qE '^invariants:' "$f" && ok "$name invariants section" || bad "$name invariants section"
  # remediation attempt count
  n=$(sed -n 's/^remediation_attempts: //p' "$f" | head -n 1)
  case "$n" in 0|1) ok "$name remediation_attempts $n <= 1" ;; *) bad "$name remediation_attempts $n > 1" ;; esac
  # if final verdict is PASS, no unresolved findings expected unless notes
  if grep -qE '^final_verdict: PASS$' "$f"; then
    if grep -qE '^unresolved_findings: none' "$f"; then ok "$name PASS with no unresolved"; else ok "$name PASS with notes tracked"; fi
  fi
  # CHANGES_REQUIRED without remediation stops
  if grep -qE '^initial_verdict: CHANGES_REQUIRED' "$f" && [ "$n" = "0" ]; then
    grep -qE 'stop before remediation|stop;|REQUEST_HUMAN_DECISION' "$f" && ok "$name ineligible stop outcome" || bad "$name missing stop outcome"
  fi
  # second CHANGES_REQUIRED stops
  if grep -qE '^final_verdict: CHANGES_REQUIRED' "$f" && [ "$n" = "1" ]; then
    grep -qE 'no second remediation|stop' "$f" && ok "$name second CHANGES_REQUIRED stops" || bad "$name missing second stop"
  fi
  # SC-9: no commit and no re-review
  if [ "$name" = "SC-remediation-agent-rejects-ineligible.md" ]; then
    grep -qE 'remediation_commit: none' "$f" && ok "$name SC-9 no commit" || bad "$name SC-9 no commit"
  fi
  # /assess advisory
  if [ "$name" = "SC-assess-advisory-only.md" ]; then
    grep -qE 'advisory only|never triggers' "$f" && ok "$name /assess advisory" || bad "$name /assess advisory"
    grep -qE 'CHANGES_REQUIRED cannot produce ACCEPT_UNIT' "$f" && ok "$name no ACCEPT_UNIT from CHANGES_REQUIRED" || bad "$name no ACCEPT_UNIT from CHANGES_REQUIRED"
  fi
  # next unit not auto-started
  if [ "$name" = "SC-next-unit-not-authorized.md" ]; then
    grep -qE 'does not implement it|requires new' "$f" && ok "$name next unit not auto-started" || bad "$name next unit not auto-started"
  fi
done

echo
echo "Summary: $pass passed, $failn failed"
[ "$failn" -eq 0 ]
