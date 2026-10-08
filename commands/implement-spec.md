# implement-spec

1. Read project-local `AGENTS.md` and repository instructions.
2. Locate and read the authoritative active SPEC or bounded task.
3. Inspect relevant architecture, security, data, and ADR docs.
4. Inspect branch and working-tree state; preserve unrelated changes.
5. If too large for one bounded unit, use `split-spec`.
6. Route using `route-task`.
7. Use the matching primary OpenCode agent: `economy`, `standard`, `strong`, or `premium`.
8. Implement only the current bounded unit.
9. Run project-required validation.
10. Commit only after validation passes.
11. Produce an implementation handoff.
12. Record the actual model/model family when observable.
13. If review is required, start a fresh opposite-family review.
14. If `CHANGES_REQUIRED`, route fixes, validate, commit, and re-review.
15. Do not push, merge, deploy, or publish unless explicitly requested.
