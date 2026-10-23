# Global AI Development Orchestration Contract

## Authority order
1. Active implementation SPEC or equivalent product contract.
2. Project-local `AGENTS.md` and repository instructions.
3. Repository architecture, security, data, and ADR documentation.
4. Task prompt.
5. This reusable orchestration contract.

## Core workflow
1. Read project-local instructions.
2. Identify the authoritative active SPEC or bounded task.
3. Inspect the relevant repository surface.
4. Split oversized work into independently verifiable phases.
5. Classify the current unit as `economy`, `standard`, `strong`, or `premium`.
6. Implement only the bounded unit.
7. Run required validation and tests.
8. Commit only after validation passes.
9. Produce an implementation handoff.
10. Verify completion read-only against the actual diff, commit, and Git state before the review decision (`VERIFIED`, `PARTIALLY_VERIFIED`, or `FAILED`); never report complete unless `VERIFIED` (`FAILED` stops before the review decision; review fields `NOT_REACHED`).
11. Choose a fresh opposite-family reviewer based on the actual implementation model family.
12. If review returns `CHANGES_REQUIRED`, attempt at most one bounded automatic remediation cycle: verify every finding is eligible, delegate the remediation to the minimum safe tier, capture fresh start/end checkpoints, validate before commit, and run a fresh opposite-family re-review. If any finding is ineligible, stop and request human intervention. After one remediation attempt, any remaining `CHANGES_REQUIRED` stops and requires a new explicitly user-initiated bounded unit.
13. Stop at the agreed phase or SPEC boundary.

## Git rules
Follow `policies/git-safety.md`.
Project-local Git conventions take precedence when explicitly defined.

## Control-plane changes
Files that define agent behavior, routing, review, permissions, Git safety, or orchestration are executable governance, not ordinary documentation.
Such changes:
- have a minimum capability tier of `standard`;
- require independent review before closure.