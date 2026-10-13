---
description: Close the current coherent implementation unit and produce a concise handoff for a fresh session. Never starts the next phase, pushes, or merges.
subagent: false
---

Close out the current work and prepare a handoff for a fresh session. Extra context: $ARGUMENTS

1. Stop expanding scope. Make no new implementation changes; only run validation and, if allowed below, commit.
2. Identify the current task or active SPEC from the conversation and repository artifacts. If none can be identified, say so; do not invent one.
3. Read project-local `AGENTS.md` and the repository's Git conventions.
4. Run the validation that task or SPEC requires, where feasible. Never bypass or weaken it. Report only commands that actually ran and their real results; mark anything not run as "not run" with the reason.
5. Inspect `git branch --show-current`, `git rev-parse --short HEAD`, `git status --short`, and the final diff (`git diff`, `git diff --staged`, `git diff --check`). Classify changes as belonging to this unit or unrelated.
6. Commit only if ALL hold: the repository workflow permits committing; the unit is complete; required validation passed; there are changes for this unit. Otherwise do not commit; preserve the working tree as is and report the uncommitted changes.
   - Never create a commit solely to produce a handoff.
   - Stage only this unit's files by explicit path. Leave unrelated changes untouched and uncommitted.
   - Use Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`) and the configured Git author. Add no AI co-author trailers. Do not change Git identity.
7. Produce the handoff in exactly this structure:

Completed unit:
- ...

Validation:
- ...

Repository state:
- ...

Changed areas:
- ...

Unresolved:
- ...

Next fresh-session task:
- ...

Rules:
- If there is no completed unit, or the working tree holds unfinished changes, report the actual state under "Completed unit" (for example "none" or "incomplete") and list the uncommitted changes under "Repository state". Do not manufacture success.
- "Repository state" gives branch, HEAD SHA, whether a commit was made by this command, and working-tree status.
- A handoff is not independent review or approval. If review is required by repository policy, put "independent review in a fresh session" under "Next fresh-session task".
- Describe the next task only. Do not start it, and do not start any further implementation phase.
- Never push, merge, deploy, force-push, rewrite Git history (no amend, rebase, or reset), or discard unrelated changes.
- Never claim tests passed unless they ran in this session. Never print secrets.
