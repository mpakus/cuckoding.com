# Distribution and Operations

## Initial target

The first supported artifact is a macOS Apple Silicon `.app` built from the menubar shell (`docs/DESKTOP_SHELL.md`) with the Phoenix release, ERTS, assets, bundled plugins, and required native libraries inside `Contents/Resources`. Git, agent runtimes, and plugin binaries are discovered on the machine; the UI makes bundled versus discovered explicit.

## Build pipeline

1. Build and test Phoenix assets and the production release for the target.
2. Verify native library paths and release startup without system Erlang/Elixir and without an interactive shell `PATH`.
3. Build the shell and embed the release directory as a resource.
4. Generate an SBOM and dependency/license inventory.
5. Sign every Mach-O in the bundle (including ERTS executables and NIFs) with hardened runtime and the JIT entitlement the BEAM needs on Apple Silicon; notarize the app and updater artifacts.
6. Publish checksums, provenance, update manifest, and release notes.
7. Install and smoke-test on a clean supported machine.

## Startup contract

See the shell contract in `docs/DESKTOP_SHELL.md`. The production Tauri project
is `desktop/`; its local build embeds the release and runs `desktop/verify.rb`
under a sterile environment. That local artifact is not signed or notarized.

## Tool discovery

macOS GUI applications do not inherit an interactive shell's dotfile `PATH`. Search configured paths and known safe locations (Homebrew, `~/.local/bin`, npm global, cargo), allow the user to select an executable, and store verified paths. Display version and health for Git, each agent runtime, and each plugin binary.

## Data locations and backup

Application data in `~/Library/Application Support/Cuckoding/`: SQLite, artifacts, logs, plugins, global knowledge, and the default workspace root. Before updates and migrations, make a versioned database backup and a knowledge snapshot and record active run identifiers. Offer export of configuration, audit, and knowledge artifacts.

## Updates

- Verify update signatures and channel.
- Show release notes and migration impact.
- Require hibernation of running stages before schema-changing updates.
- Back up the database, knowledge, and configuration.
- Roll back the application if health checks fail; never pretend a downgraded binary can use an incompatible migrated database.
- Keep a safe mode that opens history and export without starting runners.

## Diagnostics bundle

Generate a user-reviewed, redacted archive containing versions, configuration schemas and hashes, health checks, plugin states, power events, recent normalized errors, migration status, process summaries, and selected event IDs. Exclude source contents, raw prompts, credentials, and full environment variables by default.

## Future targets

Linux: the same release with a tray icon shell (or none, headless `cuckoding serve` packaged with Burrito) and container runner plugins where Docker is native. Windows: later. A remote runner uses the same `RunnerBridge` semantics with mutual authentication, transport security, artifact transfer, and remote secret boundaries.
