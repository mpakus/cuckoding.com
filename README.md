# B\*SS

Local coding-agent orchestration for macOS. The public introduction is
[cuckoding.com](https://cuckoding.com/). Behavior is specified in
[BOSS_PLAN.md](BOSS_PLAN.md).

B\*SS runs a Phoenix LiveView dashboard on your machine. You register a Git
repository, provide Markdown specs or committed documentation, and choose a
check command you trust. It plans, implements, checks and reviews in retained
Git worktrees, then integrates an exact checked commit. A model's "done"
message is not Done. Done requires that published SHA, passing postchecks and
the retained checkout.

You start the work, choose the reviewer, and keep Pause and Stop. A merge
conflict, unknown cleanup, an unresolved decision or a provider outage still
waits for you. The dashboard binds to loopback. Coding agents use your
installed CLIs and provider accounts, which can send data to those services
and incur charges.

Task execution is macOS. Linux task execution is not available, and the Linux
folder picker has not been verified on a desktop. `0.1.0-rc.2` is a local beta
you build yourself. There is no public installer, notarized download or stable
release tag. See the [build and installation guide](docs/RELEASE.md) and
[release notes](CHANGELOG.md).

The running program still uses `Boss.*` modules, `BOSS_DATA_DIR` and `~/.boss`.
This page uses B\*SS for the product name.

Under that name, the app provides local browser access, native folder
selection, validated project registration, automatic Markdown sync,
transactional spec/revision/task history and versioned task commands with
immutable receipts, a Kanban board, a revision-aware task drawer, persistent
local CLI detection with per-agent authorization and model catalogs, role-based
agent routing (`Reviewer`, `Implementer`, `Analytic` and custom roles), manual
Codex attempts, and fresh read-only Codex review in retained Git worktrees.
Managed workflows and Autopilot add a typed plan, bounded fixes, role-pinned
planning/implementation/diagnosis/review across **Codex**, **Claude Code**,
**Cursor Agent** and **OpenCode**, live pipeline telemetry, explicit integration
and postchecks before Done. Task source adoption and Done-only dependency
readiness keep execution pinned to reviewed inputs.

## Run locally

Use Elixir 1.20.3 compiled for OTP 28, an OTP 28 runtime, and Node.js 20+ with npm.
`.tool-versions` pins Elixir; Erlang/OTP and Node come from your local installation.
macOS task runs also require a C compiler (Xcode Command Line Tools); `mix compile`
builds the bundled process guardian.
Check `elixir --version`: the compiled OTP version should match the running OTP.
If Homebrew takes precedence over asdf in PATH, use `rtk proxy asdf exec mix`
instead of `rtk proxy mix` for the commands below.

```sh
rtk proxy mix setup
rtk proxy mix phx.server
```

`mix setup` downloads dependencies, runs `npm ci` in `assets/` and builds assets.
Tailwind uses the official npm CLI; standalone macOS binaries failed code-signature
validation on the development machine. No system security setting is changed.

Open **http://127.0.0.1:4000** and enter the one-use token printed in the terminal.
It expires after ten minutes. The token is submitted with CSRF protection and is
never included in the URL. The browser receives a signed, HttpOnly, SameSite=Strict
cookie. Closing a tab does not stop B\*SS. Without **Remember this browser**, a
restart or expiration of the 12-hour browser session requires a new token.

Select **Remember this browser for 30 days** at unlock to reconnect automatically
on the same loopback address and port, including after a B\*SS restart. B\*SS
remembers one browser per data directory. A new remembered unlock replaces the
previous one. B\*SS keeps a hash and expiry in its private data directory and
issues a fresh ordinary session on automatic unlock. Clearing the browser’s
site data removes its saved access. To revoke automatic unlock on the server,
run `Boss.LocalAccess.forget_browser()` from its local IEx console.
The remembered cookie is scoped to the unlock path on the loopback host.
Browsers share cookies across ports on the same host.

For a replacement token without stopping an IEx server, run
`Boss.LocalAccess.new_token()` in that server's local console. This invalidates
any unused token and keeps existing browser sessions valid. Start an IEx server
with `rtk proxy iex -S mix phx.server` when you need this capability.

## Register a project

After connecting the browser, click **Choose repository…** and select a folder in
the operating system dialog. Paths are read-only in the browser. The specs folder
defaults to `specs` inside that repository; use **Choose specs folder…** to change
it. Both folders must already exist. B\*SS accepts a local Git working tree
with at least one commit; the optional base branch defaults to its current branch.
The base must be an existing local branch. A detached checkout needs an explicit
base branch. The optional project name defaults to the folder name.

The dialog opens on the computer running B\*SS: macOS uses its built-in folder
chooser; Linux requires a graphical desktop session and `zenity` on PATH.
A graphical desktop session is required; an unavailable picker reports an error.
Only one dialog can be open at a time. Cancel keeps the form unchanged; a dialog
times out after two minutes. Closing its requesting browser session or stopping
B\*SS terminates the owned picker helper. Selected paths stay in the LiveView
process and are validated again before registration.

B\*SS stores canonical paths in its own database without editing the repository.
The specs directory must be strictly inside the repository, with no symlink
components. Registering the same repository through another path or linked
worktree returns an error. Projects survive tab closure and backend restart.

Runner and Git research live in `spikes/`, separately from the application.
The [transport experiment](spikes/transport/README.md) evaluates demand-driven
stdout/stderr, genuine EOF and bounded reader state with local fixtures. It is
separate from the macOS native process-group owner used by manual task runs.
Its fixture results do not certify other adapters or detached process trees.

## Sync specs

B\*SS reads registered projects' `.md` files automatically, including subfolders.
Open a project to see imported tasks, the latest source revision and pinned task
snapshot; **Sync specs** checks immediately. Source Markdown is stored exactly
and is never rewritten.

One background sweep starts with B\*SS and processes projects sequentially. The
next sweep starts two seconds after the previous one finishes; new projects join
that sweep. Changed files are read again after 300 ms and must have the same
identity/path/source before import. A changing or invalid scan keeps the previous
snapshot and is retried on the next sweep. This coalesces short save bursts; it
cannot observe every intermediate edit or guarantee an atomic filesystem snapshot.

Set `config :boss, spec_poll_interval_ms: 2000` to change the gap between sweeps,
or `spec_auto_sync: false` to use manual Sync only. Restart B\*SS after changing
configuration. A large or slow project increases the time until later projects
are checked. Unchanged scans perform no database writes. Errors appear on the
project page, including when it is opened after a failed background scan. Open
pages reload saved entries after completed syncs, with one active read and at most
one queued refresh. Repeated identical errors do not create repeated notifications.

Frontmatter is optional. It must be one nonempty YAML mapping between opening
and closing `---` lines. Optional `id` and `title` must be nonempty strings of at
most 200 bytes and 200 characters respectively. The title otherwise comes from
the first H1 outside fenced code, then the filename. BOM and CRLF are supported.
Duplicate keys, aliases, keys starting with `<<`, custom tags and binary tags are
rejected.
`priority` remains source-only. `depends_on` accepts up to 32 unique explicit
frontmatter IDs from this project. Only Done satisfies a dependency; missing IDs,
invalid declarations and cycles block new task starts. See
[dependency readiness and pinned-revision limits](docs/TASK_DEPENDENCIES.md).

Identity is scoped to the project: an explicit ID survives moves; without an ID,
a renamed file creates a new task and the old identity becomes **File missing**.
Deleting a file retains its task and all revisions. Reusing a missing path for a
new explicit ID creates a separate history. Duplicate IDs abort the entire scan.
Moving an explicit-ID file records a revision even when its text is unchanged,
so the historical source path remains accurate.

Each spec has one task, initially `new`, pinned to its first revision and title.
Later source changes never advance that pin. Repeating the latest text/path is
a no-op; A→B→A creates three revisions. To update an eligible idle task, inspect a
newer source in its drawer and select **Use revision N**. This resets it to New
and retires an unintegrated approval while retaining all history. See
[explicit revision adoption](docs/TASK_REVISIONS.md).
SQLite rejects updates/deletes of revisions and prevents
a task from referencing another spec's revision.

A failed scan preserves the previous snapshot, including missing flags. The
complete scan and reconciliation share an immediate SQLite transaction, which
holds the write lock during local reads and the settle pause for changed automatic
scans. This also serializes actual manual and automatic scans. At most four import
workers can run;
each has a 10-second deadline and a memory ceiling. Workers stop before Repo on
application shutdown. Stopping only the poller ends its owned sweep; an in-flight
import may finish within its existing deadline. No remaining projects from that
sweep are started. Interruption after commit can have an unknown result, so
the UI reloads saved entries and asks for a retry instead of claiming rollback.

Limits: 256 Markdown files, 1 MiB per file, 8 MiB total, 16 KiB frontmatter,
1,000 directory entries and nesting depth 16. Files and filenames must be UTF-8.
Symlinks and special files anywhere under the specs folder reject the scan.
These checks suit local files; they do not provide an atomic filesystem snapshot
or an OS sandbox against hostile concurrent path replacement. Large retained
histories are not paginated in this initial list.

Backend APIs: `Boss.Projects.SpecImporter.sync(project_id)` returns counts or
path-specific errors; its internal `settle_ms` option enables the second observation.
`Boss.Projects.list_spec_entries(project_id)` reads the list;
`Boss.Projects.list_spec_revisions(spec_id)` returns immutable history.
`Boss.Projects.record_spec(project_id, attrs)` records one prevalidated observation
(`relative_path`, `original_text`, `title`, optional `explicit_id`). Its result is
`{:ok, %{spec: spec, revision: revision, task: task, change: change}}`, where change
is `:created`, `:unchanged` or `:revised`. Rename reconciliation belongs to the full
importer; a direct record call rejects an ID already assigned to another path.

Task commands are available through `Boss.Tasks.transition/2`, with a unique
command ID and expected state version. Attention/cancellation and safe recovery
to `new` persist together with an immutable event. Exact retries return the same
receipt; stale commands and conflicting reuse are rejected. Managed workflow
producers advance tasks only with persisted stage evidence. Manual Codex attempts
have a separate lifecycle and do not advance task workflow state. See the
[command contract and transition table](docs/TASK_WORKFLOW.md).

Migrations run at the next startup and preserve existing projects/history. The
missing-state migration makes path uniqueness apply only to present files.
Rolling it back fails atomically if retained histories share a reused path;
it never deletes those histories to make rollback succeed. The task-events migration
also refuses rollback after any command has been recorded. Rolling back the
older persistence migration drops spec/revision/task tables. Migration tests
use disposable databases only.

## Task board and details

The project board groups saved tasks into Backlog, In Progress, Review,
Needs Attention and Done. `ready_to_merge` stays in Needs Attention; only `done`
belongs in Done. Empty columns remain visible. On narrow screens the board
scrolls horizontally without widening the page.

Open a card to read its pinned task snapshot, latest source metadata, selected
source revision, current reason and latest 50 task transitions. Source Markdown
is displayed as escaped text. Selecting a historical revision changes only the
view; it never advances the task pin. The drawer URL supports reload and browser
Back/Forward. Automatic sync keeps the selected task/revision open, including
source edits, explicit-ID renames and missing files. Escape or Close returns
focus to the task card.

Details are scoped to the current project and read in one database snapshot.
Loading/error states do not substitute a different revision's cached source.
The drawer also provides managed workflows, explicit integration, manual Codex
runs/checks/reviews, saved evidence, explicit newer source adoption and Stop. Full state mapping
and the read API are documented
in [TASK_WORKFLOW.md](docs/TASK_WORKFLOW.md).

## Complete a task with a managed workflow

To process the whole current Backlog, choose **Autopilot** beside **Sync specs** on
the project page. Enter the check command and reviewer, then **Start Autopilot**.
Tasks run one at a time through fixes, review, integration and verified Done.
Independent tasks can continue after a pre-integration failure with verified
cleanup. Shared provider failures and unsafe integration outcomes stop the
batch. Watch the saved task list and board, or use Pause/Resume/Stop. Later imports
are excluded. For a specs project, select an existing target branch that is free
in every worktree before starting. For example, run `git branch boss-delivery` from
the desired base commit, then select `boss-delivery` at registration. See
[Autopilot](docs/AUTOPILOT.md).

A documentation project uses **Plan tasks from documentation**, which B\*SS
suggests for a repository with a `docs/` folder. Leaving the publication target
blank creates a local branch at the current commit. **Start Autopilot** runs one
read-only planning pass using your assigned **Analytic** agent (Codex, Claude
Code, Cursor Agent or OpenCode): at most three attempts under one 20-minute
deadline. It saves up to 32 tasks in dependency order, then dispatches the first
eligible task. Original Markdown stays on disk. Later starts continue the
remaining eligible cards and do not call the planner again. The same check,
independent review and exact-commit publication gates still decide Done.

Each managed workflow pins its **Implementer**, **Analytic** and **Reviewer**
agents at admission from your saved roles (preferring a distinct Analytic agent
for stuck-question resolution when available). When a pinned role uses Codex,
B\*SS reads and validates the installed Codex CLI's model catalog before the
first stage: planning and ordinary implementation prefer Sol, an explicitly
small first implementation prefers Luna, and a second opinion prefers Astra or
Terra at extra-high reasoning (or the 5.6 equivalents when only 5.6 is
advertised; at least two distinct strong models are required). Non-Codex
runners (`Claude Code`, `Cursor Agent`, `OpenCode`) use the model and reasoning
effort selected on the **Agents** screen (`Cursor Agent` defaults to `--model
auto` and falls back once to `auto` if a requested model is unavailable on the
active tier). Catalog presence is metadata, not proof an account can call a
model. See [autonomous delivery](docs/AUTONOMY.md).

The saved check runs from a fresh candidate worktree. If dependencies are required,
point the check at a trusted, committed script that installs the locked dependencies
and runs the checks. A bare `mix test` assumes its dependencies are already available.
Include appropriate generated-artifact ignore rules before verification.
Tests must preserve source and test files;
exit 0 alone cannot approve a changed candidate. See
[check integrity and recovery](docs/MANAGED_DELIVERIES.md).

Open a task, enter a trusted **Workflow check command**, select a reviewer, then choose **Start
workflow**. B\*SS saves a plan, implements in an isolated worktree, checks the
snapshot and requests a fresh review. Failed checks or requested changes can
trigger model-assisted fixes, up to five implementation cycles on new starts.
Your assigned **Implementer** plans, implements and fixes, **Analytic** diagnoses
questions and failed checks/reviews, and the selected **Reviewer** (`Codex`,
`Claude Code`, `Cursor Agent` or `OpenCode`) assesses the candidate
independently. Claude review assesses supplied evidence without model
filesystem/shell tools. Your selected local CLI accounts
may incur charges for multiple runs. Closing the browser keeps the workflow running.
See [Claude review and its limits](docs/CLAUDE_REVIEW.md).

Choose **Queue workflow** to save the command and reviewer while waiting for
capacity or Done prerequisites. **Workflow capacity** sets the global limit to 1–3
(default 2). Workflows use separate worktrees and wait before implementation when
their saved predicted file scopes overlap. **Cancel queue** withdraws an unstarted request; pending work
pauses on restart and needs **Resume**. Source adoption remains explicit. Unknown
scope predictions show a conflict warning; predictions cannot guarantee safe merges.
See [queue behavior](docs/WORKFLOW_QUEUE.md).

With manual Start/Queue, an approved result waits for **Integrate approved result**. The target branch must
not be checked out by you. If it advanced, B\*SS creates a merge candidate and runs
the saved checks and a fresh selected review before publication. The original
approval stays in history. An unchanged target fast-forwards to its approved commit.
Integrating an advanced target makes another reviewer call and may incur charges.
B\*SS publishes only the validated commit, reruns checks, retains its checkout and
frees the branch before **Done**. Under autonomy policy 1, a merge conflict,
rejected merge review, single target advance during review or first failed
postcheck enters bounded diagnosis and fresh descendant verification before
moving the branch; rewritten history, a second target drift or a second failed
postcheck stops the attempt. Published commits are never rolled back, and B\*SS
never resets your checkout. Current execution: macOS, up to three managed workflows
and exclusive integration. See
[managed delivery behavior and limits](docs/MANAGED_DELIVERIES.md).

## Run Codex manually on a task

Open a project, open a task card, then choose **Start Codex**. Install and sign in
through the official Codex CLI first; B\*SS uses the `codex` on its own PATH.
Starting an actual run uses your local account and may incur provider charges.
B\*SS runs the task's pinned revision even when another source revision is selected.

Manual execution remains exclusive with managed workflows and integration.
Each attempt gets a fresh `codex/boss-run-…` branch and worktree under the B\*SS
data directory. Closing the drawer, reloading or closing
the browser does not stop the attempt. **Stop** cancels the owned process group
and retains files. The drawer shows the last ten attempts, retained paths, event
types and reported token counts; it does not retain private model/tool transcripts.
**Codex finished — unverified** requires review and checks; it never makes a task
Done or merges changes into your source checkout.

After confirmed cleanup, **Start Codex** creates another fresh attempt. A backend
interruption or unknown cleanup blocks new attempts conservatively; there is no
automatic retry, PID-based recovery or force-unblock UI. Runs currently require
macOS. See [manual run behavior and limits](docs/MANUAL_RUNS.md).

## Check a Codex result

On a finished Codex attempt, enter a **Check command** and select **Snapshot and
run checks**. B\*SS captures current changes without altering the original run,
then executes the explicitly entered command in a separate retained worktree.
The receipt shows its candidate commit, arguments and exit status. Exit 0 with
modified files or a moved HEAD fails verification. **Checks passed — review
required** applies only to that snapshot and does not make a task Done.

Commands run with your local account's access, without implicit shell expansion.
Use trusted project commands; setup/dependencies must be handled by the command.
Stop and restart quarantine apply to both Codex and checks. See
[check behavior, limits and verification](docs/MANUAL_CHECKS.md).

## Review a checked result

After a passed check, choose **Review with Codex**. A separate read-only session
reviews that exact snapshot against its saved specification and full diff. The
drawer shows a structured **Model assessment**, acceptance evidence and issues.
Review has the same Stop/history/restart guarantees and uses your Codex account.

The report is advisory: it does not move the task, merge changes or mark Done.
Refined plans, raw test output and automatic fix loops are not yet part of this
manual flow. See [review inputs, validation and limits](docs/MANUAL_REVIEWS.md).

## Detect agents and assign roles

Open **Agents** from Projects, then click **Detect agents**. B\*SS checks Codex,
Claude Code, Cursor Agent (`agent` or `cursor-agent`), Hermes, Pi and OpenCode
on its own PATH and persists sanitized versions, local sign-in status,
capabilities and visible model/reasoning catalogs in SQLite. Reloading the page
retains the saved inventory. On macOS, **Open login in Terminal** launches the
CLI's interactive sign-in in your Terminal, and **Verify & fetch models**
refreshes status and model choices without running paid inference.

Open **Reviewer**, **Implementer**, **Analytic** or **Create role** to assign
detected and authorized agents, select a catalog model and (where supported)
choose a reasoning effort. Managed workflows and Autopilot support **Codex**,
**Claude Code**, **Cursor Agent** and **OpenCode** across planning,
implementation, diagnosis, documentation intake and independent review; Hermes
and Pi are stored as roster entries. A sign-in report or model catalog entry is
local CLI metadata, not proof of provider quota or entitlement.

Probes run outside registered projects with fixed commands, bounded time/output,
one scan at a time and cleanup of the tracked direct child. B\*SS never reads
credential files or displays raw CLI output. See
[agent discovery and roles](docs/AGENT_DETECTION.md).

## Data and ownership

For a local build and foreground launch, run `./bin/build` in your terminal. It uses port 4001
and the checkout's `_build/local-data` by default. Use an absolute data directory
outside `_build` for data you want to keep across build cleanup.

```sh
PORT=4010 BOSS_DATA_DIR=/absolute/private/boss-data ./bin/build
```

Direct Mix launches default to `~/.boss/boss.db` and support the same overrides.

```sh
rtk proxy env BOSS_DATA_DIR=/absolute/path/to/boss-data PORT=4001 mix phx.server
```

The directory is private to the user (mode 0700). SQLite runs with foreign keys,
WAL, full synchronization, two pool connections (required by Ecto migrations) and
a five-second busy timeout.
Migrations run on application startup, after obtaining ownership. A dedicated
`.owner.sqlite3` transaction permits one B\*SS instance per directory. The lock
is held in application callback state until all supervised children stop. A second
instance fails explicitly; stopping the process releases the OS-held lock.
There is no stale-PID signalling or lock-file deletion. Do not remove the lock
file or run separate `mix ecto.*` commands against a running instance. Use a local
filesystem, since network filesystems may not honor SQLite locking correctly.

The HTTP server always binds to `127.0.0.1`. Only `127.0.0.1` and `localhost` hosts
and exact same-port origins are accepted. Both HTTP and LiveView mounts require
the session; WebSocket origins are checked. This is a single-user local app, not
a network service or a sandbox for future agent processes.

## Verify

```sh
rtk proxy mix test
rtk proxy mix compile --warnings-as-errors
rtk proxy mix format --check-formatted
rtk proxy mix assets.build
rtk proxy mix assets.deploy
```

Tests ignore `BOSS_DATA_DIR`, exclusively create a random temporary data directory
and delete only that directory after stopping the test application. No existing
`~/.boss` data is used by tests. `mix test` does not call a live provider. The
release guide records one earlier opt-in Codex smoke of a single tiny task. It
does not establish acceptance for the current beta, Claude, or arbitrary work.
Folder-picker process tests use Python 3 fixtures; they do not open desktop dialogs.
Linux/Zenity GUI behavior has not yet been verified on a Linux desktop.

See [tasks/plan.md](tasks/plan.md), [tasks/todo.md](tasks/todo.md) and
[.worklog/](.worklog/) for scope, evidence and the next increment.

## License

B\*SS is licensed under the [Apache License, Version 2.0](LICENSE).
Third-party components retain their own licenses and notices, included in the
release archive's `LICENSES/` directory. Reference repositories in `examples/`
remain separately licensed research inputs.
