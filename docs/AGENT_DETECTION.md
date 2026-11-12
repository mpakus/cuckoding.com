# Agent discovery and roles

**Detect agents** checks Codex, Cursor Agent, Claude Code, Pi, Hermes and
OpenCode on the running BOSS process's PATH. If you install a CLI or change
PATH in another shell, restart BOSS from that environment. Cursor Agent uses
`agent` or its compatibility alias `cursor-agent`.

On macOS, **Open login in Terminal** starts the CLI's interactive sign-in.
Complete sign-in in that Terminal or its browser flow, then choose
**Verify & fetch models**. On Linux, run the command shown on the agent card
in your terminal and choose **Verify & fetch models** when it finishes.

| Agent | Sign-in | Model choices |
| --- | --- | --- |
| [Codex](https://developers.openai.com/codex/cli/) | `codex login` | Models visible in the local CLI catalog and advertised reasoning levels |
| [Cursor Agent](https://cursor.com/docs/cli/overview) | `agent login` | CLI-listed IDs, including any effort variants as separate models |
| [Claude Code](https://code.claude.com/docs/en/setup) | `claude auth login` | Supported aliases and reference model IDs, with known efforts gated by CLI help |
| [Pi](https://pi.dev/docs/latest/cli) | Run `pi`, then `/login` | Provider/model IDs in the local offline model list with extensions disabled |
| [Hermes](https://hermes-agent.nousresearch.com/docs/getting-started/installation) | `hermes model` | Configured model when short status reports its provider as connected |
| [OpenCode](https://opencode.ai/docs/cli/) | `opencode auth login` | Models from configured providers visible in the local CLI catalog |

Sign-in and model choices describe local CLI evidence. Provider acceptance,
account entitlements and quota require a separate live check. Pricing shown is
catalog or reference pricing. When an installed CLI has no supported evidence,
BOSS displays the incomplete check or unknown sign-in state.

## Assign a role model

Use **Create role** for a custom role or open Reviewer, Implementer or Analytic.
Check an available agent, choose a model and, where the selected model offers
one, choose a reasoning effort. Each change saves that agent's binding. Choosing
a different model resets its effort to the model default. An unavailable
binding stays saved and can be removed directly. If a model disappears from the
catalog, its saved ID remains visible until you choose a replacement.

The roster stores selections for all six agents. Managed execution currently
supports Codex, Claude Code and Cursor Agent. Codex uses its saved workflow
routing policy. Custom roles and Pi, Hermes and OpenCode bindings are roster
entries. A new workflow selects its Implementer and Analytic from supported
assigned agents and prefers a distinct Analytic when available.

## Probe boundary

BOSS runs fixed metadata commands from exclusively created scratch directories
outside projects. It persists normalized status, capabilities, model metadata
and fixed error codes in SQLite. BOSS runs no inference during detection and
retains no raw probe output, auth files, credentials or Terminal I/O. Sign-in
opens only after an explicit action. Project-specific provider settings can
differ from the local probe.

The supervised detector handles one version/help/status scan at a time. Each
command has a five-second deadline and a 64 KiB retained-output limit. The
scan has a 30-second deadline and monitors its requester. On cancellation or
failure it cleans up its tracked direct child. Catalog probes use the native
runner with separate per-command time and output bounds. Catalog results are
saved with their observation start so an earlier scan finishing late cannot
overwrite newer evidence. A transient catalog failure can retain the previous
catalog for the same recognized executable and version.

See the [verification worklog](../.worklog/2026-11-11.md).
