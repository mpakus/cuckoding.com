# R011d — Lock-free source-launcher shutdown signals

Claimed on `fix/R011d-launcher-signals`, after R100b implementation/integration.
The R100b copied QA launcher used the existing source launcher's Event-based
signal handler. It remained alive holding its private data lock after its backend
and listener exited, despite Ctrl-C/normal SIGTERM. Only that verified childless
test launcher was terminated after identity checks and a database backup.

Reproduce the potential non-reentrant Event lock interleaving before changing
code. Use disposable copied script/data roots and fake backend transport; a
separate owned test process bounds a deliberately stuck signal handler. Preserve
all ordinary launch/session/heartbeat/cleanup and data-lock rules. Ponytail full
5.3.2 MIT, RTK, security, menubar-shell and quality guidance apply. No provider
usage, profile import, original workspace access or publication.

## Reproduction and fix

`threading.Event.wait` briefly holds a non-reentrant condition. A Python signal
delivered in that window ran `stopped.set()` from the same main thread and waited
forever on its own lock. The isolated launcher regression reproduced that exact
interleaving with real SIGINT/SIGTERM, a controlled Event condition and fake
backend/transport; no provider or real app data was touched. Before the fix, both
idle signal cases deadlocked. READY/bootstrap cases also revealed post-stop
bootstrap/browser admission. Six of eight interleavings failed on old source.

The signal handler now only assigns a nonlocal boolean. Startup/READY and returned
bootstrap/handoff responses check it before further admission. Added two handoff
interleavings in review: both failed before the browser-open fence, then passed.
The five-second heartbeat
loop checks it after sleeping, then the existing finally block owns the same
bounded backend cleanup. No new framework, timer, process or permission grant.

## Verification

- `rtk proxy python3 test/dev_server_test.py`: **2 tests passed**, including the
  original real OS lock/contention/reuse case and ten signal interleavings.
  Signal fixtures cover repeated SIGINT and SIGTERM at startup, READY, bootstrap, handoff
  and idle critical-section boundaries. They check no late bootstrap/browser/
  heartbeat work, one backend cleanup, removed bootstrap and released data lock.
  The old deadlock is bounded by a parent-owned Python subprocess; the fake backend
  cannot signal a process group or open a browser. No provider/native process runs.
- Review caught an existing test-filename collision; the original OS lock test
  was retained in full alongside the new regression. The task was renamed R011d
  because historical R011b belongs to Tidewave removal. No historical task changed.
- Removing the post-bootstrap stop fence failed its signal cases. Restored exact
  source in `finally`, then all tests passed. No preview was live during mutation.
- Real `rtk proxy env PATH=<pinned> bin/dev.server --no-open --port 0` launched on
  port 61644. Ctrl-C completed terminal shutdown (outer RTK exit 1); listener and
  exact data lock were free. No forced signal or lock-file deletion.
- A second real launch on 61676 was stopped using normal SIGTERM after checking
  the exact Python lock owner, executable, start identity and cwd. It completed
  exit 0; listener and data lock were free. No forced signal.
- `rtk proxy env PATH=<pinned> bin/dev.server --smoke --port 0`: passed bootstrap,
  browser handoff/replay/origin checks, dev reload, strict app CSP and no Tidewave;
  normal cleanup completed on port 61902. All fourteen before/after developer-data
  table hashes stayed identical; integrity/FKs and exclusive lock availability
  passed. Only separate `.ccoding/ui-dev` settled fixtures were used.

Pinned PATH was `/Users/mpak/.cargo/bin:/Users/mpak/.asdf/installs/elixir/1.20.3-otp-28/bin:/opt/homebrew/opt/erlang/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.
Private command/proof artifacts are `.ccoding/r011d-*`. The initial test harness
was corrected to supply subprocess constants before the meaningful red run; no
product check was suppressed. Whitespace and local documentation links pass.

The change is the developer Python launcher only. No Elixir/Rust/app bundle input
changed, so their R100b 557/98 passing evidence is historical here, not claimed
as rerun. No bundle rebuild, paid inference, native-provider cleanup, physical
sleep or real-account beta acceptance is claimed. Original saved profiles/data
and unrelated `Untitled.md.age` remain untouched. Local integration pending.
