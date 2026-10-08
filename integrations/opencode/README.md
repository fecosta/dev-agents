# OpenCode integration

This adapter turns the portable dev-agents contracts into native OpenCode commands and an orchestrator agent.

## Milestones

- **v2 (history):** `/implement-spec` routes and delegates exactly one bounded implementation unit to `economy`, `standard`, `strong`, or `premium`.
- **v3a:** conditional independent review and opposite-family routing, with `REVIEW_BLOCKED_MODEL_UNKNOWN` when the family was not observable.
- **v3b.1:** standalone 9Router runtime model resolver (below).
- **v3b.2 (current):** the orchestrator uses the resolver to pick the opposite-family reviewer from runtime evidence, and fails closed otherwise (see "Runtime family detection flow").

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
mkdir -p ~/.config/opencode/scripts
cp integrations/opencode/scripts/resolve-model-family.sh integrations/opencode/scripts/review-route.sh ~/.config/opencode/scripts/
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
- **Window capture (v3b.2):** `start-id` (max `usageHistory.id`) is captured immediately before child delegation and `end-id` immediately after the child returns. Orchestrator calls made during delegation or end-checkpoint capture can still fall inside the window.

**Output contract (key=value, one per line):**

- `status=resolved combo= window= family= reviewer= models= providers= usage_ids=` (exit 0). `family=claude` -> `reviewer=review-openai`; `family=non-claude` -> `reviewer=review-claude`.
- `status=ambiguous reason=MODEL_DETECTION_AMBIGUOUS` (exit 5) when the window holds both families.
- `status=failed reason=<CODE>` otherwise. Exit codes: 2 `USAGE`/`INVALID_CHECKPOINT`/`INVALID_WINDOW`/`INVALID_COMBO_NAME`/`SQLITE3_NOT_FOUND`/`DB_NOT_FOUND`/`DB_NOT_READABLE`; 3 `COMBO_NOT_FOUND`; 4 `MODEL_DETECTION_FAILED`; 6 `RUNTIME_ERROR`/`MODEL_PARSE_FAILED`; 7 `MODEL_FAMILY_UNKNOWN`; 8 `MODEL_ATTRIBUTION_UNKNOWN`; 9 `UNSAFE_OUTPUT_VALUE`.

**Fail-closed behavior:**

- Family: Claude if provider/model contains `claude` or `anthropic` (case-insensitive); non-Claude only if the model contains `gpt`, `codex`, `kimi`, `deepseek`, or `glm`. Anything else is `MODEL_FAMILY_UNKNOWN`, never assumed non-Claude.
- Attribution: combo entries are `route/model`. A usage row counts only if its model matches a candidate **and** its provider matches that route's runtime provider (`cc`->`claude`, `cx`->`codex`, `ocg`->`opencode-go`, `dmas`->`anthropic-compatible-*`, `oc-dmas`->`openai-compatible-responses-*`; mapping documented with evidence in the resolver). Unknown route prefix, NULL/other provider, or provider/model basename collisions yield `MODEL_ATTRIBUTION_UNKNOWN`. Duplicate basenames across routes never widen the match.
- Safe output: every emitted provider/model value must match `[A-Za-z0-9._-]+`; otherwise `UNSAFE_OUTPUT_VALUE`. No credential fields are ever selected or printed.

The resolver is strictly read-only: it opens SQLite with `-readonly` and `PRAGMA query_only=1`, issues only `SELECT`, and reads only `combos.name/models` and `usageHistory.id/provider/model/status`. It does not use SQLite JSON1.

**Known limitation:** `usageHistory` has no session/correlation id, so unrelated concurrent traffic *inside* the window with the same provider and model cannot be distinguished (mixed families or unmapped providers fail closed; identical provider/model traffic does not). Only traffic after `end-id` is excluded; the orchestrator's own traffic during the window is not.

**Tests:** `integrations/opencode/scripts/test-resolve-model-family.sh` (bash 3.2+; uses temporary DBs only). Because the resolver does not use JSON1, there is no JSON1-unavailable fallback to test.

**v3b.1 scope:** the resolver and its test harness. The orchestrator integration is v3b.2, below.

## Runtime family detection flow (v3b.2)

Helper: `integrations/opencode/scripts/review-route.sh` (bash 3.2+, `sqlite3` only). Tests: `integrations/opencode/scripts/test-review-route.sh` (temporary DBs and stub resolvers only; never the live DB).

1. **Start checkpoint** immediately before delegating: `review-route.sh checkpoint start` runs the read-only query below and validates one integer (`^[0-9]{1,15}$`).
2. **Delegate** to the already-selected agent. The capability alias stays in orchestration state and becomes the resolver `<combo-name>`.
3. **End checkpoint** immediately after the child returns, before the review decision.
4. **Review decision** from the handoff (control-plane changes always need review). If review is not required, resolution is skipped and no family is reported.
5. **Resolve** (review required only): `review-route.sh resolve <start> <end> <alias>` runs `resolve-model-family.sh`, strictly validates the key=value output, and checks family and reviewer agree (`claude` -> `review-openai`, `non-claude` -> `review-claude`).
6. **Route** to that reviewer in a fresh read-only child session (one verdict: `PASS`, `PASS_WITH_NOTES`, `CHANGES_REQUIRED`; no automatic fix; no push/merge/deploy), or **fail closed** with `REVIEW_BLOCKED_MODEL_RESOLUTION`.

The only SQL the integration runs:

```bash
sqlite3 -init /dev/null -batch -list -noheader -readonly "$DB" ".timeout 2000" "PRAGMA query_only=1;" "SELECT COALESCE(MAX(id),0) FROM usageHistory;"
```

`DB` is `${NINEROUTER_DB:-$HOME/.9router/db/data.sqlite}`. No credential-bearing columns, no writes.

If the start checkpoint fails the orchestrator does not delegate (reported as a runtime-model-resolution setup failure, `START_CHECKPOINT_FAILED`). Only a certainly trivial, low-risk, non-control-plane task may proceed, reporting `Start checkpoint: unavailable` and `Model resolution: skipped (not needed)`. Control-plane tasks never proceed.

| Outcome | Behavior |
| --- | --- |
| Review not required | Resolution skipped; no family claimed; stop |
| `status=resolved`, `family=claude`, `reviewer=review-openai` | Launch `review-openai` |
| `status=resolved`, `family=non-claude`, `reviewer=review-claude` | Launch `review-claude` |
| Family/reviewer mismatch, missing/duplicate/unknown keys, bad output | `REVIEW_BLOCKED_MODEL_RESOLUTION`, reason `RESOLVER_OUTPUT_INVALID`; no reviewer |
| Resolver missing or not executable | `REVIEW_BLOCKED_MODEL_RESOLUTION`, reason `RESOLVER_UNAVAILABLE`; no reviewer |
| `MODEL_DETECTION_FAILED`, `MODEL_DETECTION_AMBIGUOUS`, `MODEL_FAMILY_UNKNOWN`, `MODEL_ATTRIBUTION_UNKNOWN`, `UNSAFE_OUTPUT_VALUE`, `MODEL_PARSE_FAILED`, `RUNTIME_ERROR`, other resolver reasons | `REVIEW_BLOCKED_MODEL_RESOLUTION` with that reason; no reviewer |
| End checkpoint fails (review required) | `REVIEW_BLOCKED_MODEL_RESOLUTION`, reason `END_CHECKPOINT_FAILED`; no reviewer |
| Start checkpoint fails | No delegation (setup failure), except the trivial non-control-plane case above |

Review stays required for every blocked outcome. `REVIEW_BLOCKED_MODEL_UNKNOWN` is a legacy v3a status for when no runtime evidence mechanism exists; resolver failures never use it. The report adds `Start checkpoint`, `End checkpoint`, `Model resolution` (resolved|blocked|skipped), `Model resolution reason` (when blocked), `Actual models and providers`, `Actual family`, `Reviewer`, and `Verdict`/block status.

**Limitations (accepted, no heuristic fallback):**

- `usageHistory` has no session/correlation id. Orchestrator calls during delegation or end-checkpoint capture, and unrelated concurrent traffic, can fall inside the window. The integration never subtracts rows it assumes belong to the orchestrator (no removal by model, family, newest/oldest row, or picking one row).
- Ambiguous resolution is expected sometimes, for example overlapping `strong`/`premium` traffic whose families differ. It blocks review rather than guessing.
- The family is never inferred from the capability tier, combo definition, fallback order, child alias, or provider assumptions, and children are never asked to self-report it as authority.
- Future upgrade path: a 9Router/OpenCode session correlation id recorded per usage row, which would let the resolver scope the window exactly.

## First test

Use a harmless docs-only task in a clean or understood working tree:

```text
/implement-spec Update one explicitly named README sentence from X to Y.
```

Expected flow:

1. orchestrator inspects repository state;
2. selects `economy`;
3. captures the start checkpoint and launches `economy` as a child session;
4. child edits only the bounded target;
5. child validates and commits;
6. child returns a handoff; orchestrator captures the end checkpoint;
7. a docs-only sentence change is typically not review-worthy, so the orchestrator reports `Model resolution: skipped (independent review not required)` and stops;
8. no push, merge, or deploy.
