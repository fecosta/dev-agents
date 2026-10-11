# split-spec

1. Split the SPEC into ordered, bounded units. Each unit is one coherent, independently implementable and verifiable outcome that preserves acceptance criteria, non-goals, security constraints, and data constraints; has a clear validation condition; and fits one fresh implementation context.
2. Prefer vertical slices: narrow but complete behavior across the layers it needs, independently demonstrable. Do not decompose by horizontal layer only.
3. State explicit dependencies per unit: what it delivers, what (if anything) it genuinely cannot begin until, and how completion is validated. Dependencies are ordering constraints only.
4. Preserve sequential execution: `/implement-spec` implements exactly one unit per invocation. No frontier execution, automatic traversal of ready units, parallel/concurrent implementers, worktree-per-unit orchestration, automatic continuation, or multi-unit execution.
5. Wide-refactor exception only: when a mechanical change has broad blast radius and vertical slices are invalid, use expand → migrate in bounded batches by blast-radius seam → contract. Keep the old form available until migration is complete and validated.
6. Do not over-specify or invent product decisions. If the SPEC exposes unresolved contradictions or missing decisions, report it is not ready to split safely.

Do not edit files or begin implementation.
