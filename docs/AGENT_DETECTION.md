# Agent discovery

The Agents page checks the Codex, Claude Code, Cursor Agent, Hermes, Pi and
OpenCode executables visible to the running BOSS process. Detection starts only
when the user presses **Detect agents**.
Installing a CLI in another shell may require restarting BOSS to update its PATH.
This page does not start agent tasks. Saved roles record which detected
agents belong to which role. Reviewer reviews specs and code. Implementer
writes code and tests from the specs. Analytic analyzes prompts, specs, and
the project to create specs, and helps the Reviewer with questions or when
work is stuck. Those three stay in place. A role can include many agents, and
an agent can belong to many roles. A workflow still runs an agent through that
agent's existing runner.

## What a result means

- **Version:** a recognized CLI identity/version response, not just any successful
  executable. Unknown versions/output are reported explicitly.
- **Local sign-in status:** what the CLI's status command reports. Configured
  credentials do not prove provider acceptance, model access or remaining quota.
- **Capabilities:** flags or subcommands advertised by the installed CLI's help.
  These observations do not certify a BOSS adapter. Usage reporting remains
  unknown until a real adapter validates its event protocol.

The six tools are deliberately explicit. There is no plugin registry or database
agent table. Cursor Agent is the `agent` executable, or `cursor-agent` when
`agent` is not on PATH. The `cursor` editor binary is not the agent CLI.
Results belong to the current page and expire when it is reloaded.
A failed rescan keeps the earlier results with a notice that the latest scan failed.

## Probe boundary

BOSS resolves each executable once from its inherited PATH and invokes fixed argv
without a shell, in an exclusively created temporary directory outside projects.
Only version/help and advertised local authentication-status commands are used.
BOSS does not run `doctor`, installation, update, login or model commands, and does
not read credential files. The CLI itself may use its own configuration to answer
status queries. Project-specific provider settings can differ from this environment.

Raw status output can contain account information or key fragments. BOSS keeps
only normalized status/capability facts and fixed error codes, never raw probe
output in page state or persistent logs. Unexpected or conflicting output gives
Unknown, not a sign-in failure inferred from an arbitrary nonzero exit.

A single supervised detector accepts one scan at a time. Probes are sequential,
with a five-second command deadline, 64 KiB retained-output limit and 30-second
scan deadline. It monitors the requesting process. On timeout, output overflow,
caller loss or orderly shutdown it terminates its tracked direct child and closes
the port. These are metadata probes, not the production coding-run transport.
Wrappers may create descendants that escape direct-child cleanup; process-tree,
independent stream EOF and transport backpressure guarantees remain runner gates.

## Setup

Use the official setup for
[Codex](https://developers.openai.com/codex/cli/),
[Claude Code](https://code.claude.com/docs/en/setup),
[Cursor Agent](https://cursor.com/docs/cli/overview),
[Hermes](https://hermes-agent.nousresearch.com/docs/getting-started/installation),
[Pi](https://pi.dev/docs/latest/quickstart) or
[OpenCode](https://opencode.ai/docs/cli/). Sign in yourself, then detect again.
BOSS never runs those login commands on your behalf. Cursor sign-in is read only
from `agent status --format json` after that command's help advertises JSON, and
only the `isAuthenticated`/`status` pair is kept. Hermes status text, Pi's
per-provider `auth check`, and OpenCode's account list are not probed, so their
sign-in report stays unknown. Status syntax is checked against installed help and
the [Codex CLI reference](https://developers.openai.com/codex/cli/reference/),
[Claude CLI reference](https://code.claude.com/docs/en/cli-reference),
[Cursor CLI reference](https://cursor.com/docs/cli/reference/parameters) and
[Pi command line](https://pi.dev/docs/latest/cli).

## Verification

The compatibility fixtures cover Codex 0.146.0 and Claude Code 2.1.142 help/status
contracts, malformed/contradictory evidence, missing executables, timeout/output
limits, cancellation, redacted diagnostics and scratch cleanup. Other CLI formats
fail explicitly rather than inheriting capabilities from a version number.

On macOS, the real installed versions above were detected through the browser;
both CLIs reported credentials configured and five help-advertised capabilities,
with usage reporting Unknown. No model request was made. Keyboard navigation,
reload reset and 320/768/1024/1440 px layouts were checked. The application suite
passed 181 tests with one existing Linux-only skip; compile, format and assets
checks passed. Linux and wrapper descendants remain unverified; the existing
unattributed IAB MutationObserver error persists.
See [.worklog/2026-10-25-agent-detection.md](../.worklog/2026-10-25-agent-detection.md).
