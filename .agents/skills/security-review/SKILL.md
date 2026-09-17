---
name: security-review
description: Review changes involving processes, paths, credentials, networks, updates, Git operations, plugins, or knowledge publication.
---

# Security Review

1. Identify assets, attackers, trust boundaries, and new capabilities.
2. Trace every external input (repository, model, plugin, browser) to privileged side effects.
3. Check authentication, authorization, scope, expiry, and audit; check `/open` token single use.
4. Check path canonicalization, symlinks, command arguments, environment allowlist, and process groups.
5. Check secret storage, injection, redaction, retention, and export; no secret reaches an agent process.
6. Check plugin permissions against manifests and the effective runtime grant against the capability grant.
7. Check knowledge scope, redaction, and publication approvals.
8. Add adversarial tests and document residual risk, including host-runner limitations.

Stop for human review on escalation, ambiguous destructive ownership, secret exposure, unsafe migration, undeclared plugin access, or cross-project publication.
