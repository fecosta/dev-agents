scenario: SC-ineligible-finding-stops
basis: assumption-based fixture (not a historical record)
initial_verdict: CHANGES_REQUIRED
findings:
  - id: R1-1
    severity: blocking
    eligibility: ineligible
    description: requires material architecture decision
remediation_attempts: 0
final_verdict: CHANGES_REQUIRED
expected_outcome: stop before remediation; request human decision
unresolved_findings: R1-1 OPEN
next_action: REQUEST_HUMAN_DECISION
invariants:
  - mixed eligible/ineligible findings stop without edits
  - scope expansion or architecture decisions stop
