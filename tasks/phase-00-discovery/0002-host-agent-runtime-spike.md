# 0002 — Host Agent Runtime Feasibility Spike

## Objective

Create a disposable repository, feature branch, and worktree under a workspace root.

## Dependencies

- 0001.

## Scope

Create a disposable repository, feature branch, and worktree under a workspace root. Invoke one selected MVP runtime non-interactively on the host on a small change with a restricted permission grant. Capture public events, artifacts, exit status, process group identity, usage when available, cancellation, and native resume or continuation. Verify the worktree gitdir works and the agent commits on the host.

## Deliverables

- Capability report for the tested runtime/version including its permission system and what it cannot restrict.
- Worktree and process-group lifecycle script or spike module.
- Fixture output suitable for adapter contract tests.
- List of unsupported assumptions and architecture updates.

## Checklist

- [ ] Launch in a fresh process group with an allowlisted environment.
- [ ] Configure the runtime's allowed tools and working directory from a grant; record the effective grant.
- [ ] Capture structured output or document parsing limitations.
- [ ] Test cancellation of the process group.
- [ ] Test native resume or bounded continuation fallback.
- [ ] Confirm the runtime's memory/config files are not written outside the run folder or, if unavoidable, document exactly where.

## Acceptance criteria

- [ ] The agent changes only the assigned worktree in the benign case.
- [ ] The run is attributable to stable PIDs, start identity, and session ID.
- [ ] Cancellation leaves no unowned child process.
- [ ] Capability claims are based on observed evidence.

## Verification and evidence

Attach the repository diff, process inspection, redacted invocation, and resume results to the worklog.
