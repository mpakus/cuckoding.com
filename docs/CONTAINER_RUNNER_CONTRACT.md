# Container Runner Plugin Contract

## Status

This document freezes the MVP-facing contract for Docker, OrbStack, Colima,
and Apple Containers. No backend is implemented or selectable yet. The bundled
stub stays `missing` until a reviewed backend executable exists.

## Stable request boundary

A container plugin implements every `Cuckoding.Plugins.Kinds.Runner` operation
through the same run-scoped capability as other plugins. `prepare` validates
the immutable environment and returns a plan; `start` and `exec` accept only a
previously policy-resolved argv; `pause`, `hibernate`, `resume`, `inspect`,
`stream_events`, and `destroy` preserve the existing durable lifecycle.
Process/container IDs and start identity are recorded before work is treated as
running. Operations are idempotent by the host command key.

## Filesystem and Git

- Mount only the canonical run worktree read/write and run directory read/write.
- Never mount the home directory, repository parent, SSH directory, Keychain,
  provider credential directories, or unrelated workspaces.
- Git remains host-side. The container receives no `.git` directory or
  worktree `gitdir`, Git credential, push capability, or PR capability.
- The host creates and inspects worktrees, commits the approved candidate, and
  performs push/PR only after the existing human gate.

This avoids backend-specific linked-worktree metadata mounts and keeps one
audited Git boundary. A future read-only gitdir mount requires a separate ADR
and confinement proof.

## Images and resources

- Images use an immutable digest, never a mutable tag alone. Pulling or updating
  an image is a separate reviewed host action, not an agent command.
- Entrypoints and environment are built by Cuckoding; no shell string is used.
- CPU, memory, process, file-descriptor, and wall-time limits are explicit.
  Unsupported limits are recorded as unenforced and never promoted in the UI.
- Ports come only from the durable project lease range and bind to loopback on
  the host. Hibernation releases listeners and records the container identity.
- Network is deny-by-default. `loopback` and `external` require their existing
  distinct approvals and backend evidence; host loopback is not silently the
  container's loopback.

## Isolation claims and labels

Allowed claims are `filesystem`, `network`, `resource_limits`, and `egress`.
The Settings UI renders only manifest-declared claims and prefixes them with
`Declared`; a real backend may promote a claim to `Verified` only after a
backend-specific probe records evidence. Empty claims render `No container
isolation declared`. The stub claims nothing.

## Open questions for the first backend

- Which macOS backend offers stable process identity and pause/resume semantics?
- How is host-loopback access represented without granting arbitrary egress?
- Which resource limits are enforceable on both Apple Silicon and CI hosts?
- What signed image source, digest refresh, SBOM, and rollback policy ship?
- How are orphaned containers reconciled after daemon restart, sleep, or update?
- Can preview-port ownership be proven without trusting backend-reported state?
