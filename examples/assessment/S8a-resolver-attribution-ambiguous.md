fixture: S8a-resolver-attribution-ambiguous
basis: assumption-based fixture (not a historical record)
scenario: Review required; resolution blocked because both families appear in the window
assessed_commit: C1
implementation: complete
review: blocked(REVIEW_BLOCKED_MODEL_RESOLUTION,MODEL_DETECTION_AMBIGUOUS)@none
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=met
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: blocked
expected_decision: REQUEST_HUMAN_DECISION
rules: 3.3 I3 blocked (kept without a reviewed commit, 5.3) -> blocked; 6.2 rule 2
must_not_decide: ACCEPT_UNIT, VERIFY_FURTHER
