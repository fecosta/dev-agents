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
NINEROUTER_DB=/path/to/data.sqlite ./integrations/opencode/scripts/resolve-model-family.sh <start-id> <end-id> <combo-name>
```

- Default DB path: `~/.9router/db/data.sqlite`; override with `NINEROUTER_DB`.
- `start-id`, `end-id`: non-negative integers with `end-id >= start-id` (else `INVALID_WINDOW`). Only rows with `id > start-id AND id <= end-id` are inspected.
- `combo-name`: OpenCode combo (e.g. `economy`, `standard`, `strong`, `premium`); must match `[A-Za-z0-9._-]+` and is never echoed unless valid.
- **Window capture (for v3b.2):** capture `start-id` (max `usageHistory.id`) immediately before child delegation and `end-id` immediately after child completion. This keeps later orchestrator traffic out of the window.

**Output contract (key=value, one per line):**

- `status=resolved combo= window= family= reviewer= models= providers= usage_ids=` (exit 0). `family=claude` -> `reviewer=review-openai`; `family=non-claude` -> `reviewer=review-claude`.
- `status=ambiguous reason=MODEL_DETECTION_AMBIGUOUS` (exit 5) when the window holds both families.
- `status=failed reason=<CODE>` otherwise. Exit codes: 2 `USAGE`/`INVALID_CHECKPOINT`/`INVALID_WINDOW`/`INVALID_COMBO_NAME`/`SQLITE3_NOT_FOUND`/`DB_NOT_FOUND`/`DB_NOT_READABLE`; 3 `COMBO_NOT_FOUND`; 4 `MODEL_DETECTION_FAILED`; 6 `RUNTIME_ERROR`/`MODEL_PARSE_FAILED`; 7 `MODEL_FAMILY_UNKNOWN`; 8 `MODEL_ATTRIBUTION_UNKNOWN`; 9 `UNSAFE_OUTPUT_VALUE`.

**Fail-closed behavior:**

- Family: Claude if provider/model contains `claude` or `anthropic` (case-insensitive); non-Claude only if the model contains `gpt`, `codex`, `kimi`, `deepseek`, or `glm`. Anything else is `MODEL_FAMILY_UNKNOWN`, never assumed non-Claude.
- Attribution: combo entries are `route/model`. A usage row counts only if its model matches a candidate **and** its provider matches that route's runtime provider (`cc`->`claude`, `cx`->`codex`, `ocg`->`opencode-go`, `dmas`->`anthropic-compatible-*`, `oc-dmas`->`openai-compatible-responses-*`; mapping documented with evidence in the resolver). Unknown route prefix, NULL/other provider, or provider/model basename collisions yield `MODEL_ATTRIBUTION_UNKNOWN`. Duplicate basenames across routes never widen the match.
- Safe output: every emitted provider/model value must match `[A-Za-z0-9._-]+`; otherwise `UNSAFE_OUTPUT_VALUE`. No credential fields are ever selected or printed.

The resolver is strictly read-only: it opens SQLite with `-readonly` and `PRAGMA query_only=1`, issues only `SELECT`, and reads only `combos.name/models` and `usageHistory.id/provider/model/status`. It does not use SQLite JSON1.

**Known limitation:** `usageHistory` has no session/correlation id, so unrelated concurrent traffic *inside* the window with the same provider and model cannot be distinguished (mixed families or unmapped providers fail closed; identical provider/model traffic does not). Traffic after `end-id` (including the orchestrator's own) is excluded.

**Tests:** `integrations/opencode/scripts/test-resolve-model-family.sh` (bash 3.2+; uses temporary DBs only). Because the resolver does not use JSON1, there is no JSON1-unavailable fallback to test.

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
