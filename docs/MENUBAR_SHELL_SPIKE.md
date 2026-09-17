# Menubar Shell and Bundled Release Spike

The completed task 0003 implementation supports ADR-011 for the MVP. A small Tauri 2 process can own a tray-only macOS application, launch an embedded Phoenix release and ERTS without an interactive shell, authenticate browser handoff, report status, and cleanly stop its child tree. The same bundle also passed from a separate clean macOS account.

## Reproduce

The disposable implementation is under `spikes/0003-menubar-release/`. Run:

```sh
rtk proxy sh spikes/0003-menubar-release/build.sh
```

The script pins Rust 1.90.0 for this spike, builds the Phoenix release, copies it into Tauri resources, runs the Elixir and Rust tests, builds the `.app`, and runs the loopback integration verifier. The output app is ignored build output at:

```text
spikes/0003-menubar-release/shell/src-tauri/target/release/bundle/macos/Cuckoding Shell Spike.app
```

## Measured results

Environment: Apple Silicon, macOS 27.0, Erlang/OTP 28 with ERTS 16.4, Elixir 1.19.5, Phoenix 1.8.13, LiveView 1.2.11, Bandit 1.12.5, Tauri 2.11.5.

| Check | Result |
| --- | --- |
| Release readiness | exact `READY` JSON in 0.781 seconds on the final cold Bandit run |
| Browser bootstrap | missing, invalid, and replayed credentials rejected |
| Browser session | single-use token redirected to `/settings`; authenticated LiveView rendered |
| Crash after readiness | injected exit 42 observed in 0.156 seconds; no owned descendants remained |
| Graceful shutdown | successful exit in 1.134 seconds; no owned descendants remained |
| Crash before readiness | exit 41 in under 2 seconds; no false readiness line or descendants |
| Bundle | arm64 `.app`, 36 MiB, embedded ERTS 16.4 |
| Native surface | `LSUIElement=true`, Accessory activation policy, no native window |
| Network | one `beam.smp` listener on `127.0.0.1`; Erlang distribution disabled; no `epmd` |
| Sterile-home run | launched with a new temporary `HOME`, empty inherited environment, and no Elixir/Mix in `PATH`; bundled `beam.smp` served LiveView |
| Clean-account run | UID 502 launched the copied `.app`; bundled ERTS, loopback-only listening, authenticated browser handoff, and descendant cleanup passed |
| Signal shutdown | `SIGINT` reached the Tauri signal waiter, invoked the same shutdown ladder, and left no shell, BEAM, helper, or `epmd` process |

The timestamped protocol log is `spikes/0003-menubar-release/evidence/verification.log`; the separate-account log is `spikes/0003-menubar-release/evidence/clean-account-qa.log`. The app was also launched from the bundle for process-tree, listener, `LSUIElement`, sterile-home, signal-shutdown, and clean-account inspection. The clean-account operator used the tray action and confirmed the authenticated LiveView in the default browser before the verifier exercised shutdown.

The first reproducibility run surfaced Cowlib advisories in the then-current Cowboy graph. The spike switched to Phoenix's default Bandit server at pinned version 1.12.5; the final dependency resolution shown by `build.sh` contains no Cowboy or Cowlib package and emitted no advisory warning.

## Confirmed protocol

1. The shell generates a per-launch 64-byte Phoenix session-signing secret and a separate 32-byte bootstrap token, then writes both to a unique mode-0600 file under its application data directory.
2. The child receives only a safe environment, the selected loopback port, the bootstrap-file path, and `RELEASE_DISTRIBUTION=none`. The credential never appears in argv.
3. Phoenix uses the first value as `secret_key_base`; the authentication process reads the bootstrap value and deletes the file. Only then does the application write exactly `READY {"port":…, "version":…}`.
4. The shell exchanges the bootstrap credential once for a private shell token. Missing, invalid, and replayed bootstrap credentials return 401.
5. A menu action requests a 60-second, single-use browser token. `/open` consumes it, creates the cookie session, and redirects only to an allowlisted local path.
6. The shell polls authenticated `/shell/status` every three seconds.
7. Quit requests graceful shutdown, waits three seconds, then sends `SIGINT`, `SIGTERM`, and `SIGKILL` to the control-plane process group. `SIGINT` and `SIGTERM` received by the shell enter the same path.
8. Startup failures kill the child group before returning an error; a post-readiness child crash changes the menu status and does not restart-loop.

The Host header must be `127.0.0.1`; the endpoint binds only to `{127, 0, 0, 1}`. Production browser state changes still require the normal CSRF layer when the Phase 1 application replaces this protocol-only spike.

## Reference coding

XERJ retrieval found Hydra's explicit child lifecycle in `electron/daemon/lifecycle.ts:32-124`: detect early exit, poll readiness, request graceful shutdown, then use a bounded forced-stop fallback. The spike follows that shape while adding Cuckoding's process-group and credential requirements. Tauri's official resource, tray, and activation-policy APIs were used for bundle layout and native behavior.

## Packaging gates retained for Phase 9

The local bundle is only ad-hoc linker-signed. `codesign --verify --deep --strict` correctly fails because nested ERTS resources are not sealed. A release build must:

- sign every nested Mach-O and native library inside-out, then sign the app with a Developer ID identity, secure timestamp, and hardened runtime;
- determine and test the least BEAM JIT entitlement, beginning with `com.apple.security.cs.allow-jit` on `beam.smp`, before notarization;
- run `codesign --verify --deep --strict`, `spctl`, notarization, stapling, and clean-Mac installation evidence;
- preserve `RELEASE_DISTRIBUTION=none`; enabling distribution silently creates a wildcard listener and `epmd`;
- decide whether to prune unused ERTS tools after the signing layout is proven;
- remove the temporary `strip = false` workaround after rust-lang/rust#157750 is fixed for macOS 27, then remeasure bundle size.

No production signing identity or notarization credential was used in this discovery task.
