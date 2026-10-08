# Independent Review Routing

- Claude implementation -> `review-openai`
- Non-Claude implementation -> `review-claude`

Choose based on the actual model family that completed the implementation when observable.

Use a fresh review session and inspect the SPEC/task, repository instructions, diff, tests, validation evidence, security/data boundaries, acceptance criteria, regressions, and hidden coupling.

Verdicts:
- `PASS`
- `PASS_WITH_NOTES`
- `CHANGES_REQUIRED`
