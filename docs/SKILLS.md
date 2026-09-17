# Repository Skill Registry

Skills under `.agents/skills/` are concise execution guides for humans and compatible agents. They do not replace task requirements, architecture decisions, or security policy.

Before unfamiliar implementation work, also follow `docs/REFERENCE_CODING.md`. It is a repository-wide evidence workflow rather than a role-specific skill: retrieve from the project and pinned peer indices, cite `path:line`, check the pinned license, and record the adaptation in the task worklog.

| Skill | Use when |
| --- | --- |
| `cuckoding-architecture` | Changing component boundaries, state ownership, or extension contracts |
| `elixir-phoenix-liveview` | Building domain, OTP, Ecto, PubSub, or LiveView behavior |
| `menubar-shell` | Packaging, starting, authenticating, or stopping the release from the shell |
| `local-runner` | Worktrees, process groups, ports, confinement, hibernate/resume, power handling |
| `agent-adapter` | Adding or changing a coding-agent runtime integration |
| `workflow-and-kanban` | Editing state machines, boards, scheduling, gates, or UI transitions |
| `observability` | Adding events, metrics, costs, resource sampling, or dashboards |
| `knowledge-compression` | Extraction, consolidation, publication, injection, usage tracking |
| `plugin-system` | Adding or changing any connector kind or reference plugin |
| `rtk-optimization` | Working on the RTK plugin |
| `ponytail-minimalism` | Every repository change or review, and work on the Ponytail plugin |
| `security-review` | Touching execution, credentials, paths, processes, network, updates, plugins, or publication |
| `quality-gates` | Defining or running verification and release evidence |

## Skill selection

Every repository change or review uses Ponytail in full mode by default, and every shell command uses RTK. Add only the other skills relevant to the task. Security review and quality gates are additive and cannot be disabled by minimalism. If a skill conflicts with `AGENTS.md`, architecture decisions, or the assigned task, follow the higher-level repository rule and record the conflict.

## Skill lifecycle

Keep each skill focused and version substantive changes through Git. Add evidence and review ownership before publishing a compressed skill globally. Test instructions on a representative task. Revoke or supersede stale skills rather than silently rewriting historical artifacts. Revalidate external commands and links before each release.
