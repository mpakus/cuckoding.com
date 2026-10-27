# Manual checks on a saved candidate

After a Codex attempt finishes, open its task drawer, enter a **Check command**
and choose **Snapshot and run checks**. Commands come only from this explicit
user action, never from a model message or repository configuration. Examples:
`mix test`, `npm test`, or a versioned project script such as `./scripts/check`.

The command runs locally with the account and environment inherited by BOSS;
this is not an OS sandbox. Use trusted projects and commands. Arguments support
quoting and are executed directly, with no implicit shell expansion. If a trusted
project needs several setup/test steps, use its script or tool's own command
composition. Dependencies and ignored build artifacts are not copied from the
Codex worktree; the explicit command must perform any required setup. BOSS does
not silently install dependencies or infer a test command.

Command arguments are retained as check configuration. Keep secrets in the
existing environment or tool credential store, not in command arguments.

## What is captured

BOSS preserves the task revision and source attempt, then saves snapshot intent
before Git effects. It captures the retained Codex worktree's current tracked
changes, deletions and nonignored untracked files using two fresh private indexes.
The original worktree's files, index, branch and HEAD are not modified by capture.
The two observed trees and source HEAD must agree; this is not an atomic filesystem
snapshot against concurrent editors. Stop editing the source while capturing.

A new commit is retained under `refs/boss/checks/<attempt-id>`, with a separate
detached worktree at `<data-dir>/projects/<project-id>/checks/<attempt-id>`. The
candidate commit is saved before executing the command. Its task revision, source
attempt, command/config hash and candidate SHA are immutable. Retrying an unknown
start uses the same request and command; a completed attempt is never rerun by
replaying its command ID. A fresh user request captures a new candidate.

Submodules, sparse checkouts, executable Git filters and conditional Git includes
are rejected in this initial implementation. Generated paths and linked Git
identity are validated. Snapshot helpers are bounded and use the same native
process-group owner as Codex. Check worktrees/refs are retained, never reset,
removed or merged automatically.

## Meaning of a passing check

Checks pass only after actual exit 0, genuine stdout/stderr EOF, confirmed empty
process group and a final exact clean candidate HEAD/ref/tree check. Verification
reconstructs the file tree in a fresh index, so assume-unchanged/skip-worktree flags
cannot hide tracked edits. Tracked or nonignored untracked changes, file-mode
changes, a moved HEAD/ref or an unverifiable workspace fail the check even if the
command exits 0. Ignored build products are permitted.

The receipt describes **that commit and that command**. It does not attest the
entire environment, dependencies or future source-worktree contents. It does not
prove that the chosen command is an adequate test. Task workflow transitions,
integration and Done belong to the separate [managed delivery](MANAGED_DELIVERIES.md)
with its own plan, check and review evidence; this manual receipt cannot unlock them.
The passed receipt enables an explicit [Review with Codex](MANUAL_REVIEWS.md) action;
its model assessment remains separate from workflow approval.

Manual Codex/check attempts remain exclusive with managed workflows and
integration; a pending queued workflow also owns its task. **Stop** uses the
existing direct live-worker route; closing the drawer or browser does not stop work. Repo loss
or missing cleanup receipt produces interrupted/unknown quarantine and never
an automatic rerun. Candidate changes and failed checks retain their worktrees.

Limits: one command, 4096 input bytes, 128 arguments, 2 minutes, 1 MiB combined output.
The UI retains command arguments, candidate SHA, exit/signal and byte counts;
arbitrary check output is discarded to avoid retaining secrets. Inspect/reproduce
a failure in the displayed retained worktree. Recent history shows the latest 10
attempts plus their source runs, so repeated checks do not hide their retry form.

## Verification scope

Tests use exclusively created repositories and real SQLite pools/native processes.
They cover snapshot preservation/drift, SHA256 repositories, command validation,
immutable provenance, idempotency, failure/Stop/recovery and UI request handling.
Browser evidence and exact suite results are recorded in `.worklog/2026-10-26.md`.
No provider calls are required. macOS only; no Linux/release/integration claim.
