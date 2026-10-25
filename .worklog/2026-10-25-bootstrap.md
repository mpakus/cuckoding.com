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
