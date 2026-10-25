fixture: S6-new-vs-resolved-findings
basis: assumption-based fixture (not a historical record)
scenario: Cycle 2 review confirms cycle-1 findings resolved and raises new findings
assessed_commit: C2
implementation: complete
review: CHANGES_REQUIRED@C2
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=met; AC-2=not_met
findings: R1-1=resolved/blocking; R1-2=resolved/blocking; R2-1=open/blocking; R2-2=open/non-blocking
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: not_ready
expected_decision: REMEDIATE_FINDINGS
rules: 3.3 I3 CHANGES_REQUIRED, I9 not_met, I10 open/blocking -> not_ready; 6.2 rule 6 (scope R2-1, R2-2; R1-* stay resolved)
must_not_decide: ACCEPT_UNIT
