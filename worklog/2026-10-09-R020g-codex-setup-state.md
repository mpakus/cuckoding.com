# R020g worklog — Connection state and desktop runtime

Claimed clean main `0520ed4`, three local commits ahead of origin/main. User reports
unrelated consent clearing, duplicate sign-in while connected, and missing GPT-6/
6.1 models. Prior R020f fixes picker filtering only; it did not solve runtime age.
Ponytail full 5.1.0 (MIT), LiveView, agent-adapter, menubar-shell, security-review,
quality-gates and official OpenAI documentation apply. No subagents/dependencies.

Scope: HomeLive consent scopes/account visibility, native version and RPC startup,
host version normalization, metadata discovery if needed, regressions and docs.
Keep immutable saved team/model bindings and action-specific execution consent.
RTK proxy preserves source, structured protocol, test scripts and packaging.

Metadata resolves standalone `/Users/mpak/.local/bin/codex` to 0.146.0. Its public
models_cache.json was freshly fetched 2026-10-09T05:00:54Z with six older IDs.
Desktop `/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`
reports `0.162.0-alpha.2` in a clean empty scratch. The old version parser rejects
all prereleases. The old connection helper also returns unexpected_message at
startup with this runtime; investigate rather than broadening unknown permissions.
User asked which runtime to retain via asynchronous preference question.

Sources: [app-server](https://learn.chatgpt.com/docs/app-server),
[changelog](https://learn.chatgpt.com/docs/changelog), retrieved 2026-10-09.
Official 0.156.1 notes introduce GPT-6 Sol/Luna, later than the selected CLI.
No upstream source copied; current shared implementation is the reference.

## Result and verification

Connection submission consumes its own confirmation; reload invalidates profile
confirmations only on verified executable/account-state changes. Authentication
still clears them all. Exact connection changes clear model usage consent but
preserve the selected model. Session/form-key/revision guards remain. Connected
profiles and pending authentication hide duplicate sign-in; sign-out/refresh stay.
Known desktop locations are checked by metadata only, with a separate consented
version check required to activate a choice. Alpha output is bounded; the host
allowlists only 0.146.0 and 0.162.0-alpha.2.

Sanitized fixed RPC diagnosis showed `account/updated` before `account/read` on
the signed-in desktop runtime. Permit it only while awaiting the authoritative
snapshot; reject unsolicited login completions, host requests and later drift.
Planning/diagnostics share this account reader. No credential files, raw accounts
or raw frames were printed or retained. Profile locks/process cleanup remain.

Commands from the repository root:

- `rtk mix test test/cuckoding_web/foundation_live_test.exs test/cuckoding/codex_test.exs`:
  21 passed before adding the final desktop-choice regression.
- `rtk mix quality`: 170 tests passed; format/compile/Credo/Sobelow/audit passed.
  Existing Sobelow quoted-keyword warnings from mix.lock remain; no vulnerability
  finding and no dependency changes.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`: passed.
- `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`:
  passed.
- `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`: 44 passed.
  New cases cover initial vs later account updates, forged login completion and
  malformed/oversized alpha versions.
- `rtk proxy bin/dev.build`: passed, including production assets/native bundle.
  Existing OpenSSL relocation warnings are followed by local re-signing.
- `rtk proxy bin/smoke`: passed packaged bootstrap/cookie/replay/origin/heartbeat/
  graceful-quit/listener checks. Fresh data: `/private/tmp/ccoding-smoke.KhhXYP`.

The rebuilt helper observed 0.162.0-alpha.2 and fetched ten models through the
existing private profile. A deliberately nonexistent model passed effective-config,
account and catalog preflight, then stopped at `model_unavailable`. No thread/start
or turn/start, no inference. This does not prove a successful model response.

The runtime preference question was optional; no answer arrived during work.
To fulfill the requested newer catalog, stated the desktop choice in commentary
before applying it through the visible version/connection forms. No global CLI
upgrade, credential transfer or saved role/model substitution.

Proof root: `/private/tmp/cuckoding-r020g-proof-7582i7cl`. Backed up idle SQLite,
gracefully stopped only the verified R020f shell/BEAM by executable/parent/start
identity, and verified old listener cleanup. Launched a separate new app copy on
the same R050c data root, retaining old bundle/backups. Native SHA-256:
`59355e411b8685744c52409f7c1a5b5c00e6c1c6300133d7f0266175fca64e5c`.
Shell 22611 / BEAM 22619 / loopback port 54576 are this run's observations only;
revalidate identities before any future restart.

Native Chrome verification of the running app:

- Choose desktop path → consented version check → 0.162.0-alpha.2 supported.
- Check connection retained private sign-in and showed ten fresh models:
  GPT-6.1 Sol, GPT-6 Astra/Sol/Luna, Reserve, GPT-5.6 Sol/Terra/Luna, GPT-5.5 and
  Codex Auto Review. No GPT-6 Terra ID was advertised.
- Sign-in disappeared; sign-out/refresh remained.
- With GPT-6.1 selected and version/sign-out/connection checked, refresh retained
  version/sign-out, cleared connection, retained the selected model and open
  disclosure. Cleared unused version/sign-out confirmations afterwards without
  submitting either action. `agents-verified.png` records the result.
- `live-catalog.json` contains only public version/catalog metadata. SQLite
  integrity/foreign-key checks passed; all team/Arena/Tabula/draft/adoption/check
  rows compare unchanged against `before-restart.db`. Test launchers now use the
  new app copy and preserved data.

No real diagnostic inference, fresh login completion, physical sleep/wake,
clean-machine/notarized release, remote push or deployment was performed.
Those acceptance gates remain open. Local main integration follows verification.
