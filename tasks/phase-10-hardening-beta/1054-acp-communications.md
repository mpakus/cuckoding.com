---
status: done
owner: codex
started_at: 2026-09-27
completed_at: 2026-09-27
worklog: worklog/2026-09-27-1054-acp-communications.md
---

# 1054 — Rebuild agent communication around ACP

User goal: rebuild our communications to Agent Client Protocol (ACP).

- [x] Replace process-exit/log-based communication for supported coding agents with a shared ACP session boundary used by planning, proposal review, board control, delivery, and follow-ups.
- [x] Negotiate protocol/capabilities; implement initialization, session creation/loading, prompts, updates, cancellation, and bounded typed errors. Correlate requests and refuse stale/cross-session responses.
- [x] Keep protocol stdout separate from diagnostics. Bound frames, requests, output and time; redact before persistence and discard hidden reasoning before logs/events.
- [x] Preserve run-owned configuration, saved authorization, model selection, role grants, protected paths, and independent completion/review gates. Unsupported capability requirements fail before work starts.
- [x] Persist session identity and public progress before broadcasting. Account for reported usage without double counting; retain unavailable values honestly.
- [x] Preserve pause/stop, verified process cleanup, sleep/restart reconciliation, and evidence. Do not blindly replay interrupted prompts or change historical runs.
- [x] Integrate supported Codex, Claude Code, and Cursor runtime transports, including required reviewed bridges and explicit executable/version validation; keep unavailable runtimes explicit.
- [x] Add protocol, host-process, permissions, redaction, workflow, and recovery regressions; run formatter/compiler/static/full relevant gates and record real-provider evidence separately.
- [x] Update architecture decision, runtime/security/flow/development documentation and README to match the actual migration and remaining limitations.

No A2A network service, autonomous policy expansion, global runtime configuration edits, or new orchestration framework is needed for this goal.

## Progress

- Shared ACP framing/session client and separated host stdio are implemented with focused fixtures.
- Planning and delivery (including board control) accept streamed ACP results through their common adapter boundary.
- Cursor launches native ACP; Codex and Claude launch pinned app-packaged ACP bridges with policy patches. Modern configuration and native structured-output handoff are implemented.
- Run/board Stop closes admission before ACP cancellation; startup negotiation releases the launch lock, pause retains pending negotiation, and late observations preserve controls. Live recovery checks the protocol owner and recorded process identity. Startup/wake ownership and terminal-history regressions pass. Authenticated Codex/Cursor read-only turns, real Codex planning and an isolated Codex board batch pass. Cursor review permission refusal is recorded separately. The developer bundle passes packaging/sterile verification and was restarted. Physical sleep, authenticated Claude, broader provider runs and signed distribution remain external acceptance items.
- Integrated into local main and rebuilt/restarted the developer app from code commit `60267f5`. No remote publication. Existing application run history was preserved.
- Final gates: 417 tests and 10 properties, bridge/node checks, Ruby packaging/restart tests, Rust checks and sterile release verification passed. Native interactive UI inspection timed out; authenticated HTTP/LiveView rendering is recorded separately.
