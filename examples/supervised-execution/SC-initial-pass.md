scenario: SC-initial-pass
basis: assumption-based fixture (not a historical record)
initial_verdict: PASS
findings: none
remediation_attempts: 0
final_verdict: PASS
expected_outcome: stop normally
unresolved_findings: none
next_action: ACCEPT_UNIT or prepare next unit per Phase A
invariants:
  - no remediation is delegated
  - validation evidence is reused when scope unchanged
  - final commit is the implementation commit
