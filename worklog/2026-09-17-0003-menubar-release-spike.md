# Worklog — 0003 Menubar shell and bundled release spike

## Metadata

- Date/time (UTC): 2026-09-17
- Task: 0003
- Status: done
- Human/agent owner: Codex
- Branches: `feature/0003-menubar-release-spike`, `feature/0003-clean-account-verification`
- Start revision: `de4eefe`

## Acceptance criteria restatement

- A macOS arm64 `.app` bundles a minimal release and ERTS, runs without an interactive shell environment, and exposes only a tray menu.
- A bootstrap secret is passed outside argv, exchanged once for a browser session, and rejects missing, invalid, and replayed requests.
- The shell parses a dedicated readiness protocol, reports crashes before and after readiness, and terminates every owned descendant on quit.
- Startup, failure, authentication, and shutdown claims are backed by timestamped evidence; clean-user-account verification is reported separately.

## Work performed

- Claimed task and read its required architecture, security, execution, product, database, flow, desktop-shell skill, and task specifications.
- Used Ponytail to keep the spike to one Phoenix release, one Tauri binary, standard-library HTTP/process handling, and no extra runtime services.
- Queried the project and pinned reference indexes with XERJ before implementation. Hydra's `electron/daemon/lifecycle.ts:32-124` supplied the useful bounded readiness/shutdown pattern; Agetor had no closer shell implementation.
- Verified current official Tauri resource, tray, activation-policy, and macOS bundle APIs and pinned Phoenix 1.8.13, LiveView 1.2.11, Bandit 1.12.5, Tauri 2.11.5, and Rust 1.90.0 for the spike.
- Built a loopback-only Phoenix release with bundled ERTS, a random per-launch cookie-signing secret, exact readiness JSON, one-time bootstrap exchange, single-use browser tokens, cookie-backed LiveView sessions, status/shutdown endpoints, and controlled crash injection.
- Built a tray-only Tauri shell with `LSUIElement`, Accessory activation policy, Cuckoding/About/Settings/Quit menu, status polling, safe child environment, unique mode-0600 bootstrap files, process groups, early-failure cleanup, and bounded graceful/forced shutdown.
- Disabled Erlang distribution after native process inspection found the stock release opening a wildcard distribution listener and starting `epmd`; the corrected app exposes only its loopback HTTP listener.
- Added signal waiting so shell `SIGINT`/`SIGTERM` invokes the same cleanup path instead of orphaning BEAM.
- Replaced the initial Cowboy/Cowlib adapter after the full build reported current Cowlib advisories; the final Bandit dependency graph contains neither package and emitted no advisory warning.
- Added reproducible build/test automation, focused Elixir and Rust tests, a timestamped integration verifier, spike report, ADR confirmation, and shell contract updates.
- Built and launched the 36 MiB arm64 `.app` from a sterile temporary `HOME` with an empty inherited environment and no Elixir/Mix in `PATH`; process inspection showed the bundled ERTS and only `127.0.0.1` listening.
- Inspected local signing: the app is only ad-hoc linker-signed and strict deep verification fails. Recorded inside-out nested signing, BEAM JIT entitlement, hardened runtime, notarization, and stapling as Phase 9 gates.
- Added a standard-library clean-account verifier, copied the rebuilt bundle to `/Users/Shared`, and ran it from the separate `qa` account (UID 502). The verifier checks bundle execution, process ownership, bundled ERTS, loopback-only listening, human-confirmed browser handoff, and descendant cleanup.
- Fixed a verifier-only shutdown race found by the first QA run: the shell had exited and the runtime was still terminating when checked. The verifier now waits up to five seconds for that exact runtime PID and cleans it up on failure; the rerun passed.

## Verification

- `rtk proxy env MIX_ENV=test CUCKODING_PORT=0 mix test --no-start` — 1 test, 0 failures.
- `rtk proxy env MIX_ENV=prod mix compile --warnings-as-errors` — passed.
- `rtk proxy env MIX_ENV=prod mix release --overwrite` — passed; bundled ERTS 16.4.
- `rtk mix hex.audit` — no retired or security-advisory packages found in the final Bandit graph.
- pinned Rust 1.90 `cargo test --manifest-path src-tauri/Cargo.toml` — 3 tests passed.
- pinned Rust 1.90 `cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings` — passed.
- pinned Rust 1.90 `cargo-tauri build --bundles app` with stripping disabled for rust-lang/rust#157750 — passed.
- `rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/ruby verify.rb` — 28 timestamped checks passed; evidence committed at `spikes/0003-menubar-release/evidence/verification.log`.
- Native app inspection — `LSUIElement=true`; bundled `beam.smp`; one `127.0.0.1` listener; no distribution listener or `epmd`; signal shutdown left no shell, BEAM, or helper process.
- Sterile-home launch — passed with `HOME=/private/tmp/cuckoding-clean.*`, `env -i`, and system-only `PATH`; temporary evidence directory removed afterward.
- `codesign --verify --deep --strict` — expected failure for the unsigned discovery artifact; this is evidence for the recorded Phase 9 signing work, not a release-ready claim.
- Visual menu/browser capture — blocked because macOS was locked. Protocol-level browser handoff, safe redirect, cookie session, and authenticated LiveView all passed against the real release.
- `rtk proxy sh -n spikes/0003-menubar-release/verify-clean-account.command` — passed. `shellcheck` was unavailable on the host and is not recorded as passing.
- `rtk proxy sh spikes/0003-menubar-release/build.sh` — passed after the clean-account request: dependency audit clean, 1 Elixir test and 3 Rust tests passed, formatter/compiler/clippy passed, the 36 MiB `.app` rebuilt, and all 28 protocol checks passed.
- Clean-account bundle verifier — passed from `qa` (UID 502): bundled ERTS, loopback-only listener, authenticated default-browser handoff, and no surviving shell/runtime process. Evidence: `spikes/0003-menubar-release/evidence/clean-account-qa.log`.
- `rtk proxy /Users/Shared/Cuckoding-QA-Test/verify-clean-account.command mpak` — final verifier regression passed after stale-PID safety was added; the separate QA run above remains the clean-account evidence.

## Handoff

ADR-011 is technically confirmed. Task 0004 can proceed from task 0002. Do not reuse the spike as production structure wholesale; carry forward the shell contract, `RELEASE_DISTRIBUTION=none`, signal cleanup, and signing gates when Phase 9 implements the supported shell.

Task 0003 is complete. The shell protocol and actual separate-account bundle run both pass; production signing, notarization, installation, updating, and uninstall remain Phase 9 gates rather than discovery claims.
