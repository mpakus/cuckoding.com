# Demand-driven transport experiment

This BOSS-007 experiment checks Exile **0.15.0** as a byte transport. It does not
add an application dependency, a coding adapter, task execution or process-tree
ownership. No model, login command, credential file or real prompt is involved.

Run from the repository with Elixir 1.20.3 / OTP 28 and a C compiler:

```sh
rtk proxy asdf exec elixir spikes/transport/transport_test.exs
```

`Mix.install` downloads/builds Exile in Mix's external cache. The only transitive
dependency in this run was build-time `elixir_make` 0.10.1. The fixture is compiled
into an exclusively created scratch directory, never the application release.
All fixture processes have a 30-second alarm; the forked child has its own
5-second alarm. Tests remove only their own scratch roots and identify any
surviving fixture by both PID and its exclusive root in argv before signalling it.

## Mechanism and observed result

One coordinator remains available for Stop and deadlines. A linked owner starts
Exile with `stderr: :consume`, transfers stdout/stderr to two readers, closes
stdin and waits for the real exit status. The owner remains alive after exit so
its death cannot prematurely close output pipes held by descendants.

Each reader requests at most 4096 bytes and waits for an ACK before reading
again. At most two chunks, 8192 bytes total, are outstanding to the optional test
consumer. The coordinator retains counters and incremental hashes, not raw
output history. This relies on the consumer respecting the ACK contract; it
cannot bound a consumer that deliberately retains acknowledged chunks.

The coordinator accepts completion only after **both actual read EOFs and the
exit status**. `outcome: :complete` means the transport drained, including when
`exit_status` is nonzero. It never means task success. Forced close, reader
failure or Stop cannot substitute for EOF. The initiating cause remains separate
from `cleanup: :incomplete`. `cleanup: :exit_observed` means only that the direct
process's integer status was received; it does not prove descendant cleanup.
Deadlines are checked before every receive, so a
continuously nonempty mailbox cannot postpone them.

Local Apple Silicon macOS results: **12 tests passed** in 1.4 seconds. Checks cover
binary stream separation, real nonzero status, each stream closing early, late
inherited pipe output after the leader is already dead, output limits, quiet and
busy timeouts, Stop while a consumer withholds ACK, and TERM handled with exit 0
while the result remains `:cancelled`.

- Under withheld ACKs the flood fixture stopped advancing at **77,824 bytes**;
  two samples 100 ms apart were equal. All four sampled BEAM mailbox lengths
  were zero; only two chunks were outstanding. This is observed kernel-pipe
  backpressure, not a universal pipe-capacity constant or a whole-VM memory proof.
- Sustained acknowledged reads exposed a real implementation error: a `catch`
  around the recursive reader grew stacks from `[3602, 512]` words at 2 MiB to
  `[14354, 2048]` at 8 MiB. Moving catch into the individual read operation made
  both samples `[20, 8]`; the regression remains in the suite.
- Exile/Port exit notification was delayed with descendant-held pipes, consistent
  with inherited Port control descriptors. The test proves the native parent is already
  dead, then releases a child to write its exact late tails. Immediate independent
  leader-exit notification is not claimed.

An independent review also killed a reader with a pending chunk (failure, no
synthetic EOF), stopped a still-live process after both genuine EOFs (cancelled,
status 143), and ran 100 cancelled-flood → binary pairs from the same caller with
`trap_exit: false`. The caller survived, binary hashes/status stayed correct and
its final mailbox was empty.

## Source and remaining gates

Exile v0.15.0's annotated tag resolves to commit
`a4f29f31adc3c6bd2fe43ac62dc07a9eeb3bf413`, Apache-2.0. The installed Hex package's
`lib/exile/process.ex` and `c_src/exile.c` match that pinned reference byte-for-byte.
Hex outer checksum:
`eb520ea43e26793abff619d3bc3fda358b6bed5ea8ed4d3715f66b4b27ca438b`.

- [Process API](https://github.com/akash-akya/exile/blob/a4f29f31adc3c6bd2fe43ac62dc07a9eeb3bf413/lib/exile/process.ex):
  pipe ownership, separate reads, await/exit handling. `await_exit` closes pipes
  owned by its caller, so readers must own the output pipes first.
- [NIF](https://github.com/akash-akya/exile/blob/a4f29f31adc3c6bd2fe43ac62dc07a9eeb3bf413/c_src/exile.c):
  nonblocking reads, a maximum 65,535-byte native read, and `enif_select` on
  EAGAIN. [Pipe](https://github.com/akash-akya/exile/blob/a4f29f31adc3c6bd2fe43ac62dc07a9eeb3bf413/lib/exile/process/pipe.ex)
  maps a real zero-byte read to EOF; closing the pipe gives an error instead.
- [Watcher](https://github.com/akash-akya/exile/blob/a4f29f31adc3c6bd2fe43ac62dc07a9eeb3bf413/lib/exile/watcher.ex)
  acts on a cached direct PID. It provides neither safe persisted identity nor
  group containment; its BEAM-resident cleanup cannot survive a VM SIGKILL.

**Do not promote this experiment unchanged.** Detached or stubborn descendants,
VM/helper loss, safe process identity, crash recovery and packaging remain open.
The integer exit status cannot distinguish a normal exit 137 from signal-based
137. Exile's default GenServer reports can expose argv/env or pending stdin;
real prompts and secrets require a separately verified secrecy boundary. Its
temporary socket handshake and NIF failure boundary also need a production
review. This run does not establish Linux compatibility or adversarial memory
safety of the native dependency.

The next slice is a lifecycle/secrecy decision using these transport tests as
gates. Keep task execution closed until that decision and its failure tests pass.
