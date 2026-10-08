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

## 9Router runtime model resolver (v3b.1)

`integrations/opencode/scripts/resolve-model-family.sh` resolves the model family actually used by an OpenCode child session from 9Router's local SQLite usage store.

**Usage:**

```bash
NINEROUTER_DB=/path/to/data.sqlite ./integrations/opencode/scripts/resolve-model-family.sh <checkpoint-id> <combo-name>
```

- Default DB path: `~/.9router/db/data.sqlite`; override with `NINEROUTER_DB`.
- `checkpoint-id`: max `usageHistory.id` captured immediately before delegating to the child session.
- `combo-name`: OpenCode combo (e.g. `economy`, `standard`, `strong`, `premium`).

**Output contract (key=value, one per line):**

- `status=resolved family=claude reviewer=review-openai ...` when all matching rows are Claude models.
- `status=resolved family=non-claude reviewer=review-claude ...` when all matching rows are non-Claude models.
- `status=failed reason=<CODE>` for no combo, no matching rows, invalid args, DB errors, etc.
- `status=ambiguous reason=MODEL_DETECTION_AMBIGUOUS ...` when rows contain both Claude and non-Claude models.

The resolver is strictly read-only: it opens SQLite with `-readonly` and `PRAGMA query_only=1`, issues only `SELECT` statements, and never reads credential-bearing columns such as `apiKey`, `meta`, `connectionId`, `tokens`, or `endpoint`.

**Known limitation:** usage rows from unrelated concurrent sessions that happen to use the same combo models after the checkpoint cannot be distinguished. Capture a fresh checkpoint right before delegation to minimize this.

**v3b.1 scope:** this is a standalone resolver and test harness only. It does not change the orchestrator, commands, policies, or any automatic reviewer routing — integration comes later.

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
