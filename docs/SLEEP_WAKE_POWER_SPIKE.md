# Sleep/Wake and Power Assertion Spike

Task 0004 is complete. Safe automated checks, a coordinated software-sleep cycle, and physical AC and battery lid-close drills passed. The code and evidence are under `spikes/0004-sleep-wake-power/`.

## Reproduce without sleeping the Mac

```sh
rtk proxy ruby spikes/0004-sleep-wake-power/test_power_manager_spike.rb
rtk proxy ruby spikes/0004-sleep-wake-power/power_manager_spike.rb spikes/0004-sleep-wake-power/evidence
```

The second command creates and releases an idle-sleep assertion, starts disposable `sleep` workers in their own process groups, and records only the assertion lines belonging to the verifier. It does not call `pmset sleepnow` or alter power settings.

## Measured results

| Check | Result |
| --- | --- |
| Clock contract | macOS 27 `CLOCK_MONOTONIC` continues through sleep; `CLOCK_UPTIME_RAW` stops |
| Simulated gap | one tick reported exactly 10,000 ms from continuous-minus-uptime divergence |
| Software-sleep gap | first resumed tick reported 11,549 ms; continuous 23,945 ms versus uptime 12,396 ms |
| Clock-change guard | a one-hour UTC wall-clock jump with equal continuous/uptime elapsed time produced no gap |
| Delayed-tick guard | a ten-second scheduler delay with equal continuous/uptime elapsed time produced no gap |
| Assertion visible | target `caffeinate` PID appeared in `pmset -g assertions` while held |
| Explicit release | assertion disappeared while its owner process remained alive |
| Crash release | `caffeinate -w` assertion disappeared when its owner exited |
| Live process after gap | continued with PID plus start identity; provider session count unchanged |
| Dead process after gap | provider worker recovered once; durable stage execution count stayed one |
| Duplicate reconciliation | replaying the same gap ID emitted no second event or recovery |
| Provider stream EOF | classified transient only in post-sleep context |
| Software-sleep survival | worker, loopback server, port, and provider stream survived; assertion reacquired; one event and one stage execution |
| AC lid close | 4,096 ms gap; worker, stream, server, port, and existing idle assertion survived; one `continued` event |
| Battery lid close | 121,169 ms gap; missing worker recovered once, assertion reacquired, stream/server/port survived; one stage execution |

Eight unit tests with 17 assertions pass. The live verifier produced two reconciliation events, one `continued` and one `recovered`, while preserving `stage_execution_count: 1`. No verifier `sleep` or `caffeinate` process remained afterward.

## Decision

Use supervised `/usr/bin/caffeinate -i -w <beam_pid>` for the MVP. The control plane explicitly starts it when eligible work becomes active and stops it when the last eligible run stops; `-w` is the crash-safe backstop. Do not use `-s` by default: the platform documents it as AC-only, and neither an idle assertion nor an IOKit assertion overrides forced sleep or lid close.

Direct `IOPMAssertionCreateWithName` is viable without special privileges and would let the native shell own a named assertion. It is not selected for the MVP because the durable eligibility state lives in Phoenix, a supervised child already has observable ownership and automatic BEAM-exit cleanup, and native cross-process coordination would add code without improving the product contract.

Use `CLOCK_MONOTONIC` as continuous elapsed time and `CLOCK_UPTIME_RAW` as active elapsed time. A divergence above one second is the sleep gap. UTC wall time remains an event timestamp and reporting value, not the detector, so time synchronization cannot masquerade as sleep.

## Reference coding

The refreshed lexical XERJ generation `cuckoding-project-v7` indexed 22 of 22 code files and 517 records. None of the pinned peers implements macOS power assertions. The closest reusable behavior is Agetor at `src/cli/sse.ts:112-130`, which uses abortable full-jitter backoff after a stream disconnect. Cuckoding may adapt that retry shape in the adapter layer, but only after the durable Power Manager records and reconciles the sleep gap.

## Physical lid-close evidence

The AC drill ran at 80% with external power attached. macOS recorded `Clamshell Sleep`; the first resumed tick detected a 4,096 ms gap. The disposable worker, provider stream, loopback server, port, and original `caffeinate -i` assertion survived, and reconciliation emitted one `continued` event with `stage_execution_count: 1`.

The battery drill ran at 80% with AC detached. macOS recorded 131 seconds of `Clamshell Sleep`; the first resumed tick detected a 121,169 ms gap. The verifier observed the lid close, scheduled the worker-loss deadline 30 seconds later, and the deadline fell inside the recorded sleep interval. Because the CPU was suspended, the Ruby timer delivered termination immediately after resume—not while instructions were executing during sleep. Before reconciliation the worker was absent; it recovered exactly once, the assertion was reacquired, the provider stream/server/port survived, and `stage_execution_count` remained one.

Evidence is committed as `lid-close-ac-live-*` and `lid-close-battery-recover-*` under `spikes/0004-sleep-wake-power/evidence/`.

## Coordinated drill result

Five `pmset sleepnow` attempts were made after explicit approval. The first request entered a 31-second software sleep only after the initial verifier had already sampled, failed, and released its processes, so it cannot prove recovery. The next four requests reached sleep preparation but were cancelled before entry by fresh `WindowServer UserIsActive` and login-window activity. The final first-tick sample correctly reported no gap: continuous, uptime, and wall clocks each advanced 30,115 ms.

The attempts also showed that this host kept the software-sleep request pending while the owned `caffeinate -i` assertion was present. Later attempts therefore verified and deliberately released the assertion before requesting sleep, with reacquisition designed for the post-wake path.

A sixth approved attempt succeeded after the display was put to sleep. The machine entered software sleep on AC at 76%, the first resumed verifier tick measured an 11,549 ms gap, and the worker, loopback server, port, and provider stream remained live. The verifier reacquired its assertion and idempotent reconciliation emitted one `continued` event while `stage_execution_count` remained one. The summary, clock sample, and scoped power log are committed beside the earlier attempt report; unrelated assertion and hardware details were excluded.

The opt-in commands are:

```sh
rtk proxy ruby spikes/0004-sleep-wake-power/power_manager_spike.rb --real-sleep development spikes/0004-sleep-wake-power/evidence
rtk proxy ruby spikes/0004-sleep-wake-power/power_manager_spike.rb --lid-close ac live development spikes/0004-sleep-wake-power/evidence
rtk proxy ruby spikes/0004-sleep-wake-power/power_manager_spike.rb --lid-close battery recover development spikes/0004-sleep-wake-power/evidence
```

Run these only on a quiet or locked test Mac with a coordinated wake plan. The lid-close verifier validates the declared power source before and after sleep and writes distinct evidence files for each mode.
