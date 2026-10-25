scenario: SC-model-resolution-blocked
basis: assumption-based fixture (not a historical record)
initial_verdict: CHANGES_REQUIRED
findings:
  - id: R1-1
    severity: blocking
    eligibility: eligible
remediation_attempts: 1
remediation_resolution: blocked(MODEL_DETECTION_AMBIGUOUS)
final_verdict: REVIEW_BLOCKED_MODEL_RESOLUTION
expected_outcome: stop blocked; no re-review
unresolved_findings: R1-1 REMEDIATED
next_action: REQUEST_HUMAN_DECISION
invariants:
  - remediation family resolved from fresh checkpoints only
  - blocked resolution reports REVIEW_BLOCKED_MODEL_RESOLUTION with reason
  - no fallback to initial implementation family
