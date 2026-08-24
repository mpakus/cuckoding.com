# Cuckoding user manual

Cuckoding is a local desktop workspace for running several coding agents on one Git project. Each agent gets a tab, its own worktree, and a shared coordination hub. HTTP listens on `127.0.0.1` only. The UI is dark only; there is no light theme.

OTP modules remain `AgentDesk` / `AgentDeskWeb`. You do not need those names to use the app.

## What it is not

- Not a hosted account or a cloud sync service.
- Not a public agent-to-agent gateway. Nothing listens off loopback.
- Not a replacement for Git, provider billing, or provider login.
- Not an auto-merge tool. Your primary tree changes only after you confirm a merge.
- Not a bundled copy of Codex, Claude Code, Cursor, or OpenCode. Install those CLIs yourself.

## Install and run

### Development

You need Elixir, Erlang/OTP, Git, Rust, and the Tauri platform tools. Provider CLIs are optional until you start a session.

```bash
mix setup
mix phx.server          # http://127.0.0.1:4000
mix ex_tauri.dev        # native window around the same app
```

Open `http://127.0.0.1:4000` from this machine only. Other hosts cannot reach it.

### Packaged macOS app

```bash
mix cuckoding.app
```

Then open `src-tauri/target/release/bundle/macos/Cuckoding.app`.

This copies a Mix release (this machine's OTP) into the Tauri app. It is unsigned and not notarized. Quit the running `.app` and any leftover `beam.smp` process before you rebuild, or the copy step fails.

`mix desktop.app` is an alias for the same task.

## Open a Git project

1. Choose folder… uses the native macOS picker. Recent projects reopen a folder you opened before; Check again re-validates that path.
2. Cuckoding never initializes a repository. Open an existing Git repo.
3. The project appears under Recent projects. A live badge means its runtime is running.
4. First run walks ten onboarding steps: Git health, detected CLIs, roles, internal A2A, isolation, optional search, then the first session.

Coordination state lives in local SQLite under Application Support (`AgentDesk`), not in the repo.

## Start and stop sessions

Pick `+` for a new agent. Each agent is its own tab (name and a status dot; close stays inside the tab). Duplicate names get a short id so two sessions stay distinct. Clicking an agent in the sidebar or an Agent Card opens that tab. Optional Role & isolation lets you attach a saved role, opt into isolated Compose, or (experimental) share the primary tree.

The **Dashboard** tab (first in the strip) shows BEAM memory, SQLite size and row counts, search/XERJ health, remembered notes, and token/cost usage. It does not replace agent tabs.

Default providers:

| Label | CLI you install | How Cuckoding talks to it |
| --- | --- | --- |
| Codex | `codex` | `codex app-server` |
| Claude | `claude` | stream-json headless |
| Cursor | `agent` | `agent acp` |
| OpenCode | `opencode` | `opencode acp --cwd <worktree>` |
| SDK | your executable | JSONL `op` / `type` |
| Remote | your process | inbound loopback MCP; no child process |

ACP Registry can install extra agents. Mapped Codex, Claude, Cursor, and OpenCode ids use the first-class adapters. Other registry agents use generic ACP. Remove disables the agent in Cuckoding; it does not uninstall the vendor CLI.

Sign in with the vendor CLI. Cuckoding never stores provider passwords or tokens in SQLite.

### Session status

| Status | Meaning | Typical next step |
| --- | --- | --- |
| `queued` | Waiting to start | Cancel |
| `starting` | Handshake in progress | Wait, or Cancel |
| `idle` | Ready for a prompt | Send, Terminate |
| `working` | Generating or editing | Interrupt; Steer if the provider supports it |
| `waiting` | Needs input | Send, Interrupt |
| `blocked` | Lease conflict or similar | Resolve in the context panel |
| `completed` | Turn finished | Review handoff, Continue |
| `failed` | Provider error | Diagnostics, Retry |
| `interrupted` | Stopped mid-turn | Resume if supported, Terminate |
| `terminating` | Shutting down | Wait; Force terminate if it hangs |
| `terminated` | Gone | Start a new session |

Color is never the only cue. Each status uses a labeled chip.

Terminate asks for confirmation. Force terminate appears if the process hangs.

## Worktrees, isolation, and leases

By default each session gets a linked Git worktree and a branch named `agentdesk/<session-id>` under app-owned storage. Isolated mode must not edit your primary checkout. Shared primary tree is experimental and opt-in.

Isolation templates (database name, schema, ExUnit partition, Compose project, loopback bind, optional port) live in the app-owned session directory. They are never written into the Git worktree. The context panel Isolation card shows those names. Copy the `env` file from that directory when you need the same values in a shell.

Leases are time-limited claims on files, directories, globs, databases, ports, and similar resources. A lease is not a Git lock. Search, `status.md`, and live updates are not proof of ownership. When two agents overlap, the UI shows the owner and expiry. There is no silent takeover. Administrative revoke requires confirmation.

Optional Compose runs only on the session worktree. Stacks that bind `0.0.0.0`, use host networking, or request privileged mode are rejected.

## Approvals, handoffs, and merge

Risky provider actions become approval cards. Grant only what the card asks for. Cuckoding does not widen permissions on your behalf.

When an agent publishes a handoff, it lands on the merge queue. Review shows summary, base and head commits, changed files, checks, warnings, artifacts, and held leases.

- Accept records review. It does not run Git.
- Reject drops the item from the open queue.
- Merge is a second, confirmed click. It runs only when the handoff is accepted, required checks passed, your primary checkout is clean and on the target branch, and `git merge-tree` reports no conflict.
- Failed required checks keep Merge disabled.

Cuckoding never auto-merges into the primary tree.

## Agents talking to each other

Every first-class session registers a project-scoped Agent Card: name, skills, availability, load. Cards never include secrets, hidden prompts, or unrestricted paths.

Agents reach the hub through local MCP. They do not open sockets to one another and do not query SQLite. That hub is internal A2A: discovery, delegation, messages, artifacts, leases. It is not a public A2A 1.0 server.

- Delegation is a proposal until Accept. Assignment is not a lease.
- A lead crew is the exception for specialists you started for that goal: Split work records delegations and accepts them so the lanes can start. You can still revoke.
- Ack means the message was delivered, not that the work is done.
- Filter Agent Cards by skill or feature. Each card shows a load summary (status and assigned tasks).

**Split work** (Tasks panel): describe a goal, pick a lead session, optionally pick a provider, and choose backend / UI / tests. The Tasks list groups that crew under the parent and shows how many lanes are done. The lead analyzes, specialists work in isolated trees, and the lead is notified when a lane finishes. SQLite keeps the tasks, messages, and memory. Nothing auto-merges to your primary branch.

Remote attach writes a connect file under the session directory. The UI shows that path, never the raw token.

## Search, activity, grove, onboarding, shortcuts

**Search** groups code, docs, decisions, handoffs, agent history, and memory. XERJ is optional. If the binary is missing, a SQLite projection still searches. Missing search never hides tasks, leases, or Git state.

**Activity** defaults to structured cards (messages, commands, file changes, MCP tools, approvals, errors). Streamed agent tokens are grouped into one card per message so the feed reads as paragraphs, not one card per word. Switch to raw only for diagnostics. Older items load on demand. The stream is bounded.

**Composer** accepts pasted or dropped images and attached files. Meta+Enter still sends.

**Grove** is a small living canvas in the context panel. It grows while sessions are working and rests when they are idle.

**Onboarding** is the ten-step first-run panel in the sidebar. Continue through it, or skip ahead by opening a project and starting a session.

**Shortcuts** (macOS Command = Meta), editable under Settings · shortcuts:

| Action | Default |
| --- | --- |
| Send prompt | Meta+Enter |
| Interrupt | Meta+. |
| New session | Meta+Shift+Enter |
| Next tab | Meta+Shift+] |
| Previous tab | Meta+Shift+[ |
| Focus composer | Meta+L |
| Search | Meta+K |
| Load older activity | Meta+[ |

## Provider CLIs

Install and authenticate these yourself. Cuckoding discovers them on `PATH` (including Homebrew and common user bin dirs when launched from Finder).

- Codex CLI (`codex`)
- Claude Code (`claude`)
- Cursor CLI (`agent`)
- OpenCode (`opencode`)
- Optional XERJ binary for richer search
- Extra ACP agents from the registry (often via `npx`)

A missing CLI is listed as missing. It is not an error until you try to start that provider.

## Troubleshooting

**Cannot open from another computer.** HTTP binds `127.0.0.1` only. Use this machine.

**Rebuild failed or the app will not start after `mix cuckoding.app`.** Quit Cuckoding.app. Check Activity Monitor for leftover `beam.smp` and quit it, then rebuild.

**Provider shows missing.** Install the CLI, confirm it is on `PATH`, and sign in with the vendor tool. Restart Cuckoding after installing.

**Session stays on starting (Claude).** Claude's stream-json adapter waits for a user turn before it finishes handshake. Send a prompt, or Terminate and try again.

**Merge is disabled.** Accept the handoff first. Fix failing required checks. Commit or stash unrelated changes on the primary tree. Check out the target branch. Resolve `merge-tree` conflicts.

**Lease conflict.** Use Message owner, Wait and retry, or Reassign. Do not force a takeover.

**Search empty or stale.** Enable XERJ in onboarding if you have the binary, or use the projection adapter. Coordination still works while search is unavailable.

**UI is always dark.** That is intentional. There is no theme switch.

**Need the quality gate as a developer.** `mix check` runs format, compile with warnings as errors, tests, Credo, Dialyzer, and Sobelow. Live CLI protocol tests skip when a binary is missing and never send a paid prompt.

## More documentation

Product specs live under [`docs/README.md`](README.md). Agent working rules: [`AGENTS.md`](../AGENTS.md). Architecture decisions: [`DECISIONS.md`](DECISIONS.md).
