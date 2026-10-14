# First real-world validation cycle

Validation report for the first real-world dev-agents cycle, run against the D+ Base Curricular SPEC-008.

## Scope

This report records what could be verified directly in this repository and what is attributed to the supplied execution reports. It does **not** claim SPEC-008 itself is complete; Production blockers were recognized per the reports and are not resolved by this report.

## Repository-verified evidence

The following facts were checked directly in the repository.

### Commits that changed completion-verification behavior

- `a69ca17ef56de34dec8dbc7709da86dc458208cd` — `docs(orchestrator): require completion verification before handoff`
  - Author: Felipe Costa <costa.felipe@gmail.com>
  - Date: Wed Oct 14 13:36:24 2026 -0300
  - Changed 7 files, 86 insertions(+), 23 deletions(-)
  - Files: [`AGENTS.md`](../../AGENTS.md), [`commands/implement-spec.md`](../../commands/implement-spec.md), [`docs/PRODUCT.md`](../../docs/PRODUCT.md), [`integrations/opencode/README.md`](../../integrations/opencode/README.md), [`integrations/opencode/agents/orchestrator.md`](../../integrations/opencode/agents/orchestrator.md), [`integrations/opencode/commands/implement-spec.md`](../../integrations/opencode/commands/implement-spec.md), [`integrations/opencode/scripts/test-review-route.sh`](../../integrations/opencode/scripts/test-review-route.sh)
  - Adds/updates mandatory orchestrator completion verification before the review decision across the portable contract, OpenCode orchestrator command, and AGENTS.md core workflow.

- `08e36b1170fcbfb06ed8c5656057c57895bf6fcb` — `docs(orchestrator): resolve verification review findings`
  - Author: Felipe Costa <costa.felipe@gmail.com>
  - Date: Wed Oct 14 13:54:39 2026 -0300
  - Changed 6 files, 88 insertions(+), 9 deletions(-)
  - Files: [`AGENTS.md`](../../AGENTS.md), [`commands/implement-spec.md`](../../commands/implement-spec.md), [`integrations/opencode/README.md`](../../integrations/opencode/README.md), [`integrations/opencode/agents/orchestrator.md`](../../integrations/opencode/agents/orchestrator.md), [`integrations/opencode/commands/implement-spec.md`](../../integrations/opencode/commands/implement-spec.md), [`integrations/opencode/scripts/test-review-route.sh`](../../integrations/opencode/scripts/test-review-route.sh)
  - Remediates findings from the independent review of `a69ca17`; expands wording, examples, and regression tests for verification ordering and `NOT_REACHED` fields.

Both SHAs resolve as `commit` objects per `git cat-file -t`.

### Regression tests W4/W5

The W4/W5 checks referenced in the review notes exist in [`integrations/opencode/scripts/test-review-route.sh`](../../integrations/opencode/scripts/test-review-route.sh), lines 402–405.

- W4 mutates the OpenCode command by renumbering `Completion verification` from step 12 to step 14 and checks that the ordering assertion detects the move.
- W5 mutates the orchestrator command by replacing the `Completion verification` heading with `Zompletion verification` and checks that the ordering assertion detects the removed heading.

### Portable command wording (L2 observation)

[`commands/implement-spec.md`](../../commands/implement-spec.md), step 13, says verification happens "after the end checkpoint and before the review decision". The portable document does not define an explicit end-checkpoint step. [`integrations/opencode/commands/implement-spec.md`](../../integrations/opencode/commands/implement-spec.md) defines the `START CHECKPOINT` and `END CHECKPOINT` explicitly.

## User-reported execution evidence (not independently verifiable from this repository)

The following items are attributed to the supplied execution reports. They describe runtime behavior against D+ Base Curricular SPEC-008 that cannot be reproduced from this repository alone.

- Active SPEC discovery and reconciliation.
- Capability-based routing across `economy`, `standard`, and `strong` tiers.
- Mandatory start/end checkpoints around delegated implementation.
- Bounded implementation and local commits.
- Independent cross-family security review.
- Review-driven remediation.
- Orchestrator completion verification of actual artifacts.
- Recognition of Production blockers.
- Originally the orchestrator trusted delegated handoffs without inspecting artifacts.
- Independent review identified two medium findings.
- Remediation in `08e36b1` resolved both medium findings.
- A fresh review returned `PASS_WITH_NOTES`.
- Runtime validation demonstrated artifact inspection.

## Validated vs untested

**Validated per reports:** the items listed above under user-reported execution evidence.

**Untested at runtime:** the `FAILED` and `PARTIALLY_VERIFIED` completion-verification paths. This report does not claim they behave correctly under real runtime failure conditions.

## Review verdict

Final review verdict: `PASS_WITH_NOTES`.

Two outstanding notes were recorded as **OPEN** and **NONBLOCKING**:

- **L1 — Regression test description overstates its coverage.** The W5 test description claims to test a section-ordering mutation, but the test actually removes the completion-verification heading. W4 already covers ordering by step number in the OpenCode command. Test-quality debt, not a blocking workflow defect.
- **L2 — Portable workflow references an undefined checkpoint.** In [`commands/implement-spec.md`](../../commands/implement-spec.md), completion verification is described as occurring "after the end checkpoint", but the portable document does not define an explicit end-checkpoint step. The OpenCode integration defines the checkpoint correctly. The portable wording therefore depends on context not established within that document.

Both notes remain open in this report; they are not fixed here.

## Conclusions

- The repository contains the two remediation commits (`a69ca17` and `08e36b1`) that document and test the completion-verification requirement.
- The supplied execution reports describe a full cycle through SPEC-008 that ended with `PASS_WITH_NOTES` after remediation.
- The `FAILED`/`PARTIALLY_VERIFIED` paths have not been demonstrated at runtime.
- This report does not resolve Production blockers recognized during the cycle.

## Remaining limitations

- Untested `FAILED`/`PARTIALLY_VERIFIED` completion-verification paths.
- L1 and L2 remain open and nonblocking.
- Runtime evidence from the SPEC-008 execution is not independently verifiable in this repository.
- 9Router `usageHistory` lacks a session/correlation ID; see [`docs/PRODUCT.md`](../../docs/PRODUCT.md) § Known current limitations.
