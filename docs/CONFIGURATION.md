# Project Configuration

## Current UI configuration flow

The three-step project wizard creates identity, repository/branch, and a first
trusted configuration revision with unassigned default roles. Agent setup lives
on `/projects/:id/edit`, after registration.

| Layer | Stored information | Effect of later edits |
| --- | --- | --- |
| Machine-local `provider_accounts` | Saved label, adapter, validated non-secret settings, authentication mode/status | Catalog metadata changes; existing project copies are not synchronized |
| Project configuration revision | Connections with stable account IDs, copied settings, role names/instructions/assignments | New saves append revisions; newly created boards use the latest revision |
| Board | Default workflow version and copied role assignments/settings | Existing boards are not rewritten by project saves |
| Run | Board workflow/roles plus trusted project policy and fixed repository revision | Historical snapshots remain unchanged |

**Use in this project** stages a saved connection in the form; save the agent
or full configuration to persist attachment. Saving the full configuration
requires every role to be assigned. Removing a connection from a project does
not delete or revoke the machine-wide account. Custom roles can be saved, but
the default delivery launcher uses Specifications, Coding, and Review.

Runtime authentication is a live dependency: `AgentRuntime` looks up the saved
account's current authentication mode by ID. It is not fully frozen by the role
snapshot. A cached successful check is not a launch guarantee. Codex account
login and run probes use different homes; credential-only reuse across them is
still an explicit real-provider verification gate in [TESTING.md](TESTING.md).

Legacy board/run snapshots without `provider_account_id` keep their run-scoped
setup. Saving the project cannot upgrade them, even for a new run on that old
board. Create a new board after saving the desired assignments; retain the old
board and its tasks/history. There is no automatic board migration in the UI.

## Configuration layout

Projects may commit a `.cuckoding/` directory:

- `project.yml` — identity, repository conventions, commands, dev server, ports, protected paths, knowledge settings.
- `workflow.yml` — board workflow templates and gates.
- `policies.yml` — capabilities, budgets, approvals, retention, power behavior.
- `plugins.yml` — plugins the project would like to use, with the scopes it proposes; never auto-enabled.
- `agents/*.md` — role-specific instructions and output contracts.
- `knowledge/` — project knowledge files (see `docs/KNOWLEDGE_COMPRESSION.md`).

Example files in this pack use the `.example.yml` suffix. Rename and review them before execution.

The implemented project loader accepts one regular, non-symlinked `project.yml` up to 1 MiB, requires `schema_version: 2`, validates command declarations and protected paths, and computes the SHA-256 source hash used by the immutable configuration version. Commands may be written as a shell-like string for readability or as an argv list. Parsing never invokes a shell: Cuckoding resolves the executable once per execution and passes the remaining tokens directly to `RunnerBridge`. Shell executables, NUL bytes, absolute argument paths, and parent traversal are rejected. This is a static policy check on trusted declarations, not filesystem isolation for the child process.

## Precedence

From lowest to highest:

1. Application safe defaults.
2. User global settings.
3. Committed project configuration.
4. Board settings.
5. Run-specific approved overrides.
6. Time-limited human capability grant.

Higher precedence cannot bypass hard security prohibitions unless the application explicitly supports a reviewed exception flow.

## Trust model

Configuration from a repository is untrusted until the user reviews and trusts a content hash. Each run snapshots the trusted hash. Changes are presented as a semantic diff. An active agent cannot grant itself new tools, paths, plugins, secrets, or budgets by editing configuration.

## Enforced versus advisory

Every policy field is classified. Enforced fields change what Cuckoding does (budgets, approvals, protected paths, ports, plugin enablement, checkpoint cadence). Advisory fields are passed to the runtime or shown to the user but not enforced by Cuckoding (network class, resource ceilings on the host runner). Advisory fields are marked `advisory: true` in the schema and rendered with that label in the UI. A runner plugin may promote an advisory field to enforced by declaring it in its manifest.

The current schema exposes UI-ready classification records. Declared commands, protected paths, and preview port ranges are `enforced`; host-runner network class and memory ceilings are `advisory`. The shared badge renders the latter as **Advisory · not enforced**, including an explicit accessible label.

When `commands.dev_server` is present, its declaration is launched through the same declared-command boundary. `ports.range` is enforced by the project record; `ports.health_path` must be an origin-relative path with no control characters. Cuckoding supplies `HOST=127.0.0.1` plus matching `PORT` and `CUCKODING_PORT` values, so a compatible development server needs no interpolated shell command.

Application power defaults live under `:cuckoding, :power_manager`: `enabled: true`, a 5-second `tick_ms`, a 1-second `tolerance_ms`, and `prevent_display_sleep: false`. Idle-sleep prevention uses `caffeinate -i`; enabling display-sleep prevention adds `-d` but never adds AC-only `-s`. A board's `unattended_until` is a durable UTC expiry, not an approval override.

## Validation

- Define and version a schema for every YAML document.
- Reject unknown security-sensitive fields; warn on unknown descriptive fields.
- Resolve paths and symlinks before confinement checks.
- Validate workflow graphs for missing stages, invalid transitions, unsafe cycles, and role kinds (`agent`, `human`, `system`).
- Validate role references and adapter capability compatibility.
- Validate plugin references against installed manifests.
- Show actionable errors with the source file and field path.

## Secrets and machine-specific values

Committed configuration references named secrets and tool paths; it never contains secret values. Machine-specific resolution belongs in user settings or Keychain. Exports redact local absolute paths by default.

## Versioning

Each config file declares a schema version. Migrations must be deterministic and previewable. Runs keep the original parsed snapshot, so later config edits never rewrite history.
