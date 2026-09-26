# Phase 4 Walking Skeleton

This document describes the retained execution service and its original demo.
The 2026-09-17 provider checkpoint below is historical, not acceptance of the
current board controller or packaged application. For normal operation use
[FLOW.md](FLOW.md) and [CUCKODING-CONTROL.md](CUCKODING-CONTROL.md).

## Implemented loop

`Cuckoding.WalkingSkeleton.create/1` is an all-in-one fixture/demo constructor:
one project, policy, workflow, board, five role assignments, task, run and owned
worktree. Normal onboarding creates these separately. `GuidedRun` and board
delivery use its bounded executor with saved runtime assignments.

New defaults run Speculator → Implementor → Reviewer, plus explicitly scheduled
custom roles. The host validates closed Review output and routes corrections
through Speculator within the attempt/budget limits (at most three Reviews).
Task descriptions, the latest spec and returned findings pass between stages;
legacy run snapshots preserve earlier routing. Passing review produces private
evidence and a project-scoped knowledge candidate. Manual completion policy
waits for a decision; explicit local policy completes automatically. Board
delivery then validates the candidate again before advancing its reviewed head.
Speculator and Reviewer remain read-only; Implementor may leave a patch for the
host Git service to validate/commit when provider permissions deny Git metadata.

The status LiveView lists pending choices and shows the candidate base/head, changed files, tests, typed artifacts, and project-knowledge citations. **Complete locally** requires visible confirmation and atomically marks the release decision rejected, the waiting human attempt cancelled, and the run/task done; no `VcsHost` is invoked, and the branch, worktree, and evidence remain. Release is a separate two-step keyboard-accessible action: **Review release**, then **Approve and release**. Approval is persisted before the system release stage calls the configured `VcsHost`. `LocalBareRemote` accepts only an absolute existing local bare `origin`; `GitHubVcsHost` fetches an opaque credential through `SecretStore`, pushes the candidate, and creates a draft pull request. Both require a clean recorded candidate revision, an approval for the same run, a non-protected branch, and a non-force exact branch refspec. If the handoff fails after approval, the attempt is durably failed and the approved release remains visible as **Retry release**; startup recovery can resume a waiting handoff without creating another approval decision. Merge remains outside the MVP workflow.

The deterministic demo can simulate a sleep gap while Specification is active.
The checkpoint is persisted, the run hibernates, the worktree/policy marker is
revalidated, and resume reuses the attempt ID. Normal GuidedRun and controller
launches disable that fixture-only simulation; real wake handling belongs to the
power/reconciliation services.

## Evidence

Each run writes owner-only files under its run directory:

- `artifacts/specification.md` and per-attempt specification artifacts
- `artifacts/qa.md`
- `artifacts/evidence.json`, a versioned typed bundle containing adapter, branch, base/candidate SHA, test results, structured findings, artifact hashes, knowledge citations, and measured active/wall milliseconds for each agent stage
- `artifacts/release.json` after the approved push
- `knowledge/candidates/walking-skeleton.md`, labeled project-only and unreviewed

Every file creation, finding, stage transition, checkpoint, completion choice, candidate revision, and release handoff has an ordered durable run event. Released branches remain available in the local bare remote. Locally completed branches remain only in the owned local worktree unless the user later exports them outside this workflow.

## Fake and replacement ledger

| Current Phase 4 choice | What is real | Replacement owner |
| --- | --- | --- |
| `FakeAdapter` in CI | Database state, worktree, commit, sleep/resume lifecycle, evidence files, approval UI, and local Git push | Retain as the deterministic regression lane; the opt-in Codex lane is now demonstrated |
| Deterministic `WALKING_SKELETON.md` CI change | Candidate confinement, explicit file staging, commit, SHA recording, and remote branch are real | The real demo generated `Greeting.hello/1` and tests; the host committed the confined patch |
| Provider specification and QA output | Typed provider output, digest-verified files, structured findings, measured timing, event ordering, and approval evidence are real | Later tasks can add project-specific gate types without changing the bundle boundary |
| Plain knowledge candidate | Owner-only Markdown and project scope are real | Phase 7 review, index, provenance, publication, and usage tracking |
| Local bare `origin` | Approval-gated, idempotent non-force push is real | `GitHubVcsHost` now provides the credential-isolated draft-PR path; later plugin work can add hosts |

The original thin demo does not exercise every plugin/knowledge subsystem.
Those services now exist elsewhere in the application. Automatic merge and a
second application frontend remain outside this loop.

## Demo procedure

Use a disposable clean Git repository whose `origin` is an absolute path to an
existing local bare repository, plus an isolated development database. From
`rtk iex -S mix phx.server`:

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

Open `http://127.0.0.1:4000`, review the pending item, then either confirm local completion and verify no remote branch was created, or confirm release and verify the new `feature/walking-*` reference in the bare remote. Focused automated tests cover both paths with real temporary Git repositories and LiveView clicks.

For an opt-in real provider run, set `adapter_key` during `create/1`, pass the matching adapter module to `run/2`, disable the fake-only sleep simulation, and supply only verified run-scoped authentication options. Global provider credentials must not be copied into the run directory.

## Real-provider checkpoint

On 2026-09-17, Codex `0.146.0` authenticated inside the run-scoped home and completed run `01a0b1e6-ae77-73d3-85cd-a368d5eed432`. The three successful provider stages measured 25,462 ms, 46,781 ms, and 42,312 ms. The host committed candidate `5c040f3bae8652f4cf57b9315b49debd164d4ca3`; the browser approval pushed that exact SHA to `feature/walking-01a0b1e6` in the local bare remote. `evidence.json` has SHA-256 `056a1fc184f45c3de94471786ddeee8465309e682c902ffb85c9eb25380022a0`, and `release.json` has SHA-256 `a9dd4019064082e7207f2cef72eecdcc32380b78e63e01071a52e7d764d9dbab`. Both files were verified mode `0600`.

The run exposed five failed specification attempts before the successful retry: an unapplied local migration, delayed stdin EOF, a provider schema incompatibility, correctly protected Git metadata, and an adapter timeout that ignored its declared wall limit. Each failure remained durable and led to the narrow fixes documented in the worklog. The provider's safe PATH did not contain Mix, so the host independently ran the generated fixture's explicit-file formatter check and two-test suite. Run-scoped toolchain resolution remains a Phase 5 runner follow-up, not hidden demo evidence.

## Historical Phase 4 product judgment

**GO to continue implementation, recorded in Phase 4.** The checkpoint established
value in durable progress, retained failures, evidence and human-controlled
release. It is not the current MVP release decision, which remains
[no-go pending release acceptance](RELEASE_READINESS.md).
