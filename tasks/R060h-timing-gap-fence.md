# R060h — Fence battle work after timing gaps

Status: verified; local integration pending, 2026-10-15.

- [x] Freeze `timing_guard: elapsed-gap-v1` in new Starts; observe UTC and
  monotonic elapsed time in a supervised guard independent of the coordinator.
- [x] Check before admission, during native/provider polling and before result
  settlement. Record a bounded public gap event before closing stage admission.
- [x] Pause a clean boundary for explicit Resume; a backward clock change or
  interrupted active work needs attention. Cancel active work through its existing
  owned helper path, retain its exact rejected receipt and verify cleanup for Stop.
- [x] Never advance cards/head from a fenced result, reset deadlines/budgets,
  replay native work or infer actual sleep/process death. Guard failure restarts
  its execution group and preserves existing uncertain-effect gates.
- [x] Cover injected timing gaps, forward/backward clock shifts, cleanup/Stop,
  worker/coordinator crashes, stale controls and UI reconnect; update docs,
  AGENTS and README.
- [x] Verified final package/smoke; reopened and compared the saved workspace.
- [ ] Merge into local main and delete the merged branch.

Physical sleep, native power assertions, lease/process reconciliation, active-time
accounting and parallel scheduling remain separate acceptance gates.

Evidence: final `mix quality` passed all 355 tests; source/package smoke, build,
Rust format/Clippy and saved-data comparison passed. Interactive browser check
unavailable while the Mac was locked; physical sleep/provider acceptance not run.
[Worklog](../worklog/2026-10-15-R060h-timing-gap-fence.md).
