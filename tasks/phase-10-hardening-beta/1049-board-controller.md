---
status: done
owner: codex
started_at: 2026-09-25
completed_at: 2026-09-25
worklog: worklog/2026-09-25-1049-board-controller.md
---

# 1049 — Sequential board controller

Implement the accepted [control plan](../../docs/CUCKODING-CONTROL.md) as one
coherent feature task. CTRL-01–07 are implementation slices, not separate claims.

- [x] Durable batch snapshots, commands, exclusive board ownership, safe migrations.
- [x] Reviewed Draft/Ready Start board preflight and explicit local completion.
- [x] Active read-only Speculator decisions and shared, sequential admission.
- [x] Reviewed commit handoff preserving default-branch drift and ownership checks.
- [x] Board pause/resume/stop/skip/retry, blocker settlement and crash/wake recovery boundaries.
- [x] Live board/home progress, whole-batch statistics, accessible controls/motion.
- [x] Focused/full quality, security/migration/recovery and rendered UI checks; synchronized docs.
- [x] Record real-provider/native acceptance separately; preserve open gates honestly.

Source and local verification complete; real-provider, physical sleep/wake and
packaged-app acceptance remain unchecked in the linked plan/worklog. Delivery
is the feature working tree, not an installed app or main/remote integration.
