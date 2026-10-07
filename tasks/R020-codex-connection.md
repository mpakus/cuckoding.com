# R020 — Codex connection and durable models

Status: R020a version readiness, R020b inspection/cache, R020c managed sign-in/out and R020d fixed model check delivered; parent R020 remains partial.
Date: 2026-10-06. Branch: `feature/r020-codex-connection`.
Installed runtime observed: Codex CLI 0.146.0; schema generated from that binary.

## R020a delivered acceptance

- [x] Manual executable selection and fresh confirmation; discovery remains metadata-only.
- [x] Native fixed version check, private scratch/HOME, clean environment,
  bounded output, timeout/cancellation and owned process-group cleanup.
- [x] Adapter version boundary, durable keys/revisions/intent/results and public
  audit events; separate compatibility and not-connected account status.
- [x] Reconnectable LiveView result, input preservation, elapsed state and Cancel.
- [x] Malformed/split/oversized/nonzero output, canaries, identity changes,
  interrupted claims, late completion, descendants, prior-schema copy and UI checks.
- [x] Real installed Codex 0.146.0 observed through the packaged app/browser.
- [x] Update docs, AGENTS and README; verify and integrate this slice into local main.

## Remaining R020 acceptance

- [ ] Extend the adapter to bounded structured runtime transport and permissions.
- [x] Separate detection, compatibility, app-owned login/status/logout; persist
  non-secret connection state and public audit events in SQLite.
- [ ] Fetch and retain validated model metadata after login, expose source/freshness,
  refresh without confusing catalog failures with authorization failures.
- [x] Extend LiveView controls to sign-in/model operations; keep login
  credentials/URLs out of logs and stored events.
- [ ] Cover malformed/split/oversized protocol, canaries, restart and lost-process
  outcomes, plus migration and UI behavior.
- [ ] Prove real-provider sign-in/model reuse and scoped read/write execution across
  two isolated workspaces; separate unavailable human/account gates honestly.

R020b implements private-profile status and the durable model-catalog path with
fixture coverage, plus real signed-out inspection. See [R020b](R020b-codex-connection-inspection.md).
[R020c](R020c-codex-sign-in.md) adds managed sign-in/out, transient links and
account-change invalidation. [R020d](R020d-model-access-check.md) adds one bounded,
consented model diagnostic, with real restrictive thread preflight but fixture-only
successful responses. Next: human-completed sign-in/model validation;
retain real authorization and two-workspace execution as separate proof gates.
R020a is not evidence of sign-in, models or task execution.
