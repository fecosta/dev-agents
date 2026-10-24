fixture: S11-docs-out-of-sync
basis: assumption-based fixture (not a historical record)
scenario: Unit fully verified, but the SPEC status still reads Draft
assessed_commit: C1
implementation: complete
review: PASS@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=met
findings: none
conflicts: none
doc_state: out_of_sync
human_acceptance: not_recorded
next_unit: none
expected_readiness: ready_with_notes
expected_decision: RECONCILE_DOCS
rules: 3.3 I12 out_of_sync -> ready_with_notes; 6.2 rule 9
must_not_decide: ACCEPT_UNIT
