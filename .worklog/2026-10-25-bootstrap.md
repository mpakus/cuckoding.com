# 2026-10-25 — Phoenix / SQLite foundation

## Scope and baseline

- Isolated `codex/boss-phoenix-base` worktree, starting from documentation-only main.
- BOSS-001a/b only: minimal local server, durable SQLite directory ownership, local browser authentication. No project/task schemas or fake orchestration UI.
- Skills: Ponytail, TDD, source-driven-development, git-workflow-and-versioning.
- Generator: Phoenix 1.8.13; installed Elixir 1.20.3 built for OTP 28; runtime OTP 28. Generator ran into `/tmp/boss-phoenix-generated`, then copied app files while preserving existing `.gitignore` and AGENTS.

## Source research

- xerj `localhost token origin` was weak; `validateToken` missed; fallback `rg` found Agetor auth. `tokenMatches` found `agetor/src/bun/server.ts:425`. Read `server.ts:400–442` and `server-auth.test.ts` at pinned `fbd68603afef778a618a94ca88e0c00997956afd` (MIT). Adopt per-launch random authentication and constant-time compare; reject long-lived query-string tokens and broad CORS origins. No code copied.
- Official Phoenix 1.8.13 Endpoint docs: https://phoenix.hexdocs.pm/1.8.13/Phoenix.Endpoint.html — runtime configuration, loopback binding and origin checks.
- Official LiveView security model: https://phoenix-live-view.hexdocs.pm/security-model.html — authenticate HTTP and live mount.
- Official Plug CSRF: https://plug.hexdocs.pm/Plug.CSRFProtection.html — POST session exchange protected; rotate CSRF after sign-in.
- Official SQLite adapter: https://ecto-sqlite3.hexdocs.pm/Ecto.Adapters.SQLite3.html — WAL, foreign keys, busy timeout and Exqlite driver.

## Decisions

- Trim generator mailer/dashboard/gettext, DNS cluster, DaisyUI/Heroicons and promotional page. Keep Phoenix LiveView, Tailwind, Ecto SQLite and standard local telemetry only.
- Bootstrap token is typed into a CSRF-protected POST form; never in URLs. Cookie authorizes reopen in the same browser while the backend runs. Restart requires a fresh terminal token.
- Owner lock uses a dedicated SQLite exclusive transaction, not PID signalling or stale-file deletion. Tests and smoke use disposable data directories.

## Verification in progress

- No acceptance claim yet; focused behavior tests precede custom implementation.

## Implemented and verified

- App versions locked: Phoenix 1.8.16, LiveView 1.2.13, Ecto SQLite3 0.26.0,
  Exqlite 0.43.0; Elixir 1.20.3/OTP 28 used via explicit PATH prefix.
- Custom modules: DataDirectory, LocalAccess, LocalSession and AccessController
  (with its HTML component), plus the minimal HomeLive. No project/task schema.
- Owner lock is acquired before Repo/migrations; `rest_for_one` stops later
  children if ownership is lost. DB uses WAL, foreign keys, full synchronization,
  pool size 1 and busy timeout 5000ms. Exqlite ownership uses `BEGIN EXCLUSIVE` on
  its separate lock file and a zero lock wait; no PID recovery logic.
- Test runtime creates a cryptographically random directory with exclusive
  `File.mkdir!`; test cleanup stops BOSS before deleting only that owned directory.
- Bootstrap: 10-minute single-use token, CSRF POST, signed Strict/HttpOnly session,
  port-specific Origin/Host checks, LiveView on_mount validation and WebSocket
  origin validation. Token never appears in a URL or persisted file. Local IEx
  can issue a replacement token; a full VM restart invalidates browser access.
- Source inspection found LiveView's default debug mount logger prints the raw
  session. Regression test failed with the session grant in captured output,
  then passed after disabling per-LiveView logging in BossWeb. Secret process
  state is redacted through LocalAccess.format_status/1.
- Official lock docs consulted: https://exqlite.hexdocs.pm/Exqlite.Sqlite3.html
  and https://www.sqlite.org/lang_transaction.html. Runtime server detection uses
  the public Phoenix.Endpoint.server?/2 API (plain config misses mix phx.server).

### Commands and results

All shell commands used RTK. Commands needing the matched toolchain used PATH
prefixed with the installed Elixir 1.20.3-otp-28 bin and the existing Volta bin.

- `mix compile --warnings-as-errors`: initial skeleton passed. A dependency
  (`phoenix_ecto`) emitted its upstream xref deprecation notice on first compile;
  the application itself compiled without warnings.
- Generated controller tests: 4 passed. Owner/token tests initially failed
  4/4 because modules did not exist; local web auth tests initially failed 7/7.
- Latest full `mix test`: 17 passed, including expected-error capture.
- Mutation experiment: removing only the HTTP session check still passed because
  LiveView on_mount provided an independent guard. Bypassing Origin/Host checks
  caused two expected security test failures; original source restored.
- Tailwind standalone 4.3.0 and 4.1.18 exited 137; `codesign --verify` reported
  invalid signatures. Replaced the Mix binary wrapper with official npm CLI
  4.3.0 and a package lock; did not bypass macOS security. `npm install` succeeded,
  `npm audit --audit-level=high` found 0 vulnerabilities, `mix assets.build` passed.
- Disposable real VM probe created a row via Boss.Repo, stopped, started another
  VM against that same directory and read exactly the original row.
- Actual server on 127.0.0.1:4317: anonymous redirect, CSRF bootstrap form,
  token exchange, cookie-backed reopen succeeded. Foreign/null/wrong-port
  Origin POSTs returned 403 without consuming the token. Actual foreign-origin
  WebSocket upgrade returned 403. A second VM against the same data directory
  failed at Boss.DataDirectory before running its supplied expression.
- HTTP request logs showed token/CSRF fields filtered. No bootstrap token or
  session grant is recorded in this journal.
- CUA could not attach a browser from the subagent (IAB unsupported for subagent,
  Chrome unavailable). Root agent will perform browser smoke after integration.
- Smoke server stopped; only its created `/tmp/boss-bootstrap-smoke.1IYiYh`
  directory was removed. Existing `~/.boss` was never opened.

## Scope limits / handoff

Browser rendering and a connected real browser WebSocket await root smoke.
Linux, network filesystems and release packaging were not tested. No provider
run or runner selection is implied by this foundation. The first skeleton commit
is 0a00e56; parent owns AGENTS/tasks/research updates, domain work and final merge.

## Integration and review corrections

- Final initial foundation checks: `mix test` 17 passed;
  `mix compile --warnings-as-errors`, `mix format --check-formatted`,
  `git diff --check` and `mix assets.deploy` passed. Auth commit: 56838a2.
- Parent's first real project migration exposed a missing guard in the empty
  skeleton: Ecto.Migrator requires two pool connections. Changed the global
  pool size from 1 to 2 (see dependency source `ecto_sql/lib/ecto/migrator.ex:400`).
  The combined application's real migration on every fresh test directory is
  the regression check; no redundant synthetic migration test was added.
- Independent runner-agent review found directory chmod occurred before lock
  acquisition. The existing lock-refusal test was strengthened to preserve the
  incumbent directory's permissions and failed as expected; chmod now occurs
  only after successfully acquiring the lock. A denied contender leaves the
  owner's directory permissions untouched.
- Added narrow ignore patterns for `phx.digest`'s generated robots outputs.
  npm/Mix build outputs remain disposable; no source specification was edited.

- Peer crash-boundary experiment exposed a deeper ownership issue: killing the
  owner GenServer could release its NIF handle while later supervised children
  were still terminating. Replaced that child with a simpler application-held
  handle: acquire before Supervisor.start_link; return `{:ok, pid, lock}`;
  release in Application.stop/1, after child teardown; close on startup failure.
  Actual Application.stop test holds a child in terminate, verifies contender
  refusal, finishes teardown, reacquires the lock and restarts the application.
  Sources: https://hexdocs.pm/elixir/1.20.3/Application.html#c:stop/1 and
  https://hexdocs.pm/ecto_sql/3.14.0/Ecto.Migrator.html.
- Parent observed two fresh Repo connections racing to set WAL before Exqlite's
  busy timeout is installed. Initialize boss.db WAL once while holding ownership,
  before starting the pool; return errors explicitly. Corrupt-database test
  preserves the file, fails startup and proves ownership can be reacquired after
  the disposable invalid file is removed.
- After lifecycle/WAL corrections: 19 tests passed. Parent owns browser-driven
  router/referrer changes; this branch does not duplicate them.
