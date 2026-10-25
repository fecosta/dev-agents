scenario: SC-assess-advisory-only
basis: assumption-based fixture (not a historical record)
remediation_attempts: 0
assessment_input:
  review: CHANGES_REQUIRED@C1
  findings:
    - id: R1-1
      status: open
      severity: blocking
assess_output:
  recommended_action: REMEDIATE_FINDINGS
expected_outcome: recommendation is emitted but not executed
invariants:
  - /assess remains advisory only
  - /assess never triggers implementation or remediation
  - CHANGES_REQUIRED cannot produce ACCEPT_UNIT
  - a new /implement-spec is required to act on REMEDIATE_FINDINGS
