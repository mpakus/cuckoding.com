defmodule Cuckoding.Repo.Migrations.CreateEventAndCommandFoundation do
  use Ecto.Migration

  def change do
    create table(:run_event_sequences, primary_key: false) do
      add :run_id, :string, primary_key: true
      add :last_sequence, :integer,
        null: false,
        default: 0,
        check: %{name: "last_sequence_is_non_negative", expr: "last_sequence >= 0"}
    end

    create table(:run_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :run_id, :string, null: false
      add :sequence, :integer,
        null: false,
        check: %{name: "sequence_is_positive", expr: "sequence > 0"}
      add :event_type, :string, null: false
      add :public_summary, :text, null: false
      add :payload, :map, null: false
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create unique_index(:run_events, [:run_id, :sequence])

    execute(
      """
      CREATE TRIGGER run_events_no_update
      BEFORE UPDATE ON run_events
      BEGIN
        SELECT RAISE(ABORT, 'run_events are append-only');
      END;
      """,
      "DROP TRIGGER run_events_no_update"
    )

    execute(
      """
      CREATE TRIGGER run_events_no_delete
      BEFORE DELETE ON run_events
      BEGIN
        SELECT RAISE(ABORT, 'run_events are append-only');
      END;
      """,
      "DROP TRIGGER run_events_no_delete"
    )

    create table(:commands, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :idempotency_key, :string, null: false
      add :kind, :string, null: false
      add :target_type, :string, null: false
      add :target_id, :string, null: false
      add :payload, :map, null: false
      add :state, :string,
        null: false,
        default: "pending",
        check: %{
          name: "state_is_valid",
          expr: "state IN ('pending', 'running', 'succeeded', 'failed')"
        }

      add :attempts, :integer,
        null: false,
        default: 0,
        check: %{name: "attempts_are_non_negative", expr: "attempts >= 0"}

      add :max_attempts, :integer,
        null: false,
        default: 3,
        check: %{
          name: "attempts_are_bounded",
          expr: "max_attempts > 0 AND attempts <= max_attempts"
        }
      add :not_before, :utc_datetime_usec, null: false
      add :last_error, :text
      add :result, :map
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:commands, [:idempotency_key])
    create index(:commands, [:state, :not_before])

  end
end
