---
description: Run the read-only OpenCode orchestration health check and summarize results. Never repairs anything.
agent: doctor
subagent: false
---

Run the dev-agents orchestration doctor: `~/.config/opencode/scripts/doctor.sh $ARGUMENTS`

Allowed arguments: none, `--quiet`, or `--machine`.

Then summarize:
1. the `overall=` result and the passed/warnings/failed counts;
2. each WARN or FAIL check with its detail, most severe first;
3. the recommended manual fix commands (the `hint:` lines), for the user to run themselves.

This command is read-only. Do not edit files, copy files, change OpenCode or 9Router configuration, run Git write commands, or run any fix command. Do not delegate to the orchestrator or any implementation agent. Never print secrets.
