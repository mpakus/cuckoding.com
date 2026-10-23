# R060q — Structured Codex failure handling

Status: implemented and verified; local integration pending, 2026-10-23. Base `dbdf4ad`.

- [x] Classify typed Codex usage-limit/overload/auth errors and HTTP 429 without
  parsing or storing provider messages; preserve exact thread/turn scope.
- [x] Let bounded provider-internal retries finish; terminal failures retain
  edit evidence and verified cleanup. No replay or wider runtime grant.
- [x] Freeze backoff v2 for explicit overload with bounded jitter inside existing
  two-retry budgets/deadlines. Keep 429 manual, usage exhaustion nonretryable and
  historical backoff v1 behavior unchanged.
- [x] Verify native/domain/OTP/UI paths and update docs/AGENTS/README.
- [ ] Merge locally to main without publication. Real-provider/remaining-runtime
  acceptance stays separate.

Evidence: [worklog](../worklog/2026-10-23-R060q-provider-failures.md).
