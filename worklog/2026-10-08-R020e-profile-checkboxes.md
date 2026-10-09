# R020e worklog — Profile consent checkboxes

Claimed from clean main `99fb771`, one local commit ahead of origin/main.
User screenshot identifies login and connection consent immediately resetting.
Ponytail full (upstream 5.1.0 MIT), LiveView, security-review, quality-gates and
menubar-shell apply. No dependency, migration, provider protocol or domain change.

Scope: HomeLive's login/logout/connection forms, timer/reload handlers and submit
callers, FoundationLiveTest, affected UI/development docs, README and AGENTS.
Version/model forms already bind checkbox state; the three profile forms do not.
Reuse that existing pattern with scoped recovery guards. Retain action-specific
confirmation and existing domain command/events; checkbox edits are ephemeral UI.

Acceptance: stable mouse/keyboard checkbox state through clock and unrelated
updates, deliberate unchecking, stale/setup/reconnect/submission resets, session
guard, packaged verification and preserved existing test data on restart.

`rtk proxy` is used for exact source/structured evidence and packaging scripts
without a semantic wrapper. Reference: current Apache-2.0 repository
`lib/cuckoding_web/live/home_live.ex:43` version consent and
`lib/cuckoding_web/live/tabula_live.ex:257` scoped form consent. No external code.

## Result and verification

Confirmed the reported bug in the running bundle: checking login and connection
returned true immediately, then both reverted after the ordinary one-second
clock patch. The three forms lacked `phx-change` and server-owned checked state.
Existing version/model forms already preserve consent that way.

HomeLive now tracks action-specific selections, bound to the current form key
and setup revision. Clock/unrelated broadcasts preserve them; unchecking,
submission and setup changes clear them as appropriate. An earlier page's form
cannot recover or submit consent into a new mount. Domain commands/session guards
and public action events are unchanged; checkbox edits create no durable event.

- `rtk mix format lib/cuckoding_web/live/home_live.ex test/cuckoding_web/foundation_live_test.exs` — passed.
- `rtk mix test test/cuckoding_web/foundation_live_test.exs` — 13 passed.
  The initial regression failed because the form had no change handler. Tests now
  cover clock/PubSub, deliberate unchecking, setup revision reset, stale revision/
  foreign form-key change and submit, reconnect, expired session, consumption and
  no cross-action consent. Fixture commands run no provider.
- `rtk mix quality` — 167 passed; format, warnings-as-errors compile, Credo,
  Sobelow and dependency audit passed. Existing Sobelow quoted-atom lockfile
  diagnostics remain tool warnings.
- `rtk proxy bin/dev.build` — passed; production assets/release and native bundle
  built. OpenSSL relocation emitted the known signature warnings before re-signing.
- `rtk proxy bin/smoke` — passed bootstrap, browser cookie, replay/origin refusal,
  heartbeat, graceful quit and listener cleanup; retained data
  `/private/tmp/ccoding-smoke.g263Ch`.
- Exact Python local-link check — 102 references exist across changed docs/task/
  worklog. `rtk proxy git diff --check` passed.

## Running artifact and browser proof

Before restart, verified shell 96007/BEAM 96023, parent/executable/start identities,
working directories and loopback listener 62885. No pending/running commands.
Retained a SQLite backup at
`/private/tmp/cuckoding-r020e-proof-xvx6ow1c/before-restart.db`. Native menu access
timed out, so sent SIGTERM only to the verified owned BEAM, allowing graceful OTP
shutdown and shell heartbeat exit. Verified both processes/listener disappeared.
Kept the old bundle for rollback and launched the corrected copied native shell
with the exact existing test data root; no direct release launch or credential
read/copy. The native browser handoff opened the current user profile.

- App: `/private/tmp/cuckoding-r020e-proof-xvx6ow1c/Cuckoding.app`.
- Data: `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data` (unchanged).
- Shell/BEAM: 5985/5993, started `Thu Oct  8 23:33:27 2026`.
- Listener: `127.0.0.1:49524`.
- Packaged HomeLive BEAM SHA-256: `0980c3f696494cdd96d1b8bb1c6557246562b89636b676072060a2afce2348f0` (matches rebuilt bundle).
- Native SHA-256: `ea4def60b6902e30db3176d4c9b967a470abc2027b8f2076ac3e932c7e59c542`.

The user resumed setup in Chrome during verification. We stopped UI actions in
that browser. Prior commands/events/team/Arena/board rows remain intact; later
user setup/version/login/inspection commands advanced the workspace legitimately.
Database quick_check is ok. The original reopen shortcut now points to the
corrected bundle and same data root. No user provider/profile files were changed
by this fix or its verification. Existing ChatGPT observation remains visible.

Completed browser regression separately with the identical bundle and a synthetic
QA database at `/private/tmp/cuckoding-r020e-qa-0s62m2hm` (no copied credentials).
Its first launch correctly refused a copied DB without its rebuild ownership
marker; copying that QA marker allowed native bootstrap. A short-lived, one-use
handoff was inserted only in the disposable QA DB for the in-app browser.
Login/inspect were selected by mouse and logout by Space. All three remained
checked over 13.7 seconds of normal clock updates with the same keyboard focus
and expanded disclosure. Mouse/Space unchecking persisted afterward. Command
count stayed seven: no form was submitted and no provider action was launched.
Screenshot: `/private/tmp/cuckoding-r020e-proof-xvx6ow1c/checkboxes-stable.png`.
QA shell/BEAM 6876/6878 and port 49990 were stopped/cleaned; user instance stays
running. This is checkbox evidence, not new real-provider acceptance.

README, AGENTS and UI/development/testing/plan docs now describe the consent
lifetime and recovery guard. No schema, protocol, dependency or native code changed.
Rust suites were not rerun; native packaging/smoke were run. Real-provider model
execution, notarization, clean-machine and physical sleep checks remain open.

Integration: task committed and fast-forwarded into local main; fix branch removed.
No push/publication. Continue R020/R050 acceptance from docs/PLAN.md after this fix.
