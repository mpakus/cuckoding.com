# 0902 — Release Bundling, Signing, and Notarization

## Objective

Automate the build pipeline: release with ERTS in the bundle, per-binary signing with hardened runtime and required entitlements, notarization, SBOM, checksums, provenance..

```yaml
status: in_progress
owner: codex
started_at: 2026-09-18
worklog: worklog/2026-09-18-0902-release-signing-notarization.md
```

## Dependencies

- 0901.

## Scope

Automate the build pipeline: release with ERTS in the bundle, per-binary signing with hardened runtime and required entitlements, notarization, SBOM, checksums, provenance.

## Deliverables

- CI pipeline and scripts.
- Signed, notarized artifact.

## Checklist

- [ ] No system Erlang/Elixir needed at runtime.
- [ ] All Mach-O files signed.

## Acceptance criteria

- [ ] Gatekeeper accepts the artifact on a clean machine.

## Verification and evidence

Install on a clean Mac; verify signature and notarization.
