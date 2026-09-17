# 0801 — Plugin Manifest, Discovery, Registry, and Health

## Objective

Implement the manifest schema, discovery from bundled and user directories, detection of binaries/versions, health states, per-scope enablement with approval and audit, plugin supervisor with restart limits, and the Settings → Plugins UI..

## Dependencies

- 0201.

## Scope

Implement the manifest schema, discovery from bundled and user directories, detection of binaries/versions, health states, per-scope enablement with approval and audit, plugin supervisor with restart limits, and the Settings → Plugins UI.

## Deliverables

- Schema, registry, supervisor, settings LiveView.

## Checklist

- [ ] Project-proposed plugins never auto-enable.
- [ ] Permissions narrow by scope; never expand.
- [ ] Network permission accepts only `none`, `loopback`, or `external`; loopback and external grants have distinct approval and enforcement paths.
- [ ] Crash degrades feature only.

## Acceptance criteria

- [ ] Fixtures for valid, over-permissive, missing, and wrong-version manifests behave as specified.

## Verification and evidence

Run registry and supervisor tests.
