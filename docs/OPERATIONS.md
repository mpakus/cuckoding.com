# Operations

## SQLite backup

Canonical state is the SQLite file under `data_root` (see `AgentDesk.Storage`).

Create a snapshot:

```elixir
{:ok, path} = AgentDesk.Backup.snapshot()
```

The copy is written to `<data_root>/backups/agentdesk.sqlite3`. Copy that file off-machine before risky upgrades.

WAL mode is enabled. Stop the app or checkpoint before treating a file copy as consistent if you snapshot while the BEAM is running a write-heavy workload. For desktop use, quit AgentDesk first, then copy `agentdesk.sqlite3`, `agentdesk.sqlite3-wal`, and `agentdesk.sqlite3-shm` together.

## Migration rollback

Do not edit an applied migration. Rollback means:

1. Restore a SQLite snapshot taken before the migration.
2. Or ship a **new** forward migration that reconstructs the previous shape.
3. Never `mix ecto.rollback` against a user's live desktop database as an automatic updater step.

XERJ directories under `<data_root>/xerj` may be deleted at any time; they are rebuilt from SQLite and the project tree.

## Team sync

Export writes `<data_root>/projects/<id>/sync/bundle.json`. Copy that file to the other machine and import it from the workspace Team sync panel. Import is rejected unless Git `origin` matches or `settings.sync_id` already matches. This does not replace Git remotes and does not open a listener.

## Forced termination

Worktrees live on disk under `<data_root>/projects/<id>/worktrees/`. Stopping the BEAM or the project runtime must not delete a dirty worktree. Cleanup is an explicit UI action that refuses dirty trees.

Isolation templates live under `<data_root>/projects/<id>/sessions/<session_id>/isolation/`. Isolated sessions never write those files into the Git worktree or the user's primary checkout.
