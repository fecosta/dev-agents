---
description: Split oversized implementation work into independently verifiable phases without implementing it.
agent: orchestrator
subagent: false
---

Split this SPEC/task into ordered, bounded units: $ARGUMENTS

Read repository instructions and the authoritative contract. Decompose into behaviorally coherent units, each independently implementable and verifiable in one fresh session, preserving acceptance criteria, non-goals, security constraints, and data constraints. Prefer vertical slices (narrow complete behavior across needed layers) over horizontal layer-only phases.

For each unit return: scope, explicit dependencies (genuine "cannot begin until" ordering constraints only), validation condition, likely capability tier, and stop condition. Dependencies do not authorize automatic scheduling or parallel execution.

`/implement-spec` executes exactly one unit per invocation. Never plan frontier execution, automatic traversal of ready units, parallel/concurrent implementers, worktree-per-unit orchestration, automatic continuation, or multi-unit execution.

Wide-refactor exception only: for a mechanical change with broad blast radius where vertical slices are invalid, use expand → migrate in bounded batches by blast-radius seam → contract; keep the old form available until migration is complete and validated.

Do not over-specify, dictate implementation details, or invent unresolved product decisions. If the SPEC exposes missing or contradictory product decisions, report it is not ready to split safely.

Do not edit files or begin implementation.
