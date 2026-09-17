# Worklog — 0004 Sleep/wake and power assertion spike

## Metadata

- Date/time (UTC): 2026-09-17
- Task: 0004
- Status: review
- Human/agent owner: Codex
- Branch: `feature/0004-sleep-wake-power-spike`
- Start revision: `07c7a2c`
- Environment: Apple Silicon macOS 27.0, Ruby 3.4.2

## Acceptance criteria restatement

- A power assertion is observable only while active work needs it and is released when ownership ends.
- A simulated clock gap and a coordinated real sleep are detected on the first post-wake tick with the measured gap duration.
- Wake reconciliation continues a live process, recovers a dead process, classifies a dropped provider stream as transient, and never launches the durable stage twice.
- AC, battery, and lid-close behavior is reported from evidence without extrapolating unperformed tests.

## Initial findings

- The macOS 27 `clock_gettime(3)` contract contradicts the planning assumption: `CLOCK_MONOTONIC` continues during sleep. `CLOCK_UPTIME_RAW` is the clock that stops while the system sleeps, so active/wall divergence must use uptime, not monotonic time.
- `caffeinate(8)` confirms `-i` owns an idle-sleep assertion and `-w <pid>` releases it when the owner process exits. `-s` prevents system sleep only on AC and is not the MVP default.
- XERJ project refresh required a new `cuckoding-project-v4` prefix because the frozen v3 schema predated source files. The completed generation indexed 20 of 20 code files and 424 records; the local node briefly required a 96% transient flood watermark because the data volume was at the default 95% threshold. The default was restored.
- Pinned peers contain no direct macOS power manager. Agetor `src/cli/sse.ts:112-130` provides the closest useful adjacent pattern: abortable, bounded full-jitter reconnect for dropped streams. Cuckoding still requires durable wake reconciliation and idempotent stage ownership.

## Human-coordinated checks

`pmset sleepnow` and lid-close tests intentionally remain pending until an immediate safe test window is confirmed. They change the workstation's power state and can interrupt the user's session; broad implementation approval is not treated as permission to sleep the machine at an arbitrary moment.

## Work performed

- Added a Ruby-standard-library spike with explicit continuous, uptime, and wall clock samples; a one-second gap tolerance; a supervised `caffeinate` assertion; idempotent reconciliation by gap ID; live PID/start-identity checks; provider recovery; and post-sleep stream classification.
- Added unit coverage for exact gap duration, wall-clock-change and delayed-tick false positives, duplicate reconciliation, live continuation, dead-process recovery, and post-sleep EOF handling.
- Ran the live assertion verifier without sleeping the Mac. It observed the target PID in `pmset`, released it while the owner stayed alive, and verified `-w` cleanup when the owner exited.
- Kept captured `pmset` evidence scoped to the target PID so unrelated user processes and hardware do not enter the repository.
- Corrected the power documentation and added ADR-022 rather than rewriting ADR-016's history.
- Refreshed XERJ under `cuckoding-project-v4`, updated the corpus manifest and commands, and inspected Agetor's bounded stream-reconnect pattern.

## Verification

- `rtk proxy ruby -w -c spikes/0004-sleep-wake-power/power_manager_spike.rb` — syntax OK.
- `rtk proxy ruby spikes/0004-sleep-wake-power/test_power_manager_spike.rb` — 6 runs, 14 assertions, 0 failures, 0 errors.
- `rtk proxy ruby spikes/0004-sleep-wake-power/power_manager_spike.rb spikes/0004-sleep-wake-power/evidence` — live assertion, owner-exit release, live/dead reconciliation, and cleanup passed.
- `rtk ps -axo pid,ppid,pgid,command` scoped to the verifier commands — no owned `sleep` or `caffeinate` process remained.
- `rtk xerj autoindex ... --prefix cuckoding-project-v4` — generation 1 committed, 424 records, 20/20 code files indexed, exit 3 only for declared junk files.
- `rtk xerj autoindex ... --prefix cuckoding-project-v5` — generation 1 committed, followed by documentation and final source refreshes through generation 3; 493 records and 22/22 code files are live, with exit 3 only for declared junk files. The immutable v4 schema rejected the new evidence shape, so v5 became the documented current generation.
- XERJ v5 required a temporary 97% flood-stage watermark with 45 GiB free; the default was restored immediately after indexing and verified as `null`.
- `rtk xerj def --prefix cuckoding-project-v5 -k 5 RealSleepVerifier` — returned the current class at `spikes/0004-sleep-wake-power/power_manager_spike.rb:268`.
- `rtk proxy ruby spikes/0004-sleep-wake-power/power_manager_spike.rb --real-sleep ...` — five approved attempts. One 31-second sleep started only after the initial verifier had failed and cleaned up; four later preparations were cancelled by fresh user-activity assertions. No attempt is counted as recovery evidence.
- Final rejected attempt — continuous 30,115 ms, uptime 30,115 ms, wall 30,115 ms, detected gap `null`; correct rejection rather than a false sleep event.
- Cleanup inspection after every attempt — no owned worker, loopback server, provider-stream fixture, or `caffeinate -i -w` process remained.

## Handoff

ADR-022 selects supervised `caffeinate -i -w <beam_pid>` and continuous-minus-uptime gap detection. Task 0306 should carry this contract into the Phoenix Power Manager and persist reconciliation before scheduling.

Task 0004 remains in review. It still needs an immediate human-coordinated window for `pmset sleepnow`, AC lid close, and battery lid close. Do not mark those outcomes from simulation.

The active workstation could not provide that window reliably: current user/login activity cancelled four sleep preparations. Repeat on a quiet or locked test Mac rather than retrying indefinitely in an active session.
