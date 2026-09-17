# Implementation Readiness

Prepared on 2026-09-17 from revision `897bc30a0712bdd68bec745daa8a1b987190df57`. This repository is structurally ready for Phase 0 discovery spikes. It is not yet approved for Phase 1 product implementation.

## Repository baseline

- Commit `b101eee` deliberately removed the v1 application. The current tree is a clean-slate planning, policy, task, and tooling baseline; do not restore or copy v1 wholesale.
- Repository skills are at `.agents/skills/` and example Cuckoding configuration is at `.cuckoding/`, matching `AGENTS.md`, `README.md`, and `docs/CONFIGURATION.md`.
- No `mix.exs`, Phoenix application, database, assets, or native shell source exists yet. That is expected until task 0101.
- `inspire.jpg` remains untracked because its source and redistribution license are unknown. It is not an implementation input.
- The generic GitHub MCP example remains disabled because its npm package is not exactly pinned with integrity evidence.

## Verified local toolchain

| Tool | Verified version/status | Needed for |
| --- | --- | --- |
| macOS | 27.0, Apple Silicon | supported MVP host |
| Erlang/OTP | 28 / ERTS 16.4 | Phoenix release |
| Elixir / Mix | 1.19.5, compiled for OTP 28 | pinned project runtime; installed during task 0006 |
| Git | 2.51.1 | worktrees and branches |
| SQLite | 3.54.0 | durable local store |
| Rust / Cargo | 1.97.1 installed; task 0003 pins 1.90.0 | Tauri shell; 1.90 avoids a macOS 27 stripped proc-macro defect during the discovery build |
| Xcode / Swift | Xcode 27.0 / Swift 6.4 | macOS shell and signing experiments |
| Node / npm | 24.13.0 / 11.6.2 | Phoenix assets and Tauri tooling |
| Claude Code | 2.1.142 | available adapter candidate |
| Codex CLI | 0.146.0 | available adapter candidate |
| Cursor Agent | 2026.09.15-d2fe57e | measured; experimental and blocked from production enablement by task 0002 isolation findings |
| OpenCode | reported installed; executable not found in the current shell | resolve path and probe in task 0404 |
| GitHub CLI | 2.87.3 | later host-side VCS spike; no credential is given to agents |
| RTK / XERJ | 0.49.0 / 1.0.0-rc.74 | required repository command wrapper / reference retrieval |

`phx.new` is not installed. Leave it absent until task 0101 pins the Phoenix generator version from official release evidence; installing an arbitrary latest archive now would make the clean bootstrap non-reproducible.

## Required execution order

```text
0001 product/security decisions
 ├─> 0002 host agent runtime spike ─> 0004 sleep/wake and power spike
 └─> 0003 menubar shell and bundled release spike

0005 documentation/reference baseline ─┐
0006 implementation readiness ─────────┴─> Phase 0 go/no-go ─> 0101 Phoenix foundation
```

Tasks 0002 and 0003 may run in parallel after 0001. Task 0004 requires the observed runtime behavior from 0002. Phase 1 starts only after all Phase 0 acceptance criteria have evidence and any architecture changes are recorded in `docs/DECISIONS.md`.

## Next executable task: 0004

Tasks 0001–0002 and 0005–0007 are complete. Task 0003's implementation and acceptance checks pass, but its distinct clean-user-account run remains in review. Task 0004 can proceed from task 0002 and must now prove power-assertion ownership and sleep/wake reconciliation before Phase 1:

- hold and release the idle-sleep assertion with observable ownership;
- detect simulated and coordinated real sleep gaps without duplicate stage execution;
- classify provider-stream interruption separately from agent-process survival;
- record honest AC, battery, and lid-close evidence and confirm or revise ADR-016.

Task 0003 confirmed the tray-shell architecture and bundled-release path. Its clean-user-account review item remains a Phase 1 gate. Developer ID signing and notarization remain Phase 9 gates.

## Phase 1 entry gate

Before task 0101 may scaffold Phoenix:

1. Tasks 0001–0004 are `done`, with worklogs and measured evidence.
2. ADR-011, ADR-012, and ADR-016 are confirmed or superseded from spike results.
3. The supported Elixir/OTP/Phoenix/Tailwind versions are pinned from official sources.
4. The task 0003 release experiment proves whether the Phoenix release and ERTS can be embedded and launched without an interactive shell environment.
5. The task 0002 adapter experiment produces redacted fixtures and an observed capability report.
6. The task 0004 sleep experiment records a safe test window; real sleep and lid-close tests require explicit human coordination.
7. The branch is clean except for intentionally excluded local assets, and the Phase 0 evidence is committed.

When the gate passes, task 0101 should generate a fresh minimal Phoenix/LiveView application and reuse only the reviewed root tooling files. Old v1 code is historical reference through Git, not a scaffold.

## Working rules

- Prefix every repository shell command with `rtk`; use `rtk proxy` only for exact unfiltered streams.
- Search `cuckoding-project-v4` and the relevant pinned peer index before unfamiliar implementation work, then inspect and cite `path:line`.
- Keep implementation changes within the claimed task and its branch.
- Do not enable the MCP example, activate a plugin, use credentials, publish externally, or perform real sleep tests without the corresponding task and approval.
