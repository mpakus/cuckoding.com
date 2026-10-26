defmodule Boss.Repo.Migrations.CreateTaskEvents do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :state_version, :bigint, null: false, default: 0
      add :attention_reason, :text
      add :recovery_state, :string
    end

    create table(:task_events) do
      add :task_id, references(:tasks, on_delete: :restrict), null: false
      add :spec_revision_id, references(:spec_revisions, on_delete: :restrict), null: false
      add :command_id, :string, null: false
      add :version, :bigint, null: false
      add :action, :string, null: false
      add :from_state, :string, null: false
      add :to_state, :string, null: false
      add :reason, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:task_events, [:task_id, :command_id])
    create unique_index(:task_events, [:task_id, :version])

    for operation <- ["UPDATE", "DELETE"] do
      name = "task_events_no_#{String.downcase(operation)}"

      execute(
        "CREATE TRIGGER #{name} BEFORE #{operation} ON task_events BEGIN SELECT RAISE(ABORT, 'task events are immutable'); END",
        "DROP TRIGGER #{name}"
      )
    end
  end
end
