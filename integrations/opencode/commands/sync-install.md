---
description: Preview (default) or apply a safe sync of the dev-agents OpenCode integration into ~/.config/opencode. Writes only with a literal --apply.
agent: sync-install
subagent: false
---

Run the dev-agents install sync helper from the current project (it must be a dev-agents checkout): `integrations/opencode/scripts/sync-install.sh $ARGUMENTS`

Allowed arguments: none, `--check` (both are a read-only preview), or `--apply`. Writes happen only when `$ARGUMENTS` literally contains `--apply`; never infer it from other wording.

Then summarize:
1. the per-file `status=` (`in_sync`, `missing`, `different`) and, for `--apply`, the `copied=` / `chmodded=` files;
2. the final `sync_status=` (`clean`, `drift`, `failed`) with the in_sync/different/missing counts and any `reason=`;
3. for `--apply`, the post-install doctor result (`doctor_overall`, `doctor_passed`, `doctor_warnings`, `doctor_failed`, and any non-pass `doctor_check*` lines);
4. the exit code meaning: `0` clean or applied, `1` drift (preview), `2` setup, validation or post-install failure, `64` usage error.

The installed copy `~/.config/opencode/scripts/sync-install.sh` fails closed outside a checkout (`SOURCE_REPOSITORY_UNVERIFIED`); always use the checkout's script. If the project is not a checkout, report that and stop.

Do not edit or copy files yourself, change `opencode.json`, provider or 9Router configuration, run Git commands, or delegate to the orchestrator or any implementation agent. Never print secrets.
