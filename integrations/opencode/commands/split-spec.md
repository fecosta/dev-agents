---
description: Split oversized implementation work into independently verifiable phases without implementing it.
agent: orchestrator
subagent: false
---

Split this SPEC/task into ordered, bounded units: $ARGUMENTS

Read repository instructions and the authoritative contract. Decompose into behaviorally coherent units that are meaningful outcomes, not merely sets of files or single architectural layers; each independently implementable and verifiable in one fresh session, preserving acceptance criteria, non-goals, security constraints, data constraints, and product scope without silent change. Prefer vertical slices where appropriate (narrow complete behavior across needed layers) over horizontal layer-only phases; do not require every layer to appear in every slice.

For each unit return: scope, explicit dependencies (genuine "cannot begin until" ordering constraints only), validation condition, likely capability tier, and stop condition. Dependencies do not authorize automatic scheduling or parallel execution.

`/implement-spec` executes exactly one unit per invocation. Never plan frontier execution, automatic traversal of ready units, parallel/concurrent implementers, worktree-per-unit orchestration, automatic continuation, or multi-unit execution.

Wide-refactor exception only: for a mechanical change with broad blast radius where vertical slices are invalid, use expand → migrate in bounded batches by meaningful blast-radius seam (package, subsystem, directory, or other repo-specific seam) → contract. Each migration batch must be independently verifiable. Keep the old form available until migration is complete when feasible; contract/removal only after all required migration batches are complete and validated. This decomposition does not authorize automatic migration execution; preserve sequential execution semantics (each expand/migrate-batch/contract step is its own unit, implemented one per /implement-spec invocation).

Describe outcomes, dependencies, preserved constraints, and validation; do not dictate implementation details unless the authoritative SPEC requires them; do not invent or reinterpret unresolved product decisions. If the SPEC exposes missing or contradictory product decisions, report it is not ready to split safely.

Do not edit files or begin implementation.
