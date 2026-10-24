---
description: Read-only post-implementation assessment and advisory Decision Helper recommendation. Executes nothing.
agent: orchestrator
subagent: false
---

Run `/assess` for: $ARGUMENTS

This command uses the existing orchestrator session to perform a read-only assessment only. It is the OpenCode adapter for the portable `commands/assess.md` procedure and the `policies/verification-assessment.md` contract.

1. Read project-local `AGENTS.md` and repository instructions.
2. Read the authoritative SPEC or bounded task and its acceptance criteria.
3. Read the implementation handoff, the orchestrator report, and any review report(s) for the unit.
4. Inspect Git state `[observed]` only:
   - `git branch --show-current`
   - `git rev-parse HEAD`
   - `git status --short`
   - `git log --oneline` for the unit range
   Do not run any Git write command.
5. Determine the assessed commit:
   - Use the commit named by the user, if any.
   - Otherwise use the unit's resulting commit `[observed]` (normally `HEAD`).
   - If neither can be determined, record `assessed_commit = unknown`.
6. Map evidence to the state contract in `policies/verification-assessment.md`:
   - Validation entries without a stated result or commit are `unknown`.
   - Failed checks without an identified cause are `failed(unexplained)`.
   - Copy the review verdict verbatim; apply freshness only to verdicts.
   - Keep `not_required`, `pending`, `blocked(...)`, and `unknown` review states as written.
7. Map findings with stable IDs (`R<cycle>-<n>` or `I-<n>`). Map ledger statuses to Phase A I10 without changing their meaning.
8. Derive readiness from the cap table. Readiness is the most severe cap present.
9. Apply the Decision Helper rules (first match wins) and recommend exactly one action from the closed action set.
10. Emit the fixed `Assessment` block, then the fixed `Decision Helper` block.

Output blocks:

```text
Assessment:
- Unit:
- Assessed commit:
- Evidence basis: <source — label>, ...
- Implementation:
- Validation:
- Review: <verbatim verdict | not_required | pending | stale | blocked (<status>, <reason>) | unknown> (cycle <n>, reviewed commit <sha>)
- Environments:
- Requirements completed:
- Requirements unverified:
- Blocking findings:
- Non-blocking findings:
- Failures and causes:
- Missing evidence:
- Conflicts:
- Human decisions required:
- Readiness: <value> — <one-line reason naming the governing cap(s)>
```

```text
Decision Helper (advisory only — nothing has been executed):
- Recommended action: <ACTION> — <one line>
- Rationale: <decision rule number and governing evidence>
- Supporting evidence: <item — label>, ...
- Unresolved risks:
- Prerequisites:
- Required authorization: <who must authorize what>
- Evidence limitations / confidence: high|medium|low — <why>
- Why not ACCEPT_UNIT: <only when another action is recommended>
```

Hard rules:

- Do not edit files, run validation or tests, re-run model resolution, delegate to any agent, run Git write commands, or contact deployed environments.
- Allowed shell use is read-only Git inspection only.
- The recommendation is advisory only. Do not execute, schedule, or retry it.
- Do not authorize another bounded unit, a second remediation cycle, push, merge, deployment, or history rewrite.
- Empty lists are written `none`, never omitted.
