---
description: Route and automatically delegate one bounded implementation unit, then stop after the implementation handoff.
agent: orchestrator
subagent: false
---

Work on SPEC/task: $ARGUMENTS

Execute the v2 implementation workflow:

1. Read project-local AGENTS.md and relevant repository instructions.
2. Locate and read the authoritative SPEC/task and relevant architecture/security/data/ADR context.
3. Inspect branch and working-tree state and preserve unrelated user changes.
4. Determine whether this fits one bounded, independently verifiable unit.
5. Stop and ask about material product ambiguity. Do not invent behavior.
6. If oversized, return an ordered phase split and stop unless the user explicitly requested execution of the first phase.
7. Classify the current bounded unit as economy, standard, strong, or premium.
8. Delegate implementation to that exact agent using the subagent tool.
9. Require the child agent to:
   - implement only the bounded unit;
   - follow project-local instructions and Git conventions;
   - preserve unrelated working-tree changes;
   - run required validation;
   - commit only after validation passes;
   - use the configured local Git author only;
   - add no AI co-author metadata;
   - never push, merge, deploy, force-push, rewrite shared history, or bypass protections;
   - return a structured implementation handoff with files changed, validation evidence, commit SHA, unresolved risks, and actual model/model family if observable.
10. Inspect the returned handoff and summarize it.
11. Do not run independent review automatically in v2.
12. Stop after the implementation handoff.
