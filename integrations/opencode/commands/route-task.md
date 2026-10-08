---
description: Inspect and classify a development task without modifying files.
agent: orchestrator
subagent: false
---

Route this task: $ARGUMENTS

Read repository instructions and relevant context. Return:
- whether there is enough information to route;
- whether there is enough information to implement;
- risk;
- minimum safe capability tier;
- bounded scope;
- validation plan;
- whether independent review is required;
- escalation triggers.

Do not edit files, commit, push, merge, or deploy.
