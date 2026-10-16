# Engineering skills

RTK and Ponytail full are mandatory contributor defaults. RTK 0.49.0 and the
installed Ponytail 4.13.0 (MIT) were read/checked for R001; this does not establish
a future packaged tool version. No extra plugin was needed for this reset.

Load only relevant repository skills under [the skill directory](../.agents/skills):

| Work | Skill |
| --- | --- |
| Every change/review | ponytail-minimalism |
| Before task completion | quality-gates |
| Workflow, roles, Tabula and battles | workflow-and-kanban |
| Architecture/state ownership | cuckoding-architecture |
| Elixir/LiveView/UI | elixir-phoenix-liveview |
| Processes, worktrees, ports and sleep | local-runner |
| Runtime authorization/models | agent-adapter |
| Execution/path/credential/network boundaries | security-review |
| Native packaging/tray | menubar-shell |
| Public activity and measured usage | observability |
| RTK integration | rtk-optimization |

Plugin-system and knowledge-compression remain guidance for explicitly deferred
work; their presence does not add features to the rebuild. Use the existing
skills before installing anything. Any future dependency must solve a demonstrated
gap, have a checked source/license and respect the user's grants.

Managed agent roles receive versioned Ponytail full instructions and RTK shell
guidance in attempt-owned configuration. Neither instruction text nor a skill
grants host access. See [execution](EXECUTION_ENVIRONMENTS.md).

## Installed Addy Osmani skills (R080f)

The user-requested [agent-skills](https://github.com/addyosmani/agent-skills)
collection is installed locally: all 25 skills, pinned to
`aeac41d4d005999432bb7312f7ff06383a91d59d` (MIT), with all seven original shared
references. Skills live under `~/.codex/skills/`; references retain their upstream
relative layout at `~/.codex/references/`. Source, hashes and license are retained
in `~/.codex/skills/.sources/addyosmani-agent-skills/`. Discovery applies from the
next Codex turn; direct skill reads guided this change.

For UI/flow changes, use **frontend-ui-engineering** for hierarchy, responsive
states and keyboard behavior; **code-simplification** for fewer user decisions
without removing domain gates; **incremental-implementation** for verified slices.
Load other skills only when relevant. Repository LiveView/HEEx, forward-only
migration, scoped consent and verification rules take precedence over generic
framework or workflow examples. Installation does not add app dependencies,
provider tools, managed-agent prompts or execution permissions.
