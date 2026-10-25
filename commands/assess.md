# assess

Perform a read-only post-implementation assessment and emit an advisory Decision Helper recommendation. Execute nothing.

1. Read project-local `AGENTS.md` and repository instructions.
2. Read the authoritative active SPEC or bounded task and its acceptance criteria.
3. Read the implementation handoff, the orchestrator report, and any review report(s) for the unit.
4. Inspect Git state `[observed]`: current branch, `HEAD`, `git status --short`, and `git log` for the unit range. Do not run Git write commands.
5. Determine the assessed commit:
   - Use the commit the user named, if any.
   - Otherwise use the unit's resulting commit `[observed]` (normally `HEAD` of the unit branch).
   - If neither can be determined, record `assessed_commit = unknown`.
6. Map the handoff validation entries to the `verification-assessment` state contract (`policies/verification-assessment.md`):
   - A validation entry without a stated result or commit is `unknown`.
   - A failed check without an identified cause is `failed(unexplained)`.
7. Map the review state:
   - Copy the verdict verbatim (`PASS`, `PASS_WITH_NOTES`, `CHANGES_REQUIRED`).
   - Apply freshness only to verdicts: compare the reviewed commit to the assessed commit.
   - Keep non-verdict states (`not_required`, `pending`, `blocked(...)`, `unknown`) as written.
8. Map findings using stable IDs (`R<cycle>-<n>` or `I-<n>`). Map ledger statuses to Phase A I10 without changing their meaning.
9. Derive readiness from the cap table in `policies/verification-assessment.md`. Readiness is the most severe cap present.
10. Apply the Decision Helper rules from `policies/verification-assessment.md` (first match wins). Recommend exactly one action from the closed action set.
11. Emit the fixed `Assessment` block, then the fixed `Decision Helper` block.

Constraints:

- Do not edit files, run validation or tests, re-run model resolution, delegate to agents, run Git write commands, or contact deployed environments.
- Allowed shell use is read-only Git inspection only.
- The recommendation is advisory only. Do not execute or retry it.
- Do not authorize another bounded unit, a second remediation cycle, push, merge, deployment, or history rewrite.
- Empty lists are written `none`, never omitted.
