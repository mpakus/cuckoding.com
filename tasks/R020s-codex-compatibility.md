# R020s — Verify the installed Codex runtime cohort

Status: implemented and verified, local integration pending, 2026-10-23. Base `bbdec5e`.

- [x] Verify signed installed 0.163.0-alpha.11.2 with fresh private profiles:
  offline schema, effective task/no-tools policy, ephemeral thread preflight and
  two-workspace/single-process canaries, plus setup/login-start/cancel without
  opening a browser. No inference or personal profile access.
- [x] Admit only that exact version after successful conformance, alongside the
  old execution baseline. Keep setup-only versions separate and unknown versions
  unsupported; never substitute an agent/account/model.
- [x] Freeze the actual observed isolation version and reject a successful
  receipt for a different accepted version. Preserve old commands/receipts.
- [ ] Update UI/docs/AGENTS/README, verify native/domain/UI/regression/build and
  merge local main without publication. Real-account execution remains open.

[Verification and artifact](../worklog/2026-10-23-R020s-codex-compatibility.md).
