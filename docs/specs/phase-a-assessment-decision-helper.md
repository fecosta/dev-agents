# SPEC: Phase A — Post-Implementation Assessment & Decision Helper

- **Status:** Draft — design only, not implemented. Requires independent review (control-plane contract) and user approval before Unit U1 starts.
- **Baseline:** `main` at `9711baa` (equal to `origin/main` at drafting time).
- **Tier for implementing units:** at least `standard` (control-plane); independent opposite-family review required for every unit.
- **Authority:** subordinate to [AGENTS.md](../../AGENTS.md) and project-local instructions. Where this SPEC and an existing policy disagree, the existing policy wins until a unit of this SPEC changes it with review.

Paths written as code spans (for example `policies/verification-assessment.md`) are proposed files that do not exist yet. Paths written as links exist today.

## 0. Purpose and non-goals

The existing workflow stops after the first review verdict ([agents/orchestrator.md](../../integrations/opencode/agents/orchestrator.md), "Review decision"). It does not say what was actually verified or what to do next. In the Huellas authentication work, several things went wrong:

- Passing tests and a `PASS` verdict were treated as "done" while production and security checks were still pending.
- Test-fixture failures looked like application defects.
- Findings from different review cycles were mixed together.

Phase A adds four things:

1. A verification-state contract (A1).
2. An optional evidence extension to the handoff (A2).
3. A read-only post-implementation assessment (A3).
4. An advisory-only Decision Helper that recommends exactly one next action and executes nothing (A4).

Non-goals:

- Implementing anything in this document's own change.
- Changing routing, model resolution, reviewer selection, checkpoints, or review verdict semantics.
- Autonomous continuation, deployment automation, persistent telemetry, retrospectives, debugging automation.
- Changes to external project repositories.

## 1. Current-state architecture assessment

| Area | What exists today | Source |
| --- | --- | --- |
| Authority and workflow | Authority order; 12-step core workflow ending at the phase/SPEC boundary | [AGENTS.md](../../AGENTS.md) |
| Routing | `economy` / `standard` / `strong` / `premium`; control-plane minimum `standard` | [policies/model-routing.md](../../policies/model-routing.md), [commands/route-task.md](../../commands/route-task.md) |
| Bounded units | Vertical slices, one unit per `/implement-spec`, no automatic continuation | [commands/split-spec.md](../../commands/split-spec.md) |
| Implementation flow | Start/end checkpoints (mandatory), delegation, review decision, runtime family resolution, fail-closed reasons, report fields, stop after first verdict | [integrations/opencode/commands/implement-spec.md](../../integrations/opencode/commands/implement-spec.md), [agents/orchestrator.md](../../integrations/opencode/agents/orchestrator.md) |
| Runtime provenance | `review-route.sh` checkpoint/resolve; `resolve-model-family.sh` key=value contract | [integrations/opencode/README.md](../../integrations/opencode/README.md) |
| Review | Opposite-family reviewer; verdicts `PASS` / `PASS_WITH_NOTES` / `CHANGES_REQUIRED`; blocking / non-blocking findings | [policies/review-routing.md](../../policies/review-routing.md), [templates/review-report.md](../../templates/review-report.md), [commands/review-change.md](../../commands/review-change.md) |
| Handoff (template) | Unit, start/result commit, tier, model/family, reviewer, files, tests, lint/build, risks, next phase | [templates/implementation-handoff.md](../../templates/implementation-handoff.md) |
| Handoff (command) | `/handoff`: fixed six-section close-out (`Completed unit`, `Validation`, `Repository state`, `Changed areas`, `Unresolved`, `Next fresh-session task`); structure asserted by `test-sync-install.sh` | [integrations/opencode/commands/handoff.md](../../integrations/opencode/commands/handoff.md) |
| Install / health | `sync-install.sh` hard-coded 14-entry manifest (mirrored in `test-sync-install.sh` `NMAN=14` and the README install list); `doctor.sh` `command_sync` covers every `commands/*.md` automatically, `installed_commands` requires a fixed four | [integrations/opencode/scripts/sync-install.sh](../../integrations/opencode/scripts/sync-install.sh), [integrations/opencode/scripts/doctor.sh](../../integrations/opencode/scripts/doctor.sh) |
| Product record | CURRENT STATE / DECISIONS / FUTURE VISION | [docs/PRODUCT.md](../PRODUCT.md) |

No SPEC convention existed before this document; earlier SPECs were task prompts. This SPEC establishes `docs/specs/` as the location.

## 2. Gap analysis

| Need | Existing behavior | Gap | Phase A response |
| --- | --- | --- | --- |
| Distinguish implementation, validation, review, environment verification, readiness | Report fields cover implementation result, validation result, verdict | No environment dimension, no per-criterion status, no derived readiness | A1 state contract |
| Partial verification and missing evidence | "Not run" wording in `/handoff`; fail-closed resolver reasons | No uniform `unknown` / `pending` representation | A1 `unknown` and `pending` everywhere; fail closed |
| Observed vs asserted evidence | Orchestrator does not trust child self-reported family | No general labeling for other evidence | A1 evidence labels |
| Finding identity across review cycles | Free-text findings per report | Cycle-2 findings can be confused with cycle-1 findings | A2 finding IDs `R<cycle>-<n>` |
| Interpreting results into a next action | Orchestrator stops; human interprets | No structured recommendation | A3 assessment + A4 Decision Helper |
| Re-assessment after out-of-band evidence (e.g. production check) | None | No entry point | `/assess` command |
| Handoff model/family fields | Template has "Actual implementation model/family"; orchestrator forbids child self-report | Ambiguous ownership | A2 clarification: filled only from resolver output |

Not gaps (reused unchanged): checkpoints, resolver, reviewer selection, verdict set, Git safety, `/handoff` output structure, doctor and sync-install behavior apart from one manifest entry.

## 3. A1 — Verification-state contract

### 3.1 Dimensions

Each dimension is recorded independently. They are never collapsed into a single PASS/FAIL.

| Dimension | Values | Notes |
| --- | --- | --- |
| `implementation` | `complete`, `incomplete`, `none`, `unknown` | Whether the bounded unit's changes exist at a known commit |
| `validation` (per required check) | `passed`, `failed`, `partial`, `not_run`, `unknown` | One entry per check the SPEC/project requires (tests, typecheck, lint, build, other) |
| `review` | `PASS`, `PASS_WITH_NOTES`, `CHANGES_REQUIRED` (verbatim), or `not_required`, `pending`, `stale`, `blocked`, `unknown` | Bound to `{cycle, reviewed_commit}`. `blocked` carries the existing status and reason unchanged (e.g. `REVIEW_BLOCKED_MODEL_RESOLUTION` + `MODEL_DETECTION_AMBIGUOUS`). `stale` = reviewed commit is not the assessed commit |
| `environments[]` | `verified`, `pending`, `failed`, `not_applicable`, `unknown` | Environment names are project-defined (e.g. `local`, `ci`, `preview`, `production`), taken from project `AGENTS.md` or the SPEC |
| `acceptance[]` | `met`, `unverified`, `not_met`, `needs_human_decision` | One entry per acceptance criterion; tagged `functional`, `user-facing`, `security`, `data`, or `other` |
| `readiness` (derived) | `blocked`, `not_ready`, `needs_human_decision`, `ready_with_notes`, `ready` | Never set directly; computed by 3.3 |

A required item with no evidence is `unknown` (or `not_run` for validation, `pending` for environments). It is never assumed to be satisfied.

### 3.2 Evidence labels

Every evidence item carries exactly one label:

- `[observed]`: the assessor inspected it in the current session. Examples: `git rev-parse`, `git log`, `git status`, or a review report file read directly.
- `[reported]`: stated in another agent's output (implementation child, reviewer, `/handoff`, or an orchestrator report from another session).
- `[human]`: stated by the user.

An assessor may upgrade `[reported]` to `[observed]` only by re-inspecting the fact read-only. It never re-runs tests (they may have side effects; see 5.4). Recommendations are not evidence and are never labeled as such.

### 3.3 Readiness derivation

Rules are applied in order; the first match wins. Readiness is scoped to closing the current bounded unit against its own acceptance criteria.

1. **`blocked`**: core evidence is `unknown`, ambiguous, or conflicting. This covers:
   - `implementation` unknown;
   - review required but `pending`, `stale`, `blocked`, or `unknown`;
   - a conflict listed under 5.3 that cannot be resolved from the authority order.
2. **`not_ready`**: any of:
   - a required validation `failed`, `partial`, or `not_run`;
   - review is `CHANGES_REQUIRED`;
   - an open blocking finding;
   - an acceptance criterion `not_met` or `unverified`;
   - a required environment `failed` or `pending`.
3. **`needs_human_decision`**: all technical gates are satisfied, but at least one acceptance criterion is `needs_human_decision`, for example security or product sign-off.
4. **`ready_with_notes`**: review is `PASS_WITH_NOTES`, or there are open non-blocking findings.
5. **`ready`**: everything else.

### 3.4 Relationship to existing review verdicts

| Verdict / status | Review gate | Readiness cap | Can yield `ACCEPT_UNIT` |
| --- | --- | --- | --- |
| `PASS` | satisfied for `reviewed_commit` only | none | yes |
| `PASS_WITH_NOTES` | satisfied for `reviewed_commit` only; notes become non-blocking findings | `ready_with_notes` | yes |
| `CHANGES_REQUIRED` | failed | `not_ready` | **never** |
| `REVIEW_BLOCKED_MODEL_RESOLUTION` (any reason) | not satisfied; existing fail-closed semantics unchanged | `blocked` | never |
| `Independent review: not required` | satisfied by the orchestrator's existing decision | none | yes |

Verdict text is copied verbatim and never rewritten, softened, or reinterpreted. The assessment adds no new verdicts, and the reviewer still returns exactly one of the three.

## 4. A2 — Structured evidence handoff

### 4.1 Evaluation of the current template

[templates/implementation-handoff.md](../../templates/implementation-handoff.md) already covers:

- the bounded unit;
- starting and resulting Git state;
- tier and provenance fields;
- tests and checks run;
- unresolved risks;
- the next phase.

These fields are reused as-is. Three things are missing: acceptance-criterion status, environment verification, and evidence labels and finding identity.

### 4.2 Extension (optional, backward compatible)

Append one optional section to the template. No existing field is renamed or removed.

```markdown
## Verification evidence (optional; see policies/verification-assessment.md)
- Acceptance criteria: <AC-id> — met|unverified|not_met|needs_human_decision — [observed|reported|human] <evidence>
- Validation: <command> — passed|failed|partial|not_run — [label] <result summary>
- Environment verification: <env> — verified|pending|failed|not_applicable — [label] <evidence / who>
- Open findings: <R<cycle>-<n> or I-<n>> — blocking|non-blocking — <source> — <one line>
- Unknowns:
- Suggested next step (implementer, non-authoritative):
```

Clarification of existing fields (no behavior change):

- "Actual implementation model" and "Actual model family" are filled only from the orchestrator's resolver output.
- When resolution was skipped they read `skipped (independent review not required)`, and when blocked they read `blocked (<reason>)`.
- The implementation child never self-reports them, as already required by [agents/orchestrator.md](../../integrations/opencode/agents/orchestrator.md).

Optional additions to [templates/review-report.md](../../templates/review-report.md):

- Finding IDs `R<cycle>-<n>` on each blocking and non-blocking finding.
- One line `Prior findings status: <id> — resolved|still open|not re-checked`.

The verdict line is unchanged.

`/handoff` output is unchanged in Phase A. `/assess` reads it as `[reported]` evidence and maps its sections as follows:

- `Validation` maps to validation.
- `Repository state` maps to implementation and Git.
- `Unresolved` maps to findings and unknowns.

### 4.3 Backward compatibility

A handoff without the new section is still valid. The new dimensions assess as `unknown`, so readiness is at most `blocked` and the Decision Helper recommends `VERIFY_FURTHER`. Old handoffs therefore fail closed: they are never treated as verified, and nothing breaks.

## 5. A3 — Post-implementation assessment

### 5.1 Inputs, in authority order

1. The authoritative SPEC/task and its acceptance criteria.
2. Git state `[observed]`: branch, `HEAD`, `git status`, and `git log` for the unit range.
3. The latest review report whose `reviewed_commit` equals the assessed commit.
4. The orchestrator report: checkpoints, model resolution, review decision.
5. The implementation handoff or `/handoff` output `[reported]`.
6. User statements `[human]`, for example "I verified login in production".

### 5.2 Output block (fixed structure)

```text
Assessment:
- Unit:
- Assessed commit:
- Evidence basis: <source — label>, ...
- Implementation:
- Validation:
- Review: <verbatim verdict | not_required | pending | stale | blocked (<status>, <reason>)> (cycle <n>, commit <sha>)
- Environments:
- Requirements completed:
- Requirements unverified:
- Blocking findings:
- Non-blocking findings:
- Missing evidence:
- Conflicts:
- Human decisions required:
- Readiness: <value> — <one-line reason>
```

Empty lists are written `none`, never omitted.

### 5.3 Conflicting or incomplete evidence

- **Reviewer vs implementer:** the reviewer's verdict governs the review dimension. Implementer claims stay `[reported]`.
- **Commit mismatch:** if the handoff commit, the reviewed commit, and `HEAD` disagree, review becomes `stale` and readiness `blocked`. Both SHAs are listed under Conflicts.
- **Review cycles:** only the latest review of the assessed commit governs.
  - New findings get new IDs.
  - A finding is `resolved` only when a later review confirms it, never on the implementer's word.
  - Resolved findings are reopened only if a later review restates them.
- **Unexplained failure:** a failed validation whose cause is not established is classified `unexplained`. Hypotheses are listed (application defect, infrastructure, test fixture/data, environment), and the failure is never treated as an application defect without evidence.
- **Disagreement with a verdict:** the assessor may record a Conflict and require a human decision. It never overrides or reinterprets the verdict.
- **Insufficient evidence:** missing items go under Missing evidence and set the dimension to `unknown`. Nothing is inferred.

### 5.4 Read-only boundary

Assessment never:

- edits files;
- runs validation or tests;
- delegates to any agent;
- runs Git write commands;
- contacts deployed environments.

Allowed shell use is read-only Git inspection only.

## 6. A4 — Advisory-only Decision Helper

### 6.1 Action set (closed)

Exactly one is recommended per assessment.

| Action | Meaning |
| --- | --- |
| `ACCEPT_UNIT` | Ask the user to accept the completed bounded unit |
| `REMEDIATE_FINDINGS` | Fix identified findings or unmet criteria with a known cause (scoped to listed IDs) |
| `VERIFY_FURTHER` | Obtain missing verification: re-run validation, independent review or re-review, environment check |
| `INVESTIGATE_FAILURE` | Establish the cause of an unexplained failure before any remediation |
| `RECONCILE_DOCS` | Bring SPEC/doc state in line with the repository (e.g. SPEC status, PRODUCT.md current state) |
| `PREPARE_NEXT_UNIT` | Prepare the next unit of an approved split; only after `[human]` acceptance of the current unit |
| `REQUEST_HUMAN_DECISION` | A product, security, release, or conflict judgment only the user can make |

### 6.2 Decision rules (first match wins)

1. Readiness `blocked` by a conflict needing judgment, or by `REVIEW_BLOCKED_MODEL_RESOLUTION`: `REQUEST_HUMAN_DECISION`. The existing fail-closed semantics are kept: never guess a family.
2. Readiness `blocked` by missing or stale evidence that can be obtained: `VERIFY_FURTHER`.
3. An `unexplained` failure: `INVESTIGATE_FAILURE`.
4. `CHANGES_REQUIRED`, an open blocking finding, or an acceptance criterion `not_met` with a known cause: `REMEDIATE_FINDINGS`.
5. A required environment or acceptance criterion `pending` or `unverified`: `VERIFY_FURTHER`.
6. An acceptance criterion `needs_human_decision`: `REQUEST_HUMAN_DECISION`.
7. SPEC or documentation state out of sync with the repository: `RECONCILE_DOCS`.
8. Readiness `ready` or `ready_with_notes`: `ACCEPT_UNIT`, or `PREPARE_NEXT_UNIT` if a `[human]` acceptance of this unit is already recorded and an approved split has a next unit.

### 6.3 Output block

```text
Decision Helper (advisory only — nothing has been executed):
- Recommended action: <ACTION> — <one line>
- Rationale:
- Supporting evidence: <item — label>, ...
- Unresolved risks:
- Prerequisites:
- Required authorization: <who must authorize what, e.g. "user runs /implement-spec for R2-1..R2-3">
- Evidence limitations / confidence: high|medium|low — <why>
- Why not ACCEPT_UNIT: <only when another action is recommended>
```

### 6.4 Hard rules

- The Decision Helper never executes, delegates, or schedules its recommendation. The turn ends after the block.
- Each next action requires a new explicit user command, for example `/implement-spec` for remediation or `/review-change` for re-review.
- It never initiates implementation, push, merge, deployment, history rewrite, or production changes. These may appear only as steps the user performs, with the required explicit authorization named.
- It does not change the existing "stop after the first review verdict" rule. It runs after that point and stops.

## 7. Integration architecture (minimal)

| Change | File(s) | Kind |
| --- | --- | --- |
| Portable contract: dimensions, labels, readiness rules, verdict mapping, action set, decision rules. Single source; other files reference it | `policies/verification-assessment.md` (new) | control-plane |
| Portable procedure for assessment + Decision Helper | `commands/assess-change.md` (new) | control-plane |
| OpenCode `/assess` command: `agent: orchestrator`, `subagent: false`; text forbids delegation, edits, validation runs, Git writes; emits 5.2 + 6.3 | `integrations/opencode/commands/assess.md` (new) | control-plane |
| Final report appends the Assessment and Decision Helper blocks (also for blocked outcomes); "stop" unchanged | [commands/implement-spec.md](../../commands/implement-spec.md), [integrations/opencode/commands/implement-spec.md](../../integrations/opencode/commands/implement-spec.md) step 18, [agents/orchestrator.md](../../integrations/opencode/agents/orchestrator.md) "Orchestration report fields" | control-plane |
| Manifest +`commands/assess.md`; `NMAN` 14→15 plus an assess block modeled on the handoff block; README install list 14→15 | [sync-install.sh](../../integrations/opencode/scripts/sync-install.sh), [test-sync-install.sh](../../integrations/opencode/scripts/test-sync-install.sh), [integrations/opencode/README.md](../../integrations/opencode/README.md) | control-plane |
| Optional template sections (section 4) | [templates/implementation-handoff.md](../../templates/implementation-handoff.md), [templates/review-report.md](../../templates/review-report.md) | contract |
| One workflow step: "Assess verification state and record an advisory next-action recommendation; do not execute it." | [AGENTS.md](../../AGENTS.md), [README.md](../../README.md) | control-plane |
| CURRENT STATE capability list (final unit only) | [docs/PRODUCT.md](../PRODUCT.md) | product record |

Unchanged:

- routing policy;
- checkpoints;
- `review-route.sh` and `resolve-model-family.sh`;
- reviewer selection;
- the verdict set;
- `/handoff` output;
- `doctor.sh` (`command_sync` already covers new command files; `installed_commands` keeps its required four, so `assess.md` is optional for health);
- `/doctor` and `/sync-install` agents.

Portability: the contract and procedure live in `policies/` and `commands/` and do not depend on OpenCode. The OpenCode command is a thin adapter, consistent with the existing split.

## 8. Acceptance criteria

**A1 — State contract (`policies/verification-assessment.md`)**

- AC-A1.1 Defines the six dimensions, value sets, and evidence labels exactly as in section 3.
- AC-A1.2 Defines readiness by the ordered rules in 3.3, with `unknown` never satisfying a requirement.
- AC-A1.3 Contains the verdict mapping in 3.4. `CHANGES_REQUIRED` and `REVIEW_BLOCKED_MODEL_RESOLUTION` cannot yield `ACCEPT_UNIT`.
- AC-A1.4 States that verdict text and existing block statuses/reasons are passed through verbatim.

**A2 — Evidence handoff**

- AC-A2.1 The handoff template gains only the optional section in 4.2. Existing lines are unchanged.
- AC-A2.2 The template states that model/family fields come from resolver output only.
- AC-A2.3 The review template gains optional finding IDs and a `Prior findings status:` line. The verdict line is unchanged.
- AC-A2.4 The policy states that a handoff without the section assesses as `unknown` and fails closed.

**A3 — Assessment**

- AC-A3.1 The procedure emits the 5.2 block with every field present (`none` when empty).
- AC-A3.2 The procedure lists the input authority order (5.1) and the conflict rules (5.3), including stale-review and finding-identity rules.
- AC-A3.3 The procedure and `/assess` state the read-only boundary in 5.4.

**A4 — Decision Helper**

- AC-A4.1 The action set is closed (6.1), and exactly one action is recommended.
- AC-A4.2 Decision rules match 6.2.
- AC-A4.3 The output block matches 6.3, including Required authorization.
- AC-A4.4 `/assess`, `/implement-spec`, and the orchestrator state that the recommendation is never executed, and that push/merge/deploy/history rewrite/production changes are never initiated.

**Integration**

- AC-I.1 `sync-install.sh` manifest contains `commands/assess.md`; `test-sync-install.sh` passes with `NMAN=15` and an assess block.
- AC-I.2 `test-doctor.sh`, `test-review-route.sh`, and `test-resolve-model-family.sh` pass unchanged.
- AC-I.3 The `/implement-spec` step 19 and orchestrator "stop after the first verdict" wording is unchanged.
- AC-I.4 Checkpoint and resolution wording is unchanged.

**A5 — Regression scenarios**

- AC-A5.1 Fixtures S1–S8 (section 9) exist, each labeled with its basis.
- AC-A5.2 `test-assessment-fixtures.sh` checks:
  - required keys;
  - enum values against the policy file;
  - `ACCEPT_UNIT` only with readiness `ready`/`ready_with_notes`;
  - never `ACCEPT_UNIT` with `CHANGES_REQUIRED` or a blocked review;
  - `expected_decision` not in `must_not_decide`.

## 9. Historical regression scenarios (A5)

**Basis:** no execution records from the Huellas repository are available in this repository. Each scenario below is an **assumption-based fixture** derived from the summary in the task brief, not a historical record. The fixture files must carry `basis: assumption-based fixture (not a historical record)`.

Fixture format (`examples/assessment/S<n>-<slug>.md`, Markdown with a key: value header the structural test reads):

```text
fixture: S4-otp-fixture-failure
basis: assumption-based fixture (not a historical record)
review: <verdict or status>
expected_readiness: not_ready
expected_decision: INVESTIGATE_FAILURE
must_not_decide: ACCEPT_UNIT, REMEDIATE_FINDINGS
```

The header is followed by the input evidence (handoff excerpt, review report excerpt, Git facts) and the expected Assessment block.

| ID | Scenario | Key evidence (fixture) | Expected readiness | Expected decision | Must not decide |
| --- | --- | --- | --- | --- | --- |
| S1 | Repository bootstrap after multiple review cycles | Cycle 1 and 2 `CHANGES_REQUIRED` (R1-\*, R2-\*); cycle 3 `PASS` on `HEAD`; prior findings confirmed resolved by cycle 3; validation passed | `ready` | `ACCEPT_UNIT` | `REMEDIATE_FINDINGS` |
| S2 | Auth implemented; production verification incomplete | Validation passed; review `PASS`; AC "login works in production" `unverified`; `production` `pending` | `not_ready` | `VERIFY_FURTHER` (authorization: user performs or authorizes the production check) | `ACCEPT_UNIT` |
| S3 | Logout remediation | Technical logout exists, tests pass; user-facing AC (e.g. confirmation/redirect wording) `not_met` per review | `not_ready` | `REMEDIATE_FINDINGS` (scoped to that AC) | `ACCEPT_UNIT` |
| S4 | OTP failure that is a test-fixture problem | OTP integration test fails; cause unestablished; hypotheses: fixture/data, provider infra, app defect | `not_ready` | `INVESTIGATE_FAILURE` | `ACCEPT_UNIT`, `REMEDIATE_FINDINGS` |
| S5 | Security exposure verification pending | Functional ACs `met`, review `PASS`; security AC (e.g. no exposed secrets/keys in client) `needs_human_decision` | `needs_human_decision` | `REQUEST_HUMAN_DECISION` | `ACCEPT_UNIT` |
| S6 | New review findings vs resolved findings | Cycle 2 `CHANGES_REQUIRED` with new R2-1..R2-2; R1-\* marked resolved by cycle 2 | `not_ready` | `REMEDIATE_FINDINGS` scoped to R2-\* only; R1-\* not reopened | `ACCEPT_UNIT` |
| S7 | Fail closed: old-format handoff | Handoff without Verification evidence section; no AC or environment data | `blocked` | `VERIFY_FURTHER` | `ACCEPT_UNIT` |
| S8 | Fail closed: review blocked | `REVIEW_BLOCKED_MODEL_RESOLUTION`, reason `MODEL_DETECTION_AMBIGUOUS` | `blocked` | `REQUEST_HUMAN_DECISION` | `ACCEPT_UNIT`, `VERIFY_FURTHER` with a guessed reviewer |

The structural test validates the fixtures' internal consistency against the policy. It does not run an LLM. Behavioral checking of an orchestrator's assessment against these fixtures is a manual step in each unit's review until a deterministic reducer exists (open decision D1).

## 10. Implementation sequence

One unit per `/implement-spec`, sequential, each `standard` or higher, each independently reviewed. No unit authorizes the next.

| Unit | Delivers | Depends on | Validation |
| --- | --- | --- | --- |
| **U1** | `policies/verification-assessment.md`; fixtures S1–S8 in `examples/assessment/`; `integrations/opencode/scripts/test-assessment-fixtures.sh` | — | New test passes; existing four suites pass; no behavior change |
| **U2** | Template extensions (section 4) | U1 | `git diff` shows additions only; links resolve; suites pass |
| **U3** | `commands/assess-change.md`, `integrations/opencode/commands/assess.md`, manifest +1, `test-sync-install.sh` update, README install list | U1 | `test-sync-install.sh` (`NMAN=15`) and `test-doctor.sh` pass; manual `/assess` on S2 and S4 inputs matches the fixtures |
| **U4** | `/implement-spec` (portable + OpenCode) and orchestrator report integration; AGENTS.md and README workflow step | U3 | Checkpoint/resolution/stop wording diff-checked as unchanged; suites pass; manual run shows the block and stops |
| **U5** | PRODUCT.md CURRENT STATE update; SPEC status → Implemented | U4 | Links resolve; content describes only implemented behavior |

**Recommended first unit:** U1. It is a pure contract plus tests and changes no runtime behavior.

## 11. Risks, open questions, and decisions requiring approval

| ID | Item | Default in this SPEC |
| --- | --- | --- |
| D1 | Deterministic reducer script (key=value in, readiness + decision out) to make rules executable | Deferred; Markdown contract + structural fixture test (user decision) |
| D2 | `/assess` runs on the orchestrator agent, so "no delegation" is enforced by instruction rather than permissions. Alternative: a dedicated narrowly-permissioned agent like `doctor` | Orchestrator agent; revisit if review finds it insufficient |
| D3 | Fixture location `examples/assessment/` and test in `integrations/opencode/scripts/` (where all suites live), though the contract is portable | As stated |
| D4 | `PREPARE_NEXT_UNIT` requires a recorded `[human]` acceptance of the current unit | Required |
| D5 | Environment names are project-defined; projects without a definition get only `local`/`ci` as known environments, with others `unknown` | As stated |
| D6 | Approve `docs/specs/` as the SPEC location convention | Approved by this SPEC's acceptance |

Risks:

- **LLM rule-application drift without a reducer.** Mitigation: a single-source policy, fixed output blocks, fixtures, and manual fixture checks in review.
- **Longer orchestrator reports.** Mitigation: fixed compact blocks, with `none` for empty fields.
- **Recommendation mistaken for authorization.** Mitigation: an explicit "advisory only — nothing has been executed" header, a Required authorization line, and no continuation.
- **Old evidence over-trusted.** Mitigation: commit binding and `stale`.
- **9Router attribution ambiguity remains** (a known limitation in [docs/PRODUCT.md](../PRODUCT.md)). Phase A surfaces it as `blocked` review and does not resolve it.
