# Real sleep attempt evidence

Date: 2026-09-17. Power source: AC, 76% battery.

- Attempt 1: `pmset sleepnow` returned before sleep entry. The verifier sampled too early and cleaned up. macOS later recorded a 31-second software sleep, so this attempt does not prove process or stage survival.
- Attempts 2–5: macOS began sleep preparation but logged fresh `WindowServer UserIsActive` and login-window activity before entry. No `Sleep` event was recorded. The final detector sample showed equal 30,115 ms continuous, uptime, and wall elapsed time, correctly producing no gap.
- The verifier assertion was deliberately released for the later forced-sleep attempts after observation showed an active `caffeinate -i` assertion kept the request pending. The assertion lifecycle remains independently proven by the committed `pmset` evidence.
- A one-time automatic wake was requested for the later attempts, but no scheduled drill entered sleep.
- Every attempt cleaned up its worker, loopback server, provider-stream fixture, and owned `caffeinate` process group. Unrelated system assertions were not changed.

Result: real sleep reconciliation remains unverified on this active workstation session. Repeat the opt-in verifier on a quiet or locked test Mac, then run separate AC and battery lid-close drills.
