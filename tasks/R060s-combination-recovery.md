# R060s — Recover complete retained combined candidates

Status: verified and integrated locally, 2026-10-23. Base `8396de5`.

- [x] Freeze a new `combination_recovery` policy in new Starts. Only one exact
  restart-interrupted `combine` claim with otherwise settled history may use the
  existing exclusive supervised recovery queue. Historical policies and mixed
  provider/capture/preparation recovery keep their scopes.
- [x] Add a fixed read-only native operation that requires the original exact
  request, complete intent/publication/receipt, original captured candidate,
  current reviewed head/ref/config, source/worktree identity and combined tree.
  Reuse existing verification, retain the 60-second native/65-second host limits,
  cancellation and original future deadlines. Never reconstruct or replay effects.
- [x] Fix the discovered native comparison of Phoenix's canonical five-field
  preparation against the status-bearing retained receipt. Normalize only the
  comparison, preserve original intents/receipts and verify normal combination,
  fresh checks/review consumers and recovery with the actual host shape.
- [x] Retain the Interrupted claim and dated observation; a verified in-budget
  result pauses at fresh checks/independent review for explicit Resume. Keep all
  lifetime limits and binding gates. Late/fenced proof permits Stop only; missing
  or foreign proof never advances or implies cleanup. No new provider/tool grant.
- [x] Verify native adversarial/replay/path/budget cases, domain/OTP/UI recovery,
  immutable history and historical isolation; update docs/AGENTS/README, build/smoke
  and merge local main without push. Real-provider/physical recovery stays open.

[Verification, source and artifact identity](../worklog/2026-10-23-R060s-combination-recovery.md).
