# 0902 — Release Bundling, Signing, and Notarization

## Objective

Automate the build pipeline: release with ERTS in the bundle, per-binary signing with hardened runtime and required entitlements, notarization, SBOM, checksums, provenance..

```yaml
status: complete
owner: codex
started_at: 2026-09-18
completed_at: 2026-09-18
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

- [x] No system Erlang/Elixir needed at runtime.
- [x] All Mach-O files signed.

## Acceptance criteria

- [x] Gatekeeper accepts the artifact from a clean macOS account.

## Verification and evidence

The quarantined ZIP was extracted outside the worktree, its stapled ticket and
Gatekeeper acceptance were verified, and its 22 runtime checks passed under the
separate `qa` macOS account with a sterile environment. This is clean-account
evidence on the supported host, not a second physical Mac.
