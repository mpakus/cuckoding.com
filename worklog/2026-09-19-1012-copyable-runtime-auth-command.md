# Worklog — 1012 copyable runtime authentication command

## Acceptance criteria

Render complete run-scoped sign-in commands, make them directly copyable, and give an actionable retry message.

## Baseline

- Branch: `fix/1012-runtime-auth-and-planning-errors`.
- Start revision: `6044960` on `main`.
- The affected Codex run-owned home reports `Not logged in`; the installed `codex-cli 0.146.0` accepts `login --device-auth`.
- The page incorrectly split `CODEX_HOME`, the executable, and arguments, making the visible executable command authenticate the global profile.
- Mandatory Ponytail, agent-adapter, LiveView, accessibility/writing, security-review, and quality-gate guidance is active.
- Preserved the unrelated untracked root `icon.png`.

## Implementation

- Build one safely shell-quoted command from every required run-scoped
  environment variable, the reviewed executable, and the fixed login arguments.
- Replaced fragmented paths with a read-only command input and adjacent copy
  button for Codex and Cursor roles.
- Added keyboard-readable copy feedback and a manual-selection fallback.
- Replaced the generic authentication error with the exact recovery sequence.
- Fixed the strict Codex task-proposal schema by making `sources[].line`
  required and nullable, as required by the provider's JSON Schema validator.
- Persisted sanitized planning-failure events, failed the matching durable agent
  session, and rendered the failure beside planning progress with a board recovery
  link.
- Repaired the reported historical run with the already-redacted provider error;
  no credential or raw authentication artifact was read.
- Updated the beta runbook and workflow contract.

## Verification

| Command or check | Result | Evidence/notes |
| --- | --- | --- |
| Scoped `codex login status` for the reported run | expected failure | `Not logged in`; confirms the old fragmented command did not authenticate this run-owned home. |
| Installed CLI version/help | pass | `codex-cli 0.146.0`; `login --device-auth` is accepted. |
| `rtk node --check assets/js/app.js` | pass | JavaScript syntax accepted. |
| Direct esbuild bundle with project `NODE_PATH` | pass | Bundled `app.js` successfully with esbuild 0.25.4. |
| Direct Elixir compile of changed application modules | pass | Both modules compiled; only expected module-redefinition warnings. |
| Quoted command self-check | pass | Codex paths containing apostrophes produced the expected safe shell quoting. |
| `rtk git diff --check` | pass | No whitespace errors. |
| `rtk mix format --check-formatted` | pass | Repository formatting is clean. |
| `rtk mix test test/cuckoding/board_task_intake_test.exs test/cuckoding/project_workflow_test.exs test/cuckoding/walking_skeleton_test.exs` | pass | 20 tests, 0 failures. |
| `rtk env -u CR_PAT mix quality` | pass | 10 properties and 237 tests passed; Credo, Sobelow, and Hex audit reported no issues. |
| Browser smoke at `/runs/01a0bac3-d172-7274-b6aa-2f220cb7290a` | pass | Visible `Planning failed` alert explains the invalid schema and links back to the board; timeline shows the role failed. |
| Browser copy smoke on queued Codex run | pass | The read-only input showed the complete `CODEX_HOME=... codex login --device-auth` command and the button announced `Command copied to clipboard.` |

## Handoff

The updated Phoenix application is running on `http://127.0.0.1:4000`.

## Risks and blockers

- A real provider launch still requires the user to complete device authentication inside the run-owned home.
