# BOSS

Local AI agent orchestration, rebuilt from [BOSS_PLAN.md](BOSS_PLAN.md).

This increment provides a Phoenix LiveView server, local browser access,
SQLite persistence and validated project registration. Spec import and agent
execution are not implemented yet.

## Run locally

Use Elixir 1.20.3 compiled for OTP 28, an OTP 28 runtime, and Node.js 20+ with npm.
`.tool-versions` pins Elixir; Erlang/OTP and Node come from your local installation.
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

Markdown files are not imported in this increment. Runner and Git research live
in `spikes/`, separately from the application. The runner experiment is not a
production adapter; its EOF, memory and descendant-cleanup gates remain open.

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
