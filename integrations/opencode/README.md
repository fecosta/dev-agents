# OpenCode integration v2

This adapter turns the portable dev-agents contracts into native OpenCode commands and an orchestrator agent.

## v2 milestone

`/implement-spec` now routes and automatically delegates exactly one bounded implementation unit to `economy`, `standard`, `strong`, or `premium`, then stops after the implementation handoff.

Independent review remains manual in v2 and will be automated in v3.

## Required OpenCode configuration change

The four implementation agents must be launchable as child agents. In OpenCode V2, set their mode to `all` rather than `primary`:

```json
"economy":  { "mode": "all", "model": "9router/economy" },
"standard": { "mode": "all", "model": "9router/standard" },
"strong":   { "mode": "all", "model": "9router/strong" },
"premium":  { "mode": "all", "model": "9router/premium" }
```

Keep `review-openai`, `review-claude`, and `explorer` as `subagent`.

## Install

Copy:

```bash
mkdir -p ~/.config/opencode/agents ~/.config/opencode/commands
cp integrations/opencode/agents/orchestrator.md ~/.config/opencode/agents/
cp integrations/opencode/commands/*.md ~/.config/opencode/commands/
```

OpenCode reloads command and agent files automatically, but using a fresh session is recommended for the first delegation test.

## First test

Use a harmless docs-only task in a clean or understood working tree:

```text
/implement-spec Update one explicitly named README sentence from X to Y.
```

Expected flow:

1. orchestrator inspects repository state;
2. selects `economy`;
3. launches `economy` as a child session;
4. child edits only the bounded target;
5. child validates and commits;
6. child returns a handoff;
7. orchestrator summarizes and stops;
8. no push, merge, deploy, or automatic review.
