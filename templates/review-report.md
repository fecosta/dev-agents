# Independent Review Report

- SPEC / task:
- Commit(s) reviewed:
- Reviewer route:
- Implementation model family:
- Evidence inspected:
- Blocking findings:
  - `<id>` — <one-line description> — `blocking` — `Eligible for automatic remediation: yes | no | uncertain — <reason>`
- Non-blocking findings:
  - `<id>` — <one-line description> — `non-blocking` — `Eligible for automatic remediation: yes | no | uncertain — <reason>`
- Verdict: `PASS` / `PASS_WITH_NOTES` / `CHANGES_REQUIRED`
- Required follow-up:
- Prior findings status (re-review only): `<id> — resolved|still open|not re-checked`, ... | none

> **Finding IDs.** Use stable IDs: `R<cycle>-<n>` for reviewer findings, `I-<n>` for implementer/assessor findings. IDs are never reused across cycles. New findings in a re-review receive new IDs.
>
> **Automatic remediation eligibility.** For each finding, the reviewer states whether it is eligible for one bounded automatic remediation cycle. If the field is omitted, ambiguous, or `uncertain`, the orchestrator treats it as ineligible and stops for human decision. Security, architecture, scope-expansion, and ambiguous findings must be marked `no`.
>
> **Prior findings status.** In a focused re-review, explicitly record the status of every original finding. `resolved` only when the fix is confirmed and no regression is found. `still open` when the finding persists. `not re-checked` when the review did not examine it.
