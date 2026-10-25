scenario: SC-next-unit-not-authorized
basis: assumption-based fixture (not a historical record)
initial_verdict: PASS
findings: none
remediation_attempts: 0
final_verdict: PASS
approved_split_next_unit: available
expected_outcome: stop; recommend PREPARE_NEXT_UNIT but do not start it
unresolved_findings: none
next_action: PREPARE_NEXT_UNIT (requires new /implement-spec)
invariants:
  - final report recommends next action but does not implement it
  - a new unit requires new explicit user command
