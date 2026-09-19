# Worklog — 1014 reusable agent authorization

## Acceptance criteria

Persist reusable agent metadata globally, attach it to projects by stable ID, and reuse Codex authorization without sharing run state.

## Baseline

- Branch: `feature/1014-reusable-agent-authorization` from `0618ae1` on `main`.
- `provider_accounts` already exists as the intended machine-local catalog, but project settings currently duplicate all connection metadata and never write that table.
- Every Codex run currently uses a fresh file-backed `CODEX_HOME`, requiring a separate login.
- Official OpenAI documentation states that `cli_auth_credentials_store = "keyring"` stores credentials in the operating-system credential store, while `CODEX_HOME` contains configuration and other state. It also warns that file-backed `auth.json` contains access tokens.
- A sterile temporary `CODEX_HOME` with the keyring override returned `Not logged in`, confirming the current login was file-backed and that one user authorization step will be required after this change.
- XERJ was unavailable on loopback port 9200. Direct source inspection used the existing `provider_accounts`, project snapshot chain, `AgentRuntime`, and Codex adapter; no peer implementation was adapted.
- Ponytail 4.10.0 (MIT), architecture, adapter, LiveView, security, and quality-gate guidance are active.
- Preserved the unrelated untracked root `icon.png`.

## Implementation

- Saving or updating a project agent now upserts one credential-free `provider_accounts` row and snapshots its stable ID with the validated runtime settings.
- Project settings list saved machine-wide agents, attach them without retyping paths, and show provider-specific authorization state.
- Codex uses its supported Keychain credential store. Its one-time command runs from an owner-only application-data home, while launches retain a distinct generated `CODEX_HOME` per run.
- Claude helper metadata remains reusable. Cursor remains explicitly run-scoped because its retained global-session and MCP behavior has not passed credential-only isolation verification.
- Legacy planning failures without a captured validation code now explain that limitation and direct the user to a new run; new runs retain the detailed parser and proposal-validation errors from task 1013.
- Existing Echo connections were saved through the LiveView as global `Speculator` (Codex) and `Implementator` (Cursor) records. Codex correctly reports `Authorization required`; no provider-account file or credential value was created.

## Verification

- `rtk env -u CR_PAT mix test test/cuckoding/project_onboarding_test.exs test/cuckoding/project_workflow_test.exs test/cuckoding/adapters/codex_test.exs test/cuckoding_web/project_edit_live_test.exs` — 19 tests, 0 failures.
- `rtk env -u CR_PAT mix test test/cuckoding/execution/event_store_property_test.exs` — 1 property, 0 failures after one transient SQLite lock in the first full-suite pass.
- `rtk env -u CR_PAT mix test test/cuckoding/board_task_intake_test.exs test/cuckoding/project_onboarding_test.exs test/cuckoding/project_workflow_test.exs test/cuckoding/adapters/codex_test.exs test/cuckoding_web/project_edit_live_test.exs` — 24 tests, 0 failures.
- `rtk env -u CR_PAT mix quality` — 10 properties and 241 tests, 0 failures; Credo found no issues; Sobelow completed with no findings; Hex audit reported no retired or vulnerable packages. Expected plugin-supervisor crash-fixture logs were observed.
- Browser verification on the actual Echo project showed both saved-agent cards, the complete read-only Codex command and copy control, `Authorization required`, stable project revision updates, and the retained Cursor isolation explanation.
- Browser verification on `/runs/01a0baf1-25c2-74a6-9870-61ce2a873b33` showed the new explicit legacy-diagnostic message.
- `rtk git diff --check` — passed.

## Residual risk

- The existing Codex login was file-backed, so the saved `Speculator` account still requires one explicit device authorization into Keychain before a new planning run can launch.
- XERJ remained unavailable on loopback port 9200; direct source inspection was used and no peer code was adapted.
