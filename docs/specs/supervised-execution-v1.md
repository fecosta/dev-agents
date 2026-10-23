# SPEC: Supervised Execution v1

- **Status:** Draft v1. Design only, not implemented.
- **Baseline:** `main` at `0b1ae1c` (includes merged PR #2 and the approved Phase A Decision Helper SPEC).
- **Tier for implementing units:** at least `standard` (control-plane change to orchestration behavior); independent opposite-family review required for every unit.
- **Authority:** subordinate to [`AGENTS.md`](../../AGENTS.md) and project-local instructions. Where this SPEC and an existing policy disagree, the existing policy wins until a unit of this SPEC changes it with review.

## 0. Purpose and non-goals

**Purpose.** Reduce the total time and human intervention required to complete one bounded development unit invoked through `/implement-spec`, while keeping meaningful decisions with the human.

A single `/implement-spec` authorization covers the complete execution cycle for one bounded unit: implementation, validation, independent review, and—when findings are eligible—one automatic remediation cycle with a focused re-review. The user receives a concise, decision-ready result.

**Non-goals.**

- Authorizing more than one bounded unit per invocation.
- Unlimited or opaque automatic remediation loops.
- Replacing runtime evidence with model aliases or assumptions.
- Automatic push, PR creation, merge, deployment, or history rewriting.
- Advancing to the next unit without explicit user authorization.
- New persistent services or databases.
- Making the Phase A Decision Helper non-advisory.

## 1. Current-state architecture assessment

| Area | What exists today | Source |
| --- | --- | --- |
| Authority and workflow | Bounded units; one `/implement-spec` per unit; core workflow ends at the phase/SPEC boundary | [`AGENTS.md`](../../AGENTS.md) |
| Portable implementation flow | "If `CHANGES_REQUIRED`, route fixes, validate, commit, and re-review" (open-ended loop) | [`commands/implement-spec.md`](../../commands/implement-spec.md) |
| OpenCode implementation flow | Start/end checkpoints; delegation; completion verification; review decision; runtime family resolution; "Do not automatically remediate `CHANGES_REQUIRED`. Stop after the first verdict." | [`integrations/opencode/commands/implement-spec.md`](../../integrations/opencode/commands/implement-spec.md), [`integrations/opencode/agents/orchestrator.md`](../../integrations/opencode/agents/orchestrator.md) |
| Routing | `economy` / `standard` / `strong` / `premium`; control-plane minimum `standard` | [`policies/model-routing.md`](../../policies/model-routing.md), [`commands/route-task.md`](../../commands/route-task.md) |
| Review routing | Opposite-family; `PASS` / `PASS_WITH_NOTES` / `CHANGES_REQUIRED` | [`policies/review-routing.md`](../../policies/review-routing.md), [`commands/review-change.md`](../../commands/review-change.md) |
| Runtime provenance | `review-route.sh` checkpoint/resolve; `resolve-model-family.sh` key=value contract with documented block reasons | [`integrations/opencode/README.md`](../../integrations/opencode/README.md), [`integrations/opencode/scripts/resolve-model-family.sh`](../../integrations/opencode/scripts/resolve-model-family.sh), [`integrations/opencode/scripts/review-route.sh`](../../integrations/opencode/scripts/review-route.sh) |
| Handoff / review report | Structured handoff with validation evidence; review report with blocking/non-blocking findings | [`templates/implementation-handoff.md`](../../templates/implementation-handoff.md), [`templates/review-report.md`](../../templates/review-report.md) |
| Phase A Decision Helper | Advisory-only next-action recommendation; `REMEDIATE_FINDINGS` action scoped to listed IDs/causes; no automatic execution | [`docs/specs/phase-a-assessment-decision-helper.md`](./phase-a-assessment-decision-helper.md) |

## 2. Gap analysis

| Need | Existing behavior | Gap | Supervised Execution v1 response |
| --- | --- | --- | --- |
| Bounded automatic remediation | Portable contract allows an open-ended remediation loop; OpenCode stops after first verdict | Inconsistent contracts; too much human coordination required for routine fixes | §3: one bounded remediation attempt, eligible-finding gate, hard stop after second `CHANGES_REQUIRED` |
| Finding identity across review cycles | Review reports carry free-text findings | Remediation and re-review lose or duplicate finding context | §5: lightweight finding ledger with stable IDs and `OPEN → REMEDIATED → VERIFIED → CLOSED` |
| Focused re-review | A fresh reviewer re-inspects everything | Re-review is slower than necessary and may not focus on what changed | §4: targeted scope (original findings + regressions), fresh runtime family resolution, fresh reviewer session |
| Validation efficiency | Validation is re-run on every cycle | Wasted work when inputs are unchanged | §6: reuse unchanged evidence; targeted validation for remediation; stale-evidence rejection |
| Decision-ready reporting | Orchestrator report is detailed but not oriented to the next human decision | User must synthesize status across multiple sections | §7: concise terminal report with verdict, resolved/unresolved findings, and recommended next action |
| Phase A compatibility | Phase A D7 approves stop-after-verdict semantics (U4 not yet landed) | Proposed one-remediation behavior conflicts with D7 as written | §9: amend D7 before U4 lands; preserve Decision Helper advisory-only next-unit behavior |

## 3. Bounded automatic remediation

### 3.1 Authorization scope

A single `/implement-spec` invocation authorizes exactly one bounded unit. The authorization extends to:

1. The initial implementation.
2. Required validation.
3. Completion verification.
4. One independent review when required.
5. **At most one** automatic remediation cycle if the initial review returns `CHANGES_REQUIRED` and all findings are eligible.
6. One focused re-review after remediation.

It does **not** authorize:
- a second remediation cycle;
- implementation of the next unit;
- any push, merge, deploy, or history rewrite.

### 3.2 Eligibility rules

A finding is eligible for automatic remediation only when **all** of the following hold:

- It is clearly within the authorized unit's scope and existing acceptance criteria.
- It maps to a concrete, objective change in source, test, or documentation files.
- It requires no new product decision, material architecture decision, or policy interpretation.
- It is not a security-sensitive change that requires explicit human approval.
- It does not expand scope, add new dependencies, or change external interfaces not already covered by the unit.
- The failure cause is identified (not `unexplained`) or the fix is unambiguously a routine mechanical correction (typo, lint error, missing assertion, simple refactor).

A finding is **ineligible** when any of the following hold:

- Ambiguous requirement or acceptance criterion.
- Material architecture or design decision required.
- Security-sensitive change requiring approval (security findings are never silently waived).
- Scope expansion or new unit of work.
- Unresolved blocker, missing dependency, or broken environment.
- Unexplained failure whose cause has not been identified.
- The reviewer explicitly marks it as not eligible for automatic remediation.

If **any** finding is ineligible, the orchestrator stops and requests human intervention; it does not remediate the eligible subset and defer the ineligible subset.

### 3.3 Remediation attempt limit

Default maximum: **one remediation attempt** per `/implement-spec` invocation.

Counter state is tracked in the orchestration session. The counter increments when a remediation child is delegated. If the re-review returns `CHANGES_REQUIRED`, the orchestrator stops; no second remediation attempt is started.

### 3.4 Remediation delegation

The remediation cycle follows the same safeguards as the initial implementation:

- Read project-local instructions and the authoritative SPEC/task.
- Capture a start checkpoint immediately before delegating to a remediation agent.
- Delegate to the minimum safe capability tier (may differ from the initial tier if the finding nature justifies it; control-plane minimum `standard`).
- Require the remediation agent to implement only the eligible findings within the bounded unit.
- Require validation before commit.
- Commit only after validation passes.
- Capture an end checkpoint immediately after the child returns.
- Run completion verification on the final commit before any re-review decision.

If the remediation agent returns without a validated commit, or completion verification fails, the orchestrator stops and reports the failure; no re-review is launched.

## 4. Focused independent re-review

### 4.1 Trigger

A focused re-review runs only after a successful remediation cycle:

- Remediation validation passed.
- Remediation changes are committed.
- Completion verification of the final commit passes (is not `FAILED`).

### 4.2 Fresh runtime family resolution

The re-review uses the remediation agent's actual runtime family, resolved from fresh start/end checkpoints:

- Capture `rem_start_id` immediately before delegating to the remediation agent.
- Capture `rem_end_id` immediately after the remediation agent returns.
- Run `review-route.sh resolve <rem_start_id> <rem_end_id> <remediation-capability-alias>`.
- If resolution is blocked, report `REVIEW_BLOCKED_MODEL_RESOLUTION` with the documented reason and stop; do not fall back to the initial implementation family or any assumption.

### 4.3 Reviewer selection

Use only the reviewer returned by the resolver:

- `family=claude` → `review-openai`.
- `family=non-claude` → `review-claude`.

Launch the reviewer in a **fresh child session** distinct from the initial review session.

### 4.4 Review scope

The focused reviewer inspects:

- The authoritative SPEC/task and acceptance criteria.
- The final commit (including both the initial implementation and the remediation).
- The original review findings, cross-referenced by ledger ID.
- Possible regressions introduced by the remediation.
- Validation evidence for the remediation and any reused evidence.

The reviewer returns exactly one verdict: `PASS`, `PASS_WITH_NOTES`, or `CHANGES_REQUIRED`.

### 4.5 Second `CHANGES_REQUIRED`

If the focused re-review returns `CHANGES_REQUIRED`, the orchestrator stops. It does not start a second automatic remediation loop. The final report lists the unresolved findings and recommends a new user-initiated unit.

## 5. Finding lifecycle

### 5.1 Ledger format

The finding ledger is a lightweight, session-local structure carried by the orchestrator across review cycles. It is emitted in the final report. No database or persistent service is required.

Each finding has:

- `id`: stable across cycles. Format `R<cycle>-<n>` for reviewer findings, `I-<n>` for implementer/assessor findings.
- `description`: one-line summary.
- `severity`: `blocking` or `non-blocking`.
- `status`: `OPEN`, `REMEDIATED`, `VERIFIED`, or `CLOSED`.
- `source`: review cycle and commit where it was raised.
- `remediation_commit`: SHA of the commit that addressed it (when applicable).

### 5.2 Lifecycle transitions

```
OPEN → REMEDIATED → VERIFIED → CLOSED
```

- `OPEN`: raised by the initial reviewer.
- `REMEDIATED`: the remediation agent produced a commit intended to address it.
- `VERIFIED`: the focused reviewer confirms the fix and finds no regression.
- `CLOSED`: the focused reviewer returns `PASS` or `PASS_WITH_NOTES`; all verified findings close.

A finding never returns to `OPEN` without concrete regression evidence in a later review. A finding that the focused reviewer does not re-check keeps status `OPEN` (or `REMEDIATED`, depending on its last known state) and is reported as unresolved.

### 5.3 Preservation across cycles

- Finding IDs are never reused.
- New findings raised in the focused review receive new IDs.
- The ledger is included in the final report so the user can trace each finding from initial raise through remediation to closure or remaining open.

## 6. Validation efficiency

### 6.1 Evidence reuse

Valid validation evidence may be reused when:

- The validation command is identical.
- The files and dependency graph it covers are unchanged at the final commit.
- The execution environment is unchanged (same tool versions, same environment variables that affect the command).
- The evidence is bound to a commit that is an ancestor of the final commit.

Evidence is **stale** and must not be reused when:

- The referenced commit is not the current assessed commit or an ancestor of it.
- Any file in the validation scope changed after the evidence was produced.
- The dependency graph of the validated surface changed.
- The validation command, tool version, or relevant environment changed.
- The original evidence was `partial`, `not_run`, `unknown`, or `failed`.

### 6.2 Targeted validation for remediation

After remediation, run only the validation commands whose scope intersects the remediated files or their direct dependency graph, plus any commands that previously failed.

Run broader validation when:

- The remediation touches shared/core files.
- The dependency graph changes.
- A project policy or acceptance criterion requires the full suite.
- The initial validation had unexplained failures.

### 6.3 Stale evidence handling

If the orchestrator cannot determine whether evidence is current, it treats the evidence as stale and re-runs the validation. Fail-closed: missing evidence is never accepted as proof of correctness.

## 7. Concise final reporting

On every terminal path, the orchestrator emits a compact decision-oriented report:

```text
Supervised Execution Report:
- Unit: <name>
- Final commit: <sha>
- Validation status: <passed|partial|failed|...> — <summary>
- Initial implementation model family: <family>
- Remediation model family: <family> | not_applicable
- Initial reviewer: <reviewer> — Verdict: <PASS|PASS_WITH_NOTES|CHANGES_REQUIRED|not_required|blocked(...)>
- Re-reviewer: <reviewer> | not_applicable — Verdict: <PASS|PASS_WITH_NOTES|CHANGES_REQUIRED|not_applicable>
- Orchestrator verification: <VERIFIED|PARTIALLY_VERIFIED|FAILED>
- Findings resolved: <id>, ... | none
- Findings unresolved: <id> — <status>, ... | none
- Required human decision: <what and why> | none
- Recommended next action: <action>
```

Empty lists are written `none`, never omitted.

The report avoids duplicating full implementation and review transcripts; it references them by commit and review cycle.

## 8. Mandatory safeguards

Supervised Execution v1 preserves all existing safeguards:

- **Bounded implementation units:** one unit per `/implement-spec`; no automatic continuation.
- **Capability/risk-based model routing:** minimum safe tier; control-plane changes at least `standard`.
- **Mandatory start/end checkpoints** for every delegated implementation or remediation.
- **Runtime model-family resolution:** from fresh checkpoints only; no aliases or assumptions.
- **Fresh opposite-family independent review** for the initial review and for the focused re-review.
- **Completion verification** before any review decision.
- **Git safety and configured authorship:** Conventional Commits, configured local author, no AI co-author metadata, no push/merge/deploy/rewrite.
- **Fail-closed behavior** when required evidence is missing: blocked model resolution, checkpoint failures, stale evidence, and unexplained failures all stop.
- **No automatic push, PR creation, merge, deployment, or history rewriting.**
- **No automatic advancement to the next unit.**

## 9. Phase A compatibility

### 9.1 Conflict

The approved Phase A Decision Helper SPEC records decision **D7** (approved, assigned to U4):

> The portable `/implement-spec` contract adopts stop-after-verdict semantics. `CHANGES_REQUIRED` must not trigger automatic remediation. Fixes and re-review run only as a new, explicitly user-initiated bounded unit, typically after a `REMEDIATE_FINDINGS` recommendation.

Supervised Execution v1 proposes the opposite behavior: one bounded automatic remediation attempt inside the same `/implement-spec` authorization. This conflicts with D7 as currently worded and with the portable contract in [`commands/implement-spec.md`](../../commands/implement-spec.md) and the core workflow in [`AGENTS.md`](../../AGENTS.md).

The OpenCode integration ([`integrations/opencode/commands/implement-spec.md`](../../integrations/opencode/commands/implement-spec.md) and [`integrations/opencode/agents/orchestrator.md`](../../integrations/opencode/agents/orchestrator.md)) already implements stop-after-verdict; it needs to be updated to permit the one remediation cycle.

### 9.2 Affected decisions and contracts

| Decision / contract | Current state | Required change |
| --- | --- | --- |
| Phase A D7 | Approved stop-after-verdict; U4 not yet landed | Amend D7 to allow one bounded automatic remediation attempt per `/implement-spec`; keep advisory-only next-unit behavior |
| Phase A §6.4 | Decision Helper output does not trigger portable remediation loop | Retain: `/assess` remains advisory; `/implement-spec` owns the one remediation attempt |
| [`commands/implement-spec.md`](../../commands/implement-spec.md) step 17 | "If `CHANGES_REQUIRED`, route fixes, validate, commit, and re-review" | Update to one-remediation semantics |
| [`AGENTS.md`](../../AGENTS.md) core workflow | "Fix material findings, validate, commit, and re-review" | Update to one-remediation semantics |
| OpenCode `/implement-spec` and orchestrator | "Do not automatically remediate `CHANGES_REQUIRED`. Stop after the first verdict." | Add the eligible-finding gate and one-remediation loop; stop after second `CHANGES_REQUIRED` |

### 9.3 Recommended resolution

Implement Supervised Execution v1 **before** Phase A U4 lands. Update D7 to:

> Within a single `/implement-spec` authorization, the orchestrator may perform at most one bounded automatic remediation cycle when the initial independent review returns `CHANGES_REQUIRED` and every finding is eligible. After one remediation attempt, any remaining `CHANGES_REQUIRED` verdict stops and requires a new explicitly user-initiated bounded unit. This does not authorize the next unit.

Phase A U4 then implements the amended D7 semantics across portable and OpenCode contracts instead of the original stop-after-verdict wording.

### 9.4 Distinguishing remediation from a new unit

- **Remediation:** stays within the authorized unit's scope and acceptance criteria; findings are eligible; no new product or architecture decisions; bounded by the one-attempt limit.
- **New unit:** requires fresh user authorization via a new `/implement-spec`; covers remaining findings, scope expansion, new acceptance criteria, architecture decisions, or any second remediation attempt.

### 9.5 Preserved Phase A behavior

- The Decision Helper remains **advisory-only** and executes nothing.
- `PREPARE_NEXT_UNIT` still requires recorded `[human]` acceptance of the current unit and never authorizes automatic implementation.
- `/assess` can still recommend `REMEDIATE_FINDINGS` for the *next* user-initiated unit; that recommendation is not executed automatically.

## 10. Implementation decomposition

Four independently verifiable units. Each unit is at least `standard` and requires independent opposite-family review.

| Unit | Delivers | Depends on | Validation |
| --- | --- | --- | --- |
| **U1** | Contract reconciliation: update [`commands/implement-spec.md`](../../commands/implement-spec.md) and [`AGENTS.md`](../../AGENTS.md) core workflow to one-remediation semantics; amend Phase A D7 wording; no runtime behavior change | — | Diff-checked wording; existing suites pass; no behavior change |
| **U2** | OpenCode remediation loop: add eligible-finding gate, one-attempt counter, remediation delegation with checkpoints, and second-`CHANGES_REQUIRED` stop to OpenCode `/implement-spec` and orchestrator | U1 | Manual runs with `CHANGES_REQUIRED` → eligible findings produce one remediation and re-review; ineligible findings stop; second `CHANGES_REQUIRED` stops |
| **U3** | Finding ledger, focused re-review scope, and concise final report: define ledger format; update reviewer prompt to focus on original findings + regressions; emit the §7 report block | U2 | Review reports contain stable finding IDs; final report contains ledger and recommended next action |
| **U4** | Validation efficiency policy and Phase A integration: document evidence-reuse and targeted-validation rules; ensure `/assess` Decision Helper rules remain consistent with the one-attempt remediation contract; sync-install/manifest/tests if new command files are added | U3 | Test fixtures cover stale evidence, targeted validation, and Phase A `REQUEST_HUMAN_DECISION` after one failed remediation; existing suites pass |

A smaller two-unit split (U1 = contracts; U2 = OpenCode behavior + ledger + reporting + validation efficiency + tests) is acceptable if review shows the combined change remains bounded and independently verifiable.

## 11. Acceptance criteria

### 11.1 Successful first-pass implementation

- AC-1.1 A single `/implement-spec` invocation implements, validates, commits, and—when review is required—runs one independent review of one bounded unit.
- AC-1.2 On `PASS` or `PASS_WITH_NOTES` with no remediation, the orchestrator stops normally and emits the final report.
- AC-1.3 No push, merge, deploy, or history rewrite occurs.

### 11.2 Eligible automatic remediation

- AC-2.1 When the initial review returns `CHANGES_REQUIRED` and every finding is eligible per §3.2, the orchestrator delegates exactly one remediation cycle.
- AC-2.2 The remediation agent receives only the eligible findings and the bounded unit's scope.
- AC-2.3 The remediation agent captures start/end checkpoints and commits only after validation passes.
- AC-2.4 A fresh opposite-family re-review runs against the final commit.
- AC-2.5 Resolved findings transition `OPEN → REMEDIATED → VERIFIED → CLOSED` in the ledger.

### 11.3 Ineligible remediation requiring human intervention

- AC-3.1 If any finding is ineligible per §3.2, the orchestrator does not delegate remediation; it stops and requests human intervention.
- AC-3.2 Security findings are never silently waived; they are either remediated if eligible or escalated to the user.
- AC-3.3 Scope expansion, material architecture decisions, and ambiguous requirements always stop for human approval.

### 11.4 Maximum remediation attempts

- AC-4.1 The orchestrator tracks the remediation attempt count and never exceeds one per `/implement-spec` invocation.
- AC-4.2 If the focused re-review returns `CHANGES_REQUIRED`, the orchestrator stops and reports the unresolved findings; no second remediation loop starts.

### 11.5 Fresh review of the final commit

- AC-5.1 The re-review inspects the final commit (initial + remediation), not only the remediation commit.
- AC-5.2 The re-review uses fresh runtime model-family evidence from the remediation agent's checkpoints.
- AC-5.3 The re-review session is fresh and distinct from the initial review session.
- AC-5.4 The re-review focuses on the original findings and possible regressions.

### 11.6 Model-family resolution failures

- AC-6.1 If remediation start/end checkpoints fail, the orchestrator stops blocked with the documented reason.
- AC-6.2 If remediation family resolution is blocked, the orchestrator reports `REVIEW_BLOCKED_MODEL_RESOLUTION` with the documented reason and stops without guessing.
- AC-6.3 The re-review family is never inferred from the initial implementation family, capability alias, or provider assumptions.

### 11.7 Stale validation evidence

- AC-7.1 Validation evidence is reused only when §6.1 conditions hold.
- AC-7.2 Evidence tied to a commit that is not an ancestor of the final commit is treated as stale and re-run.
- AC-7.3 Evidence whose scope files changed after it was produced is treated as stale and re-run.
- AC-7.4 Missing or unverifiable validation evidence fails closed.

### 11.8 Security findings

- AC-8.1 A security finding is eligible for automatic remediation only when the fix is unambiguous, within scope, and requires no policy or architecture approval.
- AC-8.2 A security finding that requires human approval stops and escalates to the user.
- AC-8.3 The final report explicitly lists any unresolved security findings and the required human decision.

### 11.9 Finding lifecycle and regression evidence

- AC-9.1 Each finding has a stable ID preserved across review cycles.
- AC-9.2 A finding is reopened only when a later review provides concrete regression evidence.
- AC-9.3 The final report lists resolved and unresolved findings with their lifecycle status.
- AC-9.4 No database or persistent service is introduced for the ledger.

### 11.10 Phase A compatibility

- AC-10.1 D7 is amended per §9.3 before U4 implements it.
- AC-10.2 The Decision Helper remains advisory-only and does not execute remediation.
- AC-10.3 Remediation inside the current unit is distinguished from starting a new unit per §9.4.
- AC-10.4 `PREPARE_NEXT_UNIT` still requires recorded `[human]` acceptance and a fresh `/implement-spec` invocation.

### 11.11 Git safety

- AC-11.1 Every commit uses the configured local Git author only.
- AC-11.2 No AI co-author metadata is added.
- AC-11.3 Conventional Commit format is used.
- AC-11.4 No push, merge, deploy, force-push, or shared-history rewrite occurs automatically.

### 11.12 No automatic next-unit execution

- AC-12.1 The final report recommends the next action but does not implement it.
- AC-12.2 A new unit requires a new explicit user command.

## 12. Representative test scenarios

These scenarios are assumption-based fixtures for verification; they are not historical records.

### 12.1 SC-1: eligible finding, one remediation, pass

- Initial implementation: passes validation, review returns `CHANGES_REQUIRED` with one blocking finding (typo in error message).
- Finding eligibility: eligible (routine mechanical fix, within scope).
- Remediation: fixes typo, validates, commits.
- Re-review: `PASS`.
- Expected: ledger shows `R1-1: CLOSED`; final report recommends acceptance.

### 12.2 SC-2: eligible finding, one remediation, still changes required

- Initial review: `CHANGES_REQUIRED` with one blocking finding (missing input validation).
- Remediation: adds validation, commits.
- Re-review: `CHANGES_REQUIRED` with a new finding (validation rejects valid input).
- Expected: orchestrator stops; no second remediation; ledger shows `R1-1: CLOSED`, `R2-1: OPEN`; final report recommends new user-initiated unit.

### 12.3 SC-3: ineligible finding stops

- Initial review: `CHANGES_REQUIRED` with one blocking finding requiring a material architecture decision.
- Expected: orchestrator stops before remediation; final report lists ineligible finding and requests human decision.

### 12.4 SC-4: security finding requiring approval

- Initial review: `CHANGES_REQUIRED` with one blocking security finding (residual risk in auth flow).
- Finding eligibility: ineligible (requires security-owner approval).
- Expected: orchestrator stops; security finding is not waived; final report escalates to security owner.

### 12.5 SC-5: stale validation evidence re-run

- Initial validation: tests passed at commit C1.
- Remediation changes a file covered by the test suite.
- Expected: tests are re-run at the final commit; initial C1 evidence is not reused for the changed surface.

### 12.6 SC-6: model-family resolution blocked

- Remediation start checkpoint succeeds, end checkpoint succeeds, but resolution returns `MODEL_DETECTION_AMBIGUOUS`.
- Expected: orchestrator reports `REVIEW_BLOCKED_MODEL_RESOLUTION` with reason `MODEL_DETECTION_AMBIGUOUS`; no re-review; final report recommends human decision.

### 12.7 SC-7: no review required

- Docs-only change within scope; orchestrator decides independent review is not required.
- Expected: no remediation path is evaluated; final report shows `Independent review: not required`.

### 12.8 SC-8: next unit not authorized

- Unit passes after remediation; an approved split has a next unit.
- Expected: final report recommends `PREPARE_NEXT_UNIT` or `ACCEPT_UNIT` but does not start it; starting the next unit requires a new `/implement-spec`.

## 13. Decisions, open questions, and risks

| ID | Item | Status / recommendation |
| --- | --- | --- |
| D1 | One remediation attempt is the default maximum. Raising it requires a new SPEC decision. | Proposed |
| D2 | Remediation may use the same capability tier as the initial implementation or a different tier; the orchestrator decides based on finding risk/complexity. | Proposed |
| D3 | Finding ledger is session-local; no persistent store in v1. | Proposed |
| D4 | Re-review is opposite-family to the remediation agent, not the initial reviewer. | Proposed |
| R1 | Risk: an LLM misclassifies an ineligible finding as eligible and makes an unauthorized architecture or security decision. Mitigation: hard eligibility rules, required human approval for security/architecture/scope expansion, and review of the orchestrator's eligibility decision in test scenarios. | Open |
| R2 | Risk: stale validation evidence is reused. Mitigation: fail-closed staleness rules and explicit tests. | Open |
| R3 | Risk: Phase A U4 is implemented before D7 is amended, causing a contract contradiction. Mitigation: implement Supervised Execution v1 U1 before Phase A U4. | Open |

## 14. Review record

No review cycles yet. This SPEC requires independent opposite-family review before implementation begins.
