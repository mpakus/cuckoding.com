# R050f — Task-owned verification

Status: implemented and verified · Codex · 2026-10-13

## Acceptance

- [x] Ordinary flow stays Add folder → Create tasks → Start. No mandatory Arena command-check setup.
- [x] Speculator includes expected outcomes and concrete verification instructions in generated task criteria; automatic card creation retains them.
- [x] Start freezes those criteria. Independent task and final Secutor reviews remain required; missing execution evidence cannot be called passing.
- [x] New battles without optional command checks skip command stages explicitly. Existing battle snapshots and configured command checks retain their requirements.
- [x] The board explains task verification plainly; optional executable checks remain in Advanced.
- [x] Cover no-command execution, review rejection, preserved configured checks and UI readiness with regressions. Update docs, README and AGENTS; verify, rebuild the saved local app and merge to local main.

No live provider inference or changes to saved teams/accounts are part of verification.

Evidence: [worklog](../worklog/2026-10-13-R050f-task-verification.md). Live provider battle acceptance remains open; this change does not add Cursor execution or general shell/toolchain grants.
