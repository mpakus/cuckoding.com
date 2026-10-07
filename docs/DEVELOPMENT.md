# Development

Current checkout: documentation reset with application sources intentionally
removed. There is no runnable Mix app, native build or release script here yet.
Begin with R010 in [the plan](PLAN.md); do not run old build commands or restore
the deleted implementation wholesale.

## Working procedure

1. Read [AGENTS](../AGENTS.md), the core contracts and one selected plan slice.
2. Claim one task file and add a worklog with acceptance criteria.
3. Inspect Git state; preserve the user's intentional deletions and unrelated
   edits. Use the task's feature/fix branch.
4. Search local source with RTK; follow [reference coding](REFERENCE_CODING.md)
   for unfamiliar mechanisms. Apply Ponytail full.
5. Implement the smallest complete behavior with focused checks and durable
   events; update only affected contracts.
6. Run [quality gates](TESTING.md), record exact evidence and leave an explicit
   handoff for anything still open.

Every repository shell command starts with `rtk`. Use `rtk proxy` when filtering
would corrupt exact source/protocol output or command semantics; record why.
Stored product commands describe the underlying operation, not the RTK wrapper.

## Data and runtime safety

Use an isolated development data root. The source reset does not authorize
erasing old app databases, provider profiles, knowledge, logs or worktrees.
Any import/upgrade needs backup-first tests against a copy.

A future requested restart must inspect only owned CCoding instances by executable,
PID/start identity, working directory and listeners; never dump argv/environments.
Use the graceful shell shutdown path, verify process/listener cleanup, then open
one explicitly chosen build and record its identity. Do not kill unrelated Codex,
Claude, Cursor or Hermes processes. This docs task does not restart the old app.

## Toolchain and distribution

Keep Elixir/OTP, Phoenix LiveView/Tailwind, Ecto/SQLite, Git worktrees and Tauri 2.
Choose/pin current compatible versions in R010 and prove clean-machine packaging
in R100. No macOS user should need an Elixir/Rust toolchain to run the bundle.
Reintroduce CI only with real scripts/checks; no pipeline should point to removed
files or publish documentation claims as a working release.
