---
description: Route and delegate one bounded implementation unit, then perform independent review when required.
agent: orchestrator
subagent: false
---

Work on SPEC/task: $ARGUMENTS

Execute the v3b.2 implementation, runtime model resolution, and conditional review workflow:

1. Read project-local AGENTS.md and relevant repository instructions.
2. Locate and read the authoritative SPEC/task and relevant architecture/security/data/ADR context.
3. Inspect branch and working-tree state and preserve unrelated user changes.
4. Determine whether this fits one bounded, independently verifiable unit.
5. Stop and ask about material product ambiguity. Do not invent behavior.
6. If oversized, return an ordered phase split and stop unless the user explicitly requested execution of the first phase.
7. Classify the current bounded unit as economy, standard, strong, or premium. Keep that alias as `<combo-name>` for model resolution.
8. START CHECKPOINT (mandatory for every run): immediately before delegating, run `review-route.sh checkpoint start` (read-only `SELECT COALESCE(MAX(id),0) FROM usageHistory` on `${NINEROUTER_DB:-$HOME/.9router/db/data.sqlite}`). `review-route.sh` is located exactly as in the helper-resolution block in the orchestrator agent instructions (installed path first, dev-agents checkout fallback, else `REVIEW_ROUTE_HELPER_UNAVAILABLE`); this command defines no other lookup. Success is one integer `^[0-9]{1,15}$`; record it as start_id.
   - No valid start checkpoint => no delegation, with no exceptions (not docs-only, economy, low-risk, review-not-required, or non-control-plane work). On any failure launch none of economy/standard/strong/premium and report "Review/runtime setup: blocked", "Model resolution: blocked", "Model resolution reason: START_CHECKPOINT_FAILED" (or REVIEW_ROUTE_HELPER_UNAVAILABLE if the helper is missing), then stop.
9. Delegate implementation to that exact agent using the subagent tool.
10. Require the child agent to:
    - implement only the bounded unit;
    - follow project-local instructions and Git conventions;
    - preserve unrelated working-tree changes;
    - run required validation;
    - commit only after validation passes;
    - use the configured local Git author only;
    - add no AI co-author metadata;
    - never push, merge, deploy, force-push, rewrite shared history, or bypass protections;
    - return a structured implementation handoff with files changed, validation evidence, commit SHA, and unresolved risks.
    Do not ask the child to self-report its model family as authority, and the child must not guess it.
11. END CHECKPOINT (mandatory): immediately after the child returns (before the review decision or any other call), run `review-route.sh checkpoint end`; record end_id. If it fails for any reason, stop blocked regardless of the eventual review decision: report "Model resolution: blocked", "Model resolution reason: END_CHECKPOINT_FAILED", "Independent review: REVIEW_BLOCKED_MODEL_RESOLUTION", launch no reviewer. Never mark it unavailable or continue to normal completion.
12. Inspect the returned implementation handoff.
13. Decide whether independent review is required using policies/review-routing.md and the risk/complexity of the implemented change. Control-plane changes always require review.
14. If review is not required:
    - report "Independent review: not required";
    - report "Model resolution: skipped (independent review not required)" and do not claim a family;
    - include the Review decision reason;
    - summarize the implementation handoff;
    - stop.
15. If review is required, resolve the family from runtime evidence only:
    - run (after the helper-resolution block, same shell command) `NINEROUTER_DB="${NINEROUTER_DB:-$HOME/.9router/db/data.sqlite}" "$RR" resolve <start_id> <end_id> <selected-capability-alias>`;
    - it wraps `resolve-model-family.sh` and validates its key=value output; do not reimplement classification;
    - never infer the family from the capability tier, combo name or definition, fallback ordering, child alias, provider assumptions, or implementation content;
    - do not subtract or guess orchestrator usage rows from the window.
16. If resolution is not `model_resolution=resolved` (any helper-reported failure, non-zero exit, unparseable or schema-invalid output, family/reviewer mismatch; the helper only emits documented reasons, otherwise RESOLVER_OUTPUT_INVALID; also REVIEW_ROUTE_HELPER_UNAVAILABLE):
    - report `REVIEW_BLOCKED_MODEL_RESOLUTION` and a separate line "Model resolution reason: <REASON>";
    - include the Review decision reason;
    - explain that independent review is required but opposite-family routing cannot be selected safely;
    - launch neither reviewer and stop without guessing.
    Do not use `REVIEW_BLOCKED_MODEL_UNKNOWN` here; it is only a legacy status for when no runtime evidence mechanism exists.
17. If resolved:
    - family `claude` -> delegate to `review-openai`; family `non-claude` -> delegate to `review-claude`; use only the reviewer the helper returned;
    - use a fresh reviewer child session;
    - require read-only review against the authoritative SPEC/task, repository instructions, committed diff, validation evidence, acceptance criteria, regressions, and relevant security/data boundaries;
    - require exactly one verdict: PASS, PASS_WITH_NOTES, or CHANGES_REQUIRED.
18. Report: task/SPEC; selected capability tier; delegated agent; implementation result; validation result; implementation commit SHA; Review required (yes/no); Review decision reason; Review/runtime setup (if blocked); Start checkpoint; End checkpoint; Model resolution (resolved|blocked|skipped); Model resolution reason (if blocked); Actual models and providers (if returned); Actual family (if resolved); Reviewer (if resolved and review required); Verdict (if review ran) or the block status; findings; unresolved risks.
19. Do not automatically fix CHANGES_REQUIRED. Stop after the first review verdict. Never push, merge, or deploy.
