# R012 — Asynchronous OTP workers and shared LiveComponents

Status: verified and merged locally to main as `9052733`, 2026-10-15.

- [x] Audit agent execution and application routes against the OTP/LiveView contract.
- [x] Run setup, authorization and planning in monitored supervised tasks, keeping
  the dispatcher responsive and its existing global single-command admission.
- [x] Couple each coordinator to its task supervisor so a coordinator restart
  cannot leave an old worker running beside a replacement. Persist interrupted
  claims without replay or invented cleanup evidence.
- [x] Keep validated login links transient in coordinator-owned protected ETS;
  accept progress/results only from the current task and refuse cancelled claims.
- [x] Standardize stateful components through `CuckodingWeb, :live_component`,
  preserving explicit component session guards, unsaved forms and route behavior.
- [x] Verify responsiveness, cancellation, worker/coordinator crash isolation,
  login-link handling and LiveView reconnect/session behavior; run quality gates.
- [x] Update architecture/decisions/plan, AGENTS and README.
- [x] Merge verified change into local main; feature branch deleted.

`mix quality`: 322 tests, formatter/compiler, Credo, Sobelow and dependency audit
passed. Source and packaged smoke passed; rebuilt saved workspace preserved.
Visual browser recheck was unavailable because the Mac was locked.
[Evidence](../worklog/2026-10-15-R012-otp-workers-components.md).

No provider inference, schema/grant changes or new frontend/dependencies. Native
helpers remain necessary for macOS enforcement and process ownership. Product
parallel workers and full uncertain-effect recovery stay separate acceptance gates.
