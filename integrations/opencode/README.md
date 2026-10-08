# OpenCode integration

This adapter turns the portable dev-agents contracts into native OpenCode commands and an orchestrator agent.

## Milestones

- **v2 (history):** `/implement-spec` routes and delegates exactly one bounded implementation unit to `economy`, `standard`, `strong`, or `premium`.
- **v3a:** conditional independent review and opposite-family routing, with `REVIEW_BLOCKED_MODEL_UNKNOWN` when the family was not observable.
- **v3b.1:** standalone 9Router runtime model resolver (below).
- **v3b.2:** the orchestrator uses the resolver to pick the opposite-family reviewer from runtime evidence, and fails closed otherwise (see "Runtime family detection flow").
- **v3c.1 (current):** read-only orchestration doctor and health checks (`/doctor`, `doctor.sh`; see "Doctor (v3c.1)"). No routing, resolver, reviewer-selection or review-semantics change.

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
cp integrations/opencode/scripts/resolve-model-family.sh integrations/opencode/scripts/review-route.sh integrations/opencode/scripts/doctor.sh ~/.config/opencode/scripts/
cp integrations/opencode/agents/doctor.md ~/.config/opencode/agents/
```

`commands/*.md` already includes `doctor.md`. `agents/doctor.md` is a separate, read-only diagnostic agent used only by `/doctor`; it does not touch or replace the orchestrator. The scripts must stay executable (`cp` preserves the mode of the repo files).

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

Helper: `review-route.sh` (bash 3.2+, `sqlite3` only), located by the helper-resolution rule below. Tests: `integrations/opencode/scripts/test-review-route.sh` (temporary DBs and stub resolvers only; never the live DB).

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

**Helper lookup (identical to the rule in `agents/orchestrator.md`; `commands/implement-spec.md` refers to it):**

Order: (1) the installed `~/.config/opencode/scripts/review-route.sh`, if executable; (2) otherwise, only when running from a dev-agents checkout (the git top level contains `integrations/opencode/agents/orchestrator.md`), `integrations/opencode/scripts/review-route.sh` at that top level, if executable; (3) otherwise `REVIEW_ROUTE_HELPER_UNAVAILABLE`. No other path is ever used. The install step above copies the helper next to `resolve-model-family.sh`, which the helper finds in its own directory. Before delegation a missing helper reports `Review/runtime setup: blocked`, `Model resolution: blocked`, `Model resolution reason: REVIEW_ROUTE_HELPER_UNAVAILABLE` and delegates nothing; after delegation it is `REVIEW_BLOCKED_MODEL_RESOLUTION` with that reason and no reviewer.

**Checkpoints are mandatory, with no exceptions.**

- No valid start checkpoint => no delegation to `economy`/`standard`/`strong`/`premium`, for any task (docs-only, economy, low-risk, review-not-required, or otherwise). Report `Review/runtime setup: blocked`, `Model resolution: blocked`, `Model resolution reason: START_CHECKPOINT_FAILED`; stop.
- Child returned but the end checkpoint fails => stop blocked regardless of the review decision. Report `Model resolution: blocked`, `Model resolution reason: END_CHECKPOINT_FAILED`, `Independent review: REVIEW_BLOCKED_MODEL_RESOLUTION`; never mark it unavailable and never continue to normal completion.

**Resolver output accepted by `review-route.sh resolve`** (checked against `resolve-model-family.sh`; anything else is `RESOLVER_OUTPUT_INVALID`). Every line is `key=value` with `[A-Za-z0-9._,-]` values; no duplicate, missing, or extra keys.

- `status=resolved` (exit exactly 0): exactly one each of `status`, `combo`, `window`, `family`, `reviewer`, `models`, `providers`, `usage_ids`. `combo` equals the requested alias; `window` equals `<start>-<end>` (numeric, normalized); `family` is `claude` (`reviewer=review-openai`) or `non-claude` (`reviewer=review-claude`); `models`/`providers` are non-empty comma lists of safe values; `usage_ids` is a non-empty comma list of digits. `families` or `reason` in a resolved result is invalid.
- `status=ambiguous` (exit 5): exactly `status`, `combo` (= requested alias), `reason=MODEL_DETECTION_AMBIGUOUS`, `models`, `families=claude,non-claude`, `providers`. Blocks with `MODEL_DETECTION_AMBIGUOUS`.
- `status=failed`: exactly `status` and `reason` (plus `combo` = requested alias for `COMBO_NOT_FOUND` and `MODEL_DETECTION_FAILED`), with the documented exit code: 2 `USAGE`/`INVALID_CHECKPOINT`/`INVALID_WINDOW`/`INVALID_COMBO_NAME`/`SQLITE3_NOT_FOUND`/`DB_NOT_FOUND`/`DB_NOT_READABLE`; 3 `COMBO_NOT_FOUND`; 4 `MODEL_DETECTION_FAILED`; 6 `RUNTIME_ERROR`/`MODEL_PARSE_FAILED`; 7 `MODEL_FAMILY_UNKNOWN`; 8 `MODEL_ATTRIBUTION_UNKNOWN`; 9 `UNSAFE_OUTPUT_VALUE`. Blocks with that fixed reason constant (never raw resolver text).
- Undocumented status or reason, status/reason mismatch, exit-code/schema disagreement, or any other output: `RESOLVER_OUTPUT_INVALID`.

| Outcome | Behavior |
| --- | --- |
| Review not required (valid start and end checkpoints) | Resolution skipped; no family claimed; stop |
| `status=resolved`, `family=claude`, `reviewer=review-openai` | Launch `review-openai` |
| `status=resolved`, `family=non-claude`, `reviewer=review-claude` | Launch `review-claude` |
| Documented resolver failure or ambiguity (schemas above) | `REVIEW_BLOCKED_MODEL_RESOLUTION` with that documented reason; no reviewer |
| Undocumented status/reason, status/reason or exit-code mismatch, schema violation | `REVIEW_BLOCKED_MODEL_RESOLUTION`, reason `RESOLVER_OUTPUT_INVALID`; no reviewer |
| Resolver missing or not executable | `REVIEW_BLOCKED_MODEL_RESOLUTION`, reason `RESOLVER_UNAVAILABLE`; no reviewer |
| Helper not found by the lookup rule | `REVIEW_ROUTE_HELPER_UNAVAILABLE`; no delegation (before start) or no reviewer (after) |
| End checkpoint fails (any review decision) | `REVIEW_BLOCKED_MODEL_RESOLUTION`, reason `END_CHECKPOINT_FAILED`; no reviewer; never continues to completion |
| Start checkpoint fails (any task) | No delegation; `Review/runtime setup: blocked`, reason `START_CHECKPOINT_FAILED` |

Review stays required for every blocked outcome. `REVIEW_BLOCKED_MODEL_UNKNOWN` is a legacy v3a status for when no runtime evidence mechanism exists; resolver failures never use it. The report adds `Review/runtime setup` (only when blocked before delegation), `Start checkpoint`, `End checkpoint`, `Model resolution` (resolved|blocked|skipped), `Model resolution reason` (when blocked), `Actual models and providers`, `Actual family`, `Reviewer`, and `Verdict`/block status.

**Limitations (accepted, no heuristic fallback):**

- `usageHistory` has no session/correlation id. Orchestrator calls during delegation or end-checkpoint capture, and unrelated concurrent traffic, can fall inside the window. The integration never subtracts rows it assumes belong to the orchestrator (no removal by model, family, newest/oldest row, or picking one row).
- Ambiguous resolution is expected sometimes, for example overlapping `strong`/`premium` traffic whose families differ. It blocks review rather than guessing.
- The family is never inferred from the capability tier, combo definition, fallback order, child alias, or provider assumptions, and children are never asked to self-report it as authority.
- Future upgrade path: a 9Router/OpenCode session correlation id recorded per usage row, which would let the resolver scope the window exactly.

## Doctor (v3c.1)

Read-only health check for the installed orchestration. Run `/doctor` in OpenCode, or directly:

```bash
~/.config/opencode/scripts/doctor.sh [--machine] [--quiet]
```

- Default: one line per check `PASS|WARN|FAIL  <name>  <detail>` (recommended fix commands indented under non-pass checks as `hint: ...`), a `Summary:` line, then the stable lines `overall=pass|warn|fail`, `passed=N`, `warnings=N`, `failed=N`.
- `--machine`: machine lines only. Per check `check=<name>`, `status=pass|warn|fail`, `detail=<safe text>`, plus `hint=<text>` for non-pass checks; then the summary lines. Split each line at the first `=`.
- `--quiet`: only non-pass checks (with hints) and the summary; combines with `--machine`.
- **Exit codes:** `0` all PASS (skipped checks count as PASS), `1` at least one WARN and no FAIL, `64` usage error, `2` at least one FAIL.
- **Meaning:** FAIL = the installed orchestration cannot work or is unsafe to use (missing required tool/file/config/table, helper or resolver misbehaving). WARN = degraded, stale or unverifiable (stale or missing optional file, `jq` missing, a dependent check that could not run because its prerequisite failed: `not checked: ...`).

Checks (names are stable):

| Group | Checks |
| --- | --- |
| Executables | `exe_bash`, `exe_sqlite3` (missing = FAIL), `exe_git` (missing = WARN), `exe_opencode` (missing = FAIL); versions are reported |
| Installed files (`~/.config/opencode`) | `installed_orchestrator`, `installed_commands` (implement-spec, route-task, review-change, split-spec), `installed_scripts` (review-route.sh, resolve-model-family.sh; must be executable); all FAIL if absent. `installed_doctor` (doctor command, agent, script): missing = WARN |
| Stale installs | `orchestrator_sync`, `command_sync` (every repo `commands/*.md`), `review_route_sync`, `resolver_sync`, `doctor_sync`: SHA-256 (`cksum` fallback) of the installed copy vs the repository; difference or missing = WARN `installed copy differs from repository` |
| OpenCode config | `config_file` (`opencode.json` exists and is valid JSON; missing/invalid = FAIL; no `jq` = WARN, agent checks then `not checked`), `config_impl_agents` (economy/standard/strong/premium: mode `all`, model `9router/*`), `config_review_agents` (review-openai/review-claude: mode `subagent`, model `9router/*`), `config_explorer` (mode `subagent`; WARN if not). Both the `agent` and `agents` keys are read. Upstream model names behind the 9Router aliases are not checked |
| 9Router DB (read-only metadata) | `db_file`, `db_open`, `db_combos` (`name`, `models`), `db_usagehistory` (`id`, `provider`, `model`, `status`); path `${NINEROUTER_DB:-$HOME/.9router/db/data.sqlite}` |
| Helpers | `checkpoint` (installed `review-route.sh checkpoint start`: exit 0, exactly one `^[0-9]{1,15}$` line, empty stderr), `resolver_syntax` (`bash -n`), `resolver_smoke_non_claude` / `resolver_smoke_claude` (installed resolver on a temporary fixture DB must yield `family=non-claude reviewer=review-claude` and `family=claude reviewer=review-openai`), `framing_valid` / `framing_malformed` / `framing_trailing_blank` (installed `review-route.sh resolve` run against stub resolvers via its `DEV_AGENTS_RESOLVER` override: valid output accepted, malformed or blank-line-framed output rejected with `RESOLVER_OUTPUT_INVALID`) |

Sync checks run only when `doctor.sh` is executed from a dev-agents checkout (its own location is `<root>/integrations/opencode/scripts` and `<root>/integrations/opencode/agents/orchestrator.md` exists). Elsewhere (for example the installed copy) they report `status=pass detail=skipped (not a dev-agents checkout)` and do not affect the exit code. To check for stale installs, run `integrations/opencode/scripts/doctor.sh` from the checkout.

**Strictly read-only:** the doctor never installs, copies, repairs or edits anything and never changes Git, OpenCode config or 9Router. It reads files, opens the DB with `sqlite3 -readonly` + `PRAGMA query_only=1` (only `sqlite_master`/`table_info` metadata plus the checkpoint `MAX(id)`), and does fixture tests in a `mktemp` directory removed on exit. It never selects credential-bearing columns and never prints config values, so no secrets appear in output. It never calls an LLM.

**Recommended manual sync** (printed as hints only; run them yourself from the checkout, auto-sync is a later unit):

```bash
cp integrations/opencode/agents/*.md ~/.config/opencode/agents/
cp integrations/opencode/commands/*.md ~/.config/opencode/commands/
cp integrations/opencode/scripts/resolve-model-family.sh integrations/opencode/scripts/review-route.sh integrations/opencode/scripts/doctor.sh ~/.config/opencode/scripts/
```

**`/doctor` agent:** `commands/doctor.md` runs with the separate `doctor` agent (`agents/doctor.md`), which denies every action except the shell command `~/.config/opencode/scripts/doctor.sh`. It cannot edit files and does not use the orchestrator.

**Limitations:** the doctor does not validate volatile upstream models behind the 9Router aliases or live 9Router connectivity; the fixture smoke tests are not the full suites (run `test-resolve-model-family.sh`, `test-review-route.sh` and `test-doctor.sh` from the checkout for those). The usage-history window limitation described above is unchanged. Tests: `integrations/opencode/scripts/test-doctor.sh` (bash 3.2+; temporary HOME, config and DB only).

## First test

Use a harmless docs-only task in a clean or understood working tree:

```text
/implement-spec Update one explicitly named README sentence from X to Y.
```

Expected flow:

1. orchestrator inspects repository state;
2. selects `economy`;
3. captures the start checkpoint (if that fails, nothing is delegated, even for a docs-only task) and launches `economy` as a child session;
4. child edits only the bounded target;
5. child validates and commits;
6. child returns a handoff; orchestrator captures the end checkpoint (a failure here also stops, blocked);
7. a docs-only sentence change is typically not review-worthy, so the orchestrator reports `Model resolution: skipped (independent review not required)` and stops;
8. no push, merge, or deploy.
