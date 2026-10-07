# R040c — Arena Git inspection and initialization

Status: implementation and verification complete; local integration pending.
Owner: Codex. Branch: `feature/R040c-arena-git-setup`.

- Inspect Git only on an explicit authenticated action for a registered Arena;
  persist bounded public observations, command lifecycle and audit events.
- Distinguish missing, unborn and committed standalone repositories. Refuse
  nested roots, linked/external metadata and unsafe config rather than expand scope.
- After a fresh missing-repository observation, require confirmation bound to
  that observation before initializing `.git` with branch `main` and no templates.
  Preserve all existing files/index/history; never stage, commit, fetch or push.
- Revalidate folder identity before effects; use fixed Git argv, clean environment,
  owned process groups, bounded output/deadline, cancellation and no uncertain replay.
- Keep observations across reconnect/restart; show elapsed time and safe controls.
  Missing Git or unsafe metadata must leave manual planning usable.
- Cover real temporary Git repositories, malicious metadata/config, stale consent,
  interrupted commands, process cleanup, domain/LiveView and packaged browser flow.
- Update README, AGENTS and affected docs; verify, merge local main and delete branch.

Evidence: [worklog](../worklog/2026-10-07-R040c-arena-git-setup.md).

Initial-commit file preview/consent, linked-worktree support, dirty-file inventory,
agent planning and battle execution are separate slices.
