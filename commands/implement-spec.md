# implement-spec

1. Read project-local `AGENTS.md` and repository instructions.
2. Locate and read the authoritative active SPEC or bounded task.
3. Inspect relevant architecture, security, data, and ADR docs.
4. Inspect branch and working-tree state; preserve unrelated changes.
5. If too large for one bounded unit, use `split-spec`.
6. Route using `route-task`.
7. Use the matching primary OpenCode agent: `economy`, `standard`, `strong`, or `premium`.
8. Capture a start checkpoint immediately before delegating to the implementation agent; no valid start checkpoint => no delegation. Refer to the OpenCode integration command ([`integrations/opencode/commands/implement-spec.md`](../integrations/opencode/commands/implement-spec.md)) and orchestrator agent ([`integrations/opencode/agents/orchestrator.md`](../integrations/opencode/agents/orchestrator.md)) for checkpoint mechanics.
9. Implement only the current bounded unit.
10. Run project-required validation.
11. Commit only after validation passes.
12. Produce an implementation handoff.
13. Record the actual model/model family when observable.
14. Capture an end checkpoint immediately after the child returns, before completion verification and the review decision; failure => stop blocked. Refer to the OpenCode integration command and orchestrator agent for checkpoint mechanics.
15. Verify completion read-only (no edits, commits, or fixes) after the end checkpoint and before the review decision; this is not independent review. Inspect the actual diff, commit, and Git state, not only the handoff. Check the changes against scope and acceptance criteria; verify validation evidence (re-run cheap read-only validation when feasible, otherwise mark it unverified; never accept "tests passed" without evidence); verify the commit SHA, its contents, `git status`, and that nothing was pushed; report every unverified requirement. Report `VERIFIED`; `PARTIALLY_VERIFIED` (implementation is NOT verified complete; list unverified requirements; continue to the review decision); or `FAILED` (stop before the review decision: no reviewer or remediation; review fields `NOT_REACHED`). Only `VERIFIED` may be called complete or successful on any terminal path, including review not required, review blocked, and a `PASS` verdict; a review verdict never upgrades verification status.
16. If review is required, start a fresh opposite-family review.
17. If `CHANGES_REQUIRED`, route fixes, validate, commit, and re-review.
18. Do not push, merge, deploy, or publish unless explicitly requested.
