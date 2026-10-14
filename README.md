# dev-agents

Reusable orchestration contracts for capability-based AI development workflows with OpenCode, 9Router, and Headroom.

Product definition: [docs/PRODUCT.md](docs/PRODUCT.md).

## Capability aliases
- `economy`
- `standard`
- `strong`
- `premium`
- `review-openai`
- `review-claude`
- `explorer`

Concrete model/provider mappings live in OpenCode/9Router configuration, not in this repository.

## Development workflow overview
1. Identify the authoritative active SPEC or bounded task.
2. Select the minimum capability tier that safely clears the work.
3. Delegate one bounded unit.
4. Validate the implementation.
5. Commit validated work using repository Git conventions.
6. Produce a handoff.
7. Perform independent review when required.

Policies: [policies/](policies/).
