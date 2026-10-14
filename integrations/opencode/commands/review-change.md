---
description: Prepare an independent review route and prompt. Does not launch the reviewer; automatic conditional review is performed by /implement-spec.
agent: orchestrator
subagent: false
---

Prepare independent review for: $ARGUMENTS

Read project instructions, the authoritative task/SPEC, current diff/commit state, and validation evidence. Determine whether review is required and which opposite-family reviewer should be used when the actual implementation family is known.

Do not edit files and do not launch the reviewer. Return the selected review route and a bounded review prompt.
