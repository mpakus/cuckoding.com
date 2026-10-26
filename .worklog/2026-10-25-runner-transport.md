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

- [x] Separate binary stdout/stderr, bounded reads and genuine independent EOF.
- [x] Early stream close and inherited late output are observed accurately.
- [x] Stalled consumption backpressures the fixture without output mailbox growth.
- [x] Timeout/stop stays responsive while data consumption is stalled.
- [x] Limitations and process cleanup are explicit; no live provider calls.
- [x] Independent review, local-main merge, verification and temporary cleanup.

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

- Sustained ACK/drain regression reproduced reader stack growth: 2 MiB samples
  `[3602, 512]` words grew to `[14354, 2048]` at 8 MiB before the catch scope fix.
  NetRunner `test/teardown_test.exs:17` at the pinned SHA independently documents
  the same recursion/catch hazard. Adopt the bounded-stack acceptance pattern,
  not its implementation. GREEN evidence follows after final review.

- Independent adversarial checks on writer source passed: killed reader while
  ACK withheld → `failed` / `incomplete`, neither EOF fabricated and no exit
  fabricated; Stop after both real EOFs → `cancelled` / actual status 143.
  100 cancelled-flood→binary pairs in the same default trap_exit:false caller
  retained exact bytes/hashes/status 7, caller survived and mailbox was empty.
  Reviewer compiled an exclusive scratch fixture with `cc` and used
  `rtk proxy asdf exec elixir -r spikes/transport/transport.exs -e ...`;
  only its owned scratch was cleaned. These checks did not call providers.
- Source/documentation review independently found no overclaim in the pinned
  reference findings. Final independent review accepted the fixture-only branch.
- Writer commit `b2284fe83808b1da653d9aa0ab49f1b824d1460f` integrated sequentially
  into the root branch after its 12-test GREEN run (seed 712199), direct formatter
  check and staged diff check. All source remains outside the application.

## Writer verification

- `rtk proxy asdf exec elixir spikes/transport/transport_test.exs`: 12 passed,
  1.4s. After the catch-scope fix, reader stacks stayed `[20, 8]` words at both
  2 MiB and 8 MiB. Withheld-ACK progress plateaued at 77,824 bytes and four
  sampled mailbox lengths were zero; at most two chunks were outstanding.
- Results are bounded fixture evidence, not a universal kernel pipe capacity,
  a whole-VM benchmark, Linux validation or production lifecycle acceptance.
- `rtk proxy asdf exec elixir --version` reconfirmed root Elixir 1.20.3 / OTP28.
  Six reference checkouts match the manifest, are clean and have their recorded
  license files. Existing xerj query still works; new-reference indexing is open.
- Code ownership: writer only `spikes/transport/` and its agent log; root only
  reference manifest/ignores, AGENTS, README, plan/todo, research, old-spike warning
  and worklogs. No application code, dependencies, source specs or user data changed.

## Local main integration and cleanup

- Integrated to local main `4f5a3175682e54e793c0c0e8d52d632be235136c` after
  independent writer/source review. No remote push.
- On main, `rtk proxy asdf exec mix test`: 181 passed, 1 existing Linux-only skip,
  6.9s, seed 52599. Tests exclusively create fresh data; no user DB was used.
- On main, `rtk proxy asdf exec elixir spikes/transport/transport_test.exs`:
  12 passed, 1.5s, seed 15416. Same 77,824-byte plateau, four empty mailboxes,
  two pending chunks and stable `[20, 8]` reader stacks at 2/8 MiB.
- `rtk proxy asdf exec mix compile --warnings-as-errors`,
  `rtk proxy asdf exec mix format --check-formatted`, and explicit format check
  of both transport `.exs` files passed. `git diff --check` and changed-document
  local-link validation passed. Assets/browser and the unchanged older spike
  suites were not rerun for this fixture-only increment.
- Clean writer worktree archived using the Codex app. Git now lists only main
  and the retained primary managed checkout; deleted both merged `codex/` branches.
  Primary checkout is clean/detached at main, retained because the app designates
  it primary. Reference checkouts and external Mix cache remain available.

## Next step

Completed the isolated transport proof. Next implementation gate is OS lifecycle:
evaluate the pinned guardian against stubborn descendants after leader exit and
helper/backend loss, with explicit cleanup acknowledgment and preserved worktrees.
Keep real providers disabled until ownership, secrecy and durable launch/recovery
contracts are proved. Retry xerj indexing only after disk capacity is resolved.
