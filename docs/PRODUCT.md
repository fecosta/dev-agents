# Product

Canonical product-level document for this repository. It is intentionally split into three distinct sections: CURRENT STATE describes what exists and works today, DECISIONS records choices already made and their rationale, and FUTURE VISION describes intended direction rather than commitments. Operational contracts (routing, review, Git safety, integration behavior) are not repeated here; they live in the documents linked at the end.

## CURRENT STATE

*What exists and works today: purpose, users, scope, capabilities, boundaries, and limitations of the current product.*

### Purpose

dev-agents is a portable development orchestration system that turns bounded engineering work into safely routed, independently reviewed, and verifiable AI-assisted implementation — while preserving the repository's product intent, engineering rules, and Git safety boundaries.

### Problem

AI coding agents are individually capable, but reliable software development requires more than choosing a strong model. Work must be scoped, routed according to risk, executed within project constraints, independently reviewed when required, and leave behind a trustworthy repository state.

### Primary user

An AI-assisted developer who wants to delegate real engineering work without giving a single agent unrestricted control over the development process.

### Primary job to be done

When I delegate software development to AI, I want the work automatically scoped, assigned to appropriate capability, validated, and independently reviewed when necessary, so that I can trust the resulting repository state without manually supervising every model decision.

### Product model

product intent / SPEC / bounded task → scope + risk assessment → capability-based routing → bounded implementation → validation + Git state → runtime provenance → independent opposite-family review when required → verified handoff.

### Currently implemented orchestration capabilities

- `/implement-spec` as the implementation entry point.
- `economy`, `standard`, `strong`, and `premium` capability tiers.
- Control-plane protection: changes to orchestration behavior, routing, review, permissions, Git safety, or agent instructions are treated as at least `standard` and require independent review when they alter execution behavior.
- Mandatory runtime start/end checkpoints around implementation delegation.
- 9Router runtime model-family resolution.
- Opposite-family independent review when required.
- `/doctor` read-only diagnostics.
- `/sync-install` safe OpenCode integration synchronization.

### Product boundaries

- dev-agents is not a coding model.
- dev-agents owns development orchestration contracts.
- OpenCode is currently an execution runtime/adapter.
- 9Router provides model/provider routing and runtime usage evidence.
- AI providers/models perform model execution.
- Headroom may participate in the development environment but is not automatically part of the core orchestration contract.
- Product Coherence OS owns product intent, decisions, specification readiness, and post-implementation product-coherence validation; dev-agents owns safe and verifiable AI development execution once a bounded implementation unit exists.

### Known current limitations

- 9Router `usageHistory` currently lacks a session/correlation ID, so bounded runtime windows reduce but cannot completely eliminate attribution ambiguity under concurrent identical provider/model traffic.
- `sync-install` retains its documented residual filesystem check-then-act limitation.

## DECISIONS

*Choices already made, each with its rationale and current status.*

### Product principles

- **Capability and risk before cost.** Choose the minimum capability tier that safely clears the task's quality threshold; do not downgrade below the safe tier merely to save cost. This applies the routing policy in [`policies/model-routing.md`](../policies/model-routing.md).
- **Bounded execution.** Oversized work is split into independently verifiable phases or units, and each delegation implements only the current bounded unit. This follows the core workflow in [`AGENTS.md`](../AGENTS.md).
- **Repository authority.** Product intent, engineering rules, and Git safety boundaries live in the repository and must be preserved across delegations. The authority order in [`AGENTS.md`](../AGENTS.md) and the Git rules in [`policies/git-safety.md`](../policies/git-safety.md) enforce this.
- **Fail closed when required evidence is missing, unknown, or ambiguous.** When the runtime model family or checkpoints cannot be observed or are ambiguous, independent review is blocked rather than guessed. This is implemented by the 9Router resolver and `review-route.sh` behavior documented in [`integrations/opencode/README.md`](../integrations/opencode/README.md).
- **Independent review when required.** Control-plane changes and other high-risk or complex work are verified by an opposite-family reviewer. This follows [`policies/review-routing.md`](../policies/review-routing.md) and the orchestrator instructions in [`integrations/opencode/agents/orchestrator.md`](../integrations/opencode/agents/orchestrator.md).
- **Runtime evidence over model-family assumptions.** The actual implementation family is resolved from 9Router runtime usage rather than inferred from capability aliases, combo definitions, or provider assumptions. This is enforced by the resolver contract in [`integrations/opencode/README.md`](../integrations/opencode/README.md).
- **Git safety is part of the product contract.** Commits happen only after validation passes, use the configured local Git author, add no AI co-author metadata, and never force-push, rewrite shared history, or bypass protections. This follows [`policies/git-safety.md`](../policies/git-safety.md).
- **Verification over apparent completion.** Implementation is followed by validation and, when required, independent review before handoff. This matches the product model and core workflow in [`AGENTS.md`](../AGENTS.md).

**Status:** Approved and implemented. Operational details remain authoritative in the linked documents.

## FUTURE VISION

*Intended direction and non-commitments; not a promise or a roadmap.*

### Direction

dev-agents may evolve toward a portable AI development control plane supporting multiple execution runtimes while preserving portable contracts such as bounded execution, risk-based capability selection, Git safety, runtime provenance, independent review, and fail-closed behavior.

### Non-commitments

This section contains no committed roadmap items. The only directional statement is above; any other future capability, runtime integration, or timeline is explicitly not committed.

## Related documents

- [AGENTS.md](../AGENTS.md) — global orchestration contract and authority order.
- Policies: [model-routing.md](../policies/model-routing.md), [review-routing.md](../policies/review-routing.md), [git-safety.md](../policies/git-safety.md), [context-budget.md](../policies/context-budget.md).
- [OpenCode integration](../integrations/opencode/README.md) — adapter, commands, and install/health behavior.
