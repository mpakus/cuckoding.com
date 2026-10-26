# Native process owner — 2026-10-26

- Baseline609df38; isolated codex/boss-process-owner. Own native guardian,
  Process API, build hook and focused tests only. Root owns app integration/docs.
- RTK + Ponytail. No provider calls, auth-file access or reference-code copying.
- xerj `ConfigureTreeCancellation WaitDelay` found AO command wrappers. Read
  `backend/internal/process/tree_unix.go` at Apache-2.0 SHA
  7193eff4e08f1481944845ee058fe6fd18930b6d. Read NetRunner
  `c_src/shepherd.c:492` at Apache-2.0 SHA
  5f12e06aabb70f2aafde023bf547aaaa6f8fcb36. Adopt explicit owned process group;
  reject stopping escalation when only its leader exits.
- Native guardian retains the leader with waitid WNOWAIT until group cleanup;
  separate credit-limited4096-byte pipes, real EOF/exit/signal and cleanup result.
  One owned callback worker is separate from Stop/deadline control. Prompt stdin,
  fixed errors, no raw output logging. Natural tail grace precedes forced cleanup.
- macOS group enumeration uses libproc; other OSes fail closed for this first
  production slice. Detached/new-session descendants are outside group ownership.
  Helper loss is unknown; no saved-PID signal/retry is attempted by this API.
- Elixir1.20.3/OTP28 confirmed through asdf. No production provider called.

## Implementation and review

- `Boss.Agents.Process.run/3` owns a separate coordinator and persistent callback
  worker. Caller mailbox/trap_exit is untouched; :stop reaches control while a
  callback is blocked. Success waits for callback ACKs, both genuine EOFs,
  native wait status and explicit group-empty receipt. Exit137 is not SIGKILL.
- Private packet4 Port, input≤1MiB through stdin, per-stream4096-byte credit,
  fixed32KiB native queue and bounded output/runtime. No prompt in argv or logs.
- Guardian retains leader unreaped, pauses natural500ms tail grace during
  consumer backpressure, and escalates TERM→KILL even after leader exit. Cleanup
  is bounded and returned separately from cancellation/timeout/CLI exit status.
  Forced lingering-child cleanup is failed, not ordinary transport completion.
- Independent review caught natural-grace expiry during slow consumption and a
  POLLHUP busy loop on uncredited FDs. Paused grace plus fd=-1 polling fixes are
  covered by finite-output/slow-callback and stalled-output regression tests.
- Build hook compiles the helper at mix compile time with -Wall -Wextra -Werror,
  not on Start. No runtime dependency or lockfile change. NonmacOS execution
  returns unsupported; native build is skipped there.

## Verification

- `rtk proxy cc -std=c11 -D_DARWIN_C_SOURCE -Wall -Wextra -Werror -O2 -fsyntax-only c_src/boss_guardian.c`: passed.
- `rtk proxy asdf exec mix deps.get`: fetched existing locked dependencies only;
  reported existing Bandit1.13.1 advisories to root. No upgrade or lock change.
  Initial dependency compilation emits Plug's existing deprecated-xref warning.
- `rtk proxy asdf exec mix test test/boss/agents/process_test.exs`:
  first14 passed, review regression15 passed, expanded18 passed, final **20 passed**
  in8.7s (seed535831). Includes binary/large stdin, independent early EOF, natural
  inherited tails, lingering child after leader exit, TERM→KILL, cancelled exit0,
  stalled consumer Stop/runtime, helper SIGKILL unknown, whole-BEAM SIGKILL,
  caller loss,20 repeated calls,12 immediate Stop starts and8 startup caller losses.
  Exclusively created fixture roots and own-PID command identity guard cleanup.
- `rtk proxy asdf exec mix compile --warnings-as-errors`: passed.
- `rtk proxy asdf exec mix format --check-formatted mix.exs mix/compile_guardian.exs lib/boss/agents/process.ex test/boss/agents/process_test.exs`: passed.
- Independent reviewer:5/5 stalled-callback + TERM-ignoring leader/child + killed
  caller trials cleaned coordinator/callback/helper/leader/child in231–254ms.
  Read-only reviewer approved ownership, EOF, credit and PGID scope.
- Root owns combined application/UI tests and final main merge/cleanup.

## Limits and handoff

- Group ownership does not contain setsid/setpgid escapes. Helper SIGKILL or
  missing receipt returns unknown; this API never signals a persisted PID.
- No Linux execution proof, durable reconciliation/receipt file, model/tool
  protocol, provider auth or task success is implemented by this low-level API.
- Generated priv/native/boss_guardian is not committed; root owns its ignore rule.
- Ready for root integration and combined suite. Keep unknown cleanup quarantined
  and retain the workspace; do not retry automatically.
