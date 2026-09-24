# 1037 — Installed agent executable discovery

Claimed from clean main on feature/1037-agent-path-discovery. Acceptance: find
installed CLIs and Codex Desktop's CLI automatically, keep manual overrides and
rescan, preserve authorization locks and the existing compatibility gates.

Applied Ponytail full 4.10.0 (MIT), agent-adapter, elixir-phoenix-liveview,
menubar-shell, security-review and quality-gates. Required product, architecture,
database, flow, security and execution documents inspected in this task chain.

Root cause: RuntimeConfiguration checks PATH and a few directories under
System.user_home(), but the native shell deliberately sets a system-only PATH
and an app-owned HOME. It also misses Codex Desktop's bundled executable.
Local file/version inspection found /Applications/ChatGPT.app/Contents/Resources/codex
(0.155.0-alpha.16.3); this is an installed file, not evidence that it passes the
current adapter's exact 0.146.0 compatibility gate. Discovery does not execute
found files or reuse personal provider credentials.

Reference: no XERJ listener on loopback 9200. Used bounded source inspection
instead; no completed-index claim. Hydra at pinned revision
d8ad56112c2c3acfb2f65f53b6890f30a25c693c (MIT, LICENSE inspected),
electron/util/fix-path.ts:4-5,54-78 confirms the packaged-app PATH problem and
standard-directory fallback. Reimplemented only that idea using fixed directory
checks; no login shell/dotfile execution or global PATH mutation.
Project evidence: runtime_configuration.ex:74-87 and main.rs:219-245.

`rtk proxy` exceptions: exact source reads, bounded filesystem inspection and
test/preview environment commands. No process arguments or credential files read.

## Implementation and verification

Shared discovery now tries PATH and fixed user/system CLI directories, then
Codex.app/ChatGPT.app resource executables in system/user Applications folders.
Only existing regular executable files qualify (normal executable symlinks work;
directories, non-executable files, broken symlinks and relative candidates do not).
No recursive home scan, startup scripts, candidate execution or dependency added.
The native shell passes CUCKODING_RUNTIME_HOME only to the host control plane;
the runner's scrubbed child environment continues to exclude it. Saved path
changes use the existing validated settings and audit boundary.

Agents setup retains a manual field and adds Find automatically with a live
status. A failed scan preserves manual input. The server also refuses rescans
after step-two save; editing the saved agent remains explicit. Help identifies
Codex Desktop, separate sign-in and the adapter's actual supported version.
Unsupported-version failures now explain how to choose another executable.

| Command | Result |
| --- | --- |
| `rtk mix format --check-formatted` | Pass |
| `rtk mix compile --warnings-as-errors` | Pass |
| `rtk mix test test/cuckoding/adapters/runtime_configuration_test.exs test/cuckoding_web/agent_settings_live_test.exs test/cuckoding/adapters/stable_stubs_test.exs test/cuckoding/adapters/codex_test.exs test/cuckoding/adapters/cursor_agent_test.exs test/cuckoding/adapters/claude_code_test.exs test/cuckoding/execution/local_process_runner_test.exs test/cuckoding/shared_agent_profile_test.exs test/cuckoding_web/project_setup_live_test.exs test/cuckoding_web/project_edit_live_test.exs test/cuckoding/project_onboarding_test.exs test/cuckoding/project_workflow_test.exs` | 81 tests, 0 failures |
| `rtk mix test test/cuckoding_web/agent_settings_live_test.exs` | 6 tests, 0 failures after the final copy trim |
| `rtk mix credo --strict` | Pass |
| `rtk mix sobelow --config` | Pass |
| `rtk mix assets.build` | Pass |
| `rtk cargo fmt --manifest-path desktop/src-tauri/Cargo.toml -- --check` | Pass |
| `rtk cargo test --manifest-path desktop/src-tauri/Cargo.toml` | 10 tests passed |
| `rtk cargo clippy --manifest-path desktop/src-tauri/Cargo.toml --all-targets -- -D warnings` | Pass |
| `rtk git diff --check` | Pass |

Initial Credo complexity failure was resolved with a fixed runtime-name map.
A strengthened relative-PATH regression initially used a fixture outside cwd;
Path.relative_to_cwd correctly left it absolute. Moved the test fixture under
ignored tmp/ so it actually exercises a relative path; the final suite passed.

CUA rendered the isolated test preview at 127.0.0.1:4116/settings/agents, with
system-only PATH and app-owned HOME to reproduce native launch conditions.
The form autofilled /Users/mpak/.local/bin/codex. Its --version reports 0.146.0,
so this machine has a currently supported standalone CLI in addition to the
newer Desktop bundle. Manual input remained editable; keyboard Enter on Find
automatically restored the detected path and announced the result. The button
measured 44 px high. Desktop 1280 px, mobile 390 px and narrow 320 px had no
horizontal overflow; browser console had no errors/warnings.

Preview used a separate tmp/1037-preview.db and provider directory with workers
disabled; no real accounts or provider sessions were changed. The task-owned
preview (PID 27496) was stopped with SIGTERM after checking its executable name,
cwd and loopback listener without reading process arguments. Browser tab closed
and viewport reset. The installed native app was not rebuilt/restarted, and no
real-provider sign-in, clean-machine packaging or expanded Codex-version
acceptance is claimed. Changes remain on feature/1037-agent-path-discovery.

## Documentation follow-up — 2026-09-24

The user requested an audit of what was implemented and described, followed by
updates to docs/ and AGENTS.md. Reopened this task for its documentation
follow-up; existing implementation and test edits are preserved. Acceptance:
document the two presentation surfaces, Irony default and saved Classic choice,
path discovery versus compatibility/sign-in, safe instance inspection, and the
separate source/main/packaged/deployed acceptance boundaries. Validate changed
documents and links; do not infer provider or release acceptance from local tests.

Applied Ponytail full 4.10.0 (MIT), quality-gates and security-review. Inspected
current source, recent task/worklog evidence and Git refs. Seven existing
implementation/test files were hashed before documentation edits. Exact source
reads and inline Python structural checks use `rtk proxy` to preserve content
and assertion semantics. No new reference implementation or dependency needed.

While the audit was in progress, the user clarified the three default roles:
Speculator creates specs/task descriptions from a prompt or project Markdown
plans; Implementor writes code/tests from both; Reviewer reports done or returns
comments through Cuckoding to Speculator. Users must be able to add roles and
permissions. This follow-up records the accepted contract without changing code.
Current source retains Specifications/Coding/Review, direct-to-Coding findings,
metadata-only custom roles and no role-permission editor. Those changes and their
behavioral verification remain unchecked in docs/PLAN.md; host grants and human
completion/release approval are preserved.

Documentation now centralizes the role contract in PRODUCT/FLOW and pending
implementation in PLAN, visual modes in UI_DASHBOARD, discovery in
AGENT_AUTHORIZATION_FLOW, safe restart guidance in DEVELOPMENT, and dated
evidence in DOCUMENTATION_AUDIT/RELEASE_READINESS. Configuration, shell, testing
and contributor guidance link those contracts. Corrected the stale claim that
the earlier provider-key rotation was still awaiting confirmation: BETA_REPORT
and commit 5d2d532 already contain the stakeholder's 2026-09-23 attestation.
No credential was inspected, and this does not attest to other exposures.

| Documentation follow-up command | Result |
| --- | --- |
| `rtk proxy git rev-parse HEAD refs/heads/main refs/remotes/origin/main` | All three inspected local refs resolve to 25c00d339e068e342b3903389b8d46a5fd9c3d72; no remote fetch/deployment check |
| `rtk proxy python3 - <<'PY'` structural/content checks | 14 changed Markdown files: 83 local links/anchors resolve, fences balanced, canonical role names present and all five role-implementation items remain unchecked; SHA-256 of all seven pre-existing implementation/test files unchanged |
| `rtk ruby github.page/verify.rb` | Pass: 9 local references and 4 pinned actions |
| `rtk node test/github_page_art_mode_test.cjs` | Pass: defaults, restore, invalid/denied storage, repeated switching, alt text and captions |
| `rtk node test/github_page_motion_test.cjs` | Pass: initial/changed reduced motion, content visibility and bounded parallax |
| `rtk node --check github.page/script.js` | Pass |
| `rtk git diff --check` | Pass |

No Elixir/Rust implementation, assets or dependency changes were made by this
documentation follow-up. The earlier 81-test/native/static-analysis evidence
above was not rerun or relabeled as a fresh full-suite pass. No provider action,
database change, app rebuild/restart, merge, push or Pages deployment performed.
Documentation acceptance is complete; the new role behavior remains explicit
future implementation work. Task 1037 discovery and this documentation remain
uncommitted on feature/1037-agent-path-discovery.

## Full-flow goal integration

The user subsequently authorized finishing the complete project/board/planning/
review/delivery/control flow and merging every new change to main. Revalidated
this existing slice before integration: `rtk env -u CR_PAT mix quality` passed
10 properties and 314 tests with zero failures, format/compile, strict Credo,
Sobelow and dependency audit. `rtk cargo test --manifest-path
desktop/src-tauri/Cargo.toml` passed all 10 tests; `rtk cargo fmt --manifest-path
desktop/src-tauri/Cargo.toml -- --check` and `rtk cargo clippy --manifest-path
desktop/src-tauri/Cargo.toml --all-targets -- -D warnings` passed. Reviewed the
source diff and current worktree ownership; only this task's files are staged.
The next task will retain the complete goal and separately verify the rebuilt
application. These source checks do not close that broader flow goal.
