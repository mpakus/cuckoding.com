# 1008 — Helpful user-facing messages

## Goal

Make every Phoenix UI error, status, and empty-state message plain, specific, safe, and actionable.

## Acceptance criteria

- [ ] Inventory every user-visible error/status formatter and alert in `lib/cuckoding_web/`.
- [ ] Replace raw atoms, tuples, changeset dumps, and `inspect/1` output with stable public copy.
- [ ] Errors state what happened and the next safe action; Git/worktree errors identify the relevant recovery without suggesting data loss.
- [ ] Success and empty-state copy uses consistent task, board, run, agent, and project terminology.
- [ ] Unknown failures use a redacted fallback and direct the user to durable run/activity evidence when available.
- [ ] Existing alert/status regions remain accessible and focused regression tests cover representative recovery messages.
- [ ] Documentation records the public-message boundary and verification evidence.

## Verification

- `rtk mix format --check-formatted`
- `rtk mix compile --warnings-as-errors`
- `rtk mix test`
- `rtk mix credo --strict`
- `rtk mix sobelow --config`
- `rtk git diff --check`
