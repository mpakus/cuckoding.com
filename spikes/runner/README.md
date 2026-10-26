# Runner feasibility spike

An executable experiment for BOSS-000a, **not the production runner**. The
candidate uses erlexec 2.5.0 (exact Hex version, no transitive runtime dependencies) and the
built-in Elixir JSON decoder. No application dependency or generic adapter API is
introduced. It requires Elixir 1.20.3 / OTP 28, Python 3 for deterministic fixtures
and a C++17 compiler for erlexec's native helper.

```sh
rtk proxy env ASDF_ELIXIR_VERSION=1.20.3-otp-28 asdf exec elixir spikes/runner/runner_test.exs
```

If your PATH bypasses asdf, invoke the selected installation explicitly. The
verified binary on the development machine was
`/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin/elixir`.

## What was selected and rejected

| Candidate | Evidence | Decision |
| --- | --- | --- |
| Standard `Port` | The executable comparison captures stderr by merging it with stdout, contaminating JSONL. `open_port/2` offers no independent stderr pipe or process-tree ownership primitive. | Insufficient alone; avoid inventing a custom native process supervisor. |
| ExCmd 0.18.0 | Official stream and Process APIs support demand-driven stdout, but public stderr options are console/merge/disable and `read/2` reads stdout. Introductory text about selective stderr is broader than its actual public API. No live ExCmd comparison was run. | Does not meet separate-stream capture without additional transport machinery. |
| erlexec 2.5.0 | Executed separate streams, direct argv, exit/signal status, linked ownership and process-group TERM/KILL. | Best candidate for this spike; **not approved for production** until the gaps below are resolved. |

Official sources: [OTP 28 `open_port/2`](https://www.erlang.org/docs/28/apps/erts/erlang.html#open_port/2),
[ExCmd stream](https://hexdocs.pm/ex_cmd/0.18.0/ExCmd.html),
[ExCmd Process](https://hexdocs.pm/ex_cmd/0.18.0/ExCmd.Process.html),
[erlexec command options](https://hexdocs.pm/erlexec/2.5.0/exec.html#t:cmd_option/0).
Implementation checks used the downloaded erlexec 2.5.0 package's
`src/exec.erl:1250` and `c_src/exec_impl.cpp:1400`.

## Verified behavior

- Split JSONL is reassembled; malformed JSON, non-object events, oversized
  lines, and unterminated final lines fail explicitly.
- Stdout remains separate from stderr. Nonzero or signal exit overrides a
  terminal event; exit zero without `turn.completed` is not completion.
- A cancellation/timeout cause survives erlexec's intentional normalization of
  requested stop to exit zero. Idle and absolute timeout are independent.
- Application retention is bounded: line limit 16 KiB, output limit 1 MiB,
  1,024 events and a 1 KiB diagnostic sample by default. Only event-type counts
  are retained. Limits terminate a run; they do not silently discard errors.
- Normal descendants in the owned process group are stopped, including a
  leader/child ignoring TERM. The helper escalates to KILL after one second.
- Killing the Elixir owner and killing an entire separate BEAM VM both cleaned
  up the ordinary fixture group. Whole-VM death leaves the fixture's persisted
  `started` intent unchanged. Nothing retries it automatically.

The fixture deadline is 30 seconds as a final safety bound. Tests explicitly
clean only their own surviving fixture PIDs. No provider invocation is part of
the test suite.

## Known boundaries — tests deliberately expose them

- **Unbounded intermediate mailboxes:** retained parser state is bounded, but
  erlexec pushes output through native/Erlang queues without demand-driven
  backpressure. Passing the flood test does not prove bounded VM memory.
- **No explicit stdout/stderr EOF:** the native helper drains currently readable
  output before sending exit and closes descriptors. Its public protocol does
  not prove independent EOF from both streams, especially with inherited pipes.
- **Detached descendants escape:** a child starting a new session survives group
  cancellation. A stubborn child also survives the helper's TERM-only group
  cleanup after its leader exits normally. Both are executable negative tests.
  Consequently `:completed` here means only observed CLI terminal + exit zero,
  never verified BOSS delivery or proof that the process tree is empty.
- **Crash recovery remains application work:** a plain PID is not safe persisted
  identity. No SQLite reconciliation, safe adoption, restart, retry, or reattach
  is implemented. Keep an unresolved run interrupted/attention until ownership
  and worktree effects are reconciled; never kill an arbitrary saved PID.
- **Platform coverage:** local Apple Silicon macOS only. Linux, packaging,
  helper-crash/host-crash behavior and clean-machine compilation are unverified.

- **Post-stop cleanup deadline:** source review found that this old loop checks
  its cleanup timeout only in `receive after`; continuously queued output can
  postpone that branch. Its runtime deadline checks stop once a cause is saved.
  The separate [BOSS-007a transport experiment](../transport/README.md) checks
  deadlines before each receive and exercises stalled/flooding output. This old
  spike remains unchanged and must not supply production timeout guarantees.

Do not move this script into the application unchanged. BOSS-007 needs an
explicit transport/backpressure decision, stream completion proof and a
strategy for surviving descendants before production acceptance.

## One opt-in live probe performed on 2026-10-25

Codex 0.146.0 ran **once** in a detached worktree of a newly created temporary
repository. Arguments: `exec --ignore-user-config --ephemeral --sandbox read-only
--json`; prompt: `Reply only BOSS_SPIKE_OK. Do not use tools, inspect files, or
change anything.` The runner used `timeout: 60_000`, `idle_timeout: 45_000`,
`line_limit: 262_144`, `output_limit: 1_048_576`, `event_limit: 128`.

Observed exit `0`, five events: `thread.started`, `turn.started`, two
`item.completed`, and `turn.completed`; 637 stdout bytes and 454 stderr bytes.
The scratch worktree remained clean. No raw transcript or auth-file content was
read or saved in this repository; only event types/counts, exit and byte counts
were recorded. This proves CLI streaming on this machine, not arbitrary tasks,
auth/quota recovery, tool execution, approval handling or provider reliability.
Do not automatically repeat a paid invocation.

Claude Code 2.1.142 was probed with `--version` and `--help` only. Help confirmed
`--print`, `--output-format stream-json`, `--include-partial-messages` and
`--json-schema`; no Claude model request or authentication inspection occurred.
