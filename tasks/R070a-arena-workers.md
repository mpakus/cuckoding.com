# R070a — Concurrent isolated Arenas

Status: complete, 2026-10-21. Verified and merged into local main as 23b83d4;
task branch deleted. No push/publication or native bundle replacement.

- [x] New Starts freeze `isolated-arenas-v1`: two battle stage workers globally,
  one stage per battle/Arena and one provider turn per exact saved connection.
  SQLite claims enforce capacity; old Starts retain global serial dispatch.
- [x] Fair supervised dispatch across ready Arenas; blocked/paused/backoff work
  does not reserve capacity. No synchronous native/provider work in callbacks.
  Recovery inspection stays exclusive and one_for_all stops all old workers.
- [x] Show concurrency scope in Start; preserve independent review, frozen grants,
  exact bindings, cleanup, Stop/Pause/retry and source/worktree ownership.
- [x] Cover concurrent claims, capacity, fairness, shared connections, legacy
  isolation and multi-worker crash/controls; quality/docs and local main merge.

This first R070 slice does not claim same-board parallel task cloning, combined
candidate review or real same-account/provider acceptance.

[Evidence](../worklog/2026-10-21-R070a-arena-workers.md).
