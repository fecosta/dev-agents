# Validation efficiency

Reduce redundant validation inside one `/implement-spec` authorization by reusing unchanged validation evidence and running targeted validation after remediation. Fail closed when reuse cannot be proven safe.

## 1. Declared validation scope

Each validation command must declare the files, file globs, or project-specific dependency surface it covers. Declarations may come from:

- project `AGENTS.md`;
- the SPEC/task acceptance criteria;
- the implementation handoff.

If no scope is declared, treat the command as covering the entire repository for staleness purposes. Do not infer narrow coverage from a command's name.

A dependency surface is a project-specific relation (for example a module import graph, build-system edge set, or package manifest) that lets a change in one file affect another file without editing it directly. Projects may declare their dependency surface in `AGENTS.md` or the SPEC.

## 2. Evidence format

Validation evidence is lightweight and session-local. Each entry records:

```text
<command> — <result> — [label] — at <commit>
```

where:

- `command`: the exact command that produced the evidence.
- `result`: `passed`, `failed(<cause>)`, `partial`, `not_run`, or `unknown`.
- `label`: `[observed]`, `[reported]`, or `[human]`.
- `commit`: the SHA the evidence was produced against.

Failures add `cause: unexplained|identified:<category>`.

Evidence is **trustworthy** only when the label is `[observed]` or the source is otherwise verifiable. Evidence whose original result was `partial`, `not_run`, `unknown`, or `failed` is never reused as proof of correctness.

## 3. Evidence reuse rules

A validation command's evidence may be reused only when all of the following hold:

1. The validation command is identical to the one that produced the evidence.
2. The declared scope (files, globs, or dependency surface) is unchanged at the final commit.
3. No file in the declared scope changed between the evidence commit and the final commit.
4. No relevant dependency in the declared dependency surface changed between the evidence commit and the final commit.
5. The execution environment is unchanged (same tool versions, same environment variables that affect the command).
6. The evidence commit is the current assessed commit or an ancestor of it.
7. The evidence is complete (`passed`) and trustworthy.

If any condition cannot be established, treat the evidence as stale.

## 4. Staleness triggers

Evidence is stale and must not be reused when:

- the referenced commit is not the current assessed commit or an ancestor of it;
- any file in the declared scope changed after the evidence was produced;
- the declared scope, command, tool version, or relevant environment changed;
- the orchestrator cannot determine whether the scope or environment is unchanged;
- the original evidence was `partial`, `not_run`, `unknown`, or `failed`.

Missing evidence is stale by default. Fail closed: never accept missing evidence as proof of correctness.

## 5. Targeted validation after remediation

After remediation:

1. Identify the files and dependency surfaces the remediation changed.
2. Re-run every validation command whose declared scope intersects those files or surfaces.
3. Also re-run any command that previously failed, regardless of scope intersection.
4. Reuse unrelated validation evidence only when the reuse conditions are satisfied.
5. Run broader validation when any of the following hold:
   - the remediation touches shared/core files;
   - a declared dependency surface changed;
   - a project policy or acceptance criterion requires the full suite;
   - the initial validation had unexplained failures;
   - the orchestrator cannot determine whether a narrower command is safe.

Validation must pass before the remediation commit is accepted.

## 6. Evidence reporting

Record, for each validation command, whether it was:

- `executed` during the current cycle;
- `reused` from earlier execution (with the evidence commit SHA);
- `re-run` because evidence became stale;
- `blocked` or `unavailable` (with reason).

Keep the report lightweight and compatible with the implementation handoff. No validation database, persistent cache, or orchestration framework is introduced.

## 7. Fail-closed summary

When in doubt, re-run. Stale or missing evidence never supports acceptance.
