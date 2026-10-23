# SPEC: Phase A — Post-Implementation Assessment & Decision Helper

- **Status:** Draft revision 5. Design only, not implemented.
  - Revision 2 addressed review cycle 1 (R1–R9).
  - Revision 3 addressed review cycle 2 (R2-1–R2-4) and recorded the approved decisions D6 and D7.
  - Revision 4 addressed review cycle 3 (R3-1) and passed review cycle 4.
  - Revision 5 records the approved decisions D1–D5 and the cycle-4 review (sections 11–12).

  Revision 5 requires a fresh independent review (control-plane contract). Unit U1 starts only on explicit user authorization.
- **Baseline:** `main` at `9711baa` (equal to `origin/main` at drafting time).
- **Tier for implementing units:** at least `standard` (control-plane); independent opposite-family review required for every unit.
- **Authority:** subordinate to [AGENTS.md](../../AGENTS.md) and project-local instructions. Where this SPEC and an existing policy disagree, the existing policy wins until a unit of this SPEC changes it with review.

Paths written as code spans (for example `policies/verification-assessment.md`) are proposed files that do not exist yet. Paths written as links exist today.

## 0. Purpose and non-goals

The OpenCode workflow stops after the first review verdict ([agents/orchestrator.md](../../integrations/opencode/agents/orchestrator.md), "Review decision"). It does not say what was actually verified or what to do next. In the Huellas authentication work, three things went wrong:

- Passing tests and a `PASS` verdict were treated as "done" while production and security checks were still pending.
- Test-fixture failures looked like application defects.
- Findings from different review cycles were mixed together.

Phase A adds four things:

1. A verification-state contract (A1).
2. A minimal extension of the existing handoff fields (A2).
3. A read-only post-implementation assessment (A3).
4. An advisory-only Decision Helper that recommends exactly one next action and executes nothing (A4).

Non-goals:

- Implementing anything in this document's own change.
- Changing routing, model resolution, reviewer selection, checkpoints, or review verdict semantics.
- Autonomous continuation, automatic retries, deployment automation, persistent telemetry, retrospectives, debugging automation.
- Changes to external project repositories.

## 1. Current-state architecture assessment

| Area | What exists today | Source |
| --- | --- | --- |
| Authority and workflow | Authority order; core workflow ending at the phase/SPEC boundary, including a "Fix material findings, validate, commit, and re-review" remediation loop | [AGENTS.md](../../AGENTS.md) |
| Routing | `economy` / `standard` / `strong` / `premium`; control-plane minimum `standard` | [policies/model-routing.md](../../policies/model-routing.md), [commands/route-task.md](../../commands/route-task.md) |
| Bounded units | Vertical slices, one unit per `/implement-spec`, no automatic continuation | [commands/split-spec.md](../../commands/split-spec.md) |
| Implementation flow (portable) | "If `CHANGES_REQUIRED`, route fixes, validate, commit, and re-review" | [commands/implement-spec.md](../../commands/implement-spec.md) |
| Implementation flow (OpenCode) | Start/end checkpoints (mandatory), delegation, review decision, runtime family resolution, fail-closed reasons, report fields; "Do not automatically remediate CHANGES_REQUIRED. Stop after the first verdict." | [integrations/opencode/commands/implement-spec.md](../../integrations/opencode/commands/implement-spec.md), [agents/orchestrator.md](../../integrations/opencode/agents/orchestrator.md) |
| Runtime provenance | `review-route.sh` checkpoint/resolve; `resolve-model-family.sh` key=value contract with documented block reasons. Resolution reads the *current* `usageHistory` rows and `combos` definition | [integrations/opencode/README.md](../../integrations/opencode/README.md), [resolve-model-family.sh](../../integrations/opencode/scripts/resolve-model-family.sh), [review-route.sh](../../integrations/opencode/scripts/review-route.sh) |
| Review | Opposite-family reviewer; verdicts `PASS` / `PASS_WITH_NOTES` / `CHANGES_REQUIRED`; blocking / non-blocking findings | [policies/review-routing.md](../../policies/review-routing.md), [templates/review-report.md](../../templates/review-report.md), [commands/review-change.md](../../commands/review-change.md) |
| Handoff (template) | Unit, start/result commit, tier, model/family, reviewer, files, tests, lint/build, risks, next phase | [templates/implementation-handoff.md](../../templates/implementation-handoff.md) |
| Handoff (command) | `/handoff`: fixed six-section close-out (`Completed unit`, `Validation`, `Repository state`, `Changed areas`, `Unresolved`, `Next fresh-session task`); structure asserted by `test-sync-install.sh` | [integrations/opencode/commands/handoff.md](../../integrations/opencode/commands/handoff.md) |
| Install / health | `sync-install.sh` hard-coded 14-entry manifest (mirrored in `test-sync-install.sh` `NMAN=14` and the README install list); `doctor.sh` `command_sync` covers every `commands/*.md` automatically, while `installed_commands` requires a fixed four | [integrations/opencode/scripts/sync-install.sh](../../integrations/opencode/scripts/sync-install.sh), [integrations/opencode/scripts/doctor.sh](../../integrations/opencode/scripts/doctor.sh) |
| Product record | CURRENT STATE / DECISIONS / FUTURE VISION | [docs/PRODUCT.md](../PRODUCT.md) |

No SPEC convention existed before this document; earlier SPECs were task prompts. `docs/specs/` is the approved location for Phase A specifications (D6, section 11).

## 2. Gap analysis

| Need | Existing behavior | Gap | Phase A response |
| --- | --- | --- | --- |
| Distinguish implementation, validation, review, environment verification, readiness | Report fields cover implementation result, validation result, verdict | No environment dimension, no per-criterion status, no derived readiness | A1 state contract |
| Partial verification and missing evidence | "Not run" wording in `/handoff`; fail-closed resolver reasons | No uniform representation of absent evidence | A1: every input whose evidence can be absent has an explicit absent-evidence value; fail closed |
| Observed vs asserted evidence | Orchestrator does not trust child self-reported family | No general labeling for other evidence | A1 evidence labels |
| Finding identity across review cycles | Free-text findings per report | Cycle-2 findings can be confused with cycle-1 findings | A2 finding IDs `R<cycle>-<n>` |
| Interpreting results into a next action | OpenCode orchestrator stops after the first verdict. Portable `/implement-spec` allows at most one bounded automatic remediation cycle when all findings are eligible (D7 amended by Supervised Execution U1) | No structured recommendation; portable/OpenCode stop semantics still differ until Supervised Execution U2 updates the OpenCode contract | A3 assessment + A4 Decision Helper; D7 amended by Supervised Execution U1, verified by Phase A U4 |
| Re-assessment after out-of-band evidence (e.g. a production check) | None | No entry point | `/assess` command |
| Handoff model/family fields | Template has "Actual implementation model/family", but the child returns its handoff before resolution runs, and the orchestrator forbids child self-report | Ambiguous ownership | A2: child writes `pending`; orchestrator report is authoritative (4.3) |

Not gaps (reused unchanged): checkpoints, resolver, reviewer selection, verdict set, Git safety, `/handoff` output structure, doctor and sync-install behavior apart from one manifest entry.

## 3. A1 — Verification-state contract

### 3.1 Input dimensions and value domains

The table below lists every input to readiness (3.3) and to the decision rules (6.2). Each domain is closed. Every input whose evidence can be absent has an explicit absent-evidence value, and that value never satisfies a requirement.

| # | Input | Domain | Absent evidence is | Notes |
| --- | --- | --- | --- | --- |
| I1 | `assessed_commit` | `known`, `unknown` | `unknown` | 5.1 defines how it is determined |
| I2 | `implementation` | `complete`, `incomplete`, `none`, `unknown` | `unknown` | Whether the unit's changes exist at the assessed commit |
| I3 | `review` | `PASS`, `PASS_WITH_NOTES`, `CHANGES_REQUIRED` (verbatim, fresh), `not_required`, `pending`, `stale`, `blocked(<status>, <reason>)`, `unknown` | `unknown` | Freshness (verdicts only) in 5.3. `unknown` also covers "whether review is required is unknown". `blocked` carries the existing status and reason verbatim |
| I4 | `validation[]`: each *required* check | `passed`, `failed(<cause>)`, `partial`, `not_run`, `unknown` | `unknown` | Required checks come from the SPEC/task and project `AGENTS.md`. `failed` = at least one failure; `partial` = ran without failures but did not cover the required scope |
| I5 | `validation[]`: each *non-required* check | same as I4 | `unknown` | Recorded only |
| I6 | `environments[]`: each *required* environment | `verified`, `pending`, `failed(<cause>)`, `not_applicable`, `unknown` | `unknown` | Required = named by an acceptance criterion or project `AGENTS.md`. Names are project-defined |
| I7 | `environments[]`: each *non-required* environment | same as I6 | `unknown` | Recorded only |
| I8 | `<cause>` of a `failed` item in I4–I7 | `unexplained`, `identified:<category>` | `unexplained` | Categories: `application`, `test-fixture`, `infrastructure`, `environment`, `other`. `identified` requires cited evidence; a hypothesis is not evidence |
| I9 | `acceptance[]`: each criterion | `met`, `unverified`, `not_met`, `needs_human_decision`, `unknown` | `unknown` | Tagged `functional`, `user-facing`, `security`, `data`, or `other`. If the SPEC/task's criteria cannot be located, one entry `AC-? = unknown` is recorded |
| I10 | `findings[]`: status × severity of each finding | status `open`, `resolved`, `unknown`; severity `blocking`, `non-blocking`, `unknown` | status `unknown`; severity `unknown` | IDs `R<cycle>-<n>` (review) or `I-<n>` (implementer/assessor). Resolution rules in 5.3 |
| I11 | `conflicts[]` | `resolved_by_authority`, `unresolved` | n/a (an empty list means no conflict was found) | 5.3 |
| I12 | `doc_state` | `in_sync`, `out_of_sync`, `unknown` | `unknown` | Whether SPEC status or product docs match the repository |
| I13 | `human_acceptance` | `recorded`, `not_recorded` | `not_recorded` | A `[human]` acceptance of this unit |
| I14 | `next_unit` | `available`, `none`, `unknown` | `unknown` | Whether an approved split has a next unit |

Inputs I12–I14 affect only the decision rules. They never make a unit look more verified than its evidence supports, so `doc_state = unknown` and `next_unit = unknown` are listed under Missing evidence without blocking.

**`needs_human_decision` vs `unverified` (I9):**

- **`needs_human_decision`** is only for criteria whose satisfaction is a judgment, such as accepting a residual security risk or a product/release sign-off. The required authority (e.g. "project owner", "security owner") must be named.
- **`unverified`** is for objectively checkable conditions that have not been checked yet, for example "no service-role key in the client bundle".

### 3.2 Evidence labels

Every evidence item carries exactly one label:

- `[observed]`: the assessor inspected it in the current session. Examples: `git rev-parse`, `git log`, `git status`, or a review report file read directly.
- `[reported]`: stated in another agent's output (implementation child, reviewer, `/handoff`, or an orchestrator report from another session).
- `[human]`: stated by the user.

An assessor may upgrade `[reported]` to `[observed]` only by re-inspecting the fact read-only. It never re-runs tests (see 5.4). Recommendations are not evidence and are never labeled as such.

### 3.3 Readiness derivation (total)

**Output domain:** `blocked`, `not_ready`, `needs_human_decision`, `ready_with_notes`, `ready`.

**Rule:** each input value imposes the cap in this table. Readiness is the most severe cap present, with severity ordered `blocked` > `not_ready` > `needs_human_decision` > `ready_with_notes`. If no cap applies, readiness is `ready`.

There is one rule (maximum severity) and no precedence list, so caps cannot overlap or contradict each other. Every value of every input in 3.1 has exactly one row, so readiness is defined for every state.

| Input | Value | Cap |
| --- | --- | --- |
| I1 `assessed_commit` | `known` | none |
| | `unknown` | `blocked` |
| I2 `implementation` | `complete` | none |
| | `incomplete`, `none` | `not_ready` |
| | `unknown` | `blocked` |
| I3 `review` | `PASS`, `not_required` | none |
| | `PASS_WITH_NOTES` | `ready_with_notes` |
| | `CHANGES_REQUIRED` | `not_ready` |
| | `pending`, `stale`, `blocked(...)`, `unknown` | `blocked` |
| I4 required validation | `passed` | none |
| | `failed(any cause)`, `partial`, `not_run` | `not_ready` |
| | `unknown` | `blocked` |
| I5 non-required validation | `failed(any cause)`, `partial` | `ready_with_notes` |
| | `passed`, `not_run`, `unknown` | none |
| I6 required environment | `verified`, `not_applicable` | none |
| | `pending`, `failed(any cause)` | `not_ready` |
| | `unknown` | `blocked` |
| I7 non-required environment | any value | none |
| I8 failure cause | `unexplained`, `identified:<category>` | none of its own (the cap comes from the failed item in I4–I7). The cause affects only the decision (6.2 rules 5–6) |
| I9 acceptance | `met` | none |
| | `unverified`, `not_met` | `not_ready` |
| | `needs_human_decision` | `needs_human_decision` |
| | `unknown` | `blocked` |
| I10 finding | status `resolved`, any severity | none |
| | status `open`, severity `blocking` or `unknown` | `not_ready` |
| | status `open`, severity `non-blocking` | `ready_with_notes` |
| | status `unknown`, any severity | `blocked` |
| I11 conflict | `resolved_by_authority` | none |
| | `unresolved` | `blocked` |
| I12 `doc_state` | `out_of_sync` | `ready_with_notes` |
| | `in_sync`, `unknown` | none |
| I13 `human_acceptance` | any value | none |
| I14 `next_unit` | any value | none |

### 3.4 Relationship to existing review verdicts

| Verdict / status | Review gate | Readiness cap | Can yield `ACCEPT_UNIT` |
| --- | --- | --- | --- |
| `PASS` | satisfied for `reviewed_commit` only | none | yes |
| `PASS_WITH_NOTES` | satisfied for `reviewed_commit` only; notes become non-blocking findings | `ready_with_notes` | yes |
| `CHANGES_REQUIRED` | failed | `not_ready` | **never** |
| `stale` (`reviewed_commit ≠ assessed_commit`) | not satisfied for the assessed commit | `blocked` | never |
| `REVIEW_BLOCKED_MODEL_RESOLUTION` (any reason) or any other block status | not satisfied; existing fail-closed semantics unchanged | `blocked` | never |
| `Independent review: not required` | satisfied by the orchestrator's existing decision | none | yes |

Verdict text is copied verbatim and never rewritten, softened, or reinterpreted. The assessment adds no new verdicts, and the reviewer still returns exactly one of the three.

## 4. A2 — Structured evidence handoff

### 4.1 Evaluation of the current template

[templates/implementation-handoff.md](../../templates/implementation-handoff.md) already covers:

- the bounded unit;
- starting and resulting Git state;
- tier and provenance;
- tests and typecheck/lint/build;
- unresolved risks;
- the next step.

Only two things are genuinely missing: acceptance-criterion status and environment verification. Evidence labels and finding identity can be carried as annotations on existing fields.

### 4.2 Extension: annotate existing fields, add two lines

No field is renamed, removed, or duplicated. Each existing field gains an optional annotation convention:

| Existing field | Optional annotation |
| --- | --- |
| `Tests run:` / `Typecheck / lint / build:` | per entry: `<command> — passed\|failed\|partial\|not_run — [label] — at <commit>`; failures add `cause: unexplained\|identified:<category>` |
| `Unresolved risks:` | per entry: finding ID (`R<cycle>-<n>` / `I-<n>`), `blocking\|non-blocking`, source; unknowns written `unknown: <what is missing>` |
| `Next phase or closure condition:` | unchanged text; treated by the assessment as an implementer suggestion (`[reported]`, non-authoritative) |
| `Actual implementation model:` / `Actual model family:` | see 4.3 |

Two new optional lines are appended:

```markdown
- Acceptance criteria: <AC-id> — met|unverified|not_met|needs_human_decision|unknown — [label] <evidence>
- Environment verification: <env> — verified|pending|failed|not_applicable|unknown — [label] <evidence / who>
```

Optional additions to [templates/review-report.md](../../templates/review-report.md):

- Finding IDs `R<cycle>-<n>` on each blocking and non-blocking finding.
- One line `Prior findings status: <id> — resolved|still open|not re-checked`. `not re-checked` maps to finding status `unknown`.

The verdict line is unchanged.

`/handoff` output is unchanged in Phase A. `/assess` reads it as `[reported]` evidence and maps its sections as follows:

- `Validation` maps to validation.
- `Repository state` maps to implementation and Git.
- `Unresolved` maps to findings and unknowns.

### 4.3 Model/family ownership

The implementation child returns its handoff before the end checkpoint and model resolution run (OpenCode `implement-spec` steps 10–15). Therefore:

- **Child handoff:** `Actual implementation model:` and `Actual model family:` read `pending (orchestrator resolution)`. The child never fills them, as already required by [agents/orchestrator.md](../../integrations/opencode/agents/orchestrator.md).
- **Authoritative source:** the orchestrator's final report fields "Model resolution", "Actual models and providers", and "Actual family". The assessment reads provenance from that report, never from the child handoff.
- **Skipped or blocked resolution:** the report reads `skipped (independent review not required)` or `blocked (<reason>)`, as today.

The U2 template change is wording only; no new field is added.

### 4.4 Backward compatibility

A handoff without annotations or the two new lines is still valid. Missing items take their absent-evidence value from 3.1:

- acceptance criteria without status evidence are `unknown`;
- validation entries without a stated result or commit are `unknown`.

These cap readiness at `blocked`, so the Decision Helper recommends `VERIFY_FURTHER` (fixture S7). Old handoffs therefore fail closed: they are never treated as verified, and nothing breaks.

## 5. A3 — Post-implementation assessment

### 5.1 Inputs, in authority order

1. The authoritative SPEC/task and its acceptance criteria.
2. Git state `[observed]`: branch, `HEAD`, `git status`, and `git log` for the unit range.
3. The review report(s) for the unit.
4. The orchestrator report: checkpoints, model resolution, review decision.
5. The implementation handoff or `/handoff` output `[reported]`.
6. User statements `[human]`, for example "I verified login in production".

**Assessed commit:** the commit the user names. Otherwise it is the unit's resulting commit `[observed]` from Git (normally `HEAD` of the unit branch). If neither can be determined, `assessed_commit = unknown`.

### 5.2 Output block (fixed structure)

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

Empty lists are written `none`, never omitted.

### 5.3 Freshness, conflicts, and incomplete evidence

**Review freshness** applies only to a review verdict (`PASS`, `PASS_WITH_NOTES`, `CHANGES_REQUIRED`). It is decided only by the verdict's reviewed commit versus the assessed commit:

- `reviewed_commit == assessed_commit`: the verdict is current and governs, verbatim.
- `reviewed_commit ≠ assessed_commit`: `stale`.
- `reviewed_commit` not determinable: `unknown`.

**Non-verdict review states are not freshness-evaluated.** They keep their state whether or not a reviewed commit exists:

- `blocked(<status>, <reason>)` stays `blocked(...)`, with status and reason verbatim. It never becomes `unknown` or `stale`, so 6.2 rule 2 always applies to it.
- `pending` stays `pending`.
- `not_required` stays `not_required`.

When several reviews exist, the governing one is the latest cycle with a current verdict, unless a later cycle is `blocked(...)` or `pending`; then that later cycle governs. If no current verdict exists, the latest cycle governs, with its state determined as above.

**Other evidence is also commit-bound.** A handoff whose resulting commit differs from the assessed commit does *not* change review freshness. Instead:

- The mismatch is recorded as a conflict, `resolved_by_authority`.
- Implementation is taken from `[observed]` Git state.
- Validation results that the handoff ties to a different commit, or to no commit, are `unknown` for the assessed commit.

**Reviewer vs implementer:** the reviewer's verdict governs the review dimension. Implementer claims stay `[reported]`.

**Findings across cycles:**

- New findings get new IDs; IDs are never reused.
- A finding becomes `resolved` only when a later fresh review confirms it, never on the implementer's word.
- A prior finding that the governing review does not re-check has status `unknown`.
- A resolved finding is reopened only if a later review restates it.

**Failures:**

- A failed validation or environment check is `cause: unexplained` unless evidence identifies the cause. Hypotheses may be listed (application, infrastructure, test fixture, environment), but a hypothesis is not an identified cause.
- An unexplained failure is never treated as an application defect.

**Disagreement with a verdict:** the assessor may record an `unresolved` conflict and require a human decision. It never overrides or reinterprets the verdict.

**Resolution by authority order:** a conflict that the authority order in 5.1 resolves (e.g. `[observed]` Git beats a `[reported]` commit) is listed as `resolved_by_authority`. Any other conflict is `unresolved`.

**Insufficient evidence:** missing items are listed under Missing evidence and take their absent-evidence value (3.1). Nothing is inferred.

### 5.4 Read-only boundary

Assessment never:

- edits files;
- runs validation or tests;
- re-runs model resolution;
- delegates to any agent;
- runs Git write commands;
- contacts deployed environments.

Allowed shell use is read-only Git inspection only.

In v1 these restrictions are enforced by instruction text, not by agent permissions (D2). They are not permission-level enforcement.

## 6. A4 — Advisory-only Decision Helper

### 6.1 Action set (closed)

Exactly one is recommended per assessment.

| Action | Meaning |
| --- | --- |
| `ACCEPT_UNIT` | Ask the user to accept the completed bounded unit |
| `REMEDIATE_FINDINGS` | Fix identified findings, unmet criteria, or failures with an identified cause (scoped to listed IDs/causes) |
| `VERIFY_FURTHER` | Obtain missing verification: validation re-run, independent review or re-review through the normal workflow, environment check, or locating missing evidence |
| `INVESTIGATE_FAILURE` | Establish the cause of an unexplained failure before any remediation |
| `RECONCILE_DOCS` | Bring SPEC/doc state in line with the repository (e.g. SPEC status, PRODUCT.md current state) |
| `PREPARE_NEXT_UNIT` | Prepare the next unit of an approved split; only after `[human]` acceptance of the current unit |
| `REQUEST_HUMAN_DECISION` | A product, security, release, provenance, or conflict judgment only the user can make |

### 6.2 Decision rules (first match wins)

1. Any conflict `unresolved`: `REQUEST_HUMAN_DECISION`.
2. `review = blocked(...)`, for any status and any reason: `REQUEST_HUMAN_DECISION`. Rationale:
   - Resolution reads the *current* `usageHistory` rows and `combos` definition. A later retry can see different database contents, a different combo definition, or different attribution evidence than existed at implementation time, and nothing records that they are unchanged.
   - Provenance therefore cannot be established after the fact by the Decision Helper.
   - The helper never recommends re-resolution, never proposes a reviewer or family, and never treats the unit as reviewed. Existing fail-closed behavior is unchanged. How to establish provenance (for example fixing setup via `/doctor` hints and re-running the unit with fresh checkpoints) is the user's decision.
3. `implementation ∈ {incomplete, none}`: `REQUEST_HUMAN_DECISION`. Resuming, re-splitting, or abandoning the unit is the user's call.
4. Readiness `blocked` (the remaining causes are I1, I2, I3 `pending`/`stale`/`unknown`, I4, I6, I9 and I10 status `unknown`): `VERIFY_FURTHER`, naming the evidence to obtain.
5. A required validation or required environment is `failed(unexplained)`: `INVESTIGATE_FAILURE`.
6. Any of: `review = CHANGES_REQUIRED`; an `open` finding with severity `blocking` or `unknown`; an acceptance criterion `not_met`; a required validation or environment `failed(identified:<category>)`. Action: `REMEDIATE_FINDINGS`, scoped to the listed open IDs and causes. An `identified:test-fixture` cause scopes remediation to the fixture, not application code.
7. Any of: a required validation `partial` or `not_run`; a required environment `pending`; an acceptance criterion `unverified`. Action: `VERIFY_FURTHER`.
8. An acceptance criterion `needs_human_decision`: `REQUEST_HUMAN_DECISION`, naming the authority from 3.1.
9. `doc_state = out_of_sync`: `RECONCILE_DOCS`.
10. Readiness `ready` or `ready_with_notes`:
    - `human_acceptance = not_recorded`: `ACCEPT_UNIT`.
    - `human_acceptance = recorded` and `next_unit = available`: `PREPARE_NEXT_UNIT`.
    - `human_acceptance = recorded` and `next_unit ∈ {none, unknown}`: `REQUEST_HUMAN_DECISION` (close the SPEC or define the next unit).
11. Anything else: `REQUEST_HUMAN_DECISION` (fail-closed guard).

**Coverage argument.** Readiness `blocked` is caught by rules 1, 2 or 4. `not_ready` is caught by rules 3, 5, 6 or 7, because every `not_ready` cap in 3.3 is named in one of them. `needs_human_decision` is caught by rule 8. `ready_with_notes` and `ready` are caught by rules 9 or 10. Rule 11 is therefore unreachable and exists only as a guard. Section 9.2 records the mechanical check of this argument.

**Invariants:**

- `ACCEPT_UNIT` and `PREPARE_NEXT_UNIT` are produced only by rule 10, which requires readiness `ready` or `ready_with_notes`.
- `CHANGES_REQUIRED`, `stale`, `pending`, `unknown` and `blocked(...)` reviews cap readiness at `not_ready` or `blocked`, so they can never produce an acceptance recommendation.

### 6.3 Output block

```text
Decision Helper (advisory only — nothing has been executed):
- Recommended action: <ACTION> — <one line>
- Rationale: <decision rule number and governing evidence>
- Supporting evidence: <item — label>, ...
- Unresolved risks:
- Prerequisites:
- Required authorization: <who must authorize what, e.g. "user runs /implement-spec for R2-1..R2-3">
- Evidence limitations / confidence: high|medium|low — <why>
- Why not ACCEPT_UNIT: <only when another action is recommended>
```

### 6.4 Hard rules

- The Decision Helper never executes, delegates, schedules, or retries its recommendation. The turn ends after the block.
- Each next action requires a new explicit user command, for example `/implement-spec` for remediation or `/review-change` for re-review.
- It never initiates implementation, push, merge, deployment, history rewrite, or production changes. These may appear only as steps the user performs, with the required explicit authorization named.
- It runs after the OpenCode orchestrator's "stop after the first review verdict" point and also stops.
- Its output is never authorization for any remediation loop. Supervised Execution U1 amended the portable contracts in [AGENTS.md](../../AGENTS.md) and [commands/implement-spec.md](../../commands/implement-spec.md) to allow at most one bounded automatic remediation cycle per `/implement-spec`; the Decision Helper remains advisory-only and a `REMEDIATE_FINDINGS` recommendation still requires a new explicit user command.

## 7. Integration architecture (minimal)

| Change | File(s) | Kind |
| --- | --- | --- |
| Portable contract: input domains, labels, readiness caps, verdict mapping, freshness, action set, decision rules. Single source; other files reference it | `policies/verification-assessment.md` (new) | control-plane |
| Portable procedure for assessment + Decision Helper | `commands/assess-change.md` (new) | control-plane |
| OpenCode `/assess` command: `agent: orchestrator`, `subagent: false`; text forbids delegation, edits, validation runs, re-resolution, and Git writes; emits the 5.2 and 6.3 blocks | `integrations/opencode/commands/assess.md` (new) | control-plane |
| Final report appends the Assessment and Decision Helper blocks (also for blocked outcomes); OpenCode "stop" wording unchanged | [integrations/opencode/commands/implement-spec.md](../../integrations/opencode/commands/implement-spec.md) step 18, [agents/orchestrator.md](../../integrations/opencode/agents/orchestrator.md) "Orchestration report fields" | control-plane |
| Portable one-remediation semantics (D7, 7.1; amended by Supervised Execution U1) | [commands/implement-spec.md](../../commands/implement-spec.md) (`If CHANGES_REQUIRED`, one bounded automatic remediation cycle...), [AGENTS.md](../../AGENTS.md) (one bounded automatic remediation cycle) | control-plane |
| Manifest +`commands/assess.md`; `NMAN` 14→15 plus an assess block modeled on the handoff block; README install list 14→15 | [sync-install.sh](../../integrations/opencode/scripts/sync-install.sh), [test-sync-install.sh](../../integrations/opencode/scripts/test-sync-install.sh), [integrations/opencode/README.md](../../integrations/opencode/README.md) | control-plane |
| Annotation conventions, two new lines, model/family wording (section 4) | [templates/implementation-handoff.md](../../templates/implementation-handoff.md), [templates/review-report.md](../../templates/review-report.md) | contract |
| One workflow step: "Assess verification state and record an advisory next-action recommendation; do not execute it." | [AGENTS.md](../../AGENTS.md), [README.md](../../README.md) | control-plane |
| CURRENT STATE capability list (final unit only) | [docs/PRODUCT.md](../PRODUCT.md) | product record |

Unchanged:

- routing policy;
- checkpoints;
- `review-route.sh` and `resolve-model-family.sh`;
- reviewer selection;
- the verdict set;
- `/handoff` output;
- `doctor.sh` (`command_sync` already covers new command files; `installed_commands` keeps its required four);
- the `/doctor` and `/sync-install` agents.

Portability: the contract and procedure live in `policies/` and `commands/` and do not depend on OpenCode. The OpenCode command is a thin adapter, consistent with the existing split.

### 7.1 Portable one-remediation semantics (D7: amended by Supervised Execution U1; verified by Phase A U4)

The portable contract and the OpenCode adapter previously disagreed: the portable files described an open-ended remediation loop, while the OpenCode orchestrator stopped after the first verdict.

**Decision D7 (approved, amended by Supervised Execution U1):** within a single `/implement-spec` authorization, the orchestrator may perform at most one bounded automatic remediation cycle when the initial independent review returns `CHANGES_REQUIRED` and every finding is eligible. After one remediation attempt, any remaining `CHANGES_REQUIRED` verdict stops and requires a new explicitly user-initiated bounded unit. This does not authorize the next unit.

> **Amendment note (Supervised Execution v1).** [`docs/specs/supervised-execution-v1.md`](./supervised-execution-v1.md) U1 has amended D7 and updated the wording in [AGENTS.md](../../AGENTS.md) and [commands/implement-spec.md](../../commands/implement-spec.md). Supervised Execution U2 owns the matching OpenCode `/implement-spec` and orchestrator changes. Phase A U4 verifies that the Decision Helper rules and assessment contract remain consistent with the amended portable/OpenCode contracts, updating only Phase A-specific files (`policies/verification-assessment.md`, `commands/assess.md`, `integrations/opencode/commands/assess.md`, fixtures). Phase A U4 does not re-edit the portable or OpenCode `/implement-spec` contracts.

The advisory-only Decision Helper behavior in 6.4 is preserved: a `REMEDIATE_FINDINGS` recommendation still requires a new explicit user command and never executes automatically.

## 8. Acceptance criteria

**A1 — State contract (`policies/verification-assessment.md`)**

- AC-A1.1 Defines inputs I1–I14 with the closed domains and absent-evidence values in 3.1, the evidence labels in 3.2, and the `needs_human_decision` vs `unverified` rule.
- AC-A1.2 Defines readiness by the cap table in 3.3: every value of every input has exactly one row, readiness is the most severe cap, and absent evidence never satisfies a requirement.
- AC-A1.3 Contains the verdict mapping in 3.4. `CHANGES_REQUIRED`, `stale`, and any `blocked(...)` review cannot yield `ACCEPT_UNIT`.
- AC-A1.4 States that verdict text and existing block statuses/reasons are passed through verbatim.

**A2 — Evidence handoff**

- AC-A2.1 The handoff template gains only the annotation conventions and the two new lines in 4.2. No existing field is removed or duplicated.
- AC-A2.2 The template states 4.3: the child writes `pending (orchestrator resolution)`, and the orchestrator report is the authoritative provenance.
- AC-A2.3 The review template gains optional finding IDs and a `Prior findings status:` line. The verdict line is unchanged.
- AC-A2.4 The policy states 4.4: un-annotated or old handoffs fail closed.

**A3 — Assessment**

- AC-A3.1 The procedure emits the 5.2 block with every field present (`none` when empty).
- AC-A3.2 The procedure states the input authority order and assessed-commit rule (5.1), and the 5.3 rules:
  - freshness applies only to verdicts and is decided solely by `reviewed_commit` vs the assessed commit; `blocked(...)` and `pending` keep their state without a reviewed commit;
  - a handoff mismatch is a conflict, not staleness;
  - finding identity across cycles, including `not re-checked` → `unknown`;
  - failure-cause classification.
- AC-A3.3 The procedure and `/assess` state the read-only boundary in 5.4.

**A4 — Decision Helper**

- AC-A4.1 The action set is closed (6.1), and exactly one action is recommended.
- AC-A4.2 The decision rules match 6.2. Every `blocked(...)` review maps to `REQUEST_HUMAN_DECISION`, with no retry or re-resolution recommendation.
- AC-A4.3 The output block matches 6.3, including Required authorization.
- AC-A4.4 `/assess` and the OpenCode `/implement-spec` and orchestrator state that the recommendation is never executed or retried, and that push/merge/deploy/history rewrite/production changes are never initiated.

**Integration**

- AC-I.1 `sync-install.sh` manifest contains `commands/assess.md`; `test-sync-install.sh` passes with `NMAN=15` and an assess block.
- AC-I.2 `test-doctor.sh`, `test-review-route.sh`, and `test-resolve-model-family.sh` pass unchanged.
- AC-I.3 OpenCode `/implement-spec` step 19 and the orchestrator "stop after the first verdict" wording are unchanged except as amended by Supervised Execution U2; Phase A U4 does not edit them.
- AC-I.4 Checkpoint and resolution wording is unchanged.
- AC-I.5 Portable `commands/implement-spec.md` and `AGENTS.md` describe at most one bounded automatic remediation cycle per amended D7 (Supervised Execution U1); Phase A U4 does not re-edit them.

**A5 — Regression scenarios**

- AC-A5.1 The fixtures in 9.1 exist as files, each with the complete input state, expected readiness, expected decision, rule references, `must_not_decide`, and the basis label.
- AC-A5.2 `test-assessment-fixtures.sh` checks:
  - every input I1–I14 is present;
  - values are within the 3.1 domains;
  - `ACCEPT_UNIT` only with readiness `ready`/`ready_with_notes`;
  - never `ACCEPT_UNIT` with `CHANGES_REQUIRED`, `stale`, or a `blocked(...)` review;
  - `expected_decision` not in `must_not_decide`.

## 9. Historical regression scenarios (A5)

**Basis:** no execution records from the Huellas repository are available in this repository. Each scenario below is an **assumption-based fixture** derived from the summary in the task brief, not a historical record. The fixture files must carry `basis: assumption-based fixture (not a historical record)`.

### 9.1 Fixtures (complete input state)

**Notation:**

- Lists use `name=value`, separated by `; `.
- `validation` and `environments` list *required* items. Non-required items, where present, go in `validation_optional` and `environments_optional`.
- `review` is `<value>@<reviewed_commit>`; `@none` means no reviewed commit is determinable. For verdicts, freshness is computed against `assessed_commit` (5.3); other values are kept as written.
- `findings` are `id=status/severity`. `conflicts` is `none` or a list of `id=resolved_by_authority|unresolved`.
- `rules` cites the governing 3.3 caps and the 6.2 rule.

Fixture files (`examples/assessment/<fixture>.md`) contain exactly these keys, followed by an illustrative evidence excerpt.

```text
fixture: S1-bootstrap-multi-cycle
basis: assumption-based fixture (not a historical record)
scenario: Repository bootstrap; cycles 1-2 CHANGES_REQUIRED; cycle 3 PASS confirms all prior findings resolved
assessed_commit: C3
implementation: complete
review: PASS@C3
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=met; AC-2=met
findings: R1-1=resolved/blocking; R1-2=resolved/non-blocking; R2-1=resolved/blocking
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: ready
expected_decision: ACCEPT_UNIT
rules: 3.3 no cap; 6.2 rule 10
must_not_decide: REMEDIATE_FINDINGS, PREPARE_NEXT_UNIT
```

```text
fixture: S2-auth-production-pending
basis: assumption-based fixture (not a historical record)
scenario: Authentication implemented; automated validation and review pass; production verification incomplete
assessed_commit: C1
implementation: complete
review: PASS@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: production=pending
acceptance: AC-login-local=met; AC-login-production=unverified
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: not_ready
expected_decision: VERIFY_FURTHER
rules: 3.3 I6 pending, I9 unverified -> not_ready; 6.2 rule 7
must_not_decide: ACCEPT_UNIT, REMEDIATE_FINDINGS
```

```text
fixture: S3-logout-user-facing-ac
basis: assumption-based fixture (not a historical record)
scenario: Logout works technically; review finds the user-facing acceptance criterion unmet
assessed_commit: C1
implementation: complete
review: CHANGES_REQUIRED@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-logout-session-cleared=met; AC-logout-user-feedback=not_met
findings: R1-1=open/blocking
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: not_ready
expected_decision: REMEDIATE_FINDINGS
rules: 3.3 I3 CHANGES_REQUIRED, I9 not_met, I10 open/blocking -> not_ready; 6.2 rule 6 (scope R1-1)
must_not_decide: ACCEPT_UNIT, VERIFY_FURTHER
```

```text
fixture: S4a-otp-failure-unexplained
basis: assumption-based fixture (not a historical record)
scenario: Supabase OTP check fails in the Supabase test environment; cause not established (hypotheses: test fixture, provider infrastructure, application)
assessed_commit: C1
implementation: complete
review: PASS@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: supabase-test=failed(unexplained)
acceptance: AC-otp-login=unverified
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: not_ready
expected_decision: INVESTIGATE_FAILURE
rules: 3.3 I6 failed, I9 unverified -> not_ready; 6.2 rule 5
must_not_decide: ACCEPT_UNIT, REMEDIATE_FINDINGS
```

```text
fixture: S4b-otp-failure-supabase-fixture-confirmed
basis: assumption-based fixture (not a historical record)
scenario: Same failure after investigation; evidence identifies the repository's Supabase test fixture (OTP test user/seed data); application code path not implicated
assessed_commit: C1
implementation: complete
review: PASS@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: supabase-test=failed(identified:test-fixture)
acceptance: AC-otp-login=unverified
findings: I-1=open/blocking
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: not_ready
expected_decision: REMEDIATE_FINDINGS
rules: 3.3 I6 failed, I9 unverified, I10 open/blocking -> not_ready; 6.2 rule 6 (scope: test fixture only)
must_not_decide: ACCEPT_UNIT, INVESTIGATE_FAILURE
```

```text
fixture: S5a-security-check-unverified
basis: assumption-based fixture (not a historical record)
scenario: Authentication works; the objective exposure check (no secret or service-role key reaches the client) has not been performed
assessed_commit: C1
implementation: complete
review: PASS@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-auth-functional=met; AC-sec-no-client-secrets=unverified
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: not_ready
expected_decision: VERIFY_FURTHER
rules: 3.3 I9 unverified -> not_ready; 6.2 rule 7
must_not_decide: ACCEPT_UNIT, REQUEST_HUMAN_DECISION
```

```text
fixture: S5b-security-acceptance-pending
basis: assumption-based fixture (not a historical record)
scenario: Authentication works and the exposure check passed; residual-risk acceptance requires the security owner's sign-off
assessed_commit: C1
implementation: complete
review: PASS@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-auth-functional=met; AC-sec-no-client-secrets=met; AC-sec-risk-signoff=needs_human_decision
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: needs_human_decision
expected_decision: REQUEST_HUMAN_DECISION
rules: 3.3 I9 needs_human_decision; 6.2 rule 8 (authority: security owner)
must_not_decide: ACCEPT_UNIT, VERIFY_FURTHER
```

```text
fixture: S6-new-vs-resolved-findings
basis: assumption-based fixture (not a historical record)
scenario: Cycle 2 review confirms cycle-1 findings resolved and raises new findings
assessed_commit: C2
implementation: complete
review: CHANGES_REQUIRED@C2
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=met; AC-2=not_met
findings: R1-1=resolved/blocking; R1-2=resolved/blocking; R2-1=open/blocking; R2-2=open/non-blocking
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: not_ready
expected_decision: REMEDIATE_FINDINGS
rules: 3.3 I3 CHANGES_REQUIRED, I9 not_met, I10 open/blocking -> not_ready; 6.2 rule 6 (scope R2-1, R2-2; R1-* stay resolved)
must_not_decide: ACCEPT_UNIT
```

```text
fixture: S7-old-format-handoff
basis: assumption-based fixture (not a historical record)
scenario: Handoff predates the extension; tests listed without results; no acceptance evidence
assessed_commit: C1
implementation: complete
review: PASS@C1
validation: tests=unknown; typecheck=unknown
environments: none
acceptance: AC-1=unknown; AC-2=unknown
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: blocked
expected_decision: VERIFY_FURTHER
rules: 3.3 I4 unknown, I9 unknown -> blocked; 6.2 rule 4
must_not_decide: ACCEPT_UNIT
```

```text
fixture: S8a-resolver-attribution-ambiguous
basis: assumption-based fixture (not a historical record)
scenario: Review required; resolution blocked because both families appear in the window
assessed_commit: C1
implementation: complete
review: blocked(REVIEW_BLOCKED_MODEL_RESOLUTION,MODEL_DETECTION_AMBIGUOUS)@none
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=met
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: blocked
expected_decision: REQUEST_HUMAN_DECISION
rules: 3.3 I3 blocked (kept without a reviewed commit, 5.3) -> blocked; 6.2 rule 2
must_not_decide: ACCEPT_UNIT, VERIFY_FURTHER
```

```text
fixture: S8b-resolver-setup-failure
basis: assumption-based fixture (not a historical record)
scenario: Review required; checkpoints recorded but resolution blocked by missing resolver tooling; a later retry could read changed usage rows or combo definitions
assessed_commit: C1
implementation: complete
review: blocked(REVIEW_BLOCKED_MODEL_RESOLUTION,RESOLVER_UNAVAILABLE)@none
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=met
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: blocked
expected_decision: REQUEST_HUMAN_DECISION
rules: 3.3 I3 blocked (kept without a reviewed commit, 5.3) -> blocked; 6.2 rule 2
must_not_decide: ACCEPT_UNIT, VERIFY_FURTHER
```

```text
fixture: S9-stale-review
basis: assumption-based fixture (not a historical record)
scenario: PASS was given for commit C1; a later fix commit C2 is being assessed
assessed_commit: C2
implementation: complete
review: PASS@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=met
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: blocked
expected_decision: VERIFY_FURTHER
rules: 3.3 I3 stale -> blocked; 6.2 rule 4 (re-review C2)
must_not_decide: ACCEPT_UNIT
```

```text
fixture: S10-accepted-next-unit
basis: assumption-based fixture (not a historical record)
scenario: Unit passed with notes and the user has accepted it; the approved split has a next unit
assessed_commit: C1
implementation: complete
review: PASS_WITH_NOTES@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=met
findings: R1-1=open/non-blocking
conflicts: none
doc_state: in_sync
human_acceptance: recorded
next_unit: available
expected_readiness: ready_with_notes
expected_decision: PREPARE_NEXT_UNIT
rules: 3.3 I3 PASS_WITH_NOTES, I10 open/non-blocking -> ready_with_notes; 6.2 rule 10
must_not_decide: ACCEPT_UNIT
```

```text
fixture: S11-docs-out-of-sync
basis: assumption-based fixture (not a historical record)
scenario: Unit fully verified, but the SPEC status still reads Draft
assessed_commit: C1
implementation: complete
review: PASS@C1
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=met
findings: none
conflicts: none
doc_state: out_of_sync
human_acceptance: not_recorded
next_unit: none
expected_readiness: ready_with_notes
expected_decision: RECONCILE_DOCS
rules: 3.3 I12 out_of_sync -> ready_with_notes; 6.2 rule 9
must_not_decide: ACCEPT_UNIT
```

```text
fixture: S12-implementation-incomplete
basis: assumption-based fixture (not a historical record)
scenario: The implementation child stopped before finishing the unit; partial changes are committed
assessed_commit: C1
implementation: incomplete
review: pending@none
validation: tests=passed; typecheck=passed; lint=passed
environments: none
acceptance: AC-1=unverified
findings: none
conflicts: none
doc_state: in_sync
human_acceptance: not_recorded
next_unit: available
expected_readiness: blocked
expected_decision: REQUEST_HUMAN_DECISION
rules: 3.3 I3 pending (kept without a reviewed commit, 5.3) -> blocked, I2 incomplete, I9 unverified -> not_ready; 6.2 rule 3
must_not_decide: ACCEPT_UNIT, VERIFY_FURTHER
```

### 9.2 Reducibility check (performed for revision 4)

A throwaway reducer, kept outside the repository and not part of Phase A, hand-encodes 3.3, the single-review freshness rule of 5.3, and 6.2. It is evidence for this SPEC's consistency, not an executable definition of it.

**Revision 3 correction.** The revision 3 version of this section said the reducer encoded the rules literally. That was not accurate. The reducer applied freshness only to verdicts, while the revision 3 wording of 5.3 applied it to every review value. Its 15/15 result therefore validated the intended rule, not the text as written. The independent review found the divergence (R3-1). Revision 4 changes 5.3 to the intended rule, and the reducer now follows that wording.

**Checks run on revision 4:**

1. **Fixtures.** The reducer parsed all 15 fixtures in 9.1, normalized `review` through 5.3, and recomputed readiness, decision, and the governing 6.2 rule. All 15 matched. For each fixture:
   - the required keys and basis label were present;
   - readiness and decision matched `expected_readiness` and `expected_decision`;
   - the 6.2 rule and the I3 cap named in `rules` matched;
   - the decision was not in `must_not_decide`.

   S8a and S8b reduced to I3 `blocked`, readiness `blocked`, and `REQUEST_HUMAN_DECISION` by rule 2. S12 reduced to I3 `pending`, readiness `blocked`, and `REQUEST_HUMAN_DECISION` by rule 3.
2. **Targeted regression.** The same fixtures were reduced with the revision 3 wording of 5.3 applied literally:
   - S8a and S8b gave I3 `unknown` and `VERIFY_FURTHER`, which fails.
   - S12 gave I3 `unknown`, so its cited cap no longer matched, which also fails.
   - The other 12 fixtures were unaffected.

   The check therefore detects R3-1.
3. **Review normalization.** All 21 combinations of {`PASS`, `PASS_WITH_NOTES`, `CHANGES_REQUIRED`, `not_required`, `pending`, `blocked(...)`, `unknown`} × reviewed commit {assessed, other, none} were checked. Verdicts gave current, `stale` and `unknown` respectively. `blocked(...)` always stayed `blocked`, `pending` always stayed `pending`, and no non-verdict became `stale`.
4. **State space.** The reducer enumerated 71,124,480 states over the 3.1 domains, using the normalized I3 values. Each list input took either the empty list or one item. One item is enough because caps take the maximum over items and every list rule is "any item". Results:
   - rule 11 was never reached;
   - only a review of `PASS`, `PASS_WITH_NOTES` or `not_required` produced `ACCEPT_UNIT` or `PREPARE_NEXT_UNIT`;
   - in particular, `CHANGES_REQUIRED` never produced either action;
   - neither action was produced from readiness other than `ready` or `ready_with_notes`;
   - every `blocked(...)` review produced `REQUEST_HUMAN_DECISION`;
   - no state with absent evidence in a required input produced either action. The required inputs checked were `assessed_commit`, `implementation`, `review`, required validation, required environment, acceptance, and finding status.

**Limitations.** The reducer is not proven equivalent to this SPEC:

- **Derived inputs.** Fixtures give I1–I14 already derived. The reducer does not apply 5.1 (choosing the assessed commit), the "several reviews" governing rule in 5.3, handoff-mismatch conflicts, or finding resolution across cycles. Those remain prose rules, checked only by review.
- **One representative per family of values.** Values that no cap or rule distinguishes are represented once:
  - I7 is omitted;
  - `failed(identified:<category>)` uses one category;
  - `blocked(...)` uses one status and reason.
- **`@none` notation.** Reading `@none` as "not determinable" is the notation defined in 9.1.
- **Who wrote it.** The encoding was written from the prose by the implementing session. An encoding error that mirrors a prose ambiguity would not be caught.

Unit U1's `test-assessment-fixtures.sh` performs structural checks only (AC-A5.2). No reducer is committed in v1 (D1, approved).

## 10. Implementation sequence

One unit per `/implement-spec`, sequential, each `standard` or higher, each independently reviewed. No unit authorizes the next.

| Unit | Delivers | Depends on | Validation |
| --- | --- | --- | --- |
| **U1** | `policies/verification-assessment.md`; the 9.1 fixtures in `examples/assessment/`; `integrations/opencode/scripts/test-assessment-fixtures.sh` | — | New test passes; existing four suites pass; no behavior change |
| **U2** | Template annotation conventions, two new lines, model/family wording (section 4) | U1 | `git diff` shows no removed fields; links resolve; suites pass |
| **U3** | `commands/assess-change.md`, `integrations/opencode/commands/assess.md`, manifest +1, `test-sync-install.sh` update, README install list | U1 | `test-sync-install.sh` (`NMAN=15`) and `test-doctor.sh` pass; manual `/assess` on S2, S4a and S4b inputs matches the fixtures |
| **U4** | OpenCode `/implement-spec` and orchestrator report integration; AGENTS.md and README workflow step; verify Decision Helper consistency with amended D7 (7.1) | U3 | Checkpoint/resolution/OpenCode stop wording diff-checked as unchanged by Phase A edits; AC-I.3/AC-I.5; suites pass; manual run shows the block and stops |
| **U5** | PRODUCT.md CURRENT STATE update; SPEC status → Implemented | U4 | Links resolve; content describes only implemented behavior |

**Recommended first unit:** U1. It is a pure contract plus tests and changes no runtime behavior.

## 11. Decisions, open questions, and risks

| ID | Item | Status |
| --- | --- | --- |
| D1 | Defer the deterministic reducer. v1 uses the Markdown decision contract, complete fixtures (9.1), and structural tests. Rationale: keeps v1 small; the rules are still reducible by hand and were checked with an out-of-repo reducer (9.2). Implications: U1's `test-assessment-fixtures.sh` stays structural (AC-A5.2); no reducer is committed; every unit's independent review still evaluates fixture behavior (readiness, decision, cited rule, `must_not_decide`) by hand or by an out-of-repo reducer | **Approved** by the user (decision closure after review cycle 4) |
| D2 | `/assess` uses the existing orchestrator agent in v1. Its read-only and no-delegation restrictions (5.4) are enforced by instruction, **not** by agent permissions. Rationale: no new agent or permission set in v1. Alternative not taken: a dedicated narrowly-permissioned agent like `doctor`. Implications: U3's `/assess` command and the policy state that the restrictions are instruction-based and not permission-level enforcement; a permission-enforced agent would need a new decision | **Approved** by the user (decision closure after review cycle 4) |
| D3 | Fixtures live in `examples/assessment/`; the structural test lives in `integrations/opencode/scripts/`. Rationale: all existing suites live there, although the contract is portable. Implications: U1 delivers the files at these paths (10) | **Approved** by the user (decision closure after review cycle 4) |
| D4 | `PREPARE_NEXT_UNIT` requires a recorded `[human]` acceptance of the current unit (6.2 rule 10). The recommendation never authorizes automatic implementation. Rationale: the next unit starts only by user choice. Implications: rule 10 and fixture S10 stand as written; preparing or starting the next unit still needs a new explicit user command (6.4) | **Approved** by the user (decision closure after review cycle 4) |
| D5 | Required environments are those named by acceptance criteria or project `AGENTS.md`; environment names remain project-defined. Rationale: Phase A defines no environment catalogue. Implications: I6/I7 (3.1) stand as written; fixture environment names (`production`, `supabase-test`) are illustrative | **Approved** by the user (decision closure after review cycle 4) |
| D6 | `docs/specs/` is the location for Phase A specifications | **Approved** by the user (review cycle 3 authorization) |
| D7 | Within a single `/implement-spec` authorization, the orchestrator may perform at most one bounded automatic remediation cycle when the initial independent review returns `CHANGES_REQUIRED` and every finding is eligible; after one attempt, any remaining `CHANGES_REQUIRED` requires a new user-initiated bounded unit (7.1). Amended by Supervised Execution U1; OpenCode contract changes owned by Supervised Execution U2; Phase A U4 verifies consistency | **Approved** by the user (review cycle 3 authorization); amended by Supervised Execution U1; implementation assigned to Supervised Execution U2 and Phase A U4 as described in 7.1 |

Risks:

- **LLM rule-application drift without a committed reducer.** Mitigation: a single-source policy, a total cap table, fixed output blocks, complete fixtures, and manual fixture checks in review.
- **Longer orchestrator reports.** Mitigation: fixed compact blocks, with `none` for empty fields.
- **Recommendation mistaken for authorization.** Mitigation: an explicit "advisory only — nothing has been executed" header, a Required authorization line, and no continuation or retry.
- **Portable/OpenCode stop semantics differ until Supervised Execution U2 updates the OpenCode contract to match amended D7.** Mitigation: 6.4.
- **Old evidence over-trusted.** Mitigation: commit-bound evidence and `stale`.
- **Every resolver block now requires a human decision, including simple setup failures.** This is deliberate: provenance cannot be re-established safely after the fact (6.2 rule 2). Expect more human prompts when setup is broken; `/doctor` remains the remedy for setup itself.
- **9Router attribution ambiguity remains** (a known limitation in [docs/PRODUCT.md](../PRODUCT.md)). Phase A surfaces it as a `blocked` review and does not resolve it.

## 12. Review cycle record

**Cycle 1:** `review-openai` on commit `7ae7ba9`, verdict `CHANGES_REQUIRED`. Disposition in revision 2, with the cycle-2 reviewer's status:

| ID | Severity | Finding (short) | Revision 2 disposition | Cycle-2 status |
| --- | --- | --- | --- | --- |
| R1 | blocking | Readiness not exhaustive | Partial fix | Still open → R2-1 |
| R2 | blocking | Handoff extension duplicated fields | Annotations on existing fields; two new lines | Resolved |
| R3 | blocking | Portable flow permits automatic remediation | Specified in 7.1; D7 amended by Supervised Execution U1; OpenCode contract changes owned by Supervised Execution U2 | Resolved |
| R4 | blocking | OTP fixture contradictory | S4a / S4b | Resolved |
| R5 | blocking | Staleness overbroad | Freshness by reviewed vs assessed commit | Resolved |
| R6 | non-blocking | Security fixture semantics | S5a / S5b | Resolved |
| R7 | non-blocking | Resolver blocks mapped too broadly | Setup vs judgment split | Still open → R2-3 |
| R8 | non-blocking | Model/family ownership | 4.3 | Resolved |
| R9 | non-blocking | D6 circular | D6 open | Resolved; D6 now approved |

**Cycle 2:** `review-openai` on commit `b207235`, verdict `CHANGES_REQUIRED`. Disposition in revision 3:

| ID | Severity | Finding (short) | Disposition |
| --- | --- | --- | --- |
| R2-1 | blocking | Readiness not total; `unknown` claims false | Fixed: inputs I1–I14 with closed domains and explicit absent-evidence values (3.1); a total single-rule cap table covering every value, including failure causes and finding status × severity (3.3); readiness output domain stated |
| R2-2 | blocking | Fixtures lack complete input state | Fixed: every fixture lists I1–I14 (as fixture keys), expected readiness, expected decision, rule references, and `must_not_decide`; reducibility checked (9.2) |
| R2-3 | blocking | Resolver retry could use changed evidence | Fixed: every `blocked(...)` review → `REQUEST_HUMAN_DECISION`; no retry or re-resolution recommendation (6.2 rule 2); S8b expectation changed accordingly |
| R2-4 | non-blocking | OF-1 overstated | Fixed: OF-1 now describes only the observed invocation (13) |

**Cycle 3:** `review-openai` on commit `ccb63b2`, verdict `CHANGES_REQUIRED`. It reported R2-1 and R2-4 resolved, and R2-2 and R2-3 still open through R3-1. Disposition in revision 4:

| ID | Severity | Finding (short) | Disposition |
| --- | --- | --- | --- |
| R3-1 | blocking | 5.3 made `blocked(...)@none` and `pending@none` `unknown`, contradicting S8a, S8b and S12; 9.2 overstated the reducer | Fixed: 5.3 applies freshness only to verdicts and keeps `blocked(...)`, `pending` and `not_required`; 9.1 defines `@none`; S8a, S8b and S12 citations name the kept state; 9.2 corrected and re-run with a targeted regression check |

**Cycle 4:** `review-openai` on commit `192c138` (revision 4), verdict `PASS`. It reported no blocking or non-blocking findings.

| ID | Status in cycle 4 |
| --- | --- |
| R3-1 | Resolved |
| R2-2, R2-3 | Resolved |
| R2-1, R2-4 | No regression |

Attribution:

- **Reviewer:** OpenAI family. The run was pinned with `--model 9router/review-openai`. The supporting runtime evidence is reported, not reproducible from this commit: the 9Router `usageHistory` rows in the review window all recorded `gpt-5.6-sol` with status `ok`, and the resolver returned `family=non-claude`.
- **Implementer:** Claude family, self-reported by the implementing session and not independently runtime-resolved.

## 13. Operational findings (outside Phase A scope)

**OF-1: observed unpinned reviewer invocation.**

- **When:** 2026-10-20, during review cycle 1 of this SPEC.
- **What ran:** `opencode run --standalone --agent review-openai`, invoked manually without `--model`.
- **Observed result:** that invocation ran on `9router/economy`. The CLI header read `review-openai · economy`, and 9Router `usageHistory` row 3629 recorded `deepseek-v4.1-flash`.
- **With the model pinned:** re-running with `--model 9router/review-openai` produced `gpt-5.6-sol` rows.
- **Relevant config:** the reviewer agents are configured with `"mode": "subagent"` and an explicit model (see [examples/opencode.json.example](../../examples/opencode.json.example)).
- **Evidence limits:** the header text and usage rows are session-local and cannot be reproduced from this commit. The observation does not establish whether other invocations, OpenCode versions, or orchestrator subagent delegation behave the same way; none of these were investigated.
- **Practice adopted for this SPEC's reviews:** pin the reviewer model and confirm the family from 9Router usage rows rather than from the agent name or header.

**OF-2: CLI hangs.** Two `opencode run` invocations during these reviews made no model calls before being stopped: one against the background service, and one standalone run of a different installed CLI version. They were not investigated. OpenCode CLI troubleshooting is outside this SPEC's scope.
