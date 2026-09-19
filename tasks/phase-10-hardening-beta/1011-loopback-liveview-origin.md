---
status: done
owner: codex
started_at: 2026-09-19
completed_at: 2026-09-19
worklog: worklog/2026-09-19-1011-loopback-liveview-origin.md
---

# 1011 — Loopback LiveView origin

## Goal

Keep LiveView connected through either supported loopback browser hostname.

## Acceptance criteria

- [x] LiveView accepts `127.0.0.1` and `localhost` origins only.
- [x] The HTTP listener remains bound to `127.0.0.1`.
- [x] Phoenix development code reloading uses its required Mix listener.
- [x] Focused tests and project quality gates pass.
