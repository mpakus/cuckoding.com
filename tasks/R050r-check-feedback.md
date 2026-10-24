# R050r — Bounded failed-check output for repair roles

Implemented and verified, base `054f9b3`, 2026-10-24. Local integration only;
no push or release. [Evidence](../worklog/2026-10-24-R050r-check-feedback.md).

- [x] Freeze an explicit bounded-guest-feedback-v1 policy in new guest-check Starts;
  keep historical requests/normalizers exact and disclose sharing beside Start.
- [x] Under that policy only, return at most 4 KiB of transformed failure output
  after exact output/hash/source and VM/native closure verification. Bind excerpt
  and original output metadata; no new native operation, file path, tool or grant.
- [x] Validate/store feedback with the original check attempt. Pass the immutable
  failed-candidate evidence to Secutor and subsequent assigned repair roles;
  preserve it through fresh-worktree repair and clear it when new checks settle.
  Untrusted test text never grants permissions or completion authority.
- [x] Keep raw/excerpt text out of public activity/downloads. Show only retention
  metadata in task history; no extra setup or per-task approval. Add migration
  fence, adverse tests, real synthetic VM/repair proof, docs and local-main merge.

Remaining beta gates include dependency/platform support, native/physical recovery,
real-provider/parallel/custom-stage acceptance and release. No real inference or
saved-user-data access is approved by this test slice.
