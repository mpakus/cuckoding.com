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

The Phase 8 registry implements the first five lifecycle boundaries. It scans
only direct, regular plugin directories and rejects symlinked manifests,
duplicate YAML keys, unknown fields, traversal-capable permissions, unsupported
network classes, and shell-like version probes. Bundled manifests take
precedence over duplicate user keys. Repository configuration remains a
proposal and is never discovered or activated automatically.

Activation resolves the global → project → board → role/stage ancestry and
requires every more-specific permission to be present in its enabled parent.
The approval record distinguishes standard, loopback-network, and
external-network grants. This distinction is enforced by the registry and
shown in Settings; the current host runner cannot technically isolate network
traffic, so its runtime network boundary remains visibly advisory.

## Contracts

- All plugin calls carry a signed, short-lived capability token bound to the
  exact run, plugin, current activation, optional stage/role, permissions, and
  network grant. The manifest hash and approved configuration are signed;
  disabling or changing that activation invalidates the token.
- `Cuckoding.Plugins.Contracts` exposes the closed operations for all nine
  behaviours and rejects unregistered operations or incomplete implementations.
- Public plugin results are recursively redacted and bounded to 1 MiB. Numbers
  are accepted only as typed measurements with
  `source: measured | reported | estimated`; arbitrary numeric output is
  rejected rather than relabeled.
- Plugins never receive raw secrets unless their manifest lists the secret reference and the user approved it.
- Network permission is explicit: `none`, `loopback`, or `external`. A loopback HTTP service such as XERJ is not declared `none`; external access requires a separate approval surface.
- A plugin's output is untrusted data to the workflow: it cannot promote to commands, change policy, or expand capabilities.
- Secret-store private results are the only non-public envelope field. They stay
  in memory, are hidden by inspection, and never enter events, logs, or UI.
- Every kind has a deterministic fake in `test/support/plugin_fakes.ex`; the
  reusable `Cuckoding.PluginConformance.check/3` exercises every declared
  operation and is also used by future runner stubs.

## Reference plugins

- `docs/plugins/XERJ.md` — knowledge backend with namespaced memory and code index.
- `docs/plugins/RTK.md` — shell output filter with estimated token reduction.
- `docs/plugins/PONYTAIL.md` — instruction skill for minimalism on selected stages.
- `docs/plugins/MCP_FILESYSTEM.md` — integrity-pinned official filesystem MCP
  package with offline execution and a read-only tool allowlist.

## UI

- Settings → Plugins (`/settings/plugins`): implemented list with source, kind,
  version, textual health, requested permissions, manifest hash, enabled scopes,
  approval class, and last error. Enable and disable actions require an explicit
  confirmation and reason; unavailable plugins cannot be enabled.
- Run detail shows which plugins were active for each stage and their labeled contribution.
- Missing tools are shown with install hints from the manifest, never auto-installed.
