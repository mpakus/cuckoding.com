# R050d1 — Exact task candidates

Status: verified, 2026-10-13. Branch: `feature/R050d1-task-candidates`.

One host prerequisite of R050d/e, not a new user setup step.

- [x] Capture bounded, hash-bound task edits from a verified owned checkout into
  an immutable Git candidate; preserve the original checkout/index/branch.
- [x] Verify every other tracked byte, modes, ownership, registration and extra
  entries. Reject protected paths, foreign edits and stale/partial requests.
- [x] Retain intent, candidate index, objects, reference and receipt. Never replay
  an uncertain candidate publication or infer review/completion from capture.
- [x] Independently verify the retained candidate against live workspace bytes
  before future checks/review; expose normalized receipts through the host adapter.
- [x] Package a fresh generated app bundle without stale dependency files;
  refuse replacing a running bundle and preserve its selected workspace.
- [x] Run native/transport regressions, update docs/AGENTS/README, merge local main.

Start, stage scheduling, declared checks and Secutor integration remain R050d/e.

[Verification evidence](../worklog/2026-10-13-R050d1-task-candidates.md).
