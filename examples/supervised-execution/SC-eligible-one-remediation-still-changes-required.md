scenario: SC-eligible-one-remediation-still-changes-required
basis: assumption-based fixture (not a historical record)
initial_verdict: CHANGES_REQUIRED
findings:
  - id: R1-1
    severity: blocking
    eligibility: eligible
    description: missing input validation
remediation_attempts: 1
final_verdict: CHANGES_REQUIRED
new_findings:
  - id: R2-1
    severity: blocking
    description: validation rejects valid input
expected_outcome: stop; no second remediation
unresolved_findings: R1-1 VERIFIED, R2-1 OPEN
ledger:
  - R1-1: VERIFIED
  - R2-1: OPEN
next_action: new user-initiated bounded unit
invariants:
  - remediation attempt count never exceeds one
  - second CHANGES_REQUIRED stops automatic execution
  - original finding confirmed resolved becomes VERIFIED, not CLOSED
