# Development

The local preview includes R010's tray, authenticated browser and durable setup
check, plus Codex version, private-profile inspection and managed sign-in/out.
Human-completed real-account/model acceptance and execution remain R020 work. The previous source
reset remains intentional; do not restore the deleted implementation wholesale.

## Build and open

Apple Silicon prerequisites: Xcode command-line tools, RTK, asdf with the pinned
Elixir 1.20.3-otp-28 / OTP 28.5, rustup 1.97.1 and cargo-tauri 2.11.4.
The development packaging script uses Homebrew OpenSSL 3, bundles its runtime
library/license, and relocates OTP's crypto references. Cargo.lock fixes the
compatible Tauri 2.11.5 dependency cohort; use `--locked` for native checks.
Mix.lock fixes Phoenix 1.8.15, LiveView 1.2.12, Ecto 3.14.2 and SQLite adapter 0.25.0.

From the repository root:

```sh
rtk proxy bin/dev.build
rtk proxy open desktop/src-tauri/target/release/bundle/macos/Cuckoding.app
```

Launching the app opens the browser. Choose **Open Cuckoding** from its **C/furcina** menu
bar item to return later. **Settings** opens tool
discovery; **About Cuckoding** opens workspace details; **Quit** stops the owned
release and listener. No dock window or embedded web frontend is created.
This build is not notarized or public-release certified. Clean-machine, signing,
update and physical sleep/wake acceptance remain R060/R100.

In **Agents & roles**, Check setup discovers paths without running them. Choose
or edit the Codex path, confirm that you trust it, then **Check Codex version**.
Changing the path clears confirmation. The fixed version probe expires after
five seconds, has a Cancel control and persists public results. It does not sign
in or list models. Interrupted checks need a fresh confirmation; the observed
baseline is `0.146.0`. The shell supplies its own executable as the native helper;
never point `CCODING_NATIVE_HELPER` at an unrelated program.

After a supported version check, **Check Codex connection** requires its own
confirmation. It uses the displayed verified executable with Cuckoding's private
`agents/codex` profile, a clean environment and fixed read-only account/catalog
operations. A fresh profile correctly reports Not signed in. It does not adopt
personal Codex credentials or launch a turn.
A successful catalog shows source, fetched time, IDs, effort choices and input
modalities; after 24 hours or a failed refresh it is stale. A catalog is not
proof that the account can run a model. Inspection expires after ten seconds,
can be cancelled and does not retry automatically after interruption.

**Sign in with ChatGPT** needs a separate confirmation to use the private profile.
Choose **Continue on OpenAI** and complete the provider page yourself. The local
link works only in an authenticated Cuckoding browser session, expires within ten
minutes, and is recovered after browser reconnect while the app stays running.
Credentials go directly to the provider; no token-paste form exists. A successful
matching completion triggers account/model refresh. Already-connected profiles
are inspected without replacing their account.

**Cancel account operation** waits for helper cleanup and leaves authorization
unknown: the provider may have completed just before cancellation. Check connection
before trying again. Interrupted authentication never replays automatically.
**Sign out of this private profile** has its own confirmation and affects only this
app-owned profile. Both actions immediately clear old account/catalog observations.
Setup operations serialize while authentication is active. No agent turn runs.

The shell starts a bundled OTP release with a private HOME, clean environment,
exclusive data lock and an ephemeral IPv4 loopback port. It owns the one-time
handshake: do not run `mix phx.server` or the release executable directly.
Use `CCODING_DATA_DIR` only for an absolute, empty or marked rebuild directory.
The default is `~/Library/Application Support/CCoding Rebuild`; no old database
or personal provider profile is imported. Display names use Cuckoding (CC for short);
the established data directory, marker, executable and `CCODING_*` protocol keys
remain stable so the rename does not strand data. Quit before rebuilding a running app.

The build script re-signs Tailwind 4.3.0's downloaded standalone binary locally
because its upstream ad-hoc signature is invalid on this Mac. Rust release
stripping is disabled for the verified LINKEDIT alignment failure described in
[rust-lang/rust#157750](https://github.com/rust-lang/rust/issues/157750).
These build-tool workarounds do not disable Gatekeeper or signature verification.

## Quality and bundled smoke

```sh
rtk mix quality
rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml --check
rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --locked --all-targets -- -D warnings
rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked
rtk proxy bin/dev.build
rtk proxy bin/smoke
rtk git diff --check
```

`mix quality` runs formatting, compilation with warnings treated as errors,
ExUnit, Credo, Sobelow and dependency audit. Sobelow's architecture-specific
exceptions are documented in [Security](SECURITY.md). Its Elixir 1.20 warnings
while parsing Mix's generated lockfile are tool diagnostics, not compiler errors.
The test DB is `.ccoding/test/foundation.db`; tests use rollback isolation.
The smoke test creates a new private temporary root, checks the packaged native
shell/release protocol and Quit, and prints its retained data location.

## Working procedure

1. Read [AGENTS](../AGENTS.md), the core contracts and one selected plan slice.
2. Claim one task file and add a worklog with acceptance criteria.
3. Inspect Git state; preserve the user's intentional deletions and unrelated
   edits. Use the task's feature/fix branch.
4. Search local source with RTK; follow [reference coding](REFERENCE_CODING.md)
   for unfamiliar mechanisms. Apply Ponytail full.
5. Implement the smallest complete behavior with focused checks and durable
   events; update only affected contracts.
6. Run [quality gates](TESTING.md), record exact evidence and leave an explicit
   handoff for anything still open.

Every repository shell command starts with `rtk`. Use `rtk proxy` when filtering
would corrupt exact source/protocol output or command semantics; record why.
Stored product commands describe the underlying operation, not the RTK wrapper.

## Data and runtime safety

Use an isolated development data root. The source reset does not authorize
erasing old app databases, provider profiles, knowledge, logs or worktrees.
Any import/upgrade needs backup-first tests against a copy.

A requested restart must inspect only owned Cuckoding instances by executable,
PID/start identity, working directory and listeners; never dump argv/environments.
Use the graceful shell shutdown path, verify process/listener cleanup, then open
one explicitly chosen build and record its identity. Do not kill unrelated Codex,
Claude, Cursor or Hermes processes. The R010 app identity is `com.cuckoding.rebuild`.

## Toolchain and distribution

Keep Elixir/OTP, Phoenix LiveView/Tailwind, Ecto/SQLite, Git worktrees and Tauri 2.
R010 pins development versions; prove clean-machine packaging in R100. No macOS
user should need an Elixir/Rust toolchain to run the bundle.
Reintroduce CI only with real scripts/checks; no pipeline should point to removed
files or publish documentation claims as a working release.
