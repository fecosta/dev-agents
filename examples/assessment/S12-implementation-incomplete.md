fixture: S12-implementation-incomplete
basis: assumption-based fixture (not a historical record)
scenario: The implementation child stopped before finishing the unit; partial changes are committed
assessed_commit: C1
implementation: incomplete
review: pending@none
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=unverified
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: blocked
expected_decision: REQUEST_HUMAN_DECISION
rules: 3.3 I3 pending (kept without a reviewed commit, 5.3) -> blocked, I2 incomplete, I9 unverified -> not_ready; 6.2 rule 3
must_not_decide: ACCEPT_UNIT, VERIFY_FURTHER
