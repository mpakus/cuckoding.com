# R020 — Codex connection and durable models

Claimed from main `e0b7b45`; no unrelated changes. See [acceptance](../tasks/R020-codex-connection.md).
Apply Ponytail full, agent-adapter, security-review, local-runner, Phoenix,
quality-gates and official OpenAI documentation guidance. No subagents.
RTK proxy exceptions: JSON-RPC, exact schema/source and native protocol/build
output must not be filtered. Product provider streams remain unwrapped.

Installed `/Users/mpak/.local/bin/codex --version`: `codex-cli 0.146.0`.
Generated its JSON schema into `/private/tmp/ccoding-codex-schema-0146` using
`rtk proxy /Users/mpak/.local/bin/codex app-server generate-json-schema --out ...`.
Official [app-server](https://learn.chatgpt.com/docs/app-server) describes initialize,
account login/status/logout, model/list, threads and restricted read-access grants.
Use runtime-managed auth, never external token injection. Catalog metadata is
not proof of model entitlement; successful real turns remain a separate gate.

## Delivered R020a scope

Explicit executable selection/confirmation and version readiness form the first
complete R020 substep. The checkbox resets on path edits. Metadata discovery
stays nonexecuting. Commands snapshot executable metadata; a changed candidate
is refused. One native fixed-operation helper in the existing bundle runs only
`--version`, with new private scratch HOME/CODEX_HOME/TMPDIR, allowlisted clean
environment, null stderr, 128-byte output and a five-second deadline. Its unreaped
child pins PID/PGID until TERM/KILL cleanup, including descendants. Stdin loss
cancels the child. Only normalized public fields cross the 1 KiB host response.

SQLite persists consented intents, results and audit events before broadcast.
Probe cancellation and lost-claim checks reject late results. An expired running
probe becomes interrupted; it is never automatically repeated. The existing
dispatcher/command table is reused, with a small forward migration for payload
and readiness fields. No dependency, login, credential import or model/turn
execution was added. One explicit adapter behavior covers the implemented probe.

Reference coding: inspected existing `Tools`, `Foundation`, `Dispatcher` and
native `Service` before adding the probe. The supported CLI version derives
from installed 0.146.0 and the official pinned
[CLI source](https://github.com/openai/codex/blob/rust-v0.146.0/codex-rs/cli/src/main.rs#L85)
(`codex-rs/cli/src/main.rs:85–100`, Clap version contract). Its
[license](https://github.com/openai/codex/blob/rust-v0.146.0/LICENSE) is Apache-2.0.
No upstream source was copied. CCoding adds explicit host consent, SQLite
authority, private environment and ownership cleanup to that CLI contract.
Ponytail full 4.13.0, MIT, retained; no new plugins and no XERJ.

## Verification

- `rtk mix format` and `rtk mix quality`: **30 tests pass**, formatter/compiler,
  Credo, Sobelow and dependency audit pass. Credo initially caught a nested cancel
  transaction; extracted its one mutation and reran successfully. Known Sobelow
  Elixir 1.20 generated-lockfile keyword warnings remain tool diagnostics only.
- `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check`,
  `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings`,
  `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked`:
  **8 tests pass**, format/lint pass. Covers split output, nonzero/oversized/raw
  output refusal, fixture secret canary, private directories, timeout/cancel,
  TERM-ignoring group/descendant cleanup and unrelated process preservation.
- `rtk proxy env CARGO_TARGET_DIR=/private/tmp/ccoding-r016-target bin/dev.build`:
  bundled release passes. This reuses the earlier verification target directory;
  its bundle now contains R020a. The originally running R010 bundle was not rebuilt.
- Exact `rtk proxy python3` subprocess smoke used
  `/private/tmp/ccoding-r016-target/release/bundle/macos/CCoding.app/Contents/MacOS/ccoding --probe-codex /Users/mpak/.local/bin/codex /private/tmp/ccoding-r020-real-probe`:
  actual version **0.146.0**, **153 ms** observed. Stdin held open until response.
- Prior-schema copy: Python SQLite backup from the stopped R016 smoke DB into
  `/private/tmp/ccoding-r020-upgrade`, then the same bundle `--smoke-test` with
  `CCODING_RELEASE_DIR` pointing to its `Contents/Resources/release` and
  `CCODING_DATA_DIR=/private/tmp/ccoding-r020-upgrade`: passes launch/bootstrap,
  browser cookie, handoff replay/origin refusal, heartbeat, Quit and listener
  cleanup. Schema migration count **1 → 2**; all **6 original events** unchanged;
  `PRAGMA integrity_check` = `ok`, `foreign_key_check` empty. Source DB untouched.
- Packaged browser check: launched the same native binary with
  `CCODING_DATA_DIR=/private/tmp/ccoding-r020-ui`; loopback **56611**, owned native
  PID **19872**, release **19873**. In the real browser, Check setup found Codex;
  confirmed and ran version check; UI displayed **0.146.0 / not signed in**.
  Reload retained it; SQLite had one completed probe and **140 ms** native timing.
  Desktop rendered form/result inspected. These are historical test identities.
- Cleanup fault drill: SIGTERM only to the verified test release **19873**;
  listener 56611 closed, its shell 19872 detected exit and stopped. Existing R010
  app untouched. CUA could not bind the tray-only verification app, so no live
  tray-pixel proof is claimed. App narrow-viewport and physical sleep tests were
  not run for this slice; R016 public-site desktop/narrow checks are separate.

- Final rebuilt bundle `--smoke-test` with
  `CCODING_DATA_DIR=/private/tmp/ccoding-r020-final-smoke`: all shell/auth/browser/
  shutdown checks pass. Native helper subprocess with actual stdin closed during
  a TERM-ignoring fixture: cancelled status and descendant cleanup pass.
- `rtk proxy python3` Markdown target validation: **22 documents pass**.
  `rtk proxy git diff --check` and staged equivalent: pass (exact-output proxy
  prevents whitespace diagnostics being hidden by the diff filter).

This verified R020a slice is committed and merged into local main; parent R020
remains open as listed in its task. Integration is local only.
No push, Pages deployment or public native release.

## Security limits and handoff

Host execution is not a sandbox; a trusted version executable can access the
host outside its private working directory. Metadata checks reduce accidental
binary drift but do not eliminate same-user TOCTOU attacks. No runtime permission
grant or account authorization is inferred from a matching version. The saved
PID/spawn timestamp is an observation, never a recovery kill target. Force-killing
the helper itself cannot run its cleanup; interrupted commands fail closed and
require a fresh consented check, with full ownership reconciliation still R020/R060.

R020 is partial: next implement app-owned login/status/logout and durable models,
then prove scoped turns across two workspaces. Fixtures and real version evidence
do not satisfy those account/execution gates. Retain the generated current schema
as a reference, not an installed protocol client. R030+ remains unstarted.
