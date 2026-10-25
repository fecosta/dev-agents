fixture: S9-stale-review
basis: assumption-based fixture (not a historical record)
scenario: PASS was given for commit C1; a later fix commit C2 is being assessed
assessed_commit: C2
implementation: complete
review: PASS@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=met
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: blocked
expected_decision: VERIFY_FURTHER
rules: 3.3 I3 stale -> blocked; 6.2 rule 4 (re-review C2)
must_not_decide: ACCEPT_UNIT
