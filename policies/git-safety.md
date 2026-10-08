# Git Safety and Commit Policy

## Precedence
Inspect repository-local Git conventions before committing.
If the repository defines commit or authorship rules, follow those rules. Otherwise, use this policy as the default.

## Commit format
Use Conventional Commits:
- `feat:`
- `fix:`
- `chore:`
- `docs:`
- `refactor:`
- `test:`

## Authorship
Use the Git author configured in the repository/local environment as the sole author.

Do not add:
- `Co-Authored-By: Claude`
- `Co-Authored-By: ChatGPT`
- any other AI co-author metadata

Do not modify Git user identity solely for an AI-generated change.

## Safety
Do not:
- force-push;
- rewrite shared history;
- bypass repository protections;
- reset or discard unrelated user changes;
- amend unrelated commits;
- push, merge, deploy, or publish unless explicitly requested.

If the working tree contains unrelated modifications, preserve them and keep the task scoped.

## Commit timing
Commit only after the current bounded unit passes its required validation.
For multi-phase work, prefer one validated commit per meaningful phase.
