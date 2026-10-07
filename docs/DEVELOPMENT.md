# Development

The local preview includes R010's tray, authenticated browser and durable setup
check, plus Codex version, private-profile inspection, managed sign-in/out and a
fixed model diagnostic, R030a saved default-team configuration and R040a Arena
registration, R040b Tabulae/manual drafts, R040c Git inspection/init and R040d
previewed initial commits. R040e adds Speculator proposals and explicit imports into Specs; R040f adds
selected document snapshots. R040g adds manual task prerequisites. R030b adds explicit saved-team adoption for existing scopes.
Human-completed real-account/model acceptance and repository
execution remain R020 work. The previous source
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

In **Agents**, Check setup discovers paths without running them. Choose
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
Setup operations serialize while authentication or a model check is active.

With a fresh signed-in catalog, **Try a model** offers **Check model access**.
Select a model and confirm possible provider usage. This sends one fixed prompt,
with the lowest advertised effort, restricted private scratch permissions and a
two-minute limit. It accepts only a matching completed acknowledgement and shows
requested/runtime model, timestamp and measured duration. **Cancel model check**
waits for cleanup; provider usage may already have occurred. A failed/interrupted
check requires fresh consent and never automatically retries. No repository task
or arbitrary prompt is available. Connection refresh clears the current result.

Open **Team** to rename the four default roles, edit instructions or add up to
eight custom roles. Leave assignments empty to save a draft; choose Codex and a
model from its current catalog to bind one. Save creates an immutable revision;
expand **Recent saved revisions** to inspect the latest five. Removing a saved
custom role needs confirmation. A stale editor keeps its draft and refuses to
overwrite a newer revision; **Reload saved** asks before discarding edits.
Model disconnect/drift is visible and never silently replaces the saved model.
To replace a changed model behind the same catalog ID, clear/save the binding
then explicitly select/save it again. Saving starts no agent; execution grants
remain later work. Use only non-secret role instructions.

In **Arenas**, choose an existing directory in the native macOS dialog, enter a
name and confirm the displayed path/team before **Register Arena**. The dialog
cannot create folders, expires after two minutes and can be cancelled from either
surface. Registration records metadata only. `.git` presence is unverified;
registration runs no Git commands. Expand the registration team to inspect its
frozen revision. To update future-board defaults, open the Arena and expand
**Arena team**, review both rosters and confirm **Adopt saved team**. Existing
boards stay unchanged; each has a separate **Tabula team** adoption control.
**Arena settings** on a board returns to the Arena control. Adoption needs fresh
confirmation after another team edit and waits for that board's active planning
to finish/cancel. It preserves drafts and earlier planning receipts.
Home/ancestor, system, known credential and application-data roots are refused.
Duplicates and changed directory identities require a different/reselected folder.
After interruption choose again explicitly; no dialog is automatically replayed.

Choose **Open Tabulae** on a registered Arena, name a board and **Create Tabula**.
It inherits that Arena's team revision, even if global defaults have changed.
Enter a task title, description and acceptance criteria, then **Save task**.
Use **Edit task** and the **Column** select to move between Specs and ToDo;
ToDo requires nonblank description and criteria. Use **Prerequisites** to check
up to sixteen other tasks in this board that must come first. Tab/Space operate
the native checkboxes. Circular dependencies are refused without losing your
selection; uncheck a prerequisite to remove it. Cards show saved prerequisites.
This is planning order; dependency scheduling remains future work.
Expand saved history in the
editor to inspect revisions. Stale editors keep their text; copy it before
discarding and loading the current task. Recovered mismatched forms also keep
text but cannot overwrite another task. All drafts live in SQLite; no project
files, Git commands or agent work are involved in manual draft saves.
Brief/document Speculator planning is available; custom stages, accepted Markdown
specs and battle execution remain unavailable.

Expand **Repository setup** in the Arena's Tabulae screen and choose **Inspect Git**.
This checks standalone Git metadata using `/usr/bin/git` from the installed macOS
command-line tools; it does not read or stage working files. Missing repositories
offer a checkbox and **Initialize Git**. Confirmation is valid for that observation
for five minutes, creates `.git` on `main` with no templates, and creates no commit.
For an unborn repository, enter one relative file path per line and choose
**Preview initial commit**. Leave it blank for an empty baseline. Review paths,
sizes, modes, expandable hashes, branch and fixed author/message, then check the
separate confirmation and choose **Create initial commit** within five minutes.
Only those raw bytes are committed; attributes/filters are not applied and explicit
selection may include ignored files. Limits: 16 regular files, 240-byte paths,
1 MiB each, 8 MiB total and 7,000-byte preview metadata. Existing refs/indexes,
unsafe paths and changed previews are refused. No working file is overwritten.
The commit author is `Cuckoding <local@cuckoding.invalid>`, message
`Initialize Arena with Cuckoding`; no personal identity/config is imported.
If publication is interrupted, inspect Git; staged files/objects may remain and
need manual handling. Never delete ambiguous indexes/locks to retry.
Existing HEAD is a metadata observation, not proof of clean files. Unsupported nested/linked/external layouts remain usable for manual drafts.
Cancel waits for helper cleanup; after an interrupted/uncertain result inspect again
instead of assuming initialization rolled back. Use a temporary registered project
and isolated `CCODING_DATA_DIR` for QA; never initialize a copied fixture's real path.

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

## Planning preview (R040e/f)

Save a Codex/model binding for Speculator, then create an Arena and Tabula or
explicitly adopt the saved revision under **Tabula team** on an existing board. On the board open **Ask Speculator**, enter a brief, confirm
provider usage and **Generate proposals**. Review suggestions and **Add to Specs**
individually. Existing boards do not inherit later default-team edits. Refresh a
stale catalog in Agents before confirming again. Without document selection no
project files are read.

For documents, expand **Optional documents**, enter up to four explicit relative
`.md`/`.txt` paths and **Preview documents**. Review each expandable exact text
and SHA-256 before provider consent. Limits: 4,096 bytes each, 12,000 total, five
minutes to select/send. This reads locally without launching Codex or modifying
Git/files. **Use brief only** omits snapshots; reconnect shows the retained preview
and requires **Use these snapshots** to select it again. Editing a project file
does not change an existing snapshot; preview again to send new content. Imported
drafts retain the proposal/source snapshot linkage.

Focused checks: `rtk mix test test/cuckoding/planning_test.exs test/cuckoding/planning_documents_test.exs
test/cuckoding_web/planning_live_test.exs test/cuckoding/model_check_test.exs` and
`rtk proxy cargo test --manifest-path desktop/src-tauri/Cargo.toml connection::model_check`.
Use an isolated `CARGO_TARGET_DIR` for native QA if another bundle is running.
Successful proposal fixtures are explicitly synthetic; human login and actual
provider responses remain separate acceptance work. See the
[R040e worklog](../worklog/2026-10-07-R040e-brief-planning.md).
