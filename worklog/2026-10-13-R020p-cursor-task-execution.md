# R020p — Cursor task execution

Baseline: clean main `40ef4e6`, ahead of origin/main by 11 commits. User explicitly
chose to retain Cursor assignments and implement execution. No binding substitution.
Ponytail full, agent-adapter, local-runner, security-review and quality-gates apply.
RTK prefixes shell commands; proxy preserves exact source/protocol/build output.

Acceptance is in the task file. Existing Start blockers are Cursor unsupported
and stale assigned catalogs. Current runtime supports setup only; changing the
button alone would not implement execution.

References inspected 2026-10-13 (protocol only, no source copied):
- https://cursor.com/docs/cli/acp
- https://cursor.com/docs/cli/reference/permissions
- https://cursor.com/docs/cli/reference/parameters
- Installed Cursor `2026.09.15-d2fe57e`, proprietary runtime bundle,
  `2698.index.js:1` (ACP session/model/permission routing), `index.js:1`
  (private config-directory override). Runtime code is inspected only; not vendored.

## Progress

- Claimed task before edits. Catalog/status reads and empty-profile protocol probes
  do not authorize inference or an Arena battle.


## Implementation and findings

- Added `cursor-acp-v1` over the existing native host file service and durable
  battle executor. No migration, dependency or alternate scheduler. Mixed team
  fixtures retain exact connections through a review return and final completion.
- Cursor CLI/ACP names differ. The native CLI receives the exact saved alias;
  generated selection, explicit-selection flag and every ACP model parameter must
  agree. Only the native metadata's default reasoning label may be absent from
  the CLI display name. Speed labels are never dropped or inferred.
- Schema discovery found that missing `editor.vimMode` or invalid sandbox network
  mode silently resets config. The adapter now writes the valid schema and verifies
  restrictive permissions after startup and around every prompt. All those probes
  stopped before inference. The CLI's `models` output does not mark ACP-selected
  parameterized models as current, so it is not used as an execution attestation.
- Metadata-only preflights passed for the actual saved Grok High Fast and Extra
  High Fast variants. Both retain base `grok-4.6`, their exact effort, Fast=true,
  ask mode and the restrictive policy. No `session/prompt` was sent in preflights.
- Public receipts retain requested/verified alias separately from base model and
  parameters. Native tool requests, malformed/foreign frames, parameter drift,
  path escapes and read-only edits fail closed. Cancellation/timeout retain effects,
  kill the owned group and remove transient provider session stores.
- Start readiness now gives role-specific agent links and a clickable readiness
  check instead of an unexplained disabled button. Native command checks still
  require Codex Implementor; generated task criteria need no separate command list.

Additional inspected references (same pinned proprietary build, no code copied):
`index.js:1` schema; `6508.index.js:1` native model selection;
`2698.index.js:1` public `cursor/list_available_models` extension;
`8096.index.js:1` extension-method dispatch.

## Verification

- `rtk proxy asdf exec mix quality`: 250 tests passed, Credo clean, Sobelow reports
  no vulnerabilities. Sobelow emits existing dependency keyword-quoting warnings.
- `rtk proxy env PATH=/Users/mpak/.cargo/bin:/opt/homebrew/bin:/usr/bin:/bin cargo
  test --manifest-path desktop/src-tauri/Cargo.toml --locked`: 72 passed, 5 explicitly
  ignored acceptance tests, before the final default-label regression addition.
- Rust formatting and all-target Clippy with `-D warnings` passed.
- The full suite and focused checks use synthetic protocol/model fixtures, not
  live inference. Real signed-in Cursor read/edit/review and denial sessions are
  prepared as an ignored explicit-consent test; approval requested for exactly
  three sessions, five minutes each, in new disposable app-owned folders.
- No Arena was run; no role, selected model, original repository or saved profile
  was replaced. Full mixed-runtime battle and hard-kill/sleep recovery remain open.
- Before rebuilding, verified the idle native/BEAM identities, workspace cwd and
  loopback listener, made a SQLite backup, and requested graceful native shutdown.

Private evidence is under ignored `.ccoding/r020p-validation/`. It includes config
probes; never publish them as logs because the provider may add private account
metadata. Normal runtime cleanup removes its own config/data directory. Sudden
process death can leave provider session files; cleanup remains an R060 gate.

- Final Cursor-focused checks: three tests passed, two explicit live checks ignored,
  after adding the default-reasoning-label regression. Both selected real Grok
  preflights passed with the final mapping logic; no inference.
- All-target Clippy and final Rust format passed. The full Elixir quality gate
  remained green after role-specific runtime version blockers and readiness tests.

## Final artifact and handoff

- Corrected the saved Cursor wizard's provider label and removed obsolete
  Codex-only/execution-unavailable copy. `rtk proxy asdf exec mix quality` passed
  again: 250 tests, Credo clean, Sobelow no vulnerabilities. Existing Sobelow
  dependency keyword-quoting warnings remain.
- Final `rtk proxy env PATH=/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/Users/mpak/.asdf/installs/erlang/28.5/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin bin/dev.build`
  passed; expected library-relocation signature replacement and Hex update notices.
  `rtk proxy bin/smoke` passed on that final bundle, including authenticated
  browser routes, session boundaries, heartbeat, graceful quit and listener cleanup.
  Disposable smoke data: `/private/tmp/ccoding-smoke.RApgAc`.
- Native metadata-only preflights verified the user's exact two Cursor model
  variants. The UI refresh returned all 259 Cursor models and retained seven
  selected choices. The legacy Codex connection used by Speculator and Secutor
  reports `not_connected`; the separate c2 connection was not substituted.
- Verified idle state and made another private SQLite backup before the final
  rebuild. Native termination left its BEAM child alive, so sent SIGTERM only
  to that already-verified owned child, then confirmed both processes and the
  old listener were gone. No locks were removed and no forced kill was needed.
- Relaunched the unchanged saved test launcher with its original data root.
  Native PID 31745 / BEAM 31748, started 2026-10-13 16:39:16 America/Chicago;
  verified BEAM cwd and loopback listener `http://127.0.0.1:50339/`.
  Arena, Tabula, draft revisions, team revisions and adoptions match the initial
  backup. No battle exists and no command remains active. Profiles were not copied.
- Interactive final Arena QA was stopped by the browser tool's current-URL
  restriction. No further browser automation was attempted. LiveView regressions
  and packaged smoke are the available UI evidence; no final visual pass claimed.
- Local Markdown file links and `rtk proxy git diff --check` passed. Commit and
  merge this one task into local main; no push or publication.

Live acceptance remains open. Approval requested for exactly three synthetic
Cursor sessions (read, edit, permission denial), each at most five minutes;
no answer received and none run. The assigned legacy Codex profile needs the
user's sign-in at `/agents/codex` before this Arena can be ready. After those
steps, real mixed-provider battle acceptance and R060 crash/sleep recovery still
need evidence. Fixture success is not a claim that a real Arena has completed.
