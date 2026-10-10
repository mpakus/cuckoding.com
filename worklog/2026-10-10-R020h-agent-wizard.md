# R020h — Agent wizard and model-check repair

Claimed clean main e8ad997 (four commits ahead of origin/main), branch
feature/R020h-agent-wizard. Existing review was complete; no subagents spawned.
Ponytail full 5.1.0/MIT, LiveView, adapter, security-review, menubar-shell and
quality-gates apply. RTK proxy preserves exact source, protocol, SQLite and build
output. Scope: native diagnostic notifications, setup domain, durable
model selection, Agents UI, Team picker, tests/docs and packaged proof.

The user's two persisted model checks returned unexpected_message after ~800 ms.
Prior catalog-only verification never exercised a successful real diagnostic.
Inspect fixed preflight without raw account/credential output before changing
the parser. User requests a working connection; validate a bounded fixed diagnostic
through the visible usage-confirmed action after repair, not arbitrary inference.

## Implementation and diagnosis

Read-only SQLite observation pinned the user's two failures to `unexpected_message`.
The installed desktop runtime emits `deprecationNotice` and `warning`
between thread creation and the first turn. A bounded one-off fixed diagnostic
with the same managed profile, clean environment, named read-only empty-scratch
permissions, disabled tools/features and owned group cleanup returned CC_READY.
Only method names/item types and ACK equality were printed; no raw account, warning,
reasoning, credential or model text was retained. Preflight included exact effective
configuration, selected model and grant assertions. Private proof scratch:
`/private/tmp/cuckoding-r020h-proof-blc3dhoa/diagnostic`.

The shared native parser now tolerates those two informational notification kinds.
Fixtures cover notices plus unknown methods, server requests and late account drift;
identity/grant/tool/model/foreign-completion rejection is unchanged. This also fixes
the shared restricted Speculator transport without granting new operations.

Reused version/inspection/authentication/diagnostic commands, rather than adding a
second runner or an ephemeral UI command chain. The wizard's named action buttons
are explicit scoped consent; only optional inference retains a usage checkbox.
Back/clock/PubSub preserve selections. Completed `save_agent_models` commands own
saved IDs/resolved metadata in SQLite with stable keys, setup revision/catalog
checks and atomic events. No migration or dependency was needed (eight migrations
unchanged). Team filters new choices; old binding validation still sees the full
catalog and never rewrites historical roles. Docs reflect current button behavior.

## Verification so far

- `rtk mix test test/cuckoding_web/foundation_live_test.exs test/cuckoding/connection_test.exs test/cuckoding/team_test.exs test/cuckoding_web/team_live_test.exs`: 34 passed.
- `rtk mix quality`: first run found four Credo complexity/nesting issues; extracted
  the existing decision boundaries, then passed all 168 tests, warnings-as-errors
  compile, Credo, Sobelow and dependency audit. Sobelow still prints its existing
  Elixir 1.20 quoted-keyword warnings from generated Mix.lock parsing.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked connection::model_check::tests`: 5 passed.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`: passed.
- First full Rust run: 43 passed, one non-timeout fixture hit the old 400 ms deadline
  under concurrent suite/build load. Non-timeout cases now have two seconds; the
  actual timeout case stays at 400 ms. Production timeouts are unchanged.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check` and
  `rtk git diff --check`: passed.

SQLite backup API retained `before-wizard.db` in the proof root; integrity_check=ok,
zero active commands, schema unchanged at eight migrations. Verified prior shell
22611 / BEAM22619 by exact executable/parent/start identities before graceful
SIGTERM; both exited and port54576 closed. No unrelated agent app was stopped.

## Packaged validation and current desktop version

The first rebuilt app opened through its native handoff on port52851. Chrome showed
four ordered steps, a single Connect panel, refresh, hidden sign-in and a collapsed
Disconnect control. The stored executable observation was invalid: the desktop app
had updated the binary (inode/size changed) to **0.162.0-alpha.17.2**, while SQLite
still correctly retained the old 0.162.0-alpha.2 receipt. The initial standalone
probe with closed stdin correctly cancelled; repeating with the owned input open
exposed the old parser's rejection of a two-component numeric alpha suffix.

The version parser now recognizes bounded one/two-component numeric alpha suffixes;
only explicitly verified 0.146.0, 0.162.0-alpha.2 and 0.162.0-alpha.17.2 are admitted.
Both Rust parsing and Elixir supported-vs-unsupported cases are covered. The wizard
checks live executable identity before deciding where to resume. Its new regression
also covers stale stored readiness. This fixes a second real setup blocker without
silently choosing another executable or weakening permissions.

The packaged native `--check-codex-model` helper, using the existing private profile,
new empty scratch, GPT-6.1 Sol and low effort, returned **passed in 4,717 ms** with
matching requested/observed model and `scratch-read-only-v1`. Receipt retained at
`/private/tmp/cuckoding-r020h-proof-blc3dhoa/native-model-check.json`. This is a real
response through the shipped helper, separate from LiveView fixture tests. It did
not write a synthetic success into the app database.

Native browser automation stopped when the user switched tabs; no action was sent
to the unrelated page. The first two bundled smoke attempts failed because their
success assertion still expected the removed heading "Your starting lineup.";
updated the existing native smoke assertion to "Choose your agent." (same browser
cookie, origin and replay protections). Initial UI-resume change surfaced three
focused tests: a version-only profile has no catalog identity, so resume now checks
`verified_executable` directly instead of treating a missing catalog as a changed
binary. The final suites/build/smoke are rerun after these repairs.

## Final evidence and handoff

- Final `rtk mix quality`: **169 passed**, warnings-as-errors compile, Credo,
  Sobelow and dependency audit passed (the existing Sobelow lockfile-parser notices
  described above remain).
- Final `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  **44 passed**. Clippy with `--locked --all-targets -- -D warnings` and Rust fmt check passed.
- Final `rtk proxy bin/dev.build`: passed. `rtk proxy bin/smoke`: passed native
  launch/bootstrap, authenticated browser cookie, replay/origin refusal, heartbeat,
  graceful quit and listener cleanup. Isolated smoke data: `/private/tmp/ccoding-smoke.8hlKqg`.
- Final packaged native version probe recognized `0.162.0-alpha.17.2` in 113 ms.
- After final launch, completed the real browser flow: Choose Agent → consented
  version check → Refresh connection → **10 fresh models**. Selected GPT-6.1 Sol,
  opened optional test, chose it with the keyboard, explicitly checked usage consent
  and submitted. Browser and SQLite both show **passed, 3,749 ms**, requested/runtime
  `gpt-6.1-sol`, dated `2026-10-10T17:52:42.178544Z`. Selection stayed checked through
  clock/command updates. Review selection showed the fourth Save step; Back retained
  the selection. No model preferences or Team bindings were saved during live QA.
  Save persistence/filtering/reconnect/stale guards are covered by the runnable
  LiveView/domain tests. The user can choose their desired models and Save.
- Browser screenshot: `/private/tmp/cuckoding-r020h-proof-blc3dhoa/wizard-model-test.png`.
  No separate narrow viewport run; native desktop rendering inspected. New login,
  revoked account, other models, multiple Arena execution and clean-machine/signing/
  sleep acceptance remain outside this fix. This preview does not run repository tasks.
- Final SQLite integrity/foreign-key checks passed. All eight migrations and all
  team/Arena/Tabula/draft/revision/adoption/check tables match the pre-change backup;
  no queued/running/cancelling commands remain. Original private sign-in survived.
- Changed-doc local-link validation and `rtk git diff --check` passed.

Running final artifact: `/private/tmp/cuckoding-r020h-proof-blc3dhoa/Cuckoding.app`,
private data `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data`, native shell22679 /
BEAM22681, `http://127.0.0.1:53142/settings`. PID/start identities and native SHA256
are retained in local `proof.json`; these are dated evidence, not future identities.
The new `Open Cuckoding Test.command` and existing R020g/R050c launchers point to
this final bundle. Older app copies and the SQLite backup remain intact.

Complete R020h locally and integrate into main; no push or deployment authorized.
