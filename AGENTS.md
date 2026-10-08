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
10. Choose a fresh opposite-family reviewer based on the actual implementation model family.
11. Fix material findings, validate, commit, and re-review.
12. Stop at the agreed phase or SPEC boundary.

## Git rules
Follow `policies/git-safety.md`.
Project-local Git conventions take precedence when explicitly defined.
