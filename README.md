# BOSS

Local AI agent orchestration, rebuilt from [BOSS_PLAN.md](BOSS_PLAN.md).

This increment provides a Phoenix LiveView server, local browser access,
native folder selection, validated project registration, automatic Markdown sync,
transactional spec/revision/task history and versioned task commands with immutable
receipts, a Kanban board, a revision-aware task drawer, local CLI discovery and
manual Codex attempts, explicit commit-bound checks and fresh read-only Codex review
in retained Git worktrees on macOS.

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
cookie. Reopening the same browser works while the backend remains running;
closing a tab does not stop BOSS. A server restart creates fresh signing/session
secrets and requires another terminal token. Tokens and session grants stay in
memory; LiveView session logging is disabled.

For a replacement token without stopping an IEx server, run
`Boss.LocalAccess.new_token()` in that server's local console. This invalidates
any unused token and keeps existing browser sessions valid. Start an IEx server
with `rtk proxy iex -S mix phx.server` when you need this capability.

## Register a project

After connecting the browser, click **Choose repository…** and select a folder in
the operating system dialog. Paths are read-only in the browser. The specs folder
defaults to `specs` inside that repository; use **Choose specs folder…** to change
it. Both folders must already exist. BOSS accepts a local Git working tree
with at least one commit; the optional base branch defaults to its current branch.
The base must be an existing local branch. A detached checkout needs an explicit
base branch. The optional project name defaults to the folder name.

The dialog opens on the computer running BOSS: macOS uses its built-in folder
chooser; Linux requires a graphical desktop session and `zenity` on PATH.
A graphical desktop session is required; an unavailable picker reports an error.
Only one dialog can be open at a time. Cancel keeps the form unchanged; a dialog
times out after two minutes. Closing its requesting browser session or stopping
BOSS terminates the owned picker helper. Selected paths stay in the LiveView
process and are validated again before registration.

BOSS stores canonical paths in its own database without editing the repository.
The specs directory must be strictly inside the repository, with no symlink
components. Registering the same repository through another path or linked
worktree returns an error. Projects survive tab closure and backend restart.

Runner and Git research live in `spikes/`, separately from the application.
The [transport experiment](spikes/transport/README.md) evaluates demand-driven
stdout/stderr, genuine EOF and bounded reader state with local fixtures. It is
separate from the macOS native process-group owner used by manual task runs.
Its fixture results do not certify other adapters or detached process trees.

## Sync specs

BOSS reads registered projects' `.md` files automatically, including subfolders.
Open a project to see imported tasks, the latest source revision and pinned task
snapshot; **Sync specs** checks immediately. Source Markdown is stored exactly
and is never rewritten.

One background sweep starts with BOSS and processes projects sequentially. The
next sweep starts two seconds after the previous one finishes; new projects join
that sweep. Changed files are read again after 300 ms and must have the same
identity/path/source before import. A changing or invalid scan keeps the previous
snapshot and is retried on the next sweep. This coalesces short save bursts; it
cannot observe every intermediate edit or guarantee an atomic filesystem snapshot.

Set `config :boss, spec_poll_interval_ms: 2000` to change the gap between sweeps,
or `spec_auto_sync: false` to use manual Sync only. Restart BOSS after changing
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
`priority` and `depends_on` are retained in the source only, with no workflow effect.

Identity is scoped to the project: an explicit ID survives moves; without an ID,
a renamed file creates a new task and the old identity becomes **File missing**.
Deleting a file retains its task and all revisions. Reusing a missing path for a
new explicit ID creates a separate history. Duplicate IDs abort the entire scan.
Moving an explicit-ID file records a revision even when its text is unchanged,
so the historical source path remains accurate.

Each spec has one task, initially `new`, pinned to its first revision and title.
Later source changes never advance that pin. Repeating the latest text/path is
a no-op; A→B→A creates three revisions. Revision adoption remains future work.
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
runs/checks/reviews, saved evidence and Stop. Revision adoption remains future work. Full state mapping
and the read API are documented
in [TASK_WORKFLOW.md](docs/TASK_WORKFLOW.md).

## Complete a task with Codex

Open a task, enter a trusted **Workflow check command**, then choose **Start
workflow**. BOSS saves a plan, implements in an isolated worktree, checks the
snapshot and requests a fresh review. Failed checks or requested changes can
trigger fixes, up to three cycles. This uses your Codex account and may incur
charges for multiple runs. Closing the browser keeps the workflow running.

An approved result waits for **Integrate approved result**. The target branch
must be unchanged and not checked out by you. BOSS publishes the exact reviewed
commit, reruns the checks, retains its checkout and frees the branch. Only then
does the task move to **Done**. Failed postchecks retain the published result for
inspection; BOSS never resets your checkout. First version: macOS, one active
workflow, fast-forward integration only. See [managed delivery behavior and
limits](docs/MANAGED_DELIVERIES.md).

## Run Codex manually on a task

Open a project, open a task card, then choose **Start Codex**. Install and sign in
through the official Codex CLI first; BOSS uses the `codex` on its own PATH.
Starting an actual run uses your local account and may incur provider charges.
BOSS runs the task's pinned revision even when another source revision is selected.

One manual attempt runs at a time. Each gets a fresh `codex/boss-run-…` branch and
worktree under the BOSS data directory. Closing the drawer, reloading or closing
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
run checks**. BOSS captures current changes without altering the original run,
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

## Detect agents

Open **Agents** from Projects, then click **Detect agents**. BOSS checks Codex and
Claude Code on its own PATH and shows recognized versions, local sign-in reports
and capabilities advertised by their help. Detection does not run a model or
change credentials. Follow the official setup/sign-in guidance if a tool is
missing or reports that it is signed out, then detect again.

A sign-in report does not verify model access or quota. Advertised flags do not
mean a BOSS execution adapter is ready. Results are temporary; reloading the page
requires another explicit scan. A failed rescan retains the previous results with
a failure notice. Role assignment remains future work; explicit Codex task runs
are available from the task drawer on macOS.

Probes run outside registered projects with fixed commands, bounded time/output,
one scan at a time and cleanup of the tracked direct child. BOSS never reads
credential files or displays raw CLI output. See
[agent discovery boundaries and verification](docs/AGENT_DETECTION.md).

## Data and ownership

Data defaults to `~/.boss/boss.db`. Override the entire data directory and/or port:

```sh
rtk proxy env BOSS_DATA_DIR=/absolute/path/to/boss-data PORT=4001 mix phx.server
```

The directory is private to the user (mode 0700). SQLite runs with foreign keys,
WAL, full synchronization, two pool connections (required by Ecto migrations) and
a five-second busy timeout.
Migrations run on application startup, after obtaining ownership. A dedicated
`.owner.sqlite3` transaction permits one BOSS instance per directory. The lock
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
`~/.boss` data is used by tests. Live provider tests will be opt-in when implemented.
Folder-picker process tests use Python 3 fixtures; they do not open desktop dialogs.
Linux/Zenity GUI behavior has not yet been verified on a Linux desktop.

See [tasks/plan.md](tasks/plan.md), [tasks/todo.md](tasks/todo.md) and
[.worklog/](.worklog/) for scope, evidence and the next increment.
