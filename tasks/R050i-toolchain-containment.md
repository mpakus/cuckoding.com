# R050i — Verify the child-process containment prerequisite

Status: investigation verified; local integration pending, 2026-10-23. Base `7b1b699`.

- [x] Inspect pinned Apple source and the installed OS interface for process-group
  and session changes; distinguish source reasoning from observed enforcement.
- [x] Use only fresh private synthetic fixtures to test whether a child can leave
  an owned process group under deny-default Seatbelt with fork enabled. Bound,
  reap and verify every probe; no project, account or provider access.
- [x] Record the result and an implementable next boundary in docs/AGENTS/README.
  Preserve the shipping single-process grant; research never authorizes toolchains.
- [ ] Verify the evidence/docs and merge locally without publication. Do not
  mark general Mix/npm checks or beta release acceptance complete.

Result: the tested child can leave the group through all three mechanisms.
This completes the prerequisite investigation only; the toolchain grant remains
unimplemented. [Evidence](../worklog/2026-10-23-R050i-toolchain-containment.md).
