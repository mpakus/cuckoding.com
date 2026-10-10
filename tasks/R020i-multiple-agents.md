# R020i · Multiple saved agents

Status: implemented and verified, 2026-10-10; local integration recorded in worklog.

- [x] Settings lists independent named connections and offers Add agent plus the four-step wizard.
- [x] Codex connections retain separate profiles, observations and selected models; existing Codex data/bindings survive.
- [x] Cursor supports bounded private-profile version, login/logout and account/model discovery; unsupported inference is explicit.
- [x] Each Team role chooses a saved connection and only that connection's selected models. Planning follows the assigned Codex connection without fallback.
- [x] Regression checks cover isolation, stale/foreign forms, migration preservation, provider parsing/cancellation and mixed bindings.
- [x] Update docs/AGENTS/README, verify, build/run and merge locally to main.

Real Cursor login completion/catalog and Cursor inference are not accepted by
this setup slice. Packaged version/status/login-start/cancel passed; mixed model
selection is covered by fixtures. Browser roster verified; deeper wizard checks
use LiveView regressions because the native browser was actively in use.
