# Verification-state assessment and Decision Helper

This policy is the portable source for the Phase A post-implementation assessment and the advisory-only Decision Helper. It lives under `policies/` so other contracts can reference it without depending on the OpenCode adapter.

## 1. Purpose and non-goals

The assessment reads already-produced evidence and turns it into one recommended next action. It does **not**:

- edit files, run validation, re-run model resolution, delegate to agents, run Git write commands, or contact deployed environments;
- execute its recommendation;
- authorize more than one bounded unit or a second remediation cycle;
- treat advisory output as approval.

## 2. Evidence labels

Every evidence item carries exactly one label:

- `[observed]`: inspected read-only in the current session (for example `git rev-parse`, reading a review report file).
- `[reported]`: stated in another agent's output (implementation child, reviewer, `/handoff`, or an orchestrator report from another session).
- `[human]`: stated by the user.

An assessor may upgrade `[reported]` to `[observed]` only by re-inspecting the fact read-only. Recommendations are not evidence and are never labeled as evidence.

## 3. State inputs (A1)

Each input has a closed domain. Absent evidence uses the explicit absent value and never satisfies a requirement.

| Input | Domain | Absent value | Notes |
| --- | --- | --- | --- |
| `assessed_commit` | `known`, `unknown` | `unknown` | The commit being assessed. |
| `implementation` | `complete`, `incomplete`, `none`, `unknown` | `unknown` | Whether the unit's changes exist at the assessed commit. |
| `review` | `PASS`, `PASS_WITH_NOTES`, `CHANGES_REQUIRED`, `not_required`, `pending`, `stale`, `blocked(<status>, <reason>)`, `unknown` | `unknown` | Verbatim verdict or non-verdict state. Freshness applies only to verdicts. |
| `validation[]` (required) | `passed`, `failed(<cause>)`, `partial`, `not_run`, `unknown` | `unknown` | Required checks come from the SPEC/task and `AGENTS.md`. |
| `validation[]` (optional) | same | `unknown` | Recorded only. |
| `environments[]` (required) | `verified`, `pending`, `failed(<cause>)`, `not_applicable`, `unknown` | `unknown` | Required environments are named by acceptance criteria or `AGENTS.md`. |
| `environments[]` (optional) | same | `unknown` | Recorded only. |
| `<cause>` | `unexplained`, `identified:<category>` | `unexplained` | Categories: `application`, `test-fixture`, `infrastructure`, `environment`, `other`. |
| `acceptance[]` | `met`, `unverified`, `not_met`, `needs_human_decision`, `unknown` | `unknown` | Tagged `functional`, `user-facing`, `security`, `data`, or `other`. |
| `findings[]` | status `open`, `resolved`, `unknown`; severity `blocking`, `non-blocking`, `unknown` | `unknown` / `unknown` | IDs `R<cycle>-<n>` (review) or `I-<n>` (implementer/assessor). |
| `conflicts[]` | `resolved_by_authority`, `unresolved` | n/a | Empty list means no conflict. |
| `doc_state` | `in_sync`, `out_of_sync`, `unknown` | `unknown` | SPEC/doc state vs repository. |
| `human_acceptance` | `recorded`, `not_recorded` | `not_recorded` | `[human]` acceptance of this unit. |
| `next_unit` | `available`, `none`, `unknown` | `unknown` | Whether an approved split has a next unit. |

`needs_human_decision` is only for criteria whose satisfaction is a judgment (for example accepting residual security risk). The required authority must be named. `unverified` is for objectively checkable conditions that have not been checked yet.

## 4. Readiness derivation

Output domain: `blocked`, `not_ready`, `needs_human_decision`, `ready_with_notes`, `ready`.

Readiness is the most severe cap present, ordered `blocked` > `not_ready` > `needs_human_decision` > `ready_with_notes`. If no cap applies, readiness is `ready`.

| Input | Value | Cap |
| --- | --- | --- |
| `assessed_commit` | `known` | none |
| | `unknown` | `blocked` |
| `implementation` | `complete` | none |
| | `incomplete`, `none` | `not_ready` |
| | `unknown` | `blocked` |
| `review` | `PASS`, `not_required` | none |
| | `PASS_WITH_NOTES` | `ready_with_notes` |
| | `CHANGES_REQUIRED` | `not_ready` |
| | `pending`, `stale`, `blocked(...)`, `unknown` | `blocked` |
| required validation | `passed` | none |
| | `failed(any cause)`, `partial`, `not_run` | `not_ready` |
| | `unknown` | `blocked` |
| optional validation | `failed(any cause)`, `partial` | `ready_with_notes` |
| | `passed`, `not_run`, `unknown` | none |
| required environment | `verified`, `not_applicable` | none |
| | `pending`, `failed(any cause)` | `not_ready` |
| | `unknown` | `blocked` |
| optional environment | any value | none |
| acceptance | `met` | none |
| | `unverified`, `not_met` | `not_ready` |
| | `needs_human_decision` | `needs_human_decision` |
| | `unknown` | `blocked` |
| finding | status `resolved`, any severity | none |
| | status `open`, severity `blocking` or `unknown` | `not_ready` |
| | status `open`, severity `non-blocking` | `ready_with_notes` |
| | status `unknown`, any severity | `blocked` |
| conflict | `resolved_by_authority` | none |
| | `unresolved` | `blocked` |
| `doc_state` | `out_of_sync` | `ready_with_notes` |
| | `in_sync`, `unknown` | none |
| `human_acceptance` | any value | none |
| `next_unit` | any value | none |

## 5. Review verdict mapping

| Verdict / status | Review gate | Readiness cap | Can yield `ACCEPT_UNIT` |
| --- | --- | --- | --- |
| `PASS` | satisfied for the reviewed commit only | none | yes |
| `PASS_WITH_NOTES` | satisfied for the reviewed commit only; notes become non-blocking findings | `ready_with_notes` | yes |
| `CHANGES_REQUIRED` | failed | `not_ready` | never |
| `stale` (`reviewed_commit ≠ assessed_commit`) | not satisfied for the assessed commit | `blocked` | never |
| `REVIEW_BLOCKED_MODEL_RESOLUTION` or any other block | not satisfied | `blocked` | never |
| `Independent review: not required` | satisfied by the orchestrator's existing decision | none | yes |

Verdict text is copied verbatim and never rewritten, softened, or reinterpreted.

## 6. Assessment procedure (A3)

### 6.1 Inputs, in authority order

1. The authoritative SPEC/task and its acceptance criteria.
2. Git state `[observed]`: branch, `HEAD`, `git status`, and `git log` for the unit range.
3. The review report(s) for the unit.
4. The orchestrator report: checkpoints, model resolution, review decision, ledger.
5. The implementation handoff or `/handoff` output `[reported]`.
6. User statements `[human]`.

### 6.2 Evidence resolution rules

**Assessed commit.** Use the commit the user names, otherwise the unit's resulting commit `[observed]` (normally `HEAD` of the unit branch). If neither can be determined, `assessed_commit = unknown`.

**Authority order resolves conflicts.** When two sources disagree, the authority order in 6.1 wins. A disagreement resolved by that order is recorded as a conflict with status `resolved_by_authority`. Any disagreement not resolved by the authority order is `unresolved` and caps readiness at `blocked`.

**Handoff commit mismatch.** If the handoff's resulting commit differs from `assessed_commit`, this is a `resolved_by_authority` conflict: implementation is taken from `[observed]` Git state, and validation results that the handoff ties to a different commit (or to no commit) are `unknown` for the assessed commit. It is not a stale review.

**Commit-bound validation.** A validation result proves correctness only for the commit it was produced against. Evidence whose commit is not `assessed_commit` or an ancestor of it, or whose scope or environment cannot be proven unchanged, is treated as `unknown`.

**Failure classification.** A failed validation or environment check is `cause: unexplained` unless evidence identifies the cause. Hypotheses are not identified causes. An unexplained failure is never treated as an application defect.

**Reviewer verdict governs; implementer claims are `[reported]`.** The assessor never overrides or reinterprets a verdict. Disagreement with a verdict is an `unresolved` conflict requiring human decision.

### 6.3 Review freshness

Freshness applies only to a verdict (`PASS`, `PASS_WITH_NOTES`, `CHANGES_REQUIRED`):

- `reviewed_commit == assessed_commit`: current; the verdict governs verbatim.
- `reviewed_commit ≠ assessed_commit`: `stale`.
- `reviewed_commit` not determinable: `unknown`.

Non-verdict states keep their state regardless of reviewed commit:

- `blocked(<status>, <reason>)` stays `blocked(...)`.
- `pending` stays `pending`.
- `not_required` stays `not_required`.

When several reviews exist, the governing one is the latest cycle with a current verdict, unless a later cycle is `blocked(...)` or `pending`; then that later cycle governs. If no current verdict exists, the latest cycle governs with its state determined as above.

### 6.4 Findings across cycles

- New findings get new IDs; IDs are never reused.
- A finding becomes `resolved` only when a later fresh review confirms it.
- A prior finding that the governing review does not re-check has status `unknown`.
- A resolved finding is reopened only if a later review restates it.

### 6.5 Ledger to I10 mapping

| Ledger status | Phase A I10 status |
| --- | --- |
| `OPEN` | `open` |
| `REMEDIATED` | `open` |
| `VERIFIED` | `resolved` |
| `CLOSED` | `resolved` |
| `OPEN` / `REMEDIATED` not re-checked | `unknown` |

### 6.6 Output block

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

### 6.7 Read-only boundary

`/assess` never edits files, runs validation or tests, re-runs model resolution, delegates to any agent, runs Git write commands, or contacts deployed environments. Allowed shell use is read-only Git inspection only.

## 7. Decision Helper (A4)

### 7.1 Action set (closed)

Exactly one action is recommended per assessment:

| Action | Meaning |
| --- | --- |
| `ACCEPT_UNIT` | Ask the user to accept the completed bounded unit. |
| `REMEDIATE_FINDINGS` | Fix identified findings, unmet criteria, or failures with an identified cause (scoped to listed IDs/causes). |
| `VERIFY_FURTHER` | Obtain missing verification: validation re-run, independent review or re-review, environment check, or locating missing evidence. |
| `INVESTIGATE_FAILURE` | Establish the cause of an unexplained failure before any remediation. |
| `RECONCILE_DOCS` | Bring SPEC/doc state in line with the repository. |
| `PREPARE_NEXT_UNIT` | Prepare the next unit of an approved split; only after `[human]` acceptance of the current unit. |
| `REQUEST_HUMAN_DECISION` | A product, security, release, provenance, or conflict judgment only the user can make. |

### 7.2 Decision rules (first match wins)

1. Any conflict `unresolved`: `REQUEST_HUMAN_DECISION`.
2. `review = blocked(...)`: `REQUEST_HUMAN_DECISION`. The helper never recommends re-resolution; provenance cannot be established after the fact.
3. `implementation ∈ {incomplete, none}`: `REQUEST_HUMAN_DECISION`.
4. Readiness `blocked`: `VERIFY_FURTHER`, naming the evidence to obtain.
5. A required validation or required environment is `failed(unexplained)`: `INVESTIGATE_FAILURE`.
6. Any of: `review = CHANGES_REQUIRED`; an `open` finding with severity `blocking` or `unknown`; an acceptance criterion `not_met`; a required validation or environment `failed(identified:<category>)`. Action: `REMEDIATE_FINDINGS`, scoped to the listed open IDs and causes. `identified:test-fixture` scopes remediation to the fixture.
7. Any of: a required validation `partial` or `not_run`; a required environment `pending`; an acceptance criterion `unverified`. Action: `VERIFY_FURTHER`.
8. An acceptance criterion `needs_human_decision`: `REQUEST_HUMAN_DECISION`, naming the authority.
9. `doc_state = out_of_sync`: `RECONCILE_DOCS`.
10. Readiness `ready` or `ready_with_notes`:
    - `human_acceptance = not_recorded`: `ACCEPT_UNIT`.
    - `human_acceptance = recorded` and `next_unit = available`: `PREPARE_NEXT_UNIT`.
    - `human_acceptance = recorded` and `next_unit ∈ {none, unknown}`: `REQUEST_HUMAN_DECISION`.
11. Anything else: `REQUEST_HUMAN_DECISION` (fail-closed guard).

Invariants:

- `ACCEPT_UNIT` and `PREPARE_NEXT_UNIT` are produced only by rule 10, which requires readiness `ready` or `ready_with_notes`.
- `CHANGES_REQUIRED`, `stale`, `pending`, `unknown` and `blocked(...)` reviews cap readiness at `not_ready` or `blocked`, so they can never produce an acceptance recommendation.

### 7.3 Output block

```text
Decision Helper (advisory only — nothing has been executed):
- Recommended action: <ACTION> — <one line>
- Rationale: <decision rule number and governing evidence>
- Supporting evidence: <item — label>, ...
- Unresolved risks:
- Prerequisites:
- Required authorization: <who must authorize what>
- Evidence limitations / confidence: high|medium|low — <why>
- Why not ACCEPT_UNIT: <only when another action is recommended>
```

### 7.4 Hard rules

- The Decision Helper never executes, delegates, schedules, or retries its recommendation.
- Each next action requires a new explicit user command.
- It never initiates implementation, push, merge, deployment, history rewrite, or production changes.
- It runs after the OpenCode orchestrator has produced its final report and stops.
- Its output is never authorization for any remediation loop. `/implement-spec` owns the one eligible remediation attempt; a `REMEDIATE_FINDINGS` recommendation still requires a new explicit user command.

## 8. Evidence handoff annotations (A2)

The implementation handoff remains the existing template; it gains only these annotations:

- Validation entries: `<command> — passed|failed|partial|not_run — [label] — at <commit>`. Failures add `cause: unexplained|identified:<category>`.
- Risks: finding ID (`R<cycle>-<n>` / `I-<n>`), `blocking|non-blocking`, source; unknowns written `unknown: <what is missing>`.
- Two optional appended lines:
  ```markdown
  - Acceptance criteria: <AC-id> — met|unverified|not_met|needs_human_decision|unknown — [label] <evidence>
  - Environment verification: <env> — verified|pending|failed|not_applicable|unknown — [label] <evidence / who>
  ```

The child handoff writes `pending (orchestrator resolution)` for model/family. The orchestrator's final report is the authoritative provenance.

A handoff without annotations or the two new lines is still valid; missing items take their absent-evidence value and fail closed.
