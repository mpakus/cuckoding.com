# 1027 — Guided saved-agent setup

Claimed 2026-09-21. Acceptance criteria are the checklist in the task file.

Initial state: `main` clean at `04ae814`; XERJ node at loopback:9200 unavailable. Inspected the current LiveView, `RuntimeConfiguration`, `ProjectOnboarding`, `AgentRuntime`, Codex/Cursor adapters, and focused tests. Reference: pinned MIT Hydra `electron/agents/ProviderModelCatalog.ts:171-190` reads `model/list` effort metadata; `electron/agents/providers.ts:128-137` passes validated effort as a Codex config argument. Adapt the behavior, not code: Cuckoding retains bounded model metadata, explicit saved-account authorization, validated argv, and durable run snapshots.

Official contract checked: [Codex app-server model/list](https://learn.chatgpt.com/docs/app-server) exposes `supportedReasoningEfforts` and `defaultReasoningEffort`; [Codex config basics](https://learn.chatgpt.com/docs/config-file/config-basic) documents `model_reasoning_effort`.

Implementation: the LiveView now guides creation through three steps; authorization remains in the app-owned provider profile, and a partially set-up agent remains saved if the wizard closes. Installed CLI lookup uses PATH plus the user's local bin and standard macOS binary directories, then accepts a validated absolute manual path. Codex `model/list` normalizes only bounded visible model IDs, labels, and allowlisted reasoning levels. The selected level is validated again at the adapter boundary and passed as an argv config override; different roles sharing one account retain different levels even when the authentication probe is cached. Other runtimes use their defaults until a reviewed reasoning override exists.

Verification:

- `rtk mix format` on changed Elixir files: passed.
- `rtk mix test test/cuckoding_web/agent_settings_live_test.exs test/cuckoding_web/project_edit_live_test.exs test/cuckoding/adapters/codex_test.exs test/cuckoding/adapters/stable_stubs_test.exs test/cuckoding/shared_agent_profile_test.exs test/cuckoding/project_workflow_test.exs`: 33 tests, 0 failures before final wizard edge-case additions.
- `rtk mix test test/cuckoding_web/agent_settings_live_test.exs`: 3 tests, 0 failures, including async sign-in/model discovery and setup-only back/forward.
- `rtk mix quality`: format check, unused-dependency check, compile with warnings as errors, 293 tests and 10 properties (0 failures), strict Credo (no issues), Sobelow (no findings), and Hex audit (no retired/advisory packages) passed. The expected plugin-supervisor fixture crash is logged during its recovery test; it is not a suite failure.
- Browser visual QA against the already-running signed app at `127.0.0.1:54722` was not performed: it is a separate running build and no authenticated browser tab was available in this task. The LiveView flow was exercised through server-rendered tests; restart/rebuild the app to load this source change.

No migration or provider credential change. Real provider sign-in/refresh and authenticated cross-project execution remain task 1018 acceptance gates; no paid provider run was launched.
