# Cuckoding

Local-first desktop workspace for running several coding agents on one Git project. Elixir/OTP coordinates; Phoenix LiveView renders; ExTauri wraps the native window; SQLite is canonical.

HTTP binds **loopback only** (`127.0.0.1`). The UI is **dark only**.

## Run

```bash
mix setup
mix phx.server          # http://127.0.0.1:4000
mix ex_tauri.dev        # desktop window
mix check               # format, compile -Werror, test, credo, dialyzer, sobelow
```

Local macOS `.app` (this machine's OTP; unsigned):

```bash
mix cuckoding.app       # also aliased as mix desktop.app
```

Quit the running `.app` and leftover `beam.smp` before rebuild. Output: `src-tauri/target/release/bundle/macos/Cuckoding.app`.

Install provider CLIs yourself (Codex, Claude Code, Cursor `agent`, OpenCode). Extra ACP agents come from the registry. Cuckoding does not collect provider passwords.

## What is in tree

Multi-project workspace; Codex / Claude / Cursor / OpenCode adapters plus SDK JSONL and loopback remote attach; extra ACP registry agents; internal A2A Hub over MCP; worktrees; isolation templates off the Git tree; leases; user-confirmed merge queue; search/memory; roles; graphs/workflows; usage; optional Compose; file-based team sync.

`MIX_ENV=prod mix release desktop` works on OTP 28. Signed installers do not. Burrito has no OTP 28 ERTS, so `mix cuckoding.app` copies the Mix release into the Tauri `.app` instead of wrapping a Burrito binary.

## Left to do

Do these; do not invent replacements for deferred items.

| Do | Do not |
| --- | --- |
| Wrap the Mix release in ExTauri/Burrito (OTP 28 ERTS missing today) | Public A2A 1.0 gateway or LAN listeners |
| Apple signing/notarization; Linux/Windows installer smoke | Generic PTY / ANSI scraping, bundled XERJ, hosted Cuckoding account, auto-merge, or second copies of `AGENTS.md` |

Deferred by decision: Elixir MCP library, Claude Agent SDK as primary, OpenCode HTTP server.

## Docs

User manual: [`docs/USER.md`](docs/USER.md). Specs: [`docs/README.md`](docs/README.md). Agent rules: [`AGENTS.md`](AGENTS.md). Decisions: [`docs/DECISIONS.md`](docs/DECISIONS.md). Remaining phase checkboxes: [`docs/PLAN.md`](docs/PLAN.md).
