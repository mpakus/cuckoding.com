# 0801 — Plugin Manifest, Discovery, Registry, and Health

## Objective

Implement the manifest schema, discovery from bundled and user directories, detection of binaries/versions, health states, per-scope enablement with approval and audit, plugin supervisor with restart limits, and the Settings → Plugins UI.

```yaml
status: done
owner: codex
started_at: 2026-09-18
worklog: worklog/2026-09-18-0801-plugin-registry.md
```

## Dependencies

- 0201.

## Scope

Implement the manifest schema, discovery from bundled and user directories, detection of binaries/versions, health states, per-scope enablement with approval and audit, plugin supervisor with restart limits, and the Settings → Plugins UI.

## Deliverables

- Schema, registry, supervisor, settings LiveView.

## Checklist

- [x] Project-proposed plugins never auto-enable.
- [x] Permissions narrow by scope; never expand.
- [x] Network permission accepts only `none`, `loopback`, or `external`; loopback and external grants have distinct approval and enforcement paths.
- [x] Crash degrades feature only.

## Acceptance criteria

- [x] Fixtures for valid, over-permissive, missing, and wrong-version manifests behave as specified.

## Verification and evidence

`rtk mix test test/cuckoding/plugins/manifest_test.exs test/cuckoding/plugins/registry_test.exs test/cuckoding/plugins/supervisor_test.exs test/cuckoding_web/plugin_settings_live_test.exs` — 8 tests, 0 failures.
