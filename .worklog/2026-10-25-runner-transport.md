# BOSS-007a — separate-stream transport experiment

## Scope and baseline

- Continue from local main `0a54f79`; root branch `codex/boss-runner-transport`.
- Evaluate demand-driven stdout/stderr and independent EOF with deterministic
  local fixtures before selecting a production runner. No provider calls,
  application execution controls or runtime dependency changes in this slice.
- Root owns reference provenance/index and shared documentation. Bootstrap agent
  owns the isolated transport experiment; git_spike researches process ownership;
  folder_picker_review performs independent adversarial review.
- Existing erlexec experiment cannot prove bounded transport queues, genuine
  per-stream EOF or complete descendant cleanup. BOSS-007 stays open.

## Reference research

- Query: `rtk proxy xerj search --prefix bossrefs 'process stdout stderr backpressure EOF cancellation' -k 4 --full 1200`.
- Read agent-orchestrator `backend/pkg/agentruntime/process.go` at
  `7193eff4e08f1481944845ee058fe6fd18930b6d` (Apache-2.0): separate process wait
  and cancellation; reject leader-exit as proof of group cleanup.
- Added read-only Exile v0.15.0 snapshot
  `a4f29f31adc3c6bd2fe43ac62dc07a9eeb3bf413` and NetRunner snapshot
  `5f12e06aabb70f2aafde023bf547aaaa6f8fcb36` for source comparison.
  Exile source supports demand-driven distinct pipes; its direct-PID watcher is
  not sufficient production ownership. Both root license files are Apache-2.0.
  New NetRunner checkout was detached at its recorded SHA; existing snapshots
  were not reset or updated. No source copied.
- Read Exile `lib/exile/process.ex:468/548`, `c_src/exile.c:258/330`,
  `c_src/spawner.c:199`, `lib/exile/watcher.ex:26`, and
  `test/exile/process_test.exs:89/103`. Adopt bounded demand per separate pipe;
  reject conflating `await_exit` (which closes owned pipes) with EOF. Test real
  early pipe closure rather than relying on the upstream delayed-output label.
- Index attempt: `rtk proxy env XERJ_DISABLE_FEEDBACK=true xerj autoindex ./examples --prefix bossrefs --no-graph --no-semantic --workers 4 --yes`
  in main checkout exited 1 before walking files or writing: node disk flood-stage
  watermark 95% reached (45.8 GB free). No node settings or unrelated data changed.
  New snapshots are **not indexed**; existing four-reference index remains intact.
  Source inspection falls back to `rtk proxy rg` and exact versioned source/docs.
- Isolated writer checkout: `boss-exile-transport`, branch
  `codex/boss-exile-transport`; owns only `spikes/transport/` and its agent log.

## Acceptance and evidence

- [ ] Separate binary stdout/stderr, bounded reads and genuine independent EOF.
- [ ] Early stream close and inherited late output are observed accurately.
- [ ] Stalled consumption backpressures the fixture without output mailbox growth.
- [ ] Timeout/stop stays responsive while data consumption is stalled.
- [ ] Limitations and process cleanup are explicit; no live provider calls.
- [ ] Independent review, local-main merge, verification and temporary cleanup.

## Review in progress

- Independent lifecycle research found NetRunner's guardian useful for a later
  ownership spike, but its current leader-exit and cleanup-reporting behavior
  does not close BOSS gates. Source findings are in `docs/RESEARCH.md`.
- WIP review identified recursive catch frames growing the reader stack,
  linked-owner cleanup racing trap_exit restoration, potentially vacuous timeout
  tests before first output, and cleanup timeout replacing the original cause.
  Fixes and executable regressions are required before acceptance.
- Scratch cleanup must be registered immediately after exclusive creation, even
  if fixture compilation fails. All fixture processes have finite watchdogs.

- Initial transport run preserved late inherited output and actual exit 9, but
  disproved an assumed notification order: Port exit notification arrived after
  both EOFs. Replace that assertion with a barrier proving the direct parent is
  already dead while its child holds pipes, then release and verify all bytes.
  Do not change inherited descriptors merely to satisfy an expected message order.
  Prompt leader-exit notification is not claimed; completion still requires all
  actual stream EOFs and observed exit status.

## Next step

Implement and run the isolated transport proof, then record measured outcomes
and exact remaining production gates. No result is claimed yet.
