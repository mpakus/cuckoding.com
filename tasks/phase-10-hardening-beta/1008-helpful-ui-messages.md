---
status: complete
owner: codex
started_at: 2026-09-20
completed_at: 2026-09-20
worklog: worklog/2026-09-19-1008-helpful-ui-messages.md
---

# 1008 — Helpful user-facing messages

## Goal

Make every Phoenix UI error, status, and empty-state message plain, specific, safe, and actionable.

## Acceptance criteria

- [x] Inventory every user-visible error/status formatter and alert in `lib/cuckoding_web/`.
- [x] Replace raw atoms, tuples, changeset dumps, and `inspect/1` output with stable public copy.
- [x] Errors state what happened and the next safe action; Git/worktree errors identify the relevant recovery without suggesting data loss.
- [x] Success and empty-state copy uses consistent task, board, run, agent, and project terminology.
- [x] Unknown failures use a redacted fallback and direct the user to durable run/activity evidence when available.
- [x] Existing alert/status regions remain accessible and focused regression tests cover representative recovery messages.
- [x] Documentation records the public-message boundary and verification evidence.

## Verification

- `rtk mix format --check-formatted`
- `rtk mix compile --warnings-as-errors`
- `rtk mix test`
- `rtk mix credo --strict`
- `rtk mix sobelow --config`
- `rtk git diff --check`
