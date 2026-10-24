scenario: SC-no-review-required
basis: assumption-based fixture (not a historical record)
change_type: docs-only
initial_verdict: not_required
remediation_attempts: 0
expected_outcome: stop normally; no remediation path evaluated
unresolved_findings: none
next_action: ACCEPT_UNIT
invariants:
  - independent review skipped when not required by policy
  - final report shows Independent review: not required
