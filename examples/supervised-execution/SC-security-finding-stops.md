scenario: SC-security-finding-stops
basis: assumption-based fixture (not a historical record)
initial_verdict: CHANGES_REQUIRED
findings:
  - id: R1-1
    severity: blocking
    eligibility: ineligible
    description: residual risk in auth flow requires security owner approval
remediation_attempts: 0
final_verdict: CHANGES_REQUIRED
expected_outcome: stop; security finding not waived
unresolved_findings: R1-1 OPEN
next_action: escalate to security owner
invariants:
  - security findings requiring human approval stop
  - security findings are never silently waived
