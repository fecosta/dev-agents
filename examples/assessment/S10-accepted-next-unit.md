fixture: S10-accepted-next-unit
basis: assumption-based fixture (not a historical record)
scenario: Unit passed with notes and the user has accepted it; the approved split has a next unit
assessed_commit: C1
implementation: complete
review: PASS_WITH_NOTES@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=met
findings: R1-1=open/non-blocking
conflicts: none
doc_state: in_sync
human_acceptance: recorded
next_unit: available
expected_readiness: ready_with_notes
expected_decision: PREPARE_NEXT_UNIT
rules: 3.3 I3 PASS_WITH_NOTES, I10 open/non-blocking -> ready_with_notes; 6.2 rule 10
must_not_decide: ACCEPT_UNIT
