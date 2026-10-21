# R020r — Cursor initial planning

Claimed after R060l merged locally as `f7e2fa1`; task branch deleted. Ponytail full
5.3.2 (MIT), agent-adapter/local-runner/security/quality and incremental/TDD/review
guidance apply. RTK proxy preserves exact native/JSON protocol/test output.
User `Untitled.md.age` stays excluded; no live inference is authorized here.

Current source owners: Planning.setup/execute/normalize and saved-binding guards;
Cursor.plan; cursor/task.rs isolated ACP policy/connect/selection/cleanup; existing
Codex model_check request/schema/proposal contract; PlanningComponent and fixtures.
The gap is explicit Codex-only initial planning, despite Cursor role execution.

Primary references checked 2026-10-21:
[Cursor ACP](https://cursor.com/docs/cli/acp) (transport/session flow/modes) and
[configuration](https://cursor.com/docs/cli/reference/configuration) (isolated
config location/permission fields). These establish interface intent, not
acceptance on the pinned binary. Reuse the locally verified
`2026.09.15-d2fe57e` R020p session/model/policy boundary and fixture tests rather
than adopting new CLI flags or assuming current docs prove enforcement. No new
peer code/dependency is copied. This extends the existing no-tools planning
operation, not runtime filesystem/network privileges.

## Implementation

Planning freezes provider kind and the separate `cursor-plan-no-tools-v1` grant
for the exact assigned Cursor Speculator. Dispatch and settlement use Cursor's
existing version/catalog/identity binding; old Codex requests without kind keep
their original behavior. Optional Codex diagnostics retain their Codex-only guard.
No runtime/model fallback, new command kind, migration or dependency is introduced.

The new native entrypoint reuses the R020p isolated config/data/workspace, ask mode,
deny policy, exact alias/base-model/parameter verification and cleanup path. A
single prompt receives the brief, instructions, frozen v3 snapshots and the same
proposal schema. It never constructs Files, supplies host tools or receives an
Arena root. Native callbacks/config drift abort; private stores are removed only
after verified group closure. Cursor planning receipts require exact closed public
fields, explicit cleanup and the separate grant; file-tool fields/unknown transport
are refused. Existing host graph/citation/text checks precede automatic cards.

The shared ACP stdin writer now owns its pipe in a thread with one queued bounded
message. Main polling retains cancellation/deadline control while the OS write can
block, so owned group cleanup remains reachable. A rejected native callback remains
a policy error even if sending its refusal fails. Rust ownership/concurrency/CLI
guidance informed this small message-passing boundary: no shared mutable state,
new runtime or generic bridge. The named Work lifetime borrows the caller's request;
no cloning/leaking merely to satisfy the compiler. This helper's existing framed
JSON status protocol takes precedence over generic interactive-CLI exit guidance.

## Verification

- Red: new Cursor planning host tests failed because setup had no token and
  rejected requests; the new native blocked-write test initially lacked its API.
  One test syntax error and a named-lifetime compiler error were corrected before
  successful checks. No static gate was disabled.
- Native Cursor focused suite: **6 passed, 2 ignored**. Cover normal tasks plus
  no-tools planning, 16 snapshots/65,520 source bytes with escaping, exact model
  parameters, callback/policy/model/config/foreign-output refusals, cancellation/
  deadline store removal and a blocked 500 KiB input write with bounded cleanup.
  Original source files stay unchanged and no planning tool journal exists.
- Final full native suite: **88 passed, 5 ignored**, 218.23 seconds. The earlier
  87-pass run preceded the last added planning cancellation test. Ignored real
  accounts/sandbox checks are not counted as passing evidence.
- Host routing test uses a local fake helper and asserts the exact Cursor flag,
  named private profile, requested alias and five-field stdin request. It settles
  one result and proves the completed claim cannot launch again. Fixture receipts
  create cards through the actual domain transaction; malformed grant/model/runtime/
  cleanup/transport/tool-bearing receipts cannot import them.
- Native fake CLI and host fake helper are separate tests, not real provider usage.
  LiveView coverage keeps consent, draft text, cards and reconnect state. A stronger
  Cursor runtime-label assertion caught the old hardcoded Codex history text; fixed
  it and reran final quality/build below.
- Mutation: invert the Cursor planning-grant guard; two focused tests fail (exit 2).
  Restored original bytes before quality/build.
- Pre-label full `mix quality`: **427 passed**, strict Credo clean, Sobelow complete
  and dependency audit clean. Final post-label result is recorded below.
- Native fmt/Clippy `--locked --all-targets -- -D warnings` passed. Public claims
  and all current Codex-only planning notices were updated; historical evidence
  remains dated. Local documentation links and whitespace checked.
- Packaged fake-CLI proof retained under
  `.ccoding/r020r-validation/packaged-e1705652-6a57-43da-94ae-4fe5a8e60ce2`:
  actual `--plan-cursor-brief` dispatch returned a bound proposal from 16 snapshots
  (65,520 bytes), with explicit cleanup and runtime-store removal, no Files service
  or raw thought marker. This is a helper fixture, not model/account acceptance.
- Pre-label build/smoke passed; final artifact result/hash is recorded below.

Final post-label checks: `mix quality` passed **427 tests**, strict Credo,
Sobelow and dependency audit; lockfile quoted-keyword warnings remain nonfatal.
`bin/dev.build` passed prod warnings-as-errors and strict/deep ad-hoc signing.
The final helper SHA-256 is
`adf45ed9568a79fc4dc6ca24695bdf88f1fbc1fb128fc25d112e266aea42dd1c`.
The fake-CLI canary was repeated against this exact helper and retained its
separate `final-validation.json`; all 16 snapshots/cleanup/no-tools assertions
passed. Final `bin/smoke` passed with fresh disposable data at
`/private/tmp/ccoding-smoke.8LGFsv`. No code changed after these final checks.

No source browser accessibility/timed unfamiliar-user session, real Cursor model
inference, mixed-team battle, physical sleep or release/signing acceptance is
claimed. The old saved-workspace restoration choice is still pending; no marker,
launcher or saved agents were changed. `Untitled.md.age` remains untouched. No push
or external publication. General toolchain checks, broader recovery, same-board
parallel workers, remaining providers/custom stages and release gates remain open.
