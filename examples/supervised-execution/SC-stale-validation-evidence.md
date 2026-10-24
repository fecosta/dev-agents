scenario: SC-stale-validation-evidence
basis: assumption-based fixture (not a historical record)
initial_verdict: PASS
validation:
  - command: npm test
    scope: src/
    evidence_commit: C1
    result: passed
remediation:
  - changed_file: src/module.js
remediation_attempts: 1
final_verdict: PASS
expected_outcome: tests re-run for changed scope; C1 evidence not reused for that scope
unresolved_findings: none
next_action: ACCEPT_UNIT
invariants:
  - evidence commit must be ancestor of final commit
  - changed files inside declared scope invalidate evidence
  - targeted validation runs after remediation
  - unrelated evidence may be reused when conditions hold
