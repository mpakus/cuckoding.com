# R103 — Native Tokio advisory

Status: verified locally, base `dd60fc5`, 2026-10-24.

- [x] Update the locked native Tokio to the compatible patched 1.53.3 cohort
  for RUSTSEC-2026-0386, without unrelated upgrades or advisory suppression.
- [x] Verify the resolved target graph and audit; distinguish remaining
  maintenance/platform warnings from the patched issue.
- [x] Run native formatting/lints/tests and rebuild/verify the sealed app's
  actual lifecycle and recovery with preserved synthetic fixtures.
- [x] Update docs, AGENTS.md and README.md; merge local main, no publication.

No provider grant, user workspace/profile, VM policy or schema changes.

118 native tests and current sealed recovery/lifecycle passed. The Tokio advisory
is absent; seven existing warnings remain visible. See the
[worklog](../worklog/2026-10-24-R103-native-tokio.md) for exact artifact/audit scope.
