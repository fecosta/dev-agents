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
12. Completion verification (mandatory for every delegated implementation, including docs-only and economy): after the end checkpoint and before the review decision, read-only (no edits, commits, or fixes; not independent review, it neither replaces nor triggers nor skips the review decision), do not rely on the handoff alone:
    - a. inspect the actual changed artifacts: `git show --stat <sha>`, `git show`/`git diff` of the commit, native reads of the changed files;
    - b. verify against the delegated scope and acceptance criteria (no out-of-scope files, every criterion addressed);
    - c. verify the reported validation evidence (re-run cheap read-only validation when feasible, otherwise mark it unverified; never accept "tests passed" without evidence);
    - d. verify the commit SHA exists, its contents match the reported files, `git status` is clean or unrelated changes are preserved, configured author, no AI co-author trailer, Conventional Commit message, nothing pushed or merged;
    - e. report every unverified requirement.
    Result is exactly one of: VERIFIED (a-d verified, nothing unverified); PARTIALLY_VERIFIED (required evidence missing or unverifiable, never VERIFIED; report "implementation is NOT verified complete" with the Unverified requirements, never say complete or successful, continue to the review decision if applicable); FAILED (scope/acceptance mismatch, commit/diff contradicts the handoff, validation failing, or unexpected Git state; report and stop before the review decision and resolution, no reviewer, no remediation, no re-delegation; report Review required, Review decision reason, Model resolution, Actual models and providers, Actual family, Reviewer, and Verdict as NOT_REACHED without evaluating review need). Keep end_id captured regardless; Start/End checkpoint stay reported.
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
18. Report: task/SPEC; selected capability tier; delegated agent; implementation result; validation result; implementation commit SHA; Orchestrator verification (VERIFIED | PARTIALLY_VERIFIED | FAILED); Unverified requirements (list or none); Review required (yes/no); Review decision reason; Review/runtime setup (if blocked); Start checkpoint; End checkpoint; Model resolution (resolved|blocked|skipped); Model resolution reason (if blocked); Actual models and providers (if returned); Actual family (if resolved); Reviewer (if resolved and review required); Verdict (if review ran) or the block status; Remediation attempt count (0 or 1); Remediation start/end checkpoints; Remediation model family; Re-reviewer; Re-review verdict; Findings resolved; Findings unresolved; Required human decision; Recommended next action; findings; unresolved risks. When verification is FAILED, the review and remediation fields are NOT_REACHED.
19. If the initial verdict is `PASS` or `PASS_WITH_NOTES`, stop normally. If the initial verdict is `CHANGES_REQUIRED`, evaluate automatic remediation:
    - A single `/implement-spec` invocation authorizes at most one automatic remediation cycle.
    - Evaluate every finding against the eligibility criteria in `templates/review-report.md` and the active SPEC. A finding is eligible only when it is clearly within the bounded unit's scope and existing acceptance criteria, maps to a concrete objective change in source/test/docs, requires no new product/architecture/policy decision, is not a security-sensitive change requiring explicit human approval, does not expand scope or add dependencies, and has an identified cause or is a routine mechanical correction (typo, lint error, missing assertion, simple refactor).
    - Treat missing, ambiguous, or uncertain eligibility as ineligible. Security findings, scope expansion, material architecture decisions, and ambiguous requirements stop for human decision.
    - If any finding is ineligible, stop and request human intervention; do not partially remediate a mixed eligible/ineligible set.
    - If all findings are eligible, delegate exactly one remediation cycle:
      1. Increment the remediation attempt counter; never exceed one per invocation and do not reset it through delegation, retry, or re-review.
      2. Capture a fresh start checkpoint immediately before delegating to the remediation agent (`review-route.sh checkpoint start`); record rem_start_id. A failure here stops blocked.
      3. Delegate remediation to the minimum safe capability tier implementation agent (control-plane changes minimum `standard`). Pass the original bounded scope, acceptance criteria, and eligible findings. Require the remediation agent to re-evaluate the eligibility of each finding before editing; if it judges any finding ineligible, it must stop, report the finding IDs and reasons, and make no changes.
      4. Require validation before commit; commit only after validation passes; use the configured local Git author only; add no AI co-author metadata; never push, merge, deploy, force-push, rewrite shared history, or bypass protections. Return a structured handoff with the remediation commit SHA and validation evidence.
      5. Capture a fresh end checkpoint immediately after the remediation agent returns (`review-route.sh checkpoint end`); record rem_end_id. If it fails, stop blocked.
      6. Run completion verification on the final remediation commit (actual diff, commit SHA, validation evidence, Git state) before any re-review. If FAILED, stop blocked; no re-review is launched.
      7. Resolve the remediation model family from fresh checkpoints only: run, after the helper-resolution block, `"$RR" resolve <rem_start_id> <rem_end_id> <remediation-capability-alias>`. If resolution is blocked, report `REVIEW_BLOCKED_MODEL_RESOLUTION` with the documented reason and stop; do not fall back to the initial implementation family or any assumption.
      8. Launch the resolved opposite-family reviewer in a fresh child session against the final commit (initial implementation + remediation), the original findings, and possible regressions. The re-review must return exactly one verdict.
      9. If the re-review returns `PASS` or `PASS_WITH_NOTES`, stop normally.
      10. If the re-review returns `CHANGES_REQUIRED`, stop; do not start a second remediation cycle. Report unresolved findings and recommend a new explicitly user-initiated bounded unit.
    - If the remediation agent returns without a validated commit, or completion verification fails, stop blocked and request human intervention; no re-review is launched.
20. Do not automatically fix or re-review beyond the one eligible remediation cycle. Never push, merge, or deploy.
21. On every terminal path (review not required, REVIEW_BLOCKED_MODEL_RESOLUTION, any verdict including PASS, and any re-review verdict), use "complete" or "successful" only when Orchestrator verification is VERIFIED. A PASS verdict or "review not required" never upgrades PARTIALLY_VERIFIED; a review verdict never upgrades verification status. Checkpoint failures stop blocked and are never complete.
