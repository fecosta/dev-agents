fixture: S14-review-stale-mismatch
basis: regression fixture (not a historical record)
scenario: Verdict reviewed_commit is a different known commit; freshness is stale, not unknown
assessed_commit: C1
implementation: complete
review: PASS@C2
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
rules: 3.3 I3 stale -> blocked; 6.2 rule 4
must_not_decide: ACCEPT_UNIT, REQUEST_HUMAN_DECISION

Illustrative evidence: the review report names C2, but the unit is being assessed at C1.
