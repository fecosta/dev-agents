fixture: S13-review-current-pass
basis: regression fixture (not a historical record)
scenario: Verdict reviewed_commit matches assessed_commit; current PASS yields ACCEPT_UNIT
assessed_commit: C1
implementation: complete
review: PASS@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=met
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: none
expected_readiness: ready
expected_decision: ACCEPT_UNIT
rules: 3.3 no cap; 6.2 rule 10
must_not_decide: REMEDIATE_FINDINGS, VERIFY_FURTHER

Illustrative evidence: the review report names the same commit that is being assessed.
