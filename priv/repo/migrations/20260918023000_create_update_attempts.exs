defmodule Cuckoding.Repo.Migrations.CreateUpdateAttempts do
  use Ecto.Migration

  def change do
    create table(:update_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :from_version, :string, null: false
      add :to_version, :string, null: false
      add :schema_change, :boolean, null: false

      add :state, :string,
        null: false,
        check: %{
          name: "update_attempt_state_valid",
          expr: "state IN ('preparing', 'prepared', 'installing', 'healthy', 'failed', 'rolled_back')"
        }

      add :backup_path, :text
      add :backup_manifest_hash, :string
      add :active_run_ids_json, :map, null: false, default: fragment("'[]'")
      add :failure_reason, :text
      timestamps(type: :utc_datetime_usec)
    end

    create index(:update_attempts, [:inserted_at])

    create table(:update_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :update_attempt_id, references(:update_attempts, type: :binary_id, on_delete: :restrict),
        null: false

      add :event_type, :string, null: false
      add :command_key, :string, null: false
      add :details_json, :map, null: false, default: fragment("'{}'")
      add :occurred_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:update_events, [:command_key])
    create index(:update_events, [:update_attempt_id, :occurred_at])

    execute(
      """
      CREATE TRIGGER update_events_no_update
      BEFORE UPDATE ON update_events
      BEGIN
        SELECT RAISE(ABORT, 'update events are append-only');
      END
      """,
      "DROP TRIGGER IF EXISTS update_events_no_update"
    )

    execute(
      """
      CREATE TRIGGER update_events_no_delete
      BEFORE DELETE ON update_events
      BEGIN
        SELECT RAISE(ABORT, 'update events are append-only');
      END
      """,
      "DROP TRIGGER IF EXISTS update_events_no_delete"
    )
  end
end
