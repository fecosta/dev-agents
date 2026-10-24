fixture: S5b-security-acceptance-pending
basis: assumption-based fixture (not a historical record)
scenario: Authentication works and the exposure check passed; residual-risk acceptance requires the security owner's sign-off
assessed_commit: C1
implementation: complete
review: PASS@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-auth-functional=met; AC-sec-no-client-secrets=met; AC-sec-risk-signoff=needs_human_decision
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: needs_human_decision
expected_decision: REQUEST_HUMAN_DECISION
rules: 3.3 I9 needs_human_decision; 6.2 rule 8 (authority: security owner)
must_not_decide: ACCEPT_UNIT, VERIFY_FURTHER
