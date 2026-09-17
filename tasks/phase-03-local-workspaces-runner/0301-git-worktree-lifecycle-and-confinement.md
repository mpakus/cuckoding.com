# 0301 — Git Worktree Lifecycle and Path Confinement

```yaml
status: done
owner: codex
started_at: 2026-09-17
completed_at: 2026-09-17
worklog: worklog/2026-09-17-0301-git-worktree-lifecycle.md
```

## Objective

Implement the host-side Git service: base SHA capture, branch and worktree creation under the workspace root, clean-status checks, protected-branch rules, drift detection, and confinement checks with symlink resolution..

## Dependencies

- 0203.

## Scope

Implement the host-side Git service: base SHA capture, branch and worktree creation under the workspace root, clean-status checks, protected-branch rules, drift detection, and confinement checks with symlink resolution.

## Deliverables

- Git service module.
- Worktree fixtures including dirty base and symlink escapes.

## Checklist

- [x] Worktree root must be inside the workspace root after resolution.
- [x] Record base and head SHAs on the environment.
- [x] Drift blocks resume until the user chooses.

## Acceptance criteria

- [x] Path traversal and symlink fixtures are rejected.
- [x] Two runs never share a worktree or branch.

## Verification and evidence

Run Git service integration tests against a local bare remote.
