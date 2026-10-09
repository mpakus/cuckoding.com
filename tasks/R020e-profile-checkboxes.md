# R020e — Preserve profile consent checkboxes

Status: complete, 2026-10-08. Branch: `fix/R020e-profile-checkboxes`.

- [x] Reproduce login/connection checkbox resets on clock updates; include sign-out's identical form pattern.
- [x] Keep checked state through timer/unrelated broadcasts and allow deliberate unchecking; clear on submission/setup change/recovered stale forms.
- [x] Preserve separate action consent, revision checks and session authorization; add focused regressions.
- [x] Verify the packaged UI, update docs/README/AGENTS, merge local main and remove the branch.
- [x] Rebuild/relaunch the user's test instance with its existing data/profile preserved. No provider action, push or deployment.

Evidence: [worklog](../worklog/2026-10-08-R020e-profile-checkboxes.md).
