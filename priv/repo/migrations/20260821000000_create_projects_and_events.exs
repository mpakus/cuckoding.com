defmodule AgentDesk.Repo.Migrations.CreateProjectsAndEvents do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false
      add :root_path, :text, null: false
      add :canonical_path, :text, null: false
      add :vcs_type, :text, null: false, default: "git"
      add :default_branch, :text
      add :settings, :map, null: false, default: %{}
      add :last_opened_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:projects, [:canonical_path])
    create index(:projects, [:last_opened_at])

    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_session_id, :binary_id
      add :task_id, :binary_id
      add :context_id, :binary_id
      add :type, :text, null: false
      add :source, :text, null: false
      add :correlation_id, :binary_id
      add :causation_id, :binary_id
      add :idempotency_key, :text
      add :payload, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:events, [:project_id, :occurred_at])
    create index(:events, [:agent_session_id, :occurred_at])
    create index(:events, [:task_id, :occurred_at])
    create index(:events, [:context_id, :occurred_at])
    create index(:events, [:type, :occurred_at])
    create index(:events, [:correlation_id])
  end
end
