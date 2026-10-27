# Task commands and history

`Boss.Tasks.transition/2` is a backend command API. The drawer supports
[managed delivery](MANAGED_DELIVERIES.md), including bounded fixes, explicit
integration and verified Done. It separately supports [manual Codex attempts](MANUAL_RUNS.md)
with retained workspaces and Stop, plus [manual candidate checks](MANUAL_CHECKS.md)
and [read-only Codex assessments](MANUAL_REVIEWS.md);
these attempts never advance task state.
Managed progress is derived from persisted commit-bound stage evidence; generic
caller-selected workflow edges below remain closed.

## Command contract

```elixir
task = Boss.Tasks.get_task!(task_id)

Boss.Tasks.transition(task.id, %{
  command_id: "unique-command-id",
  expected_version: task.state_version,
  action: "block",
  reason: "A product decision is missing"
})
```

The API accepts atom keys and string actions. `command_id` is nonblank UTF-8 of
at most 128 bytes; `expected_version` is a nonnegative integer below SQLite's
maximum signed integer. Optional `reason` is nonblank UTF-8 of at most 1000 bytes.
NUL is rejected. Text is preserved exactly; omitted reason equals `nil`. Unknown
keys, including `evidence`, `verified`, a target state or an alternative revision,
are rejected with `:invalid_command`.

`{:ok, event}` is a receipt for the original command. An identical repeat returns
the same event even after later commands; it does not restore the old task state.
Read `get_task!/1` for the current state and `list_events/1` for ordered history.
Command IDs are scoped to each task. Changed input with the same ID returns
`:idempotency_conflict`. A new command with an old version returns `:stale_state`,
including after the state has changed away and back.

The task update and event insert share one immediate SQLite transaction. Every
accepted command advances `state_version` once. Events record source/target
state, version, action, reason and the task's pinned spec revision; SQLite rejects
their update or deletion. Existing tasks start at version zero with no fabricated
history. Commands never change the task title or pinned revision.
Rolling back the task-events migration is refused once any event exists; an
unused migration can still be reversed without deleting existing tasks.
The command pins the actual Repo process for its whole transaction and restores
the caller's selector afterward. A restarted Repo cannot receive the old command's
remaining writes outside that transaction.
When called inside another Repo transaction, its mode is inherited and success
remains provisional until the outer transaction commits. Publish results only
after that commit.

Validation errors write nothing. A failed event insert rolls back the update.
`:storage_error` can also mean an unknown outcome after a connection failure;
retry with the **same command ID and input**, rather than assuming rollback.

## Attention and recovery

`block`, `needs_input` and `cancel` require a reason. They preserve the prior
workflow phase as `recovery_state`. Changing between attention states preserves
that original target; historical reasons remain in events. `fail` and `interrupt`
are only valid from active phases. `done` rejects all commands; `cancelled` only
allows `retry`.

| Current state | Recovery action | Target |
|---|---|---|
| `blocked`, `needs_input` | `resume` | Saved recovery state |
| `failed`, `interrupted`, `cancelled` | `retry` | Saved recovery state |

Recovery accepts no new reason or target. Only return to `new` currently succeeds,
clearing the current reason and recovery state. Recovery to a producer-dependent
phase remains unavailable. It never repeats a process or Git operation.

## Producer-owned quality gates

The declared workflow edges follow `BOSS_PLAN.md`; each currently returns
`{:error, {:gate_unavailable, producer}}` from its valid source state:

| Generic action | Source → destination | Required producer |
|---|---|---|
| `start_planning` | new → planning | runner |
| `finish_planning` | planning → ready | runner |
| `start_implementation` | ready → implementing | runner |
| `finish_implementation` | implementing → testing | runner |
| `checks_passed` | testing → reviewing | checks |
| `approve_review` | reviewing → approved | review |
| `request_changes` | reviewing → implementing | review |
| `revise_spec` | reviewing → planning | review |
| `queue_merge` | approved → ready_to_merge | integration |
| `start_integration` | approved / ready_to_merge → integrating | integration |
| `finish_integration` | integrating → done | integration |

Caller-provided SHAs, flags or a model's verdict cannot unlock these gates.
`Boss.Deliveries` owns the implemented path. Its internal `delivery_progress`
command includes a delivery UUID and a command ID prefixed by that UUID. It reads
the persisted delivery matching task/revision/expected version; it accepts no
caller-selected destination or evidence. Plan/check/review lineage, cycle budget,
exact candidate, publication and postcheck receipts gate Ready and Done. The
delivery update and task event share one transaction. External task cancellation
is preserved when a worker subsequently records its terminal outcome.

`Boss.Tasks.Transition.dependency_satisfied?/1` recognizes only `done`.
`ready_to_merge`, cancelled, failed, interrupted and all other states return false.
There is no dependency scheduler yet.

## Board and detail reads

| Column | Saved states |
|---|---|
| Backlog | `new`, `planning`, `ready` |
| In Progress | `implementing`, `testing`, `integrating` |
| Review | `reviewing`, `approved` |
| Needs Attention | `ready_to_merge`, `blocked`, `needs_input`, `failed`, `interrupted`, `cancelled`, unrecognized states |
| Done | `done` |

`Boss.Tasks.get_details(project_id, task_id, revision_number \\ nil)` returns
`{:ok, details}` or `{:error, :not_found | :storage_error}`. Project/task IDs and
optional revision numbers must be positive signed 64-bit integers. A missing or
foreign task/revision returns `:not_found` before exposing source or events.

The result contains `task`, `spec`, `pinned_revision`, `latest_revision`,
`selected_revision`, `revisions` (number/timestamp metadata, newest first) and
`events` (latest 50 by descending state version). The default selection is the
pinned revision. One deferred transaction, bound to the actual Repo PID, gives a
coherent snapshot even when another connection commits a task transition or
source revision concurrently. The existing command transaction remains immediate.

`/projects/:id/tasks/:task_id?revision=:number` opens the native modal drawer.
Omitting the query selects the task pin. Back/Forward and reload preserve URL
selection; background refresh coalesces reads and rejects stale responses.
Changing selection never mutates the task. A cached source is shown only when it
matches the desired revision. Missing files retain their revisions and events.
Only the dialog's `open` attribute is client-owned; LiveView updates its contents.
The hook keeps a focused revision select aligned with server state after history
navigation, since LiveView otherwise preserves that focused control's value.

Revision metadata is not paginated yet. Committed run/delivery notifications
coalesce board/detail refreshes. In-flight snapshot reads finish; obsolete results
are discarded before loading the latest URL selection, avoiding cancellation in
the middle of a database transaction.
