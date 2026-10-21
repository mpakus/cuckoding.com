# R102 — Bandit advisories and current audit gate

Status: complete, 2026-10-21. [Evidence](../worklog/2026-10-21-R102-bandit-security.md).
Merged into local main as `5dc3843`; task branch deleted. Not pushed.

- [x] Upgrade the Bandit dependency to a version fixing GHSA-69m6-wcv4-rwcf and
  GHSA-v53v-9hvg-37jf, including the Phoenix error-rendering compatibility fix.
  Review required transitive changes; retain all other locks.
- [x] Fail the standard quality gate on current Hex advisories as well as the
  existing audit. Do not ignore findings or add Hex to the packaged runtime.
- [x] Verify transport/session/origin/error behavior, full quality, build/signature
  and packaged smoke. Update docs/AGENTS/README and merge local main only.
