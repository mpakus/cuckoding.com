# Worklog — 0804 container runner contract

## Metadata

- Date/time (UTC): 2026-09-18
- Task: 0804
- Status: complete
- Human/agent owner: codex
- Branch: `feature/0804-container-runner-contract`
- Start revision: `473faf1`
- End revision: task commit

## Acceptance criteria

- Specify a stable container `RunnerBridge` contract without changing domain schemas.
- Decide worktree, Git, image, network, port, resource, lifecycle, and secret boundaries.
- Ship a deliberately unavailable stub that passes the runner conformance suite.
- Drive visible isolation labels only from validated manifest claims.

## Reference coding

- Focused project and pinned Vibe Kanban XERJ searches were attempted first;
  the configured loopback node was unavailable.
- Pinned Apache-2.0 Vibe Kanban resolves worktree gitdirs at
  `crates/worktree-manager/src/worktree_manager.rs:208-213` and watches the
  resolved Git metadata at `crates/services/src/services/diff_stream.rs:791-808`.
  Cuckoding does not expose that metadata to the container: Git remains a
  host-side service. No source was copied.

## Work performed

- Claimed Task 0804 and restated its acceptance criteria.
- Added a stable container-runner contract covering supported backend names,
  worktree/run-directory mounts, host-side Git, immutable image digests,
  explicit resource enforcement, loopback port leases, deny-by-default
  networking, lifecycle recovery, and open implementation questions.
- Added a deliberately unavailable bundled runner stub with no isolation claims
  and no selectable backend.
- Restricted runner isolation claims to `filesystem`, `network`,
  `resource_limits`, and `egress`; the settings UI labels them as declared and
  explicitly reports an empty claim set.
- Added runner conformance, manifest validation, discovery compatibility, and
  LiveView label regression coverage without changing domain schemas.

## Verification

| Check | Result |
| --- | --- |
| Focused container stub, manifest, reference-plugin, and settings tests | pass; 10 tests, 0 failures |
| Existing command policy, local runner, preview ports, reconciliation, and power tests | pass; 1 property and 26 tests, 0 failures |
| `rtk mix quality` | pass; 10 properties and 176 tests, 0 failures; Credo checked 158 files/2,403 functions and macros with no issues; Sobelow and dependency audit passed |
| `rtk git diff --check` | pass |

## Handoff

Task complete after the final diff review and local-main merge. No container
backend is installed or selectable; implementation and backend-specific
verification remain explicitly deferred.
