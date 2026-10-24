# Independent Review Routing

- Claude implementation -> `review-openai`
- Non-Claude implementation -> `review-claude`

Choose based on the actual model family that completed the implementation when observable.

Use a fresh review session and inspect the SPEC/task, repository instructions, diff, tests, validation evidence, security/data boundaries, acceptance criteria, regressions, and hidden coupling.

## Focused re-review after remediation

After a remediation commit, the reviewer must be the opposite family of the remediation agent, resolved from fresh runtime evidence. The re-review session is fresh and distinct from the initial review session.

The focused reviewer inspects:

- The authoritative SPEC/task and acceptance criteria.
- The final commit (initial implementation + remediation).
- Every original finding, referenced by its stable ledger ID.
- Whether the claimed remediation actually resolves each original finding.
- Regressions introduced by the remediation.
- New material issues affecting the bounded unit.
- Validation evidence for the remediation and any reused evidence.

The reviewer does not accept the remediation agent's claims without independent inspection. If an original finding was not re-examined, its unresolved state is preserved.

Verdicts:
- `PASS`
- `PASS_WITH_NOTES`
- `CHANGES_REQUIRED`
