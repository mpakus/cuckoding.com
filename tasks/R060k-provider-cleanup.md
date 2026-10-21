# R060k — Explicit bounded native provider cleanup

Status: complete, 2026-10-21. [Evidence](../worklog/2026-10-21-R060k-provider-cleanup.md).

- [x] Return explicit verified/uncertain group cleanup, with finite waits and no
  signalling after the owned unreaped leader can release its PID/PGID.
- [x] Propagate uncertainty through Codex/Cursor setup and task-turn outcomes,
  retaining edits/public evidence and refusing successful authorization/work.
  Cancellation cannot fabricate verified closure after a failed cleanup.
- [x] Preserve native grants, exact profiles/models and supervised BEAM I/O;
  do not introduce process inference, replay or general subprocess permissions.
- [x] Test descendants, unrelated peers, repeated close, early errors,
  cancellation/deadline and injected uncertainty. Verify native/domain/build
  checks, update docs/AGENTS/README and merge locally.

This is a cleanup prerequisite for broader retained-provider/restart recovery;
it does not itself recover a missing receipt or an escaped provider session.
