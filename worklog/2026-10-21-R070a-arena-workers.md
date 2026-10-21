# R070a — Concurrent isolated Arenas

Claimed 2026-10-21 on b99ff8f, after R060j was verified, fast-forwarded into local
main and its branch deleted. Untitled.md.age remains untouched. Ponytail full
5.3.2 (MIT), architecture/workflow/OTP/local-runner/security/quality skills and
incremental implementation/testing/review apply. RTK proxy preserves exact output
and pinned Elixir/OTP semantics. No provider invocation or new native grant.

Plan: freeze a new scheduler contract; enforce two global battle claims, one
stage per Arena and one turn per exact connection in SQLite. Replace the single
job cache with monitored workers and a fair cursor; preserve exclusive legacy
work/recovery and one_for_all cleanup. Same-board parallel tasks remain open.

Delivered: `Battles.Capacity` checks immutable scheduler snapshots, two global
running claims and exact-connection ownership under the existing immediate
transaction. Missing/unverified provider cleanup retains a connection reservation;
new Arenas cannot bypass it. Partial indexes keep these global queries off settled
history. No record/authority rewrites. BattleRunner owns a bounded monitor map,
one timer and fair Arena cursor, with exclusive old Starts/recovery. Task workers
still commit results before notification; one_for_all stops every old worker.
Start Inspect describes two Arenas and sequential tasks within each board.

Verification using pinned Elixir/OTP through RTK proxy:
- New regressions initially failed: missing scheduler, six admitted global claims,
  shared-connection and legacy overlap. These became passing capacity checks.
- `mix quality`: 398 tests passed, format/compile/Credo clean, Sobelow no
  vulnerabilities, dependency audit exit 0. Existing Sobelow lockfile keyword
  warnings persist. The isolated migration test can reload a migration module
  already loaded during startup; it adds no application compiler warnings.
- Eight capacity regressions cover concurrent claims, zero-cost queueing, shared
  connection/uncertain cleanup, old snapshot exclusion, three-Arena fairness,
  independent failure/Pause and all-worker restart without replay.
- Prior eleven-migration database upgraded to twelve; retained sentinel event
  unchanged, integrity/FKs pass, query plan uses the partial connection index.
  Its private 0600 pre-upgrade backup was reopened with all eleven versions and
  the unchanged event; integrity/FKs pass. No user's database used.
- Capacity mutation (`<` to `>=`) failed the concurrent-claim regression (zero
  instead of two claims). Restored original source and reran full quality.
- Four dialog/login JavaScript checks and `git diff --check` pass.
- Source review checked atomic claims, bounded task maps/timers, fairness,
  historical authority, cleanup reservations and no new native/provider grants.

No real provider invocation, native process-group change, physical sleep drill,
native bundle replacement or browser walkthrough. Existing native path/port/
process enforcement is unchanged; live provider and same-board parallel writer
acceptance remain open.
