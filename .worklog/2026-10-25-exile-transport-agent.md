# BOSS-007 transport experiment — 2026-10-25

- Baseline `0a54f79`; isolated `codex/boss-exile-transport`. Own only
  `spikes/transport/` and this log. Root owns application/shared docs.
- RTK, Ponytail and TDD; metadata/provider execution is outside this experiment.
- Research query: `xerj search --prefix bossrefs 'stdout stderr backpressure EOF
  process pipe' -k 4 --full 1400`. Read Agent Orchestrator
  `backend/pkg/agentruntime/process.go` and ACP `process.go`, pinned
  `7193eff4e08f1481944845ee058fe6fd18930b6d`, Apache-2.0. Adopt independent pipes
  and a separate exit barrier; reject discarded stderr and unproven tree cleanup.
- Read Exile 0.15.0 source, peeled tag commit
  `a4f29f31adc3c6bd2fe43ac62dc07a9eeb3bf413`, Apache-2.0:
  `lib/exile/process{.ex,/operations.ex,/pipe.ex,/exec.ex}`, `c_src/exile.c`,
  `c_src/spawner.c`, `lib/exile/watcher.ex`, and upstream process tests.
  Actual reads use nonblocking descriptors, max 65535 bytes and `enif_select`.
  `await_exit` closes caller-owned pipes: transfer output pipes to reader workers
  first. Keep the Exile owner alive after exit until both genuine EOFs arrive.
- ExCmd 0.18.0 `914d68f84d38903b4e9cb7075e6cdaae542d55b0` lacks separate
  stderr consumption. erlexec 2.5.0 pushes output without demand and closes pipes
  on exit. MuonTrap 2.0.0 `e530079a1ad703a45862de5f0908a25b3b7a65d2`
  has ACK flow control but captured streams share one untagged byte channel.
- First slice: two readers, one outstanding <=4096-byte chunk each, ACK only
  after consumption. Coordinator keeps counters/hash states, not source logs.
  Success means transport drained plus observed exit, never verified delivery.
- Explicit remaining gates: Exile only kills a direct PID; no process-group or
  BEAM-SIGKILL guarantee. Dependency crash/status reports can expose argv/env or
  pending stdin; no real prompts/secrets are used here. No runtime dependency
  added to BOSS. Reference code is read-only; implementation is independent.

## Executed evidence

- `rtk proxy asdf exec elixir --version`: Elixir 1.20.3, OTP 28 / erts 16.4.
- RED: `rtk proxy asdf exec elixir spikes/transport/transport_test.exs` against
  the stub failed all 10 tests (4.1s). Exile 0.15.0 and elixir_make 0.10.1 compiled
  in Mix's external cache; no main mix.exs/mix.lock change.
- Initial implementation passed 9/10. The failing assertion expected exit
  notification before descendant-held EOF. Actual tails and status were correct;
  notification was delayed with inherited pipes, consistent with inherited Port
  control descriptors. Replaced that unsupported
  assumption with a fixture barrier proving the native parent is already dead
  before its child is permitted to write late output.
- Review added explicit first outstanding chunk before stalled-consumer timeout,
  TERM-handler exit0 preserving cancelled cause, and a sustained stack regression.
  The latter failed meaningfully: 2MiB stacks `[3602,512]`, 8MiB `[14354,2048]`.
  Isolated catch around the individual read, preserving the tail-recursive loop.
- GREEN: same command passed **12 tests in 1.4s**. Stalled producer progress
  plateaued at 77,824 bytes, four sampled mailboxes were all0, max2 pending chunks.
  Sustained stacks were `[20,8]` at both2MiB and8MiB. These are fixture observations,
  not a whole-VM memory guarantee.
- Reader chunk requests are constrained to1..4096. Original stop cause is kept
  separately from cleanup timeout. Workers are unlinked/monitored before teardown;
  messages are scoped to this run's owner and flushed before restoring trap_exit.
- App `mix format` initially refused missing dev Ecto dependencies in this new
  worktree. Used Elixir's formatter directly, without fetching app dependencies:
  `rtk proxy asdf exec elixir -e 'Enum.each(System.argv(), fn path ->
  File.write!(path, Code.format_file!(path)) end)'
  spikes/transport/transport.exs spikes/transport/transport_test.exs`.
- Installed Hex Process/NIF source was diffed against the pinned reference;
  both match. Exile Hex outer checksum is
  `eb520ea43e26793abff619d3bc3fda358b6bed5ea8ed4d3715f66b4b27ca438b`.
- Independent read-only reviewer completed adverse checks: killing a stdout
  reader with a pending chunk returned failed/incomplete, EOF false and no exit
  status. Stop after both genuine EOFs while the direct process lived returned
  cancelled/status 143. A single caller with trap_exit false survived 100
  cancelled-flood → binary pairs with correct hashes, status, 5+5 bytes and a
  final mailbox length of 0. No source changes requested.
- Final focused rerun: **12 passed in 1.4s**, seed 712199; the same 77,824-byte
  plateau, all-zero mailbox samples and `[20,8]` stack samples were observed.
  Direct `Code.format_file!` comparison passed for both Elixir files. The fixture
  compiled with `-Wall -Wextra -Werror -O2` as part of this run.
- Final README claims review found no blockers. Staged whitespace verification
  caught an extra formatter-added newline; removed it using the formatter's own
  output and repeated the staged check.
- No application tests, browser checks or provider invocation belong to this
  isolated experiment. Next step: parent integrates the reviewed spike and runs
  its focused suite from main; lifecycle and secrecy remain closed production
  gates before any task execution adapter.
