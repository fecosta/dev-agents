# review-change

1. Start a fresh review session.
2. Read project-local instructions and the authoritative SPEC/task.
3. Inspect the reviewed commit/diff independently.
4. Inspect validation evidence.
5. Select opposite-family review:
   - Claude -> `review-openai`
   - non-Claude -> `review-claude`
6. Review correctness, regressions, acceptance criteria, tests, security/data boundaries, and hidden coupling.
7. Do not edit implementation files in the review pass.
