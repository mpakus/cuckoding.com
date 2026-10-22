# R030c — Scoped team editor

Claimed from local main `377d892` on `feature/r030c-scoped-team-editor`.
Ponytail full, local architecture/workflow/LiveView/security/quality guidance apply.
RTK proxy preserves exact source, test, build and Git output. The user-owned
`Untitled.md.age` is untouched. No inference or existing user workspace mutation.

Acceptance is in the task. The existing immutable command kind will distinguish
new scoped revisions from defaults; existing revisions/definitions and legacy
disconnect receipts remain unchanged. Save appends one scoped adoption, not a
default save followed by an automatic adoption. No new table/migration is needed.

Delivered explicit **Customize this board/Arena** links beside **Edit saved
defaults**, using the existing Team LiveView at exact scoped routes. Scope is
validated and retained at mount; wrong/foreign patches keep the draft and refuse
Save, with a direct return link. Scoped forms require their key plus the displayed
revision; expired sessions still refuse all events. **Save team here** explains
whether it affects this board's future work or new boards in an Arena. Active
planning disables/explains Save while preserving text. The old default/board-repair
path still saves defaults and requires separate **Use saved team** adoption.

`Team.save/5` appends scoped revision/adoption/command/event in one immediate
transaction using existing role/model/removal validation. Default current/history
exclude the two new scoped-only command kinds. Historical rows, old stable keys,
default saves and native profiles are unchanged. Disconnect now records exact
scope IDs, preserves scoped instructions and appends a default revision only when
the default itself changes. Replaying an old scoped Save returns its original
receipt without re-adopting it over a later explicit default adoption.

Verification:
- Four domain tests failed before domain implementation; three LiveView tests
  failed before routes/editor wiring. Focused domain/default/adoption/editor
  checks passed (41 tests) before the final added active-planning UI case.
- Full final `rtk proxy mix quality`: 452 tests passed; format/compile, strict
  Credo, Sobelow and both advisory sources clean. Existing generated-lockfile
  quoted-keyword warnings remain. An intermediate run found excessive complexity
  in persistence; intent resolution and accepted/rejected writes now have explicit
  small functions, with no lint suppression or validation removed.
  A later full run caught the old Battle repair test's link-label expectation;
  it now asserts the clearer Edit saved defaults label and retains the same
  exact-board default-save/adoption behavior before the final green run.
- Regressions cover exact current/sibling/default scope, new-board inheritance,
  stable/conflicting keys, stale and competing saves, active/cancelling planning,
  model validation, custom-role removal, audit rollback, retained completed cards/
  requests and Disconnect. UI covers exact links, dirty text/reconnects, recovered
  keys, foreign/invalid routes, mismatched patches and expired sessions. Existing
  default Team repair/adoption tests still pass.
- Mutation inverted the default projection's scoped-kind predicate: five of six
  domain regressions failed, exit 2. Restored before final checks/build; no app
  was running during mutation.
- CUA source preview at port 54229 on the existing separate UI-dev workspace:
  Board team → Customize this board opened the exact editor; desktop/actual320px
  stacked inputs, scope copy and native Return disclosure behavior observed.
  Unsaved name text enabled Save and remained in the form; no team/provider save,
  inference or folder read was invoked. Console showed extension messages, no
  observed application error. This is not full axe/screen-reader/zoom/timed-user
  acceptance. Final eyebrow/default-link wording was clarified afterward.
- Closed only the owned preview tab/DevTools. Initial shutdown verification
  refused before effects because macOS lsof did not report flock ownership as
  `lW`. Actual launcher executable/start/cwd/open lock plus a nonblocking flock
  refusal then verified ownership. Integrity/FKs and a private backup preceded
  audit-token normal SIGTERM to the launcher; authenticated shutdown closed its
  listener and exited. Backup:
  `.ccoding/r030c-validation/before-ui-stop-5cfd98eb-01cf-456e-bc43-9c330daa050e.db`.
- `rtk proxy bin/dev.build` passed production build and strict/deep ad-hoc
  signature verification; `rtk proxy bin/smoke` passed launch/session/origin/replay,
  heartbeat, normal Quit and listener cleanup. Retained smoke:
  `/private/tmp/ccoding-smoke.8zivQH`. Packaged helper SHA-256:
  `c2900edbaed688637b1e35f9bf59aa0a48612f51a6d3a611d9672d338a8d3431`.

Review checked source owners/callers, transaction rollback, exact scope/key/revision,
no default fallback, model-bound resolution, unchanged provider grants and immutable
historical payloads. No migration, native/JS change, new dependency or Rust-suite
rerun. Real-provider acceptance, custom execution stages, toolchain checks, parallel
tasks, full recovery and signed release remain open. Local main only; no push.
Changed-document links and `git diff --check` passed.
