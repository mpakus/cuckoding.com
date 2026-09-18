# Worklog — 0801 plugin manifest, discovery, registry, and health

## Metadata

- Date/time (UTC): 2026-09-18
- Task: 0801
- Status: complete
- Human/agent owner: codex
- Branch: `feature/0801-plugin-registry`
- Start revision: `bf5f2a9`
- End revision: task commit

## Acceptance criteria

- Validate plugin manifests and discover them from bundled and user directories.
- Detect declared binaries and versions, and persist explicit plugin health.
- Require human approval and an audit event for per-scope enablement; repository-proposed plugins never auto-enable.
- Narrow permissions by scope and accept only `none`, `loopback`, or `external` network grants with distinct approval and enforcement paths.
- Supervise plugin processes with restart limits so failure degrades only the plugin feature.
- Provide an accessible Settings → Plugins view.
- Cover valid, over-permissive, missing-binary, wrong-version, crash, and degraded-mode cases.

## Reference coding

- Focused project, Agetor, Vibe Kanban, and Hydra XERJ searches were attempted
  first. The configured loopback node was unavailable, so no search result was
  treated as evidence.
- Agetor revision `eb74ab5f3d6d71dfb91d5bd34e9c679c5a955a6a` is MIT licensed.
  Its unified scope and enablement resolution at `src/bun/commands.ts:448-535`
  informed the single activation path; no source was copied.
- Vibe Kanban revision `735654971bd396aa97b65166955678e4c34f8bf8` is
  Apache-2.0 licensed. Its bounded health/version outcomes at
  `crates/executors/src/executors/opencode/sdk.rs:519-552` informed explicit
  detection states; no source was copied.
- Cuckoding adds stricter manifest confinement, durable activation events,
  ancestor permission narrowing, exact network approval classes, and a restart
  budget around those reference ideas.

## Work performed

- Added forward-only `plugins` and `plugin_activations` tables with closed
  health, scope, network, and approval constraints.
- Added a strict YAML manifest parser and bundled/user discovery with safe,
  bounded executable/version detection and durable health state.
- Added audited enable/disable commands, scope ancestry, permission ceilings,
  exact network approvals, and repository-proposal non-enablement.
- Added a per-plugin process host with a bounded restart window. Exhaustion
  marks only that plugin unhealthy and leaves the application supervisor alive.
- Added the accessible `/settings/plugins` registry and approval UI, including
  textual health and the host-runner network limitation.
- Added focused parser, registry, supervisor, LiveView, migration, and fixture
  coverage; updated architecture, database, plugin, security, UI, and plan docs.
- One exact, unfiltered process inspection was required after a deliberately
  crashing supervisor fixture hung during development because filtered output
  could not identify the isolated test processes. The inspection exposed a
  credential in process metadata; work stopped, the user confirmed rotation,
  and a repository scan found no matching credential material. The credential
  value was not recorded here.

## Verification

| Check | Result |
| --- | --- |
| `rtk env MIX_ENV=test mix ecto.rollback --step 1` | pass; new migration rolled back cleanly |
| `rtk env MIX_ENV=test mix ecto.migrate` | pass; plugin schema reapplied cleanly |
| `rtk mix test test/cuckoding/plugins/manifest_test.exs test/cuckoding/plugins/registry_test.exs test/cuckoding/plugins/supervisor_test.exs test/cuckoding_web/plugin_settings_live_test.exs` | pass; 8 tests, 0 failures; crash logs are the intentional supervisor fixture |
| `rtk mix credo --strict` | pass; 149 source files, 2,240 functions/macros before final documentation pass |
| `rtk rg -l 'crsr_[A-Za-z0-9_]+' . --hidden --glob '!.git/**'` | pass; no repository match after user-confirmed credential rotation |
| `rtk mix quality` | pass; 10 properties and 164 tests, 0 failures; Credo checked 149 files/2,241 functions and macros with no issues; Sobelow and dependency audit passed |
| `rtk git diff --check` | pass |

## Handoff

Task complete after the final full quality gate and local-main merge recorded
below. Network grants are distinct, approved, persisted, and passed as runtime
configuration, but host execution remains advisory rather than a sandbox.
