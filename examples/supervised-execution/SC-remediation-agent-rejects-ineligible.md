scenario: SC-remediation-agent-rejects-ineligible
basis: assumption-based fixture (not a historical record)
initial_verdict: CHANGES_REQUIRED
findings:
  - id: R1-1
    severity: blocking
    eligibility: eligible (per reviewer)
    reevaluated: ineligible (per remediation agent)
remediation_attempts: 0
remediation_commit: none
final_verdict: CHANGES_REQUIRED
expected_outcome: remediation agent stops without changes; no commit; no re-review
unresolved_findings: R1-1 OPEN
next_action: REQUEST_HUMAN_DECISION
invariants:
  - remediation agent re-evaluates eligibility before editing
  - if any finding judged ineligible, stop without changes or commit
  - no re-review launched when remediation produces no commit
