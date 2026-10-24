scenario: SC-eligible-one-remediation-pass
basis: assumption-based fixture (not a historical record)
initial_verdict: CHANGES_REQUIRED
findings:
  - id: R1-1
    severity: blocking
    eligibility: eligible
    description: typo in error message
remediation_attempts: 1
final_verdict: PASS
expected_outcome: stop normally after re-review
unresolved_findings: none
ledger:
  - R1-1: CLOSED
next_action: ACCEPT_UNIT
invariants:
  - exactly one remediation attempt
  - fresh opposite-family re-review uses final commit
  - ledger shows OPEN -> REMEDIATED -> VERIFIED -> CLOSED
