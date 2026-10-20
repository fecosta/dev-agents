# SPEC: Phase A — Post-Implementation Assessment & Decision Helper

- **Status:** Draft, revision 2. Design only, not implemented. Revision 2 addresses review cycle 1 (findings R1–R9, see section 12). Requires a fresh independent review (control-plane contract) and user approval before Unit U1 starts.
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
- Autonomous continuation, deployment automation, persistent telemetry, retrospectives, debugging automation.
- Changes to external project repositories.

## 1. Current-state architecture assessment

| Area | What exists today | Source |
| --- | --- | --- |
| Authority and workflow | Authority order; 12-step core workflow ending at the phase/SPEC boundary. Step 11 describes a fix → validate → commit → re-review loop | [AGENTS.md](../../AGENTS.md) |
| Routing | `economy` / `standard` / `strong` / `premium`; control-plane minimum `standard` | [policies/model-routing.md](../../policies/model-routing.md), [commands/route-task.md](../../commands/route-task.md) |
| Bounded units | Vertical slices, one unit per `/implement-spec`, no automatic continuation | [commands/split-spec.md](../../commands/split-spec.md) |
| Implementation flow (portable) | Step 14: "If `CHANGES_REQUIRED`, route fixes, validate, commit, and re-review" | [commands/implement-spec.md](../../commands/implement-spec.md) |
| Implementation flow (OpenCode) | Start/end checkpoints (mandatory), delegation, review decision, runtime family resolution, fail-closed reasons, report fields; "Do not automatically remediate CHANGES_REQUIRED. Stop after the first verdict." | [integrations/opencode/commands/implement-spec.md](../../integrations/opencode/commands/implement-spec.md), [agents/orchestrator.md](../../integrations/opencode/agents/orchestrator.md) |
| Runtime provenance | `review-route.sh` checkpoint/resolve; `resolve-model-family.sh` key=value contract with documented block reasons | [integrations/opencode/README.md](../../integrations/opencode/README.md), [resolve-model-family.sh](../../integrations/opencode/scripts/resolve-model-family.sh) |
| Review | Opposite-family reviewer; verdicts `PASS` / `PASS_WITH_NOTES` / `CHANGES_REQUIRED`; blocking / non-blocking findings | [policies/review-routing.md](../../policies/review-routing.md), [templates/review-report.md](../../templates/review-report.md), [commands/review-change.md](../../commands/review-change.md) |
| Handoff (template) | Unit, start/result commit, tier, model/family, reviewer, files, tests, lint/build, risks, next phase | [templates/implementation-handoff.md](../../templates/implementation-handoff.md) |
| Handoff (command) | `/handoff`: fixed six-section close-out (`Completed unit`, `Validation`, `Repository state`, `Changed areas`, `Unresolved`, `Next fresh-session task`); structure asserted by `test-sync-install.sh` | [integrations/opencode/commands/handoff.md](../../integrations/opencode/commands/handoff.md) |
| Install / health | `sync-install.sh` hard-coded 14-entry manifest (mirrored in `test-sync-install.sh` `NMAN=14` and the README install list); `doctor.sh` `command_sync` covers every `commands/*.md` automatically, while `installed_commands` requires a fixed four | [integrations/opencode/scripts/sync-install.sh](../../integrations/opencode/scripts/sync-install.sh), [integrations/opencode/scripts/doctor.sh](../../integrations/opencode/scripts/doctor.sh) |
| Product record | CURRENT STATE / DECISIONS / FUTURE VISION | [docs/PRODUCT.md](../PRODUCT.md) |

No SPEC convention existed before this document; earlier SPECs were task prompts. This SPEC *proposes* `docs/specs/` as the location (open decision D6).

## 2. Gap analysis

| Need | Existing behavior | Gap | Phase A response |
| --- | --- | --- | --- |
| Distinguish implementation, validation, review, environment verification, readiness | Report fields cover implementation result, validation result, verdict | No environment dimension, no per-criterion status, no derived readiness | A1 state contract |
| Partial verification and missing evidence | "Not run" wording in `/handoff`; fail-closed resolver reasons | No uniform `unknown` / `pending` representation | A1: every dimension has `unknown`; fail closed |
| Observed vs asserted evidence | Orchestrator does not trust child self-reported family | No general labeling for other evidence | A1 evidence labels |
| Finding identity across review cycles | Free-text findings per report | Cycle-2 findings can be confused with cycle-1 findings | A2 finding IDs `R<cycle>-<n>` |
| Interpreting results into a next action | OpenCode orchestrator stops; human interprets. Portable command loops into remediation | No structured recommendation; portable/OpenCode stop semantics differ | A3 assessment + A4 Decision Helper; reconciliation decision D7 |
| Re-assessment after out-of-band evidence (e.g. a production check) | None | No entry point | `/assess` command |
| Handoff model/family fields | Template has "Actual implementation model/family", but the child returns its handoff before resolution runs, and the orchestrator forbids child self-report | Ambiguous ownership | A2: child writes `pending`; orchestrator report is authoritative (4.3) |

Not gaps (reused unchanged): checkpoints, resolver, reviewer selection, verdict set, Git safety, `/handoff` output structure, doctor and sync-install behavior apart from one manifest entry.

## 3. A1 — Verification-state contract

### 3.1 Dimensions

Each dimension is recorded independently. They are never collapsed into a single PASS/FAIL. Every dimension has an `unknown` value, used whenever evidence is absent or cannot be tied to the assessed commit.

| Dimension | Values | Notes |
| --- | --- | --- |
| `implementation` | `complete`, `incomplete`, `none`, `unknown` | Whether the bounded unit's changes exist at the assessed commit |
| `validation` (per check) | `passed`, `failed`, `partial`, `not_run`, `unknown` | One entry per check. *Required* checks come from the SPEC/task and project `AGENTS.md`. Evidence is bound to a commit (see 5.3) |
| `review` | `PASS`, `PASS_WITH_NOTES`, `CHANGES_REQUIRED` (verbatim), or `not_required`, `pending`, `stale`, `blocked`, `unknown` | Bound to `{cycle, reviewed_commit}`. `stale` and freshness are defined in 5.3. `blocked` carries the existing status and reason unchanged (e.g. `REVIEW_BLOCKED_MODEL_RESOLUTION` + `MODEL_DETECTION_AMBIGUOUS`). `unknown` also covers "whether review is required is unknown" |
| `environments[]` | `verified`, `pending`, `failed`, `not_applicable`, `unknown` | Names are project-defined (e.g. `local`, `ci`, `preview`, `production`). *Required* environments are those named by an acceptance criterion or by project `AGENTS.md` |
| `acceptance[]` | `met`, `unverified`, `not_met`, `needs_human_decision`, `unknown` | One entry per acceptance criterion, tagged `functional`, `user-facing`, `security`, `data`, or `other`. If the SPEC/task's acceptance criteria cannot be located, a single entry `AC-? — unknown` is recorded |
| `failures[]` | each failed validation/environment carries `cause: unexplained` or `cause: identified(<category>)` | Categories: `application`, `test-fixture`, `infrastructure`, `environment`, `other`. `identified` requires cited evidence |
| `findings[]` | `R<cycle>-<n>` (review) or `I-<n>` (implementer/assessor); `blocking` or `non-blocking`; `open` or `resolved` | Resolution rules in 5.3 |
| `readiness` (derived) | `blocked`, `not_ready`, `needs_human_decision`, `ready_with_notes`, `ready` | Never set directly; computed by 3.3 |

When to use `needs_human_decision` vs `unverified`:

- **`needs_human_decision`** is only for criteria whose satisfaction is a judgment, such as accepting a residual security risk or a product/release sign-off. The required authority (e.g. "project owner", "security owner") must be named.
- **`unverified`** is for objectively checkable conditions that have not been checked yet, for example "no service-role key in the client bundle".

### 3.2 Evidence labels

Every evidence item carries exactly one label:

- `[observed]`: the assessor inspected it in the current session. Examples: `git rev-parse`, `git log`, `git status`, or a review report file read directly.
- `[reported]`: stated in another agent's output (implementation child, reviewer, `/handoff`, or an orchestrator report from another session).
- `[human]`: stated by the user.

An assessor may upgrade `[reported]` to `[observed]` only by re-inspecting the fact read-only. It never re-runs tests (see 5.4). Recommendations are not evidence and are never labeled as such.

### 3.3 Readiness derivation (exhaustive)

Each dimension value imposes a *cap*. Readiness is the most severe cap present, with severity ordered `blocked` > `not_ready` > `needs_human_decision` > `ready_with_notes`. If no cap applies, readiness is `ready`. Every value in 3.1 appears in this table, so the derivation is total.

| Dimension | Value | Cap |
| --- | --- | --- |
| `implementation` | `complete` | none |
| | `incomplete`, `none` | `not_ready` |
| | `unknown` | `blocked` |
| `validation` (required check) | `passed` | none |
| | `failed`, `partial`, `not_run` | `not_ready` |
| | `unknown` | `blocked` |
| `validation` (non-required check) | `failed`, `partial` | `ready_with_notes` (recorded as a non-blocking finding) |
| | `passed`, `not_run`, `unknown` | none |
| `review` | `PASS`, `not_required` | none |
| | `PASS_WITH_NOTES` | `ready_with_notes` |
| | `CHANGES_REQUIRED` | `not_ready` |
| | `pending`, `stale`, `blocked`, `unknown` | `blocked` |
| `environments[]` (required) | `verified`, `not_applicable` | none |
| | `pending`, `failed` | `not_ready` |
| | `unknown` | `blocked` |
| `environments[]` (non-required) | any | none (recorded only) |
| `acceptance[]` | `met` | none |
| | `unverified`, `not_met` | `not_ready` |
| | `needs_human_decision` | `needs_human_decision` |
| | `unknown` | `blocked` |
| `findings[]` | open `blocking` | `not_ready` |
| | open `non-blocking` | `ready_with_notes` |
| | `resolved` | none |
| Conflicts (5.3) | unresolved by the authority order | `blocked` |
| Assessed commit | cannot be determined | `blocked` |

### 3.4 Relationship to existing review verdicts

| Verdict / status | Review gate | Readiness cap | Can yield `ACCEPT_UNIT` |
| --- | --- | --- | --- |
| `PASS` | satisfied for `reviewed_commit` only | none | yes |
| `PASS_WITH_NOTES` | satisfied for `reviewed_commit` only; notes become non-blocking findings | `ready_with_notes` | yes |
| `CHANGES_REQUIRED` | failed | `not_ready` | **never** |
| `stale` (`reviewed_commit ≠ assessed_commit`) | not satisfied for the assessed commit | `blocked` | never |
| `REVIEW_BLOCKED_MODEL_RESOLUTION` (any reason) | not satisfied; existing fail-closed semantics unchanged | `blocked` | never |
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
| `Tests run:` / `Typecheck / lint / build:` | per entry: `<command> — passed\|failed\|partial\|not_run — [label] — at <commit>`; failures may add `cause: unexplained\|identified(<category>)` |
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
- One line `Prior findings status: <id> — resolved|still open|not re-checked`.

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

A handoff without annotations or the two new lines is still valid. Missing items assess as `unknown`:

- acceptance criteria without status evidence;
- validation entries without a stated result or commit.

`unknown` caps readiness at `blocked`, so the Decision Helper recommends `VERIFY_FURTHER`. Old handoffs therefore fail closed: they are never treated as verified, and nothing breaks.

## 5. A3 — Post-implementation assessment

### 5.1 Inputs, in authority order

1. The authoritative SPEC/task and its acceptance criteria.
2. Git state `[observed]`: branch, `HEAD`, `git status`, and `git log` for the unit range.
3. The review report(s) for the unit.
4. The orchestrator report: checkpoints, model resolution, review decision.
5. The implementation handoff or `/handoff` output `[reported]`.
6. User statements `[human]`, for example "I verified login in production".

**Assessed commit:** the commit the user names. Otherwise it is the unit's resulting commit `[observed]` from Git (normally `HEAD` of the unit branch). If neither can be determined, readiness is `blocked`.

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
- Readiness: <value> — <one-line reason naming the governing cap>
```

Empty lists are written `none`, never omitted.

### 5.3 Freshness, conflicts, and incomplete evidence

**Review freshness** is decided only by the reviewed commit versus the assessed commit:

- `reviewed_commit == assessed_commit`: fresh; the verdict governs.
- `reviewed_commit ≠ assessed_commit`: `stale`.
- `reviewed_commit` not determinable: `unknown`.

When several reviews exist, the governing one is the latest cycle whose `reviewed_commit == assessed_commit`.

**Other evidence is also commit-bound.** A handoff whose resulting commit differs from the assessed commit does *not* change review freshness. Instead:

- The mismatch is listed under Conflicts as a `[reported]` discrepancy.
- Implementation is taken from `[observed]` Git state.
- Validation results that the handoff ties to a different commit, or to no commit, are `unknown` for the assessed commit.

**Reviewer vs implementer:** the reviewer's verdict governs the review dimension. Implementer claims stay `[reported]`.

**Findings across cycles:**

- New findings get new IDs; IDs are never reused.
- A finding becomes `resolved` only when a later fresh review confirms it, never on the implementer's word.
- A resolved finding is reopened only if a later review restates it.

**Failures:**

- A failed validation or environment check is `cause: unexplained` unless evidence identifies the cause. Hypotheses may be listed (application, infrastructure, test fixture, environment), but a hypothesis is not an identified cause.
- An unexplained failure is never treated as an application defect.

**Disagreement with a verdict:** the assessor may record a Conflict and require a human decision. It never overrides or reinterprets the verdict.

**Resolution by authority order:** a conflict resolved by the authority order in 5.1 (e.g. `[observed]` Git beats a `[reported]` commit) is listed but does not block. A conflict the order cannot resolve caps readiness at `blocked`.

**Insufficient evidence:** missing items are listed under Missing evidence and set to `unknown`. Nothing is inferred.

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
| `REMEDIATE_FINDINGS` | Fix identified findings, unmet criteria, or failures with an identified cause (scoped to listed IDs/causes) |
| `VERIFY_FURTHER` | Obtain missing verification: re-run validation, independent review or re-review, environment check, or re-run model resolution for a recorded window |
| `INVESTIGATE_FAILURE` | Establish the cause of an unexplained failure before any remediation |
| `RECONCILE_DOCS` | Bring SPEC/doc state in line with the repository (e.g. SPEC status, PRODUCT.md current state) |
| `PREPARE_NEXT_UNIT` | Prepare the next unit of an approved split; only after `[human]` acceptance of the current unit |
| `REQUEST_HUMAN_DECISION` | A product, security, release, provenance, or conflict judgment only the user can make |

### 6.2 Decision rules (first match wins; exhaustive)

1. An unresolved conflict (5.3): `REQUEST_HUMAN_DECISION`.
2. Review `blocked` with `REVIEW_BLOCKED_MODEL_RESOLUTION`. The family is never guessed, and the helper never proposes a reviewer family.
   - **Setup-class reason, both checkpoints recorded:** `VERIFY_FURTHER`. The setup-class reasons are `SQLITE3_NOT_FOUND`, `DB_NOT_FOUND`, `DB_NOT_READABLE`, `COMBO_NOT_FOUND`, `RESOLVER_UNAVAILABLE`, `REVIEW_ROUTE_HELPER_UNAVAILABLE`, `RUNTIME_ERROR`, or `RESOLVER_OUTPUT_INVALID`, with valid `start_id` and `end_id` in the orchestrator report. Prerequisite: the user fixes setup (`/doctor` hints). The user then re-runs `review-route.sh resolve <start_id> <end_id> <alias>` for the recorded window and uses only the reviewer it returns.
   - **Any other reason:** `REQUEST_HUMAN_DECISION`. This covers `MODEL_DETECTION_AMBIGUOUS`, `MODEL_DETECTION_FAILED`, `MODEL_ATTRIBUTION_UNKNOWN`, `MODEL_FAMILY_UNKNOWN`, `MODEL_PARSE_FAILED`, `UNSAFE_OUTPUT_VALUE`, `INVALID_CHECKPOINT`, `INVALID_WINDOW`, `START_CHECKPOINT_FAILED`, `END_CHECKPOINT_FAILED`, any unlisted reason, or missing checkpoints. Runtime provenance for that run cannot be obtained afterwards.
3. `implementation` is `incomplete` or `none`: `REQUEST_HUMAN_DECISION`. Resuming, re-splitting, or abandoning the unit is the user's call.
4. Any other `blocked` cap (missing, `unknown`, or `stale` evidence): `VERIFY_FURTHER`, naming the evidence to obtain.
5. A failure with `cause: unexplained`: `INVESTIGATE_FAILURE`.
6. Any of `CHANGES_REQUIRED`, an open blocking finding, an acceptance criterion `not_met`, or a failure with `cause: identified(...)`: `REMEDIATE_FINDINGS`, scoped to the listed IDs/causes. A `test-fixture` cause scopes remediation to the fixture, not application code.
7. A required validation `partial` or `not_run`, a required environment `pending`, or an acceptance criterion `unverified`: `VERIFY_FURTHER`.
8. An acceptance criterion `needs_human_decision`: `REQUEST_HUMAN_DECISION`, naming the authority from 3.1.
9. SPEC or documentation state out of sync with the repository: `RECONCILE_DOCS`.
10. Readiness `ready` or `ready_with_notes`: `ACCEPT_UNIT`. If a `[human]` acceptance of this unit is already recorded and an approved split has a next unit, the action is `PREPARE_NEXT_UNIT` instead.
11. Anything else: `REQUEST_HUMAN_DECISION` (fail closed).

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

- The Decision Helper never executes, delegates, or schedules its recommendation. The turn ends after the block.
- Each next action requires a new explicit user command, for example `/implement-spec` for remediation or `/review-change` for re-review.
- It never initiates implementation, push, merge, deployment, history rewrite, or production changes. These may appear only as steps the user performs, with the required explicit authorization named.
- It runs after the OpenCode orchestrator's "stop after the first review verdict" point and also stops.
- Its output is not authorization for the portable remediation loop described in [commands/implement-spec.md](../../commands/implement-spec.md) step 14 and [AGENTS.md](../../AGENTS.md) step 11 (see 7.1 and D7).

## 7. Integration architecture (minimal)

| Change | File(s) | Kind |
| --- | --- | --- |
| Portable contract: dimensions, labels, readiness caps, verdict mapping, freshness, action set, decision rules. Single source; other files reference it | `policies/verification-assessment.md` (new) | control-plane |
| Portable procedure for assessment + Decision Helper | `commands/assess-change.md` (new) | control-plane |
| OpenCode `/assess` command: `agent: orchestrator`, `subagent: false`; text forbids delegation, edits, validation runs, and Git writes; emits the 5.2 and 6.3 blocks | `integrations/opencode/commands/assess.md` (new) | control-plane |
| Final report appends the Assessment and Decision Helper blocks (also for blocked outcomes); OpenCode "stop" wording unchanged | [integrations/opencode/commands/implement-spec.md](../../integrations/opencode/commands/implement-spec.md) step 18, [agents/orchestrator.md](../../integrations/opencode/agents/orchestrator.md) "Orchestration report fields" | control-plane |
| Portable stop-semantics reconciliation (7.1, subject to D7) | [commands/implement-spec.md](../../commands/implement-spec.md) step 14, [AGENTS.md](../../AGENTS.md) step 11 | control-plane |
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

### 7.1 Portable stop-after-verdict reconciliation (specified, not implemented here)

The portable contract and the OpenCode adapter currently disagree:

- Portable [commands/implement-spec.md](../../commands/implement-spec.md) step 14 says "If `CHANGES_REQUIRED`, route fixes, validate, commit, and re-review".
- [AGENTS.md](../../AGENTS.md) core workflow step 11 says "Fix material findings, validate, commit, and re-review".
- The OpenCode orchestrator says "Do not automatically remediate CHANGES_REQUIRED. Stop after the first verdict."

Phase A's advisory model matches the OpenCode behavior. The portable contract must be reconciled so that remediation and re-review happen only as a new, explicitly user-initiated bounded unit (typically after a `REMEDIATE_FINDINGS` recommendation), never as an automatic loop.

Proposed wording for both portable files: "If `CHANGES_REQUIRED`, stop and report; fixes and re-review run only as a new explicit user-initiated unit."

This edits the highest-authority repository contract ([AGENTS.md](../../AGENTS.md)), so it requires approval (D7). It is scheduled in U4 and is **not implemented by this SPEC change**. Until reconciled, the Decision Helper's output must not be read as triggering the portable loop (6.4).

## 8. Acceptance criteria

**A1 — State contract (`policies/verification-assessment.md`)**

- AC-A1.1 Defines the dimensions, value sets (each including `unknown`), and evidence labels exactly as in 3.1–3.2, including the `needs_human_decision` vs `unverified` rule.
- AC-A1.2 Defines readiness by the cap table in 3.3. Every value of every dimension has a cap entry, and `unknown` never satisfies a requirement.
- AC-A1.3 Contains the verdict mapping in 3.4. `CHANGES_REQUIRED`, `stale`, and `REVIEW_BLOCKED_MODEL_RESOLUTION` cannot yield `ACCEPT_UNIT`.
- AC-A1.4 States that verdict text and existing block statuses/reasons are passed through verbatim.

**A2 — Evidence handoff**

- AC-A2.1 The handoff template gains only the annotation conventions and the two new lines in 4.2. No existing field is removed or duplicated.
- AC-A2.2 The template states 4.3: the child writes `pending (orchestrator resolution)`, and the orchestrator report is the authoritative provenance.
- AC-A2.3 The review template gains optional finding IDs and a `Prior findings status:` line. The verdict line is unchanged.
- AC-A2.4 The policy states 4.4: un-annotated or old handoffs assess as `unknown` and fail closed.

**A3 — Assessment**

- AC-A3.1 The procedure emits the 5.2 block with every field present (`none` when empty).
- AC-A3.2 The procedure states the input authority order and assessed-commit rule (5.1), and the 5.3 rules:
  - freshness is decided solely by `reviewed_commit` vs the assessed commit;
  - a handoff mismatch is a conflict, not staleness;
  - finding identity across cycles;
  - failure-cause classification.
- AC-A3.3 The procedure and `/assess` state the read-only boundary in 5.4.

**A4 — Decision Helper**

- AC-A4.1 The action set is closed (6.1), and exactly one action is recommended.
- AC-A4.2 The decision rules match 6.2, including the resolver-reason split and the fail-closed fallback.
- AC-A4.3 The output block matches 6.3, including Required authorization.
- AC-A4.4 `/assess` and the OpenCode `/implement-spec` and orchestrator state that the recommendation is never executed, and that push/merge/deploy/history rewrite/production changes are never initiated.

**Integration**

- AC-I.1 `sync-install.sh` manifest contains `commands/assess.md`; `test-sync-install.sh` passes with `NMAN=15` and an assess block.
- AC-I.2 `test-doctor.sh`, `test-review-route.sh`, and `test-resolve-model-family.sh` pass unchanged.
- AC-I.3 OpenCode `/implement-spec` step 19 and the orchestrator "stop after the first verdict" wording are unchanged.
- AC-I.4 Checkpoint and resolution wording is unchanged.
- AC-I.5 After D7 approval, portable `commands/implement-spec.md` step 14 and `AGENTS.md` step 11 no longer describe automatic remediation or re-review (7.1).

**A5 — Regression scenarios**

- AC-A5.1 The fixtures in section 9 exist, each labeled with its basis.
- AC-A5.2 `test-assessment-fixtures.sh` checks:
  - required keys;
  - enum values against the policy file;
  - `ACCEPT_UNIT` only with readiness `ready`/`ready_with_notes`;
  - never `ACCEPT_UNIT` with `CHANGES_REQUIRED`, `stale`, or a blocked review;
  - `expected_decision` not in `must_not_decide`.

## 9. Historical regression scenarios (A5)

**Basis:** no execution records from the Huellas repository are available in this repository. Each scenario below is an **assumption-based fixture** derived from the summary in the task brief, not a historical record. The fixture files must carry `basis: assumption-based fixture (not a historical record)`.

Fixture format (`examples/assessment/S<id>-<slug>.md`, Markdown with a key: value header the structural test reads):

```text
fixture: S4b-supabase-otp-fixture-confirmed
basis: assumption-based fixture (not a historical record)
review: <verdict or status>
expected_readiness: not_ready
expected_decision: REMEDIATE_FINDINGS
remediation_scope: test fixture only
must_not_decide: ACCEPT_UNIT, INVESTIGATE_FAILURE
```

The header is followed by the input evidence (handoff excerpt, review report excerpt, Git facts) and the expected Assessment block.

| ID | Scenario | Key evidence (fixture) | Expected readiness | Expected decision | Must not decide |
| --- | --- | --- | --- | --- | --- |
| S1 | Repository bootstrap after multiple review cycles | Cycles 1–2 `CHANGES_REQUIRED` (R1-\*, R2-\*); cycle 3 `PASS` with `reviewed_commit == assessed_commit`; cycle 3 confirms prior findings resolved; required validation passed | `ready` | `ACCEPT_UNIT` | `REMEDIATE_FINDINGS` |
| S2 | Auth implemented; production verification incomplete | Validation passed; review `PASS` (fresh); AC "login works in production" `unverified`; `production` `pending` | `not_ready` | `VERIFY_FURTHER` (authorization: user performs or authorizes the production check) | `ACCEPT_UNIT` |
| S3 | Logout remediation | Technical logout exists, tests pass; review `CHANGES_REQUIRED` with R1-1: user-facing AC (e.g. confirmation/redirect wording) `not_met` | `not_ready` | `REMEDIATE_FINDINGS` (scoped to R1-1) | `ACCEPT_UNIT` |
| S4a | OTP authentication failure, cause not yet established | Supabase OTP integration test fails; `cause: unexplained`; hypotheses listed (fixture/data, provider infrastructure, application) | `not_ready` | `INVESTIGATE_FAILURE` | `ACCEPT_UNIT`, `REMEDIATE_FINDINGS` |
| S4b | Same failure, cause confirmed as a Supabase test fixture | Investigation evidence identifies the repository's test fixture (e.g. misconfigured OTP test user/seed data for the Supabase test project); the application code path is not implicated; `cause: identified(test-fixture)` | `not_ready` | `REMEDIATE_FINDINGS` (scope: test fixture only) | `ACCEPT_UNIT`, `INVESTIGATE_FAILURE` |
| S5a | Security exposure check not yet performed | Functional ACs `met`, review `PASS`; security AC "no secret/service-role key exposed to the client" `unverified` | `not_ready` | `VERIFY_FURTHER` | `ACCEPT_UNIT`, `REQUEST_HUMAN_DECISION` |
| S5b | Security acceptance pending sign-off | Functional ACs `met`; exposure check `met` `[observed]`; security acceptance AC (residual-risk sign-off by the security owner) `needs_human_decision` | `needs_human_decision` | `REQUEST_HUMAN_DECISION` (authority: security owner) | `ACCEPT_UNIT` |
| S6 | New review findings vs resolved findings | Cycle 2 `CHANGES_REQUIRED` (fresh) with new R2-1..R2-2; cycle 2 marks R1-\* resolved | `not_ready` | `REMEDIATE_FINDINGS` scoped to R2-\* only; R1-\* not reopened | `ACCEPT_UNIT` |
| S7 | Fail closed: old-format handoff | Handoff without annotations or the two new lines; no AC or environment evidence | `blocked` | `VERIFY_FURTHER` | `ACCEPT_UNIT` |
| S8a | Fail closed: attribution ambiguity | `REVIEW_BLOCKED_MODEL_RESOLUTION`, reason `MODEL_DETECTION_AMBIGUOUS` | `blocked` | `REQUEST_HUMAN_DECISION` | `ACCEPT_UNIT`, `VERIFY_FURTHER` |
| S8b | Fail closed: correctable resolver setup | `REVIEW_BLOCKED_MODEL_RESOLUTION`, reason `RESOLVER_UNAVAILABLE`; `start_id`/`end_id` recorded | `blocked` | `VERIFY_FURTHER` (fix setup, re-resolve recorded window) | `ACCEPT_UNIT` |
| S9 | Fail closed: stale review | Review `PASS` for commit A; assessed commit B (a later fix commit) | `blocked` | `VERIFY_FURTHER` (re-review B) | `ACCEPT_UNIT` |

The structural test validates the fixtures' internal consistency against the policy. It does not run an LLM. Behavioral checking of an orchestrator's assessment against these fixtures is a manual step in each unit's review until a deterministic reducer exists (open decision D1).

## 10. Implementation sequence

One unit per `/implement-spec`, sequential, each `standard` or higher, each independently reviewed. No unit authorizes the next.

| Unit | Delivers | Depends on | Validation |
| --- | --- | --- | --- |
| **U1** | `policies/verification-assessment.md`; the section 9 fixtures in `examples/assessment/`; `integrations/opencode/scripts/test-assessment-fixtures.sh` | — | New test passes; existing four suites pass; no behavior change |
| **U2** | Template annotation conventions, two new lines, model/family wording (section 4) | U1 | `git diff` shows no removed fields; links resolve; suites pass |
| **U3** | `commands/assess-change.md`, `integrations/opencode/commands/assess.md`, manifest +1, `test-sync-install.sh` update, README install list | U1 | `test-sync-install.sh` (`NMAN=15`) and `test-doctor.sh` pass; manual `/assess` on S2, S4a and S4b inputs matches the fixtures |
| **U4** | OpenCode `/implement-spec` and orchestrator report integration; AGENTS.md and README workflow step; portable stop-semantics reconciliation (7.1) if D7 is approved | U3, D7 | Checkpoint/resolution/OpenCode stop wording diff-checked as unchanged; AC-I.5; suites pass; manual run shows the block and stops |
| **U5** | PRODUCT.md CURRENT STATE update; SPEC status → Implemented | U4 | Links resolve; content describes only implemented behavior |

**Recommended first unit:** U1. It is a pure contract plus tests and changes no runtime behavior.

## 11. Risks, open questions, and decisions requiring approval

| ID | Item | Default in this SPEC |
| --- | --- | --- |
| D1 | Deterministic reducer script (key=value in, readiness + decision out) to make rules executable | Deferred; Markdown contract + structural fixture test (user decision) |
| D2 | `/assess` runs on the orchestrator agent, so "no delegation" is enforced by instruction rather than permissions. Alternative: a dedicated narrowly-permissioned agent like `doctor` | Orchestrator agent; revisit if review finds it insufficient |
| D3 | Fixture location `examples/assessment/` and test in `integrations/opencode/scripts/` (where all suites live), though the contract is portable | As stated |
| D4 | `PREPARE_NEXT_UNIT` requires a recorded `[human]` acceptance of the current unit | Required |
| D5 | Environment names are project-defined; projects without a definition have no required environments beyond those named by acceptance criteria | As stated |
| D6 | Adopt `docs/specs/` as the repository's SPEC location convention | **Open**: proposed, pending user approval; not established by this draft |
| D7 | Reconcile portable `commands/implement-spec.md` step 14 and `AGENTS.md` step 11 with the stop-after-verdict behavior (7.1) | **Open**: proposed for U4; not implemented until approved |

Risks:

- **LLM rule-application drift without a reducer.** Mitigation: a single-source policy, an exhaustive cap table, fixed output blocks, fixtures, and manual fixture checks in review.
- **Longer orchestrator reports.** Mitigation: fixed compact blocks, with `none` for empty fields.
- **Recommendation mistaken for authorization.** Mitigation: an explicit "advisory only — nothing has been executed" header, a Required authorization line, no continuation, and D7.
- **Portable/OpenCode stop semantics differ until D7 lands.** Mitigation: 6.4 explicitly denies that the recommendation authorizes the portable loop.
- **Old evidence over-trusted.** Mitigation: commit-bound evidence and `stale`.
- **Re-resolving a recorded window later (rule 6.2.2) depends on the current combo definition.** Mitigation: confidence is reported as `medium` when combos may have changed since the run.
- **9Router attribution ambiguity remains** (a known limitation in [docs/PRODUCT.md](../PRODUCT.md)). Phase A surfaces it as `blocked` review and does not resolve it.

## 12. Review cycle record

Cycle 1: `review-openai` on commit `7ae7ba9`, verdict `CHANGES_REQUIRED`. Disposition in revision 2:

| ID | Severity | Finding (short) | Disposition |
| --- | --- | --- | --- |
| R1-1 (R1) | blocking | Readiness not exhaustive; `incomplete`/`none` fell through; acceptance lacked `unknown` | Fixed: `unknown` in every dimension (3.1); exhaustive cap table (3.3); decision rule 3 for `incomplete`/`none` |
| R1-2 (R2) | blocking | Handoff extension duplicated existing fields | Fixed: annotations on existing fields; only two new lines (4.2) |
| R1-3 (R3) | blocking | Portable flow permits automatic remediation | Specified, not implemented: 7.1, D7, AC-I.5, 6.4; scheduled in U4 |
| R1-4 (R4) | blocking | OTP fixture scenario contradictory; Supabase missing | Fixed: S4a unexplained → `INVESTIGATE_FAILURE`; S4b confirmed Supabase fixture → scoped `REMEDIATE_FINDINGS`; `failures[]` cause classification (3.1, 5.3) |
| R1-5 (R5) | blocking | Staleness overbroad | Fixed: freshness solely `reviewed_commit` vs assessed commit; handoff mismatch is a conflict (5.3); S9 added |
| R1-6 (R6) | non-blocking | Security fixture semantics unclear | Fixed: `needs_human_decision` vs `unverified` rule (3.1); S5a/S5b |
| R1-7 (R7) | non-blocking | Resolver-blocked mapped too broadly | Fixed: setup-class vs judgment reasons (6.2 rule 2); S8a/S8b |
| R1-8 (R8) | non-blocking | Model/family handoff ownership | Fixed: 4.3 |
| R1-9 (R9) | non-blocking | D6 circular | Fixed: D6 open, pending approval |

## 13. Operational findings (outside Phase A scope)

**OF-1: reviewer model selection when launching a reviewer directly from the OpenCode CLI.**

- **Where:** reviewer agents are configured with `"mode": "subagent"` and `"model": "9router/review-openai"` (see [examples/opencode.json.example](../../examples/opencode.json.example)).
- **Observed on 2026-10-20 during cycle 1 of this SPEC's review:** `opencode run --standalone --agent review-openai` without `--model` ran on the default model `9router/economy`. The CLI header read `review-openai · economy`, and 9Router `usageHistory` row 3629 recorded `deepseek-v4.1-flash`.
- **With the model pinned:** adding `--model 9router/review-openai` produced `gpt-5.6-sol` rows (OpenAI family).
- **Effect:** an unpinned manual review silently runs on the wrong family/tier.
- **Not investigated:** whether orchestrator subagent delegation in `/implement-spec` is affected. Nothing here suggests it is, but it was not tested.
- **Recommendation:** a separate bounded task, such as documenting the required `--model` pin for manual reviews and/or a doctor check. No runtime change is made by Phase A.

**OF-2: background-service hang.** In the same session, `opencode run` against the background service logged only `cli starting` and made no model calls. `--standalone` worked. The cause was not investigated.
