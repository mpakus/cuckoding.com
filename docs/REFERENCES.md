# External References

Reviewed on 2026-09-16. External behavior, commands, licensing, and product terms may change; implementation tasks must pin and revalidate supported versions.

## Desktop shell and Elixir packaging

- Tauri 2 tray icon and macOS activation policy: https://v2.tauri.app/
- elixir-desktop: https://github.com/elixir-desktop/desktop
- Burrito: https://github.com/burrito-elixir/burrito
- Elixir releases: https://hexdocs.pm/mix/Mix.Tasks.Release.html
- Phoenix LiveView: https://hexdocs.pm/phoenix_live_view/
- Ecto SQLite3 adapter: https://hexdocs.pm/ecto_sqlite3/
- Apple notarization and hardened runtime: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

## Execution and source control

- Git worktree: https://git-scm.com/docs/git-worktree
- macOS `caffeinate` and `pmset` man pages; IOKit power assertions
- GitHub Apps: https://docs.github.com/en/apps

## Agent runtimes

- Claude Code: https://docs.anthropic.com/en/docs/claude-code/overview and memory docs https://code.claude.com/docs/en/memory
- OpenAI Codex: https://developers.openai.com/codex/
- Cursor CLI: https://docs.cursor.com/en/cli/overview
- OpenCode: https://opencode.ai/docs/
- Agent Skills specification: https://agentskills.io/
- Model Context Protocol: https://modelcontextprotocol.io/

## Knowledge and memory landscape

- Claude Code auto memory and consolidation (see memory docs above)
- Mem0: https://github.com/mem0ai/mem0
- Graphiti: https://github.com/getzep/graphiti
- Letta: https://github.com/letta-ai/letta
- cognee: https://github.com/topoteretes/cognee
- XERJ: https://xerj.org/
- XERJ agent documentation: https://xerj.org/llms.txt
- RTK: https://github.com/rtk-ai/rtk
- Ponytail: https://github.com/DietrichGebert/ponytail

## Reference-coding corpus

Pinned revisions and license evidence are recorded in `docs/reference-corpus.yml`; the retrieval workflow is in `docs/REFERENCE_CODING.md`.

- Agetor: https://github.com/alamops/agetor — local loopback control plane, SQLite tasks, host agent processes, and worktrees.
- Vibe Kanban: https://github.com/BloopAI/vibe-kanban — Rust worktree lifecycle, task execution, executor adapters, and desktop control-plane patterns.
- Hydra: https://github.com/jpdlr/hydra — cross-provider desktop sessions, provider-session resume, MCP integration, and usage accounting.

## Observability and security

- OpenTelemetry: https://opentelemetry.io/docs/specs/
- OWASP Desktop App Security Top 10: https://owasp.org/www-project-desktop-app-security-top-10/
- OWASP LLM Top 10: https://owasp.org/www-project-top-10-for-large-language-model-applications/
