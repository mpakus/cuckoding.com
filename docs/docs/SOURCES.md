# Primary Technical Sources

These links informed the initial design. Re-check version-sensitive behavior during implementation and provider upgrades.

## ExTauri and Tauri

- ExTauri overview and installation: https://ex-tauri.build/
- ExTauri source repository: https://github.com/filipecabaco/ex_tauri
- Tauri external binaries/sidecars: https://v2.tauri.app/develop/sidecar/
- Tauri event system: https://v2.tauri.app/develop/calling-frontend/
- Tauri shell plugin: https://v2.tauri.app/plugin/shell/

## Codex

- Codex App Server: https://developers.openai.com/codex/app-server
- Codex MCP configuration: https://developers.openai.com/codex/mcp
- Codex non-interactive mode: https://developers.openai.com/codex/non-interactive-mode
- Codex CLI: https://developers.openai.com/codex/cli

The official OpenAI documentation describes App Server as the rich-client integration with authentication, conversation history, approvals, and streamed events. Its default stdio transport uses newline-delimited JSON. It also documents `codex exec --json` as a machine-readable JSONL stream suitable for non-interactive fallback workflows.

## Claude Code

- Claude Code CLI reference: https://docs.anthropic.com/en/docs/claude-code/cli-reference
- Headless/programmatic operation: https://docs.anthropic.com/en/docs/claude-code/headless
- Claude Code MCP: https://docs.anthropic.com/en/docs/claude-code/mcp
- Claude Code hooks: https://docs.anthropic.com/en/docs/claude-code/hooks

## Cursor Agent

- Cursor CLI overview: https://cursor.com/docs/cli/overview
- Cursor ACP integration: https://cursor.com/docs/cli/acp
- Cursor CLI parameters and session commands: https://cursor.com/docs/cli/reference/parameters
- Cursor headless/CI operation: https://cursor.com/docs/cli/headless
- Cursor CLI output formats: https://cursor.com/docs/cli/reference/output-format
- Cursor CLI MCP support: https://cursor.com/docs/cli/mcp
- Cursor CLI authentication: https://cursor.com/docs/cli/reference/authentication

The official Cursor ACP documentation defines `agent acp` as a custom-client interface using JSON-RPC 2.0 over newline-delimited stdio. It documents session creation/loading, streamed updates, cancellation, permission requests, MCP support, and optional `cursor/*` extension methods.

## Agent Client Protocol

- ACP introduction and architecture: https://agentclientprotocol.com/get-started/introduction
- ACP protocol documentation: https://agentclientprotocol.com/protocol/overview

ACP standardizes the client-to-coding-agent control plane. For local agents its documented transport is JSON-RPC over stdio. This is distinct from MCP, which AgentDesk uses as the agent-to-tools coordination plane.

## Agent2Agent (A2A)

- A2A 1.0 specification: https://a2a-protocol.org/latest/specification/
- A2A 1.0 release announcement: https://a2a-protocol.org/latest/announcing-1.0/
- A2A project repository: https://github.com/a2aproject/A2A
- Canonical Protocol Buffers model: https://github.com/a2aproject/A2A/blob/main/specification/a2a.proto

The reviewed A2A 1.0 specification defines independent-agent discovery through Agent Cards, asynchronous tasks, messages with structured parts, artifacts, status updates, streaming/subscriptions, version negotiation, and multiple protocol bindings. It explicitly positions A2A as complementary to MCP: MCP connects an agent to tools and data, while A2A coordinates agents as peers.

AgentDesk adopts these semantic boundaries internally but does not claim public wire compatibility in the MVP. Its internal A2A model is local, SQLite-backed, MCP-accessed, provider-neutral, and extended with durable per-recipient delivery, idempotency replay, Git handoffs, and resource leases. A future gateway may translate between A2A 1.0 and the internal domain.

## OpenCode

- OpenCode CLI, ACP, sessions, and MCP commands: https://opencode.ai/docs/cli/
- OpenCode local server API: https://opencode.ai/docs/server/
- OpenCode SDK: https://opencode.ai/docs/sdk/
- OpenCode configuration: https://opencode.ai/docs/config/
- OpenCode tools and permissions: https://opencode.ai/docs/tools/
- OpenCode source repository and MIT license: https://github.com/anomalyco/opencode

The official OpenCode CLI documentation defines `opencode acp` as an ACP server using newline-delimited JSON over stdin/stdout and exposes `--cwd` for project scoping. It separately documents a loopback OpenAPI server, session management, MCP configuration, and multiple underlying model providers.

## Git

- Git worktree documentation: https://git-scm.com/docs/git-worktree

## Elixir

- Elixir Port documentation: https://hexdocs.pm/elixir/Port.html
- Phoenix PubSub: https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html
- Elixir Registry: https://hexdocs.pm/elixir/Registry.html
- Elixir DynamicSupervisor: https://hexdocs.pm/elixir/DynamicSupervisor.html

## XERJ

- XERJ documentation: https://xerj.org/docs/
- XERJ for agents: https://xerj.org/for-agents
- Agent memory recipe: https://xerj.org/docs/recipes/agentic-memory
- Native REST API: https://xerj.org/docs/api-native
- Source repository and Apache-2.0 license: https://github.com/xerj-org/xerj

The reviewed XERJ documentation describes a single local binary, folder autoindexing, keyword/vector/hybrid search, a namespaced memory API, and an Elasticsearch-compatible surface. It also identifies the documented release as a release candidate, so AgentDesk keeps it optional and behind an adapter.

## Source policy

- Prefer official documentation and source repositories.
- Record the provider/tool version used by integration fixtures.
- Record the A2A semantic version used by gateway/mapping fixtures and never assume pre-1.0 JSON shapes.
- Generate schemas from installed tools where the official tool supports it.
- Treat undocumented protocol fields as unstable.
- Do not copy global user configuration to make an integration test pass.
