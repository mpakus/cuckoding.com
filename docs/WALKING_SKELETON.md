# Phase 4 Walking Skeleton

## Implemented loop

`Cuckoding.WalkingSkeleton` creates one project, immutable policy and default-workflow snapshot, one board, five role assignments, one task, one run, and one owned worktree. It then runs specification, development, and QA through one adapter, creates owner-only evidence and project-scoped knowledge-candidate files, and stops in the durable `waiting` state for human approval.

The status LiveView lists pending approvals. Release is a two-step keyboard-accessible action: **Review release**, then **Approve and push**. Approval is persisted before the system release stage calls `Cuckoding.Execution.LocalBareRemote`. That host-side VCS implementation accepts only an absolute existing local bare `origin`, a clean recorded candidate revision, an approval for the same run, and a non-force exact branch refspec. Merge remains outside the MVP workflow.

The simulated sleep gap occurs while the specification attempt is active. The adapter checkpoint is persisted, the run hibernates, the worktree and policy marker are revalidated, and resume reuses the same attempt ID. The temporary preview-port lease used by the existing lifecycle is released before the stage continues.

## Evidence

Each run writes owner-only files under its run directory:

- `artifacts/specification.md`
- `artifacts/qa.md`
- `artifacts/evidence.json`, including adapter, branch, candidate SHA, artifact hashes, and measured active/wall milliseconds for each agent stage
- `artifacts/release.json` after the approved push
- `knowledge/candidates/walking-skeleton.md`, labeled project-only and unreviewed

Every file creation, stage transition, checkpoint, approval, candidate revision, and release handoff also has an ordered durable run event. The branch remains available in the local bare remote after the run reaches `done`.

## Fake and replacement ledger

| Current Phase 4 choice | What is real | Replacement owner |
| --- | --- | --- |
| `FakeAdapter` in CI | Database state, worktree, commit, sleep/resume lifecycle, evidence files, approval UI, and local Git push | Opt-in Codex or Claude Code demo after a run-scoped login is provisioned |
| Deterministic `WALKING_SKELETON.md` change | Candidate confinement, explicit file staging, commit, SHA recording, and remote branch are real | A supported adapter creates and commits the requested project change |
| Generated specification and QA summaries | Files, hashes, timing, event ordering, and approval gate are real | Typed provider output and later Phase 5 quality gates |
| Plain knowledge candidate | Owner-only Markdown and project scope are real | Phase 7 review, index, provenance, publication, and usage tracking |
| Local bare `origin` | Approval-gated, idempotent non-force push is real | Phase 5 `VcsHost` plugin and draft-PR support |

No scheduler, plugin registry, GitHub credential flow, knowledge database, or second frontend was added for this checkpoint.

## Demo procedure

Use a clean Git repository whose `origin` is an absolute path to an existing local bare repository. From `iex -S mix phx.server`:

```elixir
attrs = %{
  name: "Walking skeleton demo",
  repo_path: "/absolute/path/to/clean/clone",
  workspace_root: "/absolute/path/to/workspaces",
  task_title: "Ship the walking skeleton"
}

{:ok, created} = Cuckoding.WalkingSkeleton.create(attrs)
{:ok, pending} = Cuckoding.WalkingSkeleton.run(created)
pending.approval.id
```

Open `http://127.0.0.1:4000`, review the pending item, confirm the release, and verify the new `feature/walking-*` reference in the bare remote. The focused automated demo performs this same path with real Git repositories and LiveView clicks.

For an opt-in real provider run, set `adapter_key` during `create/1`, pass the matching adapter module to `run/2`, disable the fake-only sleep simulation, and supply only verified run-scoped authentication options. Global provider credentials must not be copied into the run directory.

## Product judgment

**Conditional GO.** The loop is useful enough to continue: one action surface exposes durable progress, a recoverable pause boundary, evidence, and a clearly human-controlled release. The condition is intentional and release-blocking for task 0405 completion: repeat the same loop with a supported real adapter using isolated authentication. Fixture conformance and the deterministic CI adapter are not relabeled as that real-provider evidence.
