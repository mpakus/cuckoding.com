# Plugin and Connector System

## Purpose

Cuckoding's core is orchestration, durability, evidence, and knowledge. Everything that depends on a third-party tool installed on the user's machine is a plugin: detected, enabled per scope, health-checked, and replaceable. XERJ, RTK, and Ponytail are reference plugins, not core dependencies. The same mechanism carries MCP servers, container runners, metric sources, VCS hosts, and secret stores.

## Plugin kinds

| Kind | Behaviour | Examples |
| --- | --- | --- |
| `knowledge_backend` | `KnowledgeBackend`: index, search, recall, write to candidate space, health | XERJ, cognee, Graphiti-style graph stores, a vector index |
| `shell_filter` | `ShellFilter`: wrap or post-process a command's output, report reduction analytics | RTK |
| `instruction_skill` | `InstructionSkill`: a `SKILL.md`-style instruction package injected into selected roles/stages | Ponytail, any Agent Skills package |
| `mcp_server` | `McpServer`: a server definition passed to runtimes that support MCP, with a permission declaration | Filesystem, GitHub, database, browser MCP servers |
| `runner` | `RunnerBridge` | Docker, OrbStack, Colima, Apple Containers, remote workers |
| `metric_source` | `MetricCollector` | Plugin analytics importers, host sensors |
| `vcs_host` | `VcsHost` | GitHub, GitLab |
| `secret_store` | `SecretStore` | macOS Keychain (built-in), 1Password CLI |
| `notifier` | `Notifier` | macOS notifications (built-in), webhook, Slack |

## Manifest

Each plugin ships `plugin.yml`:

```yaml
schema_version: 1
key: rtk
name: RTK shell output filter
version: 0.3.0
kind: shell_filter
homepage: https://github.com/rtk-ai/rtk
license: MIT
detect:
  binaries:
    - name: rtk
      version_command: ["rtk", "--version"]
      min_version: "0.3.0"
  paths: []
  env: []
capabilities:
  - shell_filter.wrap_command
  - shell_filter.analytics
permissions:
  host_process: true          # may spawn host processes
  network: none               # none | loopback | external
  read_paths: ["${RUN_WORKTREE}"]
  write_paths: []
  secrets: []
config_schema:
  enabled_commands: {type: array, items: {type: string}}
scopes: [project, board, role, stage]
isolation_claims: []          # only runners declare these
```

## Discovery and lifecycle

1. Bundled plugins live in the release; user plugins in `~/Library/Application Support/Cuckoding/plugins/<key>/`; project plugins may be referenced from `.cuckoding/plugins.yml` but never auto-enabled.
2. On startup and on demand, the registry validates each manifest against the schema, runs `detect`, records binary versions, and stores a health status: `available`, `missing`, `version_mismatch`, `unhealthy`, `disabled`.
3. Enabling a plugin is a user action with an audit event. Enabling a project-referenced plugin shows the manifest and permissions first.
4. Scopes: global default, project, board, role, stage. A more specific scope may disable but not expand a plugin's permissions.
5. Plugin processes run under the plugin supervisor with restart limits; a crashing plugin degrades its feature and never the core.
6. Plugin updates change the recorded version; runs snapshot the plugin versions they used.

## Contracts

- All plugin calls carry the correlation IDs and a capability token limited to the run's scope.
- Plugins return typed results with `source: measured | reported | estimated` where numbers are involved.
- Plugins never receive raw secrets unless their manifest lists the secret reference and the user approved it.
- Network permission is explicit: `none`, `loopback`, or `external`. A loopback HTTP service such as XERJ is not declared `none`; external access requires a separate approval surface.
- A plugin's output is untrusted data to the workflow: it cannot promote to commands, change policy, or expand capabilities.
- Every kind has a conformance test suite and a fake implementation used by core tests.

## Reference plugins

- `docs/plugins/XERJ.md` — knowledge backend with namespaced memory and code index.
- `docs/plugins/RTK.md` — shell output filter with estimated token reduction.
- `docs/plugins/PONYTAIL.md` — instruction skill for minimalism on selected stages.
- Generic MCP server plugin — declares command, args, env references, and permissions; adapters translate it into the runtime's MCP configuration for the run only.

## UI

- Settings → Plugins: list with kind, version, health, enabled scopes, permissions, last error, and analytics where the plugin reports them.
- Run detail shows which plugins were active for each stage and their labeled contribution.
- Missing tools are shown with install hints from the manifest, never auto-installed.
