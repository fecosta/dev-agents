fixture: S3-logout-user-facing-ac
basis: assumption-based fixture (not a historical record)
scenario: Logout works technically; review finds the user-facing acceptance criterion unmet
assessed_commit: C1
implementation: complete
review: CHANGES_REQUIRED@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-logout-session-cleared=met; AC-logout-user-feedback=not_met
findings: R1-1=open/blocking
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: not_ready
expected_decision: REMEDIATE_FINDINGS
rules: 3.3 I3 CHANGES_REQUIRED, I9 not_met, I10 open/blocking -> not_ready; 6.2 rule 6 (scope R1-1)
must_not_decide: ACCEPT_UNIT, VERIFY_FURTHER
