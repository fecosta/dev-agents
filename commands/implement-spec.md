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
13. Verify completion read-only (no edits, commits, or fixes) after the end checkpoint and before the review decision; this is not independent review. Inspect the actual diff, commit, and Git state, not only the handoff. Check the changes against scope and acceptance criteria; verify validation evidence (re-run cheap read-only validation when feasible, otherwise mark it unverified; never accept "tests passed" without evidence); verify the commit SHA, its contents, `git status`, and that nothing was pushed; report every unverified requirement. Report `VERIFIED`; `PARTIALLY_VERIFIED` (implementation is NOT verified complete; list unverified requirements; continue to the review decision); or `FAILED` (stop before the review decision: no reviewer or remediation; review fields `NOT_REACHED`). Only `VERIFIED` may be called complete or successful on any terminal path, including review not required, review blocked, and a `PASS` verdict; a review verdict never upgrades verification status.
14. If review is required, start a fresh opposite-family review.
15. If `CHANGES_REQUIRED`, route fixes, validate, commit, and re-review.
16. Do not push, merge, deploy, or publish unless explicitly requested.
