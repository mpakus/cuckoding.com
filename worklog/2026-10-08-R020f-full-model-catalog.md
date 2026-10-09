# R020f worklog — Full agent model catalog

Claimed clean main `f4e3ad6` (two local commits ahead of origin/main).
User reports only three models after authorization. Native `catalog/1` requests
`includeHidden:false` and rejects `hidden:true`; its existing pagination and UI
have no three-entry cap. Change this shared path for inspection, post-login
refresh and model/brief preflight; keep matching and grants unchanged.

Scope: native catalog/parser/fixtures, host normalization, Agents/Team choices,
focused tests, adapter/data/development docs, README and AGENTS. No dependency,
migration, credential import or provider turn. Ponytail full 5.1.0 (MIT),
agent-adapter, security-review, LiveView, menubar-shell and quality-gates apply.
Also consulted OpenAI Docs for the runtime protocol. RTK proxy preserves exact
source, JSON protocol, build and test-helper semantics.

Primary reference: [official app-server model/list](https://learn.chatgpt.com/docs/app-server#list-models-modellist),
retrieved 2026-10-09 UTC. `hidden` means hidden from the default picker;
`includeHidden:true` requests the full list. Models/options depend on the client
and account. Current generated-schema cache was absent, so official docs are the
reference; no third-party code copied. Existing implementation reference:
`desktop/src-tauri/src/connection.rs:238`, `lib/cuckoding/codex.ex:397` on f4e3ad6.

Acceptance: full bounded agent catalog, typed visibility, persisted/UI entries,
legacy row compatibility, failed-refresh retention and no inferred entitlement;
real read-only refresh after rebuilding the user's existing test instance.

## Implementation and regression evidence

The shared native catalog sends `includeHidden:true` on every page and accepts
only boolean visibility metadata. The existing four-page/32-entry, byte, timeout,
unique-ID/cursor and all-or-nothing bounds remain. Host normalization preserves
that flag while accepting older rows that omit it. Additional entries appear in
both selectors and the catalog disclosure with a visibility label. No ID list,
account entitlement, default substitution or new runtime grant is introduced.
Diagnostic/planning preflight uses this same catalog and retains exact matching.

- `rtk mix format lib/cuckoding/codex.ex lib/cuckoding_web/live/home_live.ex lib/cuckoding_web/live/team_live.ex test/cuckoding/connection_test.exs test/cuckoding_web/foundation_live_test.exs` — passed.
- `rtk mix test test/cuckoding/connection_test.exs test/cuckoding_web/foundation_live_test.exs` — 22 passed.
  Covers persisted additional models, absent legacy flags, malformed flag refusal,
  stale retention and all seven fixture choices in Agents/Team. Initial UI fixture
  lacked verified executable identity; corrected through the normal Foundation
  probe/inspection flow rather than bypassing Team's identity guard.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked connection::tests` — 10 passed.
  Fixture refuses any page request lacking includeHidden:true; a second page
  contains a hidden model. Malformed boolean/duplicates/cursor cycles still fail.
  An overbroad edit initially changed the unrelated login test's expected count;
  restored its single-entry assertion before the passing run.
- `rtk mix quality` — 169 passed; format, warnings-as-errors compilation,
  Credo, Sobelow and dependency audit passed. Existing Sobelow quoted-lockfile-atom
  diagnostics remain tool warnings.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check` — passed.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings` — passed.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked` — 42 passed,
  including shared model/brief preflight, matching/cancellation and cleanup.
- `rtk proxy bin/dev.build` — passed assets, release, optimized native build and
  bundle. Known OpenSSL relocation signature warnings were followed by re-signing.
- `rtk proxy bin/smoke` — passed native launch/handshake, cookie, replay/origin
  refusal, heartbeat, graceful Quit and listener cleanup. Retained smoke data:
  `/private/tmp/ccoding-smoke.Fp6Nds`.

## Real runtime and preserved user app

Before restart the test app was idle with three cached models. Verified old shell
5985/BEAM5993 executable, parent/start identity and port49524; backed up SQLite to
`/private/tmp/cuckoding-r020f-proof-p6ph9ah4/before-restart.db`. Kept the old bundle.
Graceful SIGTERM to only the verified owned BEAM let OTP stop and shell heartbeat
exit; both processes/listener were checked gone. Native shell launch performs the
normal handshake and opened Chrome. Current artifact:

- App: `/private/tmp/cuckoding-r020f-proof-p6ph9ah4/Cuckoding.app`.
- Existing data: `/private/tmp/cuckoding-r050c-proof-vvr7u4wp/data` (unchanged).
- Shell/BEAM: 13343/13349, `Thu Oct  8 23:49:06 2026`.
- Listener: `127.0.0.1:51633`.
- Native SHA-256: `2741d2d0b757c7568fd84292cf993e33ed9598fc99cf86203be1f2e8d569a2ca`.

Packaged HomeLive SHA-256:
`afd0f25d4b215b709b44d2ef54502d1546bd0ae708141427e0c002a9e6b7c904`.
Both native and HomeLive bytes match the final rebuilt bundle. Existing reopen
shortcuts now target this app with the same data. All previous workspace,
commands/events/team/Arena/board rows remain; quick_check is ok. Shell lifecycle
may append events. No credentials were read, copied, imported or changed.

The user's Chrome was actively navigating elsewhere; stopped browser interaction.
Instead ran this bundle's fixed `--inspect-codex` helper against the existing
app-owned profile, with the workspace idle, keeping stdin open through completion
and using its existing profile lock/owned-group cleanup. The native public result
was checked/chatgpt/fresh: **six models, three marked hidden**:
`gpt-reserve`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-5.5`,
`codex-auto-review`. Normalized public metadata only is retained at
`/private/tmp/cuckoding-r020f-proof-p6ph9ah4/real-catalog.json`.
This is the installed client's returned catalog, potentially runtime-cached,
not all OpenAI models or proof of inference entitlement. No model prompt was run.
The read-only verification did not write into the live application projection or
forge a command: its old three-model snapshot remains until the user confirms
**Check Codex connection** in the rebuilt app. No reauthorization is necessary.

## Handoff and integration

README, AGENTS and adapter/data/development/plan/testing docs describe full-list
fetching and the additional-model label. Task integrated into local main after
verification; fix branch removed, no push or publication. Browser selector proof
is LiveViewTest evidence; real post-refresh browser screenshot was unavailable
because Chrome was in use. The existing checkbox/refresh is the user handoff.
Real inference, new provider versions, clean-machine/notarization and physical
sleep acceptance were not exercised. Continue R020/R050 from docs/PLAN.md.

Final structural check: 105 local document references exist; staged diff check passed.

Final UI wording describes what refresh fetches, so an older cached snapshot does
not falsely claim completeness. Rebuilt/relaunched the same idle test data after
that wording change; 14 focused LiveView tests and bundled smoke passed again
(`/private/tmp/ccoding-smoke.9ZzydI`). Prior native catalog behavior is unchanged.
The two additional events during restart were shell.authorized/browser.authorized.
