# R011a · Explain an already-running UI server

Claimed on clean main 328c4f7, branch fix/R011a-dev-server-lock.
Ponytail full 5.1.0 (MIT), local-runner, security-review and quality-gates.
RTK proxy preserves exact Python/process evidence and source output.

The previous turn's source server still owns `.ccoding/ui-dev/shell.lock`:
Python PID 60783, its RTK child 60790 and BEAM 60791, started 2026-10-10 14:45
local time; listener 127.0.0.1:4000 and repository working directory verified.
The second launcher fails at nonblocking flock before it launches anything.
Scope: explain this specific error, preserve the ownership guard, test actual
OS lock contention/release and free this assistant-owned server for the user's
terminal. No auto-adoption, token sharing, lock deletion or production changes.

## Change and evidence

The launcher catches only `BlockingIOError` at the ownership flock and closes its
unused descriptor. It explains the active owner, browser/Ctrl-C choices and that
another port shares the same data; other I/O failures remain errors. No launch
file or child is created on contention. README, AGENTS, Development and Testing
document the single-owner workflow and assistant-to-user terminal handoff.

- `rtk proxy python3 test/dev_server_test.py`: one passing real-OS regression in
  a temporary checkout. Held-lock rejection, readable error, no traceback/raw errno,
  original file/data preservation, and successful acquisition after release.
- `rtk proxy kill -TERM 60783`: signalled only the verified assistant launcher.
  Its existing handler used `/shell/quit`, waited for cleanup and released the lock.
  A smoke attempted during that short cleanup correctly printed the new message;
  after exit the same command succeeded.
- `rtk proxy env CCODING_DEV_PARENT_CANARY=must-not-reach-child bin/dev.server --smoke --port 0`:
  passed on port 62624, including MCP, clean environment, normal session/replay,
  toolbar/reload and foreign-origin checks, then exited normally.
- Standard-library assertions confirmed original PIDs/process group gone, ports
  4000/62624 closed, data retained and the original lock file reusable. No running
  developer instance is left competing with the user's next launch.
- `rtk git diff --check` and changed Markdown link validation passed.

Commit/fast-forward into local main, no push. No Elixir/Rust implementation change;
their full suites/native rebuild and physical sleep tests were not repeated.
Provider/Tidewave account usage was not exercised. No browser changes required.
