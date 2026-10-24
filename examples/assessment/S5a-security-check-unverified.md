fixture: S5a-security-check-unverified
basis: assumption-based fixture (not a historical record)
scenario: Authentication works; the objective exposure check (no secret or service-role key reaches the client) has not been performed
assessed_commit: C1
implementation: complete
review: PASS@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-auth-functional=met; AC-sec-no-client-secrets=unverified
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: not_ready
expected_decision: VERIFY_FURTHER
rules: 3.3 I9 unverified -> not_ready; 6.2 rule 7
must_not_decide: ACCEPT_UNIT, REQUEST_HUMAN_DECISION
