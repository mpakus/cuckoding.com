# R060l — Retained provider closure

Claimed after R060k merged locally as `2e4082f`; task branch deleted. Ponytail full
5.3.2 (MIT), local-runner, agent-adapter, security and quality guidance apply.
Native/task/host callers were inspected before changes. RTK proxy preserves exact
native, protocol, process and test output. User `Untitled.md.age` remains excluded.

Scope: close the lost-reply gap for a provider whose owned groups already closed
with verified receipts. Persist an exclusive intent before launch and a bounded
fsynced public closure before stdout. A fixed read-only native inspection and a
separate SQLite recovery observation may enable Stop, never accept/replay work.
No new provider permissions, live account usage, native signal, session-store
deletion or publication is authorized by the inspection.

## Implementation

New Starts freeze `provider_closure: retained-provider-closure-v1`; older snapshots
do not acquire it. The task-only native request carries a closed binding with the
immutable attempt-request digest, exact connection/kind, executable metadata,
model and effort. These fields never enter the model prompt. Before launching,
the helper exclusively reserves `provider-closures/<attempt UUID>` and fsyncs its
intent. After verified group closure (and Cursor runtime-store removal) it fsyncs
public PID/start/duration metadata before replying. No prompt/report/raw frame is
retained there. Partial artifacts are preserved and cannot be overwritten.

The fixed read-only helper derives this private directory from its recognized
data-root cwd and UUID, pins descriptors, validates owner/mode/single-link/size/
ctime/intent/binding and launches/signals no provider. ProviderClosure preserves the
retained execution duration separately from the helper-read duration. SQLite
appends the normalized observation/event and control revision atomically before
notifying the coordinator. The original Interrupted attempt never changes.
Verified closure permits confirmed Stop and exact-connection capacity release;
it is deliberately absent from settled/Resume/Retry/Skip predicates. Tasks, head,
deadlines and consumed budgets remain unchanged. Failed/foreign reads prove nothing.

## Verification and corrections

- Red: initial native API tests did not compile before the new guard existed.
- Native focused tests: four passed. They cover exclusive/public-only publication,
  fixed binding, missing/partial/changed/linked/oversized files, foreign runtime/
  identity/scratch and an unchanged empty runtime scratch. Existing native task
  fixtures retain exact grants, tool restrictions and cleanup coverage.
- Host focused suite: 149 passed before final helper-latency and predicate checks.
  It exposed an expected legacy-test assumption about provider stages; that fixture
  now explicitly omits the new policy. Actual legacy provider recovery remains
  refused. New tests preserve original attempts and budgets, reject malformed/foreign
  proofs, keep Stop gated until verification, release only the exact connection,
  preserve reconnect UI and settle in a supervised worker before a lost coordinator
  notification. Capacity tests explicitly resume the other clean paused Arena.
- Full `mix quality`: **423 passed**, strict Credo clean, Sobelow complete and
  dependency audit found no vulnerabilities. One Exqlite test connection logged
  a client exit during the crash-path suite; the suite settled with no failures.
  Lockfile scanner quoted-keyword warnings remain distinct from application compile.
  Earlier formatting/Credo failures were corrected rather than suppressed.
- Mutation: invert exact frozen-binding equality in ProviderClosure; the focused
  test fails (exit 2). Original bytes restored before final quality/build.
- Initial packaged canary found `unsafe_profile`: putting an intent in scratch
  violated Codex's existing required-empty check. Moved evidence outside the
  provider grant into its own private UUID directory; did not relax that check.
  Rebuilt and reran the native and packaged checks on the corrected source.
- Final packaged helper canary uses `/usr/bin/true` as a disposable non-provider
  child: cancellation closes the group and publishes closure before stdout;
  fixed inspection returns `provider_closed`, checks the file hash and refuses a
  changed attempt digest. Scratch stays empty. No provider/model/account is used.
  Fixture/report retained under
  `.ccoding/r060l-validation/helper-44cfb5b0-4baf-401d-9295-c94b3e7da68f`.
- `bin/dev.build`: passed prod warnings-as-errors and strict/deep ad-hoc bundle
  verification; no owned bundle was running at rebuild preflight. Final helper
  SHA-256: `c71aa2fa7a03857131b66a550a8c0a3f4ff6701728239ac900298d8470fc0718`.
- Final `bin/smoke`: passed bootstrap/browser session/routes/origin/heartbeat/
  graceful quit/listener cleanup. Disposable data `/private/tmp/ccoding-smoke.CfDb5T`.
- Rust fmt and final Clippy `--locked --all-targets -- -D warnings`: passed.
  Final native full suite on the corrected outside-scratch source:
  **85 passed, 5 ignored**, 218.32 seconds. Ignored provider/sandbox tests are not
  passes. Final Elixir format check and structural no-launch/no-signal read check
  also passed. No source changes followed these checks.
- Affected local links and diff whitespace checked. No migration/dependency,
  actual provider inference, real saved-workspace launch or external publication.

Only fixture/helper evidence is claimed. Hard-killed helpers without receipts,
escaped sessions, broader Git/check/port recovery, physical sleep and real-account
acceptance remain open. Source preview/browser accessibility was not rerun for
these existing inspection paragraphs; guarded LiveView/reconnect tests passed.
The user's workspace-restoration question remains pending; no old marker or
launcher was recreated and `Untitled.md.age` was neither read nor changed.
