# Model Routing Policy

Choose the minimum capability tier that safely clears the task's quality threshold.

## economy
Low-risk, reversible, easily verified work.

## standard
Normal bounded implementation with clear requirements and straightforward validation.

## strong
Multi-file or cross-layer work, integrations, substantial refactors, difficult debugging, or non-trivial product logic.

## premium
Authentication, authorization, RLS, permissions, migrations, destructive data changes, security, billing, deployment foundations, foundational architecture, or unresolved ambiguity.

Do not downgrade below the safe capability tier merely to save cost.

## Control-plane minimum

Changes that alter AI execution behavior are never `economy`, even when they are documentation-only.

Treat these as at least `standard`:

- orchestration instructions;
- routing policy;
- agent delegation behavior;
- review-routing behavior;
- Git-safety rules;
- tool permissions;
- execution guardrails;
- OpenCode/agent integration instructions.

Escalate to `strong` or `premium` when the change affects security, destructive operations, permissions, deployment, or high-risk automation.