---
description: Route and delegate one bounded implementation unit, then perform independent review when required.
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
10. Inspect the returned implementation handoff.
11. Decide whether independent review is required using policies/review-routing.md and the risk/complexity of the implemented change.
12. If review is not required:
    - report "Independent review: not required";
    - summarize the implementation handoff;
    - stop.
13. If review is required:
    - determine the actual implementation model family only from reliable runtime metadata or the implementation handoff;
    - never infer it from the capability tier, 9Router combo name, or fallback ordering.
14. If the actual family is unknown:
    - report `REVIEW_BLOCKED_MODEL_UNKNOWN`;
    - explain that independent review is required but opposite-family routing cannot be selected safely;
    - stop without guessing.
15. If the actual family is known:
    - Claude -> delegate to `review-openai`;
    - non-Claude -> delegate to `review-claude`;
    - use a fresh reviewer child session;
    - require read-only review against the authoritative SPEC/task, repository instructions, committed diff, validation evidence, acceptance criteria, regressions, and relevant security/data boundaries;
    - require exactly one verdict: PASS, PASS_WITH_NOTES, or CHANGES_REQUIRED.
16. Report the reviewer, verdict, findings, and implementation commit.
17. Do not automatically fix CHANGES_REQUIRED in v3a. Stop after the first review verdict.