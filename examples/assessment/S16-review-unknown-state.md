fixture: S16-review-unknown-state
basis: regression fixture (not a historical record)
scenario: Review state itself is unknown; freshness cannot be evaluated
assessed_commit: C1
implementation: complete
review: unknown
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=met
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: none
expected_readiness: blocked
expected_decision: VERIFY_FURTHER
rules: 3.3 I3 unknown -> blocked; 6.2 rule 4
must_not_decide: ACCEPT_UNIT, REQUEST_HUMAN_DECISION

Illustrative evidence: no review report is available for the unit.
