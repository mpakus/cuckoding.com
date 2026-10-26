defmodule Boss.Repo.Migrations.CreateAgentRuns do
  use Ecto.Migration

  def up do
    create table(:agent_runs, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, references(:projects, on_delete: :restrict), null: false
      add :task_id, references(:tasks, on_delete: :restrict), null: false
      add :spec_revision_id, references(:spec_revisions, on_delete: :restrict), null: false
      add :admitted_version, :integer, null: false
      add :command_id, :string, null: false
      add :adapter, :string, null: false, default: "codex"
      add :status, :string, null: false, default: "preparing"
      add :cleanup, :string, null: false, default: "pending"
      add :workspace, :map, null: false, default: %{}
      add :summary, :map, null: false, default: %{}
      add :reason, :string
      add :os_pid, :integer
      add :exit_kind, :string
      add :exit_code, :integer
      add :signal, :integer
      add :head_commit, :string
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_runs, [:task_id, :command_id])
    create index(:agent_runs, [:project_id, :task_id, :inserted_at])

    execute(
      "CREATE UNIQUE INDEX agent_runs_one_open ON agent_runs ((1)) WHERE status IN ('preparing','launching','running','stopping') OR cleanup = 'unknown'"
    )

    execute("""
    CREATE TRIGGER agent_runs_pin BEFORE INSERT ON agent_runs
    WHEN NOT EXISTS (SELECT 1 FROM tasks t JOIN specs s ON s.id=t.spec_id
      WHERE t.id=NEW.task_id AND t.spec_revision_id=NEW.spec_revision_id
      AND t.state_version=NEW.admitted_version AND s.project_id=NEW.project_id)
    BEGIN SELECT RAISE(ABORT, 'run snapshot mismatch'); END
    """)

    execute("""
    CREATE TRIGGER agent_runs_immutable BEFORE UPDATE ON agent_runs
    WHEN OLD.id != NEW.id OR OLD.project_id != NEW.project_id OR OLD.task_id != NEW.task_id
      OR OLD.spec_revision_id != NEW.spec_revision_id OR OLD.admitted_version != NEW.admitted_version
      OR OLD.command_id != NEW.command_id OR OLD.adapter != NEW.adapter
      OR (OLD.workspace != '{}' AND OLD.workspace != NEW.workspace)
      OR OLD.status IN ('finished','failed','cancelled','interrupted')
    BEGIN SELECT RAISE(ABORT, 'run history is immutable'); END
    """)

    execute(
      "CREATE TRIGGER agent_runs_no_delete BEFORE DELETE ON agent_runs BEGIN SELECT RAISE(ABORT, 'run history is immutable'); END"
    )
  end

  def down do
    case repo().query!("SELECT COUNT(*) FROM agent_runs").rows do
      [[0]] -> drop table(:agent_runs)
      _ -> raise "Refusing to discard agent run history"
    end
  end
end
