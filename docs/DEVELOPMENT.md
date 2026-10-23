# Development

R060o requires a rebuilt native helper for the fixed candidate-recovery read.
New Starts may recover complete retained capture/preparation checkpoints after
restart; Inspect shows dated observations and Resume stays explicit. This changes
no schema beyond seventeen. Missing proof stays blocked; no edits/capture/provider
turns are replayed. Physical sleep and broader recovery still need acceptance.

For optional custom stages (R050h), add roles in the exact board's Team,
then open **Advanced → Board columns → Add stage**. Choose file access (read by
default, or explicitly read/edit), before/after Implementor and Up/Down order,
then Save workflow. Up to four stages run between Speculator and independent
Secutor review, within existing Start limits and 64 changed files per task.
Every writer gets a retained checkpoint verified by later roles; no command
execution is added. Unused roles stay planning-only. Old read-only workflows keep
their grants; version four requires the seventeenth forward-only migration. Back
up first; schema-sixteen bundles refuse the upgraded root. Real-account custom-stage
acceptance remains open.

The local preview includes R010's tray, authenticated browser and durable setup
check, plus Codex version, private-profile inspection, managed sign-in/out and a
fixed model diagnostic, R030a saved default-team configuration and R040a Arena
registration, R040b Tabulae/manual drafts, R040c Git inspection/init and R040d
previewed initial commits. R040e adds Speculator proposals and explicit imports into Specs; R040f adds
selected document snapshots. R040g adds manual task prerequisites. R030b adds explicit saved-team adoption for existing scopes.
R040h adds proposed prerequisites and per-task selected-snapshot citations.
R040i adds accepted private Markdown specifications with revision and hash checks.
R040j adds revisioned, confirmed Arena check declarations. R050e freezes them in
Start and supports bounded native single-process checks; toolchain pipelines remain unsupported.
R050f makes those extra commands optional. Generated task criteria include verification
instructions; independent task/final Secutor reviews remain required without command setup.
R050a adds a read-only Battle preview for saved preparation and missing setup.
R050b adds consented isolated Git worktree preparation; R050c adds retained worktree inspection.
R020h fixes real model-check notices and simplifies saved agent setup. R020i adds
a named Codex/Cursor roster and per-role agent/model selections. Broader
real-account acceptance and broader provider execution remain open. The previous source
reset remains intentional; do not restore the deleted implementation wholesale.

R002 simplifies the Arena surface and creates a default board during registration.
The target is **Add folder → Create tasks → Start**. R040l adds bounded folder
snapshots and consented Speculator analysis. R040m saves the validated task graph
automatically. R050e adds a bounded sequential Codex/Cursor Start loop (R020p); see
[Arena loop](ARENA_LOOP.md) for exact prerequisites and limits.
R060a adds Pause/Resume on the same board. Pause waits for the current bounded
stage to finish; Stop cancels it. Resume keeps the original deadline and bindings.
The eleventh migration adds a control revision and paused-Arena exclusion; back
up the selected data root before upgrading. Older bundles refuse this schema.
R060b adds Retry failed stage for new battles with settled transient provider
failures. Two retries per task and two shared final retries preserve the original
limits and failed evidence. There is no new migration or native runtime grant.
R060c adds Skip with deferred dependents and reviewed Partial results. R060d
reopens fully settled restart checkpoints as Paused; Resume continues the saved
stage explicitly. In-flight or unknown effects still require inspection. These
controls never silently switch saved connections. R070a adds the twelfth
forward-only migration: partial capacity/uncertain-connection indexes only, no
record rewrites. Back up the selected data root before upgrading; older bundles
refuse the newer schema. New Starts allow two isolated Arenas to progress
concurrently; shared connections queue and each board remains sequential.
R080g adds two further index-only migrations (fourteen total) for bounded dashboard
and scoped activity reads. Keep the selected data-root backup; do not replace an
already running bundle without the graceful restart procedure below.
R080i adds public setup/planning work to the same global dashboard and a compact
Board activity disclosure for the selected Tabula's team/progress/workers. It adds
no migration, provider access or execution control.
R070d adds the fifteenth forward-only migration: per-task/final claim indexes,
without rewriting existing authority. Back up the selected data root before
upgrading; fourteen-schema bundles refuse the upgraded root. New Starts allow
waves of up to two independent task pipelines, with exact connections serialized
and checks/review/integration ordered afterward. Older battles retain their
sequential policy. R070e adds explicitly assigned paired connections per role;
real-provider parallel acceptance remains open. R060m adds a fixed read-only
retained writer-preparation checkpoint, requiring a rebuilt native helper and
matching host policy. It adds no migration and never repairs missing receipts.
No provider grant or native toolchain permission widens.
R040o adds the sixteenth additive migration, an immutable workflow revision table.
Back up before upgrading; fifteen-schema bundles refuse the new root. Existing
Tabula definitions supply revision zero without changing old rows. Use
**Advanced → Board columns** to rename the five columns; roles/order/grants stay
fixed and active planning/battles block edits. History is dated and new Starts
freeze their exact definition. R050g/R050h extend that ledger with ordered custom
read/write stages; R050h requires schema seventeen.
[Plan](PLAN.md#next-delivery-order--simple-arena) owns the remaining beta gates.

## Build and open

Apple Silicon prerequisites: Xcode command-line tools, RTK, asdf with the pinned
Elixir 1.20.3-otp-28 / OTP 28.5, rustup 1.97.1 and cargo-tauri 2.11.4.
The development packaging script uses Homebrew OpenSSL 3, bundles its runtime
library/license, and relocates OTP's crypto references. Cargo.lock fixes the
compatible Tauri 2.11.5 dependency cohort; use `--locked` for native checks.
Mix.lock fixes Phoenix 1.8.15, LiveView 1.2.12, Ecto 3.14.2 and SQLite adapter 0.25.0.
R102 pins Bandit 1.13.1 with required Thousand Island 1.6.0; use the updated lockfile.
After Tauri copies all resources, `bin/dev.build` ad-hoc signs the complete app
and runs strict/deep verification. `bin/smoke` requires that verification before
launching. This seals local resources; it supplies no Developer ID identity,
notarization, reproducibility or clean-machine guarantee.

From the repository root:

```sh
rtk proxy bin/dev.build
rtk proxy open desktop/src-tauri/target/release/bundle/macos/Cuckoding.app
```

Launching the app opens the browser. Choose **Open Cuckoding** from its **C/furcina** menu
bar item to return later. **Agents** opens the roster at `/agents`.
**Settings** and **About Cuckoding** open workspace settings at `/settings`; **Quit** stops the owned
release and listener. No dock window or embedded web frontend is created.
This build is not notarized or public-release certified. Clean-machine, signing,
update and physical sleep/wake acceptance remain R060/R100.

Development serves uncompressed assets so retained release `.gz` files cannot
hide watcher output. Production keeps compression. The source smoke checks both
encoding requests resolve to the current development script.

### If Arenas or agent/role setup seems missing

An **Agents & roles** discovery-only screen, an **Arenas · NEXT** label or the
old **CCODING** wordmark identifies the obsolete foundation UI. Verify the running
executable and its data root before changing product code. The current bundle is
`Cuckoding.app`, not the retained old `CCoding.app`. Arena simplification preserves
`/agents` (Add agent and the four-step wizard), `/team` (Add role and independent
agent/model assignments), and `/arenas`.

Stop the verified old instance, preserve its database, and launch the selected
current bundle. Keep an existing **Open Cuckoding Test.command** launcher's
`CCODING_DATA_DIR` unchanged when updating its bundle path; direct bundle launch
uses the default workspace instead. Do not merge/reset those databases to recover
apparently missing setup. Retired generated bundles may be moved out of the launch
directory with a `.retired` suffix; never remove their data. See
[R011c recovery evidence](../tasks/R011c-current-app-launch.md).

After restart, verify the actual browser and listener, not just source or build
success. The packaged smoke now checks session protection and authenticated
availability of the global dashboard, Agents, Add agent, Team/Add role, Arenas
and Settings. R100a also opened an eleven-migration retained-data copy with the
current bundle, checked the fourteen-migration result and preserved saved records.
The original nonempty data root has no ownership marker; that copy test does not
authorize recreating its marker or launching it. See the
[dated evidence](../worklog/2026-10-21-R100a-local-beta-verification.md).

In **Agents**, choose **Add agent** or **Edit** beside an existing connection,
then follow the four steps:

1. **Choose Agent.** Choose Codex or Cursor; its name and known executable path
   are prefilled. The name stays editable and custom names/paths are retained. Add
   multiple connections as needed; Claude Code and Hermes remain coming soon. **Executable details** allows a path override or **Use desktop Codex**.
   **Continue with Codex/Cursor** explicitly runs that program's fixed `--version` check.
   Supported Codex baselines are `0.146.0`, `0.162.0-alpha.2` and `0.162.0-alpha.17.2`. The desktop and standalone
   executables can advertise different models; no executable is silently replaced.
2. **Connect and Authorize.** **Refresh connection**, shown after sign-in, checks Cuckoding's private
   profile (`agents/<UUID>` for new connections; `agents/codex` for the legacy one) and fetches the full bounded catalog without inference.
   **Sign in with ChatGPT** opens a pending tab in that click and takes it to
   OpenAI once the exact login command is ready; complete the provider page yourself.
   Cursor uses the same one-click **Sign in with Cursor** handoff. The in-place
   Continue button remains for blocked/closed tabs or reconnects; it starts no
   second login. Cursor's verified CLI baseline is `2026.09.15-d2fe57e`. Connected profiles offer refresh and
   **Disconnect → Sign out** for the selected agent. Each named button explicitly authorizes
   its action; no repeated setup confirmation checkboxes are needed.
   **Next: Select models** stays visible. It becomes available after account
   connection, even if the model list is stale or a refresh failed. An active
   setup operation temporarily disables navigation.
3. **Select models.** If the catalog is missing or stale, choose **Refresh models**
   here to check the account and fetch the list without inference. Selections and
   Save remain unavailable until the catalog is fresh. Check the models you want available for new Team assignments,
   including additional models hidden in Codex's own picker. Cursor catalogs and saved
   selections accept up to 512 entries, including separately advertised effort/speed
   variants; the fixed CLI output remains bounded to 64 KiB. Selections survive
   Back and live updates. Codex’s **Test a model (optional)** sends one fixed prompt only
   after usage consent, with the lowest advertised effort, restrictive empty-scratch
   permissions and a two-minute limit. It grants no project access. Success accepts
   only the matching `CC_READY` response. Informational warning/deprecation notices
   are ignored without retaining their text; account drift, server requests, tools,
   unknown events and foreign completions are still refused.
4. **Save.** Review the selected models, then save their IDs/resolved models in
   SQLite. New Team pickers use this selection; existing bindings remain unchanged.
   Saving runs no model and survives restart. Changed setup invalidates a reviewed
   save; go Back and review again. Older workspaces without a saved selection still
   expose their full catalog until their first wizard Save.

The wizard resumes from saved setup. Executable paths are discovered from metadata
only. New model selections and optional diagnostics need a catalog checked within
24 hours. Saved role bindings remain reusable after that age limit when the last
observation succeeded and its exact identity/model binding is unchanged. Failed
refreshes, sign-out and binding changes still block use; native execution checks
the account/model before dispatch. Personal Codex
credentials are never adopted. Login URLs remain transient behind a session-protected
redirect. Cancel waits for authentication/model helper cleanup; provider usage may
already have occurred. Interrupted actions never retry automatically. Fresh connection
observations clear optional test consent but preserve model choices. Form keys and
setup revisions reject recovered stale actions. The shell supplies the native helper;
never point `CCODING_NATIVE_HELPER` at an unrelated executable.

Below the wizard, **Execution isolation (optional) → Run isolation check** tests
the verified Codex `0.162.0-alpha.17.2` sandbox with fixed commands in two disposable
folders. No account, model or Arena is used. Results are saved per connection and
include a timestamp; Cancel waits for helper cleanup. Each test retains its
synthetic fixtures under the command's private `probes/` directory. Rechecking the
version clears the current result but keeps historical events. A pass covers the
tested CLI sandbox only; it neither enables Start nor proves model-tool isolation.
The check is optional and does not block model selection or saving.

Open **Team** to rename the four default roles, edit instructions or add up to
eight custom roles. Leave assignments empty to save a draft; choose a named agent
and a model from that agent’s saved wizard selection (or full legacy Codex catalog).
For example, Speculator can save a Cursor/Grok binding when Cursor advertises that
model, while Implementor uses a Codex/GPT binding. Cursor initial planning uses
R020r's separate no-tools grant; optional Cursor model diagnostics remain unavailable.
No Codex fallback is used. Save creates an immutable revision;
expand **Recent saved revisions** to inspect the latest five. Removing a saved
custom role needs confirmation. A stale editor keeps its draft and refuses to
overwrite a newer revision; **Reload saved** asks before discarding edits.
**Disconnect** on each roster row opens a confirmation. It unassigns that exact
connection from current default, Arena and board roles before the private logout
runs. Instructions, other agents and historical teams remain intact. A failed logout
does not restore assignments. An unfinished battle using that connection or a busy
profile/planning operation refuses the action; stale forms also refuse it.
If the executable has changed or is unavailable, R080b completes Disconnect
locally without running it. The roster reports that provider sign-out was not
attempted, retains the private profile and shows Disconnected. Verify/reconnect
through Edit before selecting that connection for roles again. This local-only
receipt does not prove provider logout and cannot launch work.
Verified native logout also shows Disconnected. Its normalized native observation
stays checked/not_connected in the event receipt; the current projection records
the completed disconnect. Historical observations use only their exact completed
logout command/provider/connection to derive the same display without another call.
Edit opens Connect and Authorize when signed out, even with an older model save.
Model drift remains visible and never silently replaces the saved model.
To replace a changed model behind the same catalog ID, clear/save the binding
then explicitly select/save it again. Saving starts no agent; execution requires
a separate bounded Start. Use only non-secret role instructions.

In **Arenas**, choose an existing directory in the native macOS dialog, keep or
edit its suggested name and confirm the displayed path/team before **Add Arena**.
The default Tabula is saved atomically and opens immediately. The dialog
cannot create folders, expires after two minutes and can be cancelled from either
surface. Registration records metadata only. `.git` presence is unverified;
registration runs no Git commands. Expand the registration team to inspect its
frozen team. To update future-board defaults, open **Advanced → Team for new boards**,
review both rosters and confirm **Use saved team**. Existing boards stay unchanged;
each has a **Board team** dialog beside its title. Version numbers remain in Team history.
Home and the five-step navigation rail reuse saved setup without starting providers.
Team shows role bindings directly; optional name/instruction fields remain expandable.
The Arena's Start summary keeps full limits in Inspect and groups identical blockers
by exact connection. Known missing setup disables Start with a repair link.
An assigned agent with no model uses **Choose model** to open the affected Team
role, rather than sending the user back to provider sign-in. Team warns about
incomplete required roles. Board repair links remember that exact Arena/Tabula.
After **Save team**, choose **Review team for [board] → Use saved team**.
The direct return opens the board dialog and the single labelled submit confirms
the displayed assignments. Compact rows show bindings; expand Role instructions
to inspect the full text. No checkbox or automatic adoption is involved. Disconnect clears assignments intentionally;
reconnecting does not restore historical bindings.
Adoption rotates its form key and needs a fresh submit after another team edit and waits for that board's active planning
to finish/cancel. It preserves drafts and earlier planning receipts.
Home/ancestor, system, known credential and application-data roots are refused.
Duplicates and changed directory identities require a different/reselected folder.
After interruption choose again explicitly; no dialog is automatically replayed.

Choose **Open Arena** to return to its first board; explicit board URLs and the
selector preserve other boards. **Advanced → Add another board** creates extra
Tabulae with the Arena's team, even if global defaults changed. Old Arenas without
boards offer explicit creation; opening a page never creates data.
**Create tasks** opens the brief/folder-snapshot dialog described below.
**Repository setup** and **Add another board** are buttons in Advanced that open
dialogs. For manual work, choose **+** beside Specs or ToDo, enter a title,
description and criteria, then **Save task**. Escape or the close button returns
focus without discarding text. Reopening retains unsaved changes; selecting a
different task still requires the existing discard confirmation.
Use **Edit task** and the **Column** select to move between Specs and ToDo;
ToDo requires nonblank description and criteria. Use **Prerequisites** to check
up to sixteen other tasks in this board that must come first. Tab/Space operate
the native checkboxes. Circular dependencies are refused without losing your
selection; uncheck a prerequisite to remove it. Cards show saved prerequisites.
R050e freezes this graph and schedules prerequisite tasks before their dependents.
Expand saved history in the
editor to inspect revisions. Stale editors keep their text; copy it before
discarding and loading the current task. Recovered mismatched forms also keep
text but cannot overwrite another task. All drafts live in SQLite; no project
files, Git commands or agent work are involved in manual draft saves.
Brief/document Speculator planning and accepted Markdown specifications are
available. The default Codex workflow can Start; custom execution stages remain unavailable.

Expand **Advanced → Repository setup** in the Arena and choose **Inspect Git**.
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

After a committed Git inspection, expand **Repository setup → Isolated worktrees**.
Review the exact commit and private destination, confirm, then **Prepare worktree**
within five minutes. It creates a detached locked checkout and a source Git
registration, leaving original staged, unsaved and untracked files untouched.
Limits: 10,000 regular files, 240-byte paths, 8 MiB per blob / 64 MiB total,
1 MiB listing; no symlinks, submodules, Git filters or known credential paths.
The host is not a sandbox. Preparation runs no agents or declared project checks.

The latest ten attempts show progress/cancellation, result and retained location.
Each `<data>/runtime-home/worktrees/<command UUID>/` keeps `owner.json` beside
`checkout/`. If stopped or interrupted, inspect both this location and the source
Git worktree registration. Do not delete/reset/prune uncertain or dirty work to
retry; the app neither removes it nor replays a lost command. A new preparation
requires new consent and a new destination. Creation receipts persist across
restart but do not certify current contents. Future execution must revalidate them.

Choose **Inspect worktree** beside a completed preparation. The app checks its
private ownership, directory identity, locked detached commit, index entries and
raw tracked bytes. Extra files (including ignored files) are flagged without
reading their contents. Nothing is staged, reset or removed. Git CRLF or other
built-in checkout transformations can report differences. Missing/changed ownership
fails verification; retain the checkout and inspect manually. Results show their
UTC time, survive reconnect/restart and grant no execution. Cancel waits for native
cleanup; interrupted inspections need a new explicit request and never replay.

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

## Build identity and retained evidence

`rtk proxy bin/dev.build` generates one format-one public manifest before compiling
the production release and native shell. Settings → Build details shows its UUID,
UTC build time, source revision/dirty observation, application-input digest, target,
schema generation and tool versions. A native/release mismatch refuses before
workspace preparation; production verifies its compiled copy before migration or
dispatch. Startup does not add a general runtime file-reading API.

The builder's explicit `INPUTS` in `bin/build-info` covers application source,
configuration, locks, migrations, branding/native resources and build scripts.
Generated files, private storage and unrelated files are excluded. Git reports
only whether local changes exist; their names/content are not put into metadata.
Links/special inputs and source changes during the build refuse its evidence.
This digest does not cover dependency provenance or prove reproducible output.

After strict/deep seal verification, the build exclusively retains
`.ccoding/build-receipts/<build UUID>.json` with the manifest, actual helper SHA-256
and resource-manifest SHA-256. Previous receipts are not overwritten. These are
private local-preview observations, with release acceptance explicitly false.
Normal builds invoke `bin/build-info generate` / `record` automatically; a bare
Cargo shell without embedded metadata cannot launch a packaged release. Fixed
provider helper operations retain their existing boundaries.

`bin/dev.server` remains a separate source preview: it ignores packaged metadata
even when generated files exist. Settings labels it accordingly. Build metadata
never reattributes historical attempts or grants provider access. No schema
migration is added; the existing schema-seventeen barrier remains unchanged.

Verify metadata behavior with `rtk proxy python3 test/build_info_test.py`, focused
BuildInfo/Settings tests, Mix quality, Rust checks and bundled smoke. The native
`--build-info` switch reports only the closed public metadata or Not packaged;
it does not launch a provider or read a saved profile.

## UI development

After the first `rtk proxy bin/dev.build`, run:

```sh
rtk proxy bin/dev.server
```

This opens an authenticated source-development app at `http://127.0.0.1:4000`.
HEEx source annotations,
Phoenix code/live reload and Tailwind/esbuild watchers are enabled. Changes to
dependencies, endpoint plugs or configuration require a restart. This serves the
Phoenix application; the separate static `site/` preview keeps its existing workflow.

The launcher resolves the pinned local tools, performs the same one-use bootstrap
and browser handoff as the tray shell, and maintains its heartbeat. It reuses the
built native helper but owns separate data at `.ccoding/ui-dev/`; existing app
databases and agent profiles are not imported. Like the native shell, it passes
`CCODING_DISCOVERY_HOME` solely for known
host executable metadata lookup. Provider HOME/environment/grants stay private;
no personal authorization is imported. Only one source server can own this
root. `--port 4001` selects another port; `--port 0` chooses an ephemeral port.
`--no-open` suppresses browser launch. Ctrl-C stops the owned server and watchers,
retaining development data. Restart the launcher to reopen an expired browser session.

**Already running:** a second launcher now explains that the existing server owns
this checkout's data. The older `[Errno 35] Resource temporarily unavailable` meant
the same lock contention. Use the existing browser tab, or press Ctrl-C in its
launcher terminal before running the command again. Changing `--port` does not
create a second data root. Never delete `shell.lock`: the OS releases its lock when
the owner exits, and the retained file is safe to reuse. If an assistant started
the preview, have it stop that owned instance before handing startup back to you.

Phoenix LiveReload is development-only. Only its local reload iframe permits
inline script and same-origin framing. Application pages keep the normal strict
CSP; production/test contain no LiveReload routes. Tidewave, its external toolbar
and MCP endpoint have been removed. See [Security](SECURITY.md).

Verify the developer integration (no browser or provider usage):

```sh
rtk proxy bin/dev.server --smoke --port 0
```

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

`bin/dev.build` refuses to replace a running or linked generated release or app
bundle. After Quit it recreates `_build/prod/rel/cuckoding` and the generated app
bundle so removed dependencies cannot remain in Mix/Tauri's overlaid resources. It never removes the selected application data root.

`mix quality` first runs Hex's current retirement/advisory check, then formatting,
compilation with warnings treated as errors, ExUnit, Credo, Sobelow and the existing
dependency audit. Hex is a development tool, not a release application. A package
fetch warning is actionable even when another advisory source reports clean.
Sobelow's architecture-specific
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

If the tray is unavailable, an idle workspace can use Erlang's normal `SIGTERM`
shutdown as a fallback. First verify no battle retains resources, no provider/setup
command is active, and the database integrity/foreign-key checks pass; take a
private online backup. Bind the exact backend executable, parent, data-root cwd
and start identity, then signal through its macOS audit token so PID reuse cannot
target a different process. Wait for the backend's normal exit, the shell's
heartbeat-driven exit and listener closure before replacing the bundle. Never
escalate an uncertain shutdown or use this procedure for active work. This fallback
does not produce the tray's `shell.quit_requested` event; record it in the worklog.
[Erlang signal behavior](https://www.erlang.org/docs/29/apps/kernel/kernel_app.html).

The packaged shell now exchanges `shell-lease-v1` on its authenticated heartbeat.
Phoenix requests a fixed 15-second idle-system sleep assertion only for eligible
new battles. Settings shows the last native held/released/unavailable report and
age; the source UI launcher has no native assertion and may show Unknown.
Do not change system sleep preferences or use this report as physical wake proof.
Native tests acquire a short assertion, verify it leaves the active list on
timeout while retaining its owned ID, then verify release; they never request sleep.

## Reset all local workspace data

`bin/reset-agents` resets the whole selected Cuckoding workspace. It does not
delete your project folders or personal Codex/Cursor profiles. Quit the app first:

```sh
rtk proxy bin/reset-agents --data-dir '/absolute/path/to/cuckoding/data'
```

The directory defaults to `CCODING_DATA_DIR` when set, otherwise
`~/Library/Application Support/CCoding Rebuild`, matching the native shell.
The saved test launcher may select a different data root; pass that exact root.
For source UI development, use `--data-dir "$PWD/.ccoding/ui-dev"` after Ctrl-C.
Read the displayed target and type `RESET`; `--yes` is explicit noninteractive
confirmation. Creating/testing the helper never authorizes resetting real data.

The script validates the private canonical marker/ownership, acquires the same
exclusive `shell.lock`, checks SQLite integrity/foreign keys and refuses pending
setup or unfinished/paused/needs-attention battles. Finish/stop work through the
app first; the helper neither kills workers nor bypasses uncertain cleanup.
It retains the lock inode at the active path throughout reset.

All other contents move into a new private sibling `<data-name>-reset-*/workspace/`:
SQLite and its history, agent profiles, Arenas/boards/tasks/role registrations,
specifications, logs and runtime artifacts. `reset.jsonl` records dated intent
and completed archival without content/credential values. The archive still
contains the provider-owned authorization files; keep it private. This local reset
does not revoke provider accounts. External project Git branches/worktree
registrations are unchanged; their old records remain in the archive.

Fresh marker/lock-only storage initializes through normal migrations on the next
launch with the same data directory. No profiles, roles or tasks are imported.
The old marker moves first: an interrupted move leaves startup blocked instead
of creating a mixed workspace. Keep both paths and inspect them after any error.
To restore, quit and preserve any newly created data separately, then move the
archived `workspace/` entries (including dotfiles) back to the original root while
retaining its lock. Do not merge two databases or overwrite a new workspace.
Archive purging and automatic partial-reset recovery are deliberately absent.

Verify only disposable fixtures:
`rtk proxy python3 test/reset_agents_test.py`.

## Toolchain and distribution

Keep Elixir/OTP, Phoenix LiveView/Tailwind, Ecto/SQLite, Git worktrees and Tauri 2.
R010 pins development versions; prove clean-machine packaging in R100. No macOS
user should need an Elixir/Rust toolchain to run the bundle.
Reintroduce CI only with real scripts/checks; no pipeline should point to removed
files or publish documentation claims as a working release.

## Create tasks (R040e/f/l/m)

Save a Codex/model binding for Speculator, then create an Arena and Tabula or
choose **Use saved team** under **Board team** on an existing board.
Open **Create tasks**. Enter a brief or **Read project folder**,
review the local snapshots, confirm provider usage and **Create tasks**.
A brief is optional with nonempty sources. One successful request atomically saves
up to six editable cards in Specs, with their prerequisites and source receipts.
Existing boards do not inherit later default-team edits. Saved assignments do not
need routine refresh solely because their catalog is older than a day. A failed
lookup or invalidated connection still needs repair in Agents before planning. Without document selection no
project files are read.

**Read project folder** visits `docs/` first, then eligible text/source files.
The versioned policy stops at 2,000 entries, six directory levels, 16 files,
16 KiB per file and 64 KiB total. It excludes hidden/generated/known credential
paths, links and special files. Files are never truncated: skipped counts and
partial scope are visible. Empty folders need a brief. Exact text is saved locally;
filename filters do not detect every secret, so review before sending it.
No Git repository is needed and no provider runs during the read. Cancel waits
for native cleanup. Interrupted reads require an explicit new request.

For a narrower selection, expand **Choose specific documents instead**, enter up to four explicit relative
`.md`/`.txt` paths and **Preview documents**. Review each expandable exact text
and SHA-256 before provider consent. Limits: 4,096 bytes each, 12,000 total, five
minutes to select/send. This reads locally without launching Codex or modifying
Git/files. **Use brief only** omits snapshots; reconnect shows the retained preview
and requires **Use these snapshots** to select it again. Editing a project file
does not change an existing snapshot; preview again to send new content. Imported
drafts retain the proposal/source snapshot linkage.

New cards list their prerequisites and cite selected snapshots by exact
stored text/hash. Expand each citation and check its relevance. Duplicate results
and reconnects never create more cards. A separately consented analysis adds a new
graph without replacing existing edits. Interrupted inference is never replayed.
Old requests retain **Add to Specs** per suggestion, in prerequisite order;
their partially imported graphs and edits remain intact.
Open a created task and expand **Original proposal sources**
to inspect its citations, including after app restart. These describe the original
proposal; editing a task does not update or revalidate its source claims. Older
proposals still import with no inferred prerequisite/citation fields.

On a saved task, expand **Accepted specifications**, choose **Preview specification**
and inspect **Exact Markdown text**. Nonempty description/criteria are required.
Confirm the displayed task/prerequisite revisions and **Accept specification**.
The app writes a private Markdown artifact and moves the exact saved task to ToDo;
no agent, Git command or Arena file write occurs. Use **Reload task** for the new
editor revision. Unsaved text is preserved and guarded before reload.

**Download Markdown** verifies the file against its saved SHA-256. Artifacts live
under `<app data>/specifications/<acceptance command UUID>.md`; they survive restart.
Editing a task/prerequisite makes its old acceptance historical. Editing/removing
a Markdown file makes downloads unavailable; accept a new preview to retain a new
file. Prior files, including uncertain partial writes, are never overwritten or
automatically replayed. Specification acceptance is intent, not execution approval.

Focused acceptance checks: `rtk mix test test/cuckoding/specifications_test.exs test/cuckoding_web/specification_live_test.exs`.

Focused checks: `rtk mix test test/cuckoding/planning_test.exs test/cuckoding/planning_documents_test.exs
test/cuckoding_web/planning_live_test.exs test/cuckoding/model_check_test.exs` and
`rtk proxy cargo test --manifest-path desktop/src-tauri/Cargo.toml connection::model_check`.
Use an isolated `CARGO_TARGET_DIR` for native QA if another bundle is running.
Successful proposal fixtures are explicitly synthetic; human login and actual
provider responses remain separate acceptance work. See the
[R040e worklog](../worklog/2026-10-07-R040e-brief-planning.md).


## Project checks (R040j)

The normal flow uses acceptance criteria and verification instructions in generated
tasks; separate command configuration is not required. For extra commands open
**Advanced → Extra command checks (optional)**. **Add check** provides a name,
executable basename (for example `test`), one nonempty literal argument per line
(for example `-f` then `README.md`), relative worktree directory (`.`) and timeout
(default 300 seconds, declaration range 1–1,800). Start accepts at most 300 seconds
per command and 600 seconds combined. Use up to eight named checks. Enter no RTK
prefix or credentials. Quotes and spaces are literal, not shell syntax; leave the
whole argument field blank for no arguments. Admission verifies executable identity
and the native single-process grant; Mix/npm toolchains are not supported.

**Review changes** shows exact normalized arrays/directories/timeouts. Confirm
before **Save checks**, including staged removals. This records configuration only;
it executes nothing and grants no access. Saved settings apply to the Arena;
future battles must explicitly freeze a revision. Stale editors keep text and
refuse to overwrite. **Reload saved checks** asks before discarding edits. The
history disclosure retains the latest five definitions, with older rows in SQLite.
An empty list never counts as passing verification.

Focused checks: `rtk mix test test/cuckoding/project_checks_test.exs test/cuckoding_web/project_checks_live_test.exs`.
The additive eighth migration preserves existing drafts/specifications and creates
no check approval for old Arenas. Verify upgrades only on a backup copy. Older
seven-migration builds refuse the new schema; do not downgrade a migrated root.

## Battle preview (R050a)

From a Tabula, open **Battle preview**. Expand Git baseline, Assigned team, Saved
tasks and Project checks with mouse or keyboard. The page shows the board's saved
team revision, all draft tasks/prerequisites, current accepted Markdown status,
exact check arrays and dated Git evidence. Download links recheck artifact hashes.
Follow the settings links to address missing setup. Git observations expire after
five minutes; **Refresh preview** only re-reads saved evidence, so use **Repository
setup → Inspect Git** for a fresh repository observation.

The page marks its details stale after saved updates or one minute. Refresh keeps
disclosures open and rebuilds evidence. It creates no command, starts no provider,
reads no Arena files and changes no draft. It is not a battle authorization or a
promise that a configured command can run. Start/grants/worktrees/check execution
and the independent review loop remain the next execution work; accepting specs
beforehand stays optional. The schema is unchanged at eight migrations.

Focused checks: `rtk mix test test/cuckoding/battle_preview_test.exs test/cuckoding_web/battle_preview_live_test.exs`.

R020i's ninth migration preserves the legacy connection and all earlier records.
Back up and verify prior-schema copies before upgrading. An older eight-migration
build refuses the migrated root; use the backup for rollback, never erase new data.
Focused checks: `rtk mix test test/cuckoding/agents_test.exs test/cuckoding/cursor_test.exs
test/cuckoding_web/agents_live_test.exs`; native Cursor conformance:
`rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml --locked cursor`.
