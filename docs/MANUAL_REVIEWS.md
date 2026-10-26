# Manual review of a checked candidate

On macOS, open a task with a passed check and select **Review with Codex**.
This explicitly starts a fresh session using your locally configured Codex
account; it may incur provider charges. It reviews the existing checked
commit, rather than capturing later edits from the implementation workspace.

The reviewer receives the pinned original specification, complete diff from the
saved implementation base to the candidate, and saved check command/config hash,
exit and byte counts. Inputs over 1 MiB or an unverified candidate are refused;
diffs are never truncated. Refined plans, raw test output and previous review
feedback are not yet provided. The prompt states these limits explicitly.

## Execution and assessment are separate

The invocation is a separate ephemeral `codex exec`, with `--sandbox read-only`,
`--ask-for-approval never`, `--ignore-user-config`, `--json`, a bundled
`--output-schema` and `--output-last-message`. It does not resume the developer's
session. Read-only permission does not isolate the account from all readable files
or prove a different model reviewed the work. The reviewer is instructed not to
run tests, install dependencies or mutate files.

Admission saves the exact check parent, task/spec revision, candidate SHA,
workspace and check configuration before launch. These inputs are immutable.
The same command UUID replays its original attempt, including after completion;
a new explicit click creates a new review. Codex, checks and reviews share one
global active attempt, Stop and unknown-cleanup quarantine.

A finished review requires successful Codex protocol completion, actual exit 0,
both stream EOFs, confirmed process-group cleanup, a valid final report and exact
candidate verification before and after the run. Missing/empty/oversized output,
invalid JSON, a changed HEAD/tree/ref or unresolved cleanup cannot yield an
accepted assessment. A valid rejection is a finished review with a rejecting
verdict, not a process failure.

## Structured report

Only one UTF-8 JSON object up to 32 KiB is accepted. All fields are required;
unknown or repeated keys and trailing JSON are rejected:

- `verdict`: `approved`, `changes_requested` or `needs_spec_revision`.
- `summary`: nonempty text, at most 2,000 bytes.
- `acceptance`: 1–20 distinct criteria, each with `criterion` (1,000 bytes),
  `status` (`passed`, `failed`, `unclear`) and concrete `evidence` (2,000 bytes).
- `issues`: 0–20 items with `criterion` and actionable `message` (2,000 bytes).

Approval requires all criteria passed and no issues. Changes requested requires
a failed criterion; spec revision requires an unclear criterion. Every nonpassed
criterion needs an issue, and issues must refer to nonpassed criteria in the report.
These rules validate the report's consistency; they do not prove the model found
every requirement or that its evidence is correct. The UI labels it **Model
assessment**, escapes its text and keeps the task's workflow state unchanged.

## Output and recovery

The JSONL stream retains only bounded event types/counts/usage. Model/tool/stderr
text is not stored in the database. The CLI's last-message artifact uses an
exclusively created file in a private temporary directory (0700/0600). BOSS keeps
the original file descriptor, refuses replaced/symlink paths and reads at most
32 KiB plus one byte after cleanup. It persists only a validated report.

The temporary directory is renamed before cleanup to prevent a late CLI write
from recreating the old path. Cleanup runs on ordinary completion and worker death;
filesystem permission/I/O failures can prevent removal.
An abrupt whole-VM or machine shutdown can leave a private temporary artifact;
this initial version does not scan or erase old temporary directories on startup.
The 32 KiB limit bounds accepted/read report content, not the CLI's temporary
file writes. Native process limits remain 20 minutes and 8 MiB combined streams.

**Stop** reaches the live worker without waiting on the Manager/Repo mailbox.
Browser closure does not cancel it. Repo loss terminates the worker; restart
quarantines the attempt without reusing a PID or rerunning it. Candidate worktrees
remain retained. See [MANUAL_RUNS.md](MANUAL_RUNS.md) for process-group limits.

This is useful manual review, not the full BOSS quality gate: automated fixes,
refined-plan/test-output evidence, approval transitions, integration and Done
remain future work. Tests use local finite CLI fixtures; live provider compatibility
is not claimed without an explicit provider smoke run.
