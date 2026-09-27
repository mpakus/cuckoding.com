---
status: in_progress
owner: codex
started_at: 2026-09-27
worklog: worklog/2026-09-27-1054-acp-communications.md
---

# 1054 — Rebuild agent communication around ACP

User goal: rebuild our communications to Agent Client Protocol (ACP).

- [ ] Replace process-exit/log-based communication for supported coding agents with a shared ACP session boundary used by planning, proposal review, board control, delivery, and follow-ups.
- [ ] Negotiate protocol/capabilities; implement initialization, session creation/loading, prompts, updates, cancellation, and bounded typed errors. Correlate requests and refuse stale/cross-session responses.
- [ ] Keep protocol stdout separate from diagnostics. Bound frames, requests, output and time; redact before persistence and discard hidden reasoning before logs/events.
- [ ] Preserve run-owned configuration, saved authorization, model selection, role grants, protected paths, and independent completion/review gates. Unsupported capability requirements fail before work starts.
- [ ] Persist session identity and public progress before broadcasting. Account for reported usage without double counting; retain unavailable values honestly.
- [ ] Preserve pause/stop, verified process cleanup, sleep/restart reconciliation, and evidence. Do not blindly replay interrupted prompts or change historical runs.
- [ ] Integrate supported Codex, Claude Code, and Cursor runtime transports, including required reviewed bridges and explicit executable/version validation; keep unavailable runtimes explicit.
- [ ] Add protocol, host-process, permissions, redaction, workflow, and recovery regressions; run formatter/compiler/static/full relevant gates and record real-provider evidence separately.
- [ ] Update architecture decision, runtime/security/flow/development documentation and README to match the actual migration and remaining limitations.

No A2A network service, autonomous policy expansion, global runtime configuration edits, or new orchestration framework is needed for this goal.

## Progress

- Shared ACP framing/session client and separated host stdio are implemented with focused fixtures.
- Planning and delivery (including board control) accept streamed ACP results through their common adapter boundary.
- Cursor launches native ACP; Codex and Claude launch pinned app-packaged ACP bridges with policy patches. Modern configuration and native structured-output handoff are implemented.
- Existing process pause/cleanup remains in use; connecting board/run Stop directly to ACP cancellation, complete recovery conformance, bridge/native conformance, and authenticated/native acceptance remain open.
- No local-main integration, remote publication, native rebuild or application restart has occurred for this task.
