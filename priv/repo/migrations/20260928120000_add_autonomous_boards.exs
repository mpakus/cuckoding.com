defmodule Cuckoding.Repo.Migrations.AddAutonomousBoards do
  use Ecto.Migration

  def change do
    alter table(:board_executions) do
      add :mode, :string,
        null: false,
        default: "fixed_batch",
        check: %{name: "board_mode", expr: "mode IN ('fixed_batch','autonomous_goal')"}

      add :plan_cycle, :integer,
        null: false,
        default: 0,
        check: %{name: "board_plan_cycle", expr: "plan_cycle BETWEEN 0 AND 3"}
    end

    alter table(:board_execution_items) do
      add :criteria_json, :map, null: false, default: %{}
      add :replacement_ids_json, :map, null: false, default: %{}
      add :superseded, :boolean, null: false, default: false

      add :retry_count, :integer,
        null: false,
        default: 0,
        check: %{name: "board_retry_count", expr: "retry_count BETWEEN 0 AND 2"}
    end

    create table(:board_plan_revisions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :board_execution_id,
          references(:board_executions, type: :binary_id, on_delete: :restrict), null: false

      add :parent_id, references(:board_plan_revisions, type: :binary_id, on_delete: :restrict)
      add :run_id, references(:runs, type: :binary_id, on_delete: :restrict), null: false
      add :review_run_id, references(:runs, type: :binary_id, on_delete: :restrict)
      add :cycle, :integer, null: false

      add :state, :string,
        null: false,
        default: "proposed",
        check: %{
          name: "board_plan_state",
          expr: "state IN ('proposed','accepted','rejected','invalidated')"
        }

      add :plan_json, :map, null: false
      add :baseline_json, :map, null: false
      add :review_json, :map
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:board_plan_revisions, [:run_id])
    create index(:board_plan_revisions, [:board_execution_id, :cycle])

    create table(:board_questions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :board_execution_id,
          references(:board_executions, type: :binary_id, on_delete: :restrict), null: false

      add :task_id, references(:tasks, type: :binary_id, on_delete: :restrict)
      add :run_id, references(:runs, type: :binary_id, on_delete: :restrict), null: false
      add :revision, :integer, null: false
      add :question, :text, null: false
      add :answer, :text
      add :answered_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:board_questions, [:run_id])
    create index(:board_questions, [:board_execution_id])

    alter table(:agent_sessions) do
      add :conversation_key, :string
      add :continuation_of_id, references(:agent_sessions, type: :binary_id, on_delete: :restrict)
      add :continuation_mode, :string
      add :continuation_identity_json, :map
    end

    create index(:agent_sessions, [:conversation_key])
  end
end
