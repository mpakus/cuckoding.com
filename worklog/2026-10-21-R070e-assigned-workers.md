# R070e — Explicit additional role workers

Ponytail full (upstream 5.3.2, MIT), architecture, workflow/kanban, LiveView,
security-review and quality-gates apply. This is the next required R030/R070 slice
following local main `b9499ff`; the full beta goal stays active. RTK prefixes every
shell command; proxy preserves exact source/protocol, migration and audit output.
Untracked `Untitled.md.age` is unrelated and remains untouched.

Acceptance is in the task file. Read the existing Team save/scope/adoption,
Disconnect, snapshot, attempt claim, native/provider admission, controls and
public observation paths before edits. D040 records this boundary first.

## Implementation and focused evidence

- Team definition v2 optionally stores one exact second connection/catalog ID and
  resolved model per required role, inheriting instructions. Existing primary and
  optional selectors share a function component; drafts, independent model reset,
  sessions/form/scope/revision/adoption gates remain. Custom planning roles gain
  no execution stage. No schema migration, credential clone or runtime grant.
- Start freezes `assigned-pairs-v1` plus all extra bindings. Wave slots 0/1 select
  primary/additional deterministically; unavailable bindings block and busy ones
  wait. Invalid slots refuse even a host-stage claim. Final stages/configured
  checks retain primaries. Admission/Resume/unfinished-battle Disconnect include
  every frozen binding. Retry retains the exact slot and fresh writer path.
- Only new waves with configured extras prioritize earlier pipeline stages. This
  lets shared planning turns finish before a primary writer holds their connection.
  Old waves/no-extra ordering remains unchanged. Exact-connection/global caps stay.
- Disconnect clears that exact connection from primary/extra positions across
  current default/Arena/board teams atomically; historical revisions are unchanged.
  Public rows/rosters and Inspect show exact bindings; frozen active display uses
  the attempt request rather than the primary responsibility's lookup.
- Four initial tests failed because old Team rejected the optional fields. New
  concurrent-writer regression passes; deliberately selecting the primary for slot
  1 fails it with `capacity` (mutation exit 2). Exact source bytes restored in
  `finally`. The regression holds both writers claimed, then completes independent
  combined review and the dependent task through the existing fixture loop.
- Additional cases cover foreign catalogs/forged fields, legacy omitted-field
  preservation, same-connection duplication refusal, all-scope Disconnect,
  pre-Git admission refusal, Resume/busy Disconnect, slot-preserving writer Retry,
  public projections, stale/expired UI forms and exact scoped Save.
- The first broad run exposed changed ordering in no-extra fixtures; prioritization
  was restricted to the new extra-equipped policy. A scope test used the board's
  newer team revision for its Arena; corrected it to use each actual scope revision.
  An initial test expected the wrong domain rejection return shape/reason; fixed
  those assertions to the existing retained-command/Resume API.
- Initial full quality exposed historical reading records without a team list.
  The read-only Inspector now handles them without weakening strict launch binding
  validation. Initial strict Credo findings were resolved through focused helpers,
  shared binding validation and aliases; no checks were disabled.
- Review found v2 blank optional fields could produce a redundant adoption prompt.
  A new failing LiveView regression proves it; compare the projected role/binding
  definitions while retaining both immutable versions and revision/form guards.
  Subsequent focused results and final quality are recorded below.

## Browser and local runtime

On the separate source UI root, verified idle work, canonical marker/lock and a
private integrity/FK-checked backup at
`.ccoding/r070e-ui-backup-4fb93605-ed86-40dd-97ce-625d477d493f.db` before launch.
Desktop and 320 × 712 screenshots show readable optional-worker text/selectors;
primary selections stay visible and extras are collapsed by default. Space closes
and reopens the focused disclosure. No team Save/adoption/provider usage occurred.
A post-reading private backup precedes normal shutdown of the verified source
launcher. Launcher/backend exited, lock released and port 49812 closed; the owned
tab was closed. This is not full accessibility or timed real-account acceptance.

## Final verification and integration

- `rtk proxy mix test test/cuckoding_web/role_workers_live_test.exs
  test/cuckoding_web/team_adoption_live_test.exs test/cuckoding/role_slots_test.exs`:
  **18 passed** after the additional adoption regression; its baseline failed
  before the projected-definition fix. Earlier focused core/history checks passed
  after the read-only historical Inspector correction.
- `rtk proxy mix quality` (pinned toolchain PATH): exit 0, **494 passed**, strict
  Credo **1,940 modules/functions, no issues**, formatting/compile-with-warnings-as-
  errors, Sobelow and both dependency audits passed. Exact private output:
  `.ccoding/r070e-quality-final.log`. Existing migration-module redefinition and
  Sobelow generated-lockfile parsing diagnostics remain tool/fixture warnings.
- The earlier 493-test passing run preceded the final blank-worker adoption fix;
  it was not used as final source proof. The first broad run failed four historical
  Inspector cases and strict test-helper nesting; both were fixed, not suppressed.
- `rtk proxy bin/dev.build`: pass after the final source fix. Strict signature:
  `rtk proxy codesign --verify --deep --strict --verbose=2
  desktop/src-tauri/target/release/bundle/macos/Cuckoding.app`: pass.
  Helper SHA256: `2aec865f867b60c8ba4fe355edc9922d2ef61095704f1b97514638270470bde9`.
- `rtk proxy bin/smoke`: pass, packaged launch/bootstrap/session/handoff replay and
  origin refusal, heartbeat, normal Quit/listener cleanup. Retained isolated root:
  `/private/tmp/ccoding-smoke.BziI7p`. No app is left running.
- Local documentation reference validation: **223 targets pass**; final
  `rtk proxy git diff --check`: pass. No site or native Rust source changed.
  R070b's 94 passing / five opt-in ignored native tests plus clean format/all-target
  Clippy were not repeated; this package rebuilt the unchanged native source.
- Final review traced paired catalog resolution, legacy payload replay/omission,
  stable scoped commands and Disconnect, immutable snapshot and request identity,
  exact provider capacity, all-binding admission/control gates, no-extra/historical
  ordering and read-only public projections. Required new regression checks pass.
  No additional dependency, frontend framework, provider grant or filesystem scope.

Commit this verified slice and fast-forward it into local `main`; remove the
completed feature branch. No push/publication. The full beta goal stays active:
real-account planning/mixed/parallel execution, general subprocess/toolchain
checks, broader interrupted/sleep recovery, custom workflows/providers and signed
clean-machine release/update/rollback acceptance remain open. The unresolved saved
workspace recognition decision is unchanged; no user root/profile was restored,
reset or cloned. Untracked `Untitled.md.age` remains untouched.
