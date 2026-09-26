defmodule Cuckoding.Repo.Migrations.CreateBoardExecutions do
  use Ecto.Migration

  def change do
    create table(:board_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :board_id, references(:boards, type: :binary_id, on_delete: :restrict), null: false

      add :controller_task_id, references(:tasks, type: :binary_id, on_delete: :restrict),
        null: false

      add :state, :string,
        null: false,
        default: "running",
        check: %{
          name: "board_execution_state",
          expr:
            "state IN ('running','waiting','paused','attention','controlling','done','finished_with_skips','stopped')"
        }

      add :revision, :integer, null: false, default: 1
      add :base_sha, :string, null: false
      add :head_sha, :string, null: false
      add :snapshot_json, :map, null: false
      add :current_run_id, references(:runs, type: :binary_id, on_delete: :restrict)
      add :current_task_id, references(:tasks, type: :binary_id, on_delete: :restrict)
      add :phase, :string, null: false, default: "decision"
      add :issue, :string
      add :pending_action, :string
      add :control_json, :map, null: false, default: %{}
      add :finished_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:board_executions, [:board_id],
             name: :one_open_board_execution,
             where: "state NOT IN ('done','finished_with_skips','stopped')"
           )

    create unique_index(:board_executions, [:controller_task_id])

    create table(:board_execution_items, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :board_execution_id,
          references(:board_executions, type: :binary_id, on_delete: :restrict), null: false

      add :task_id, references(:tasks, type: :binary_id, on_delete: :restrict), null: false
      add :snapshot_json, :map, null: false

      add :state, :string,
        null: false,
        default: "pending",
        check: %{
          name: "board_item_state",
          expr: "state IN ('pending','active','done','blocked','skipped','deferred')"
        }

      add :reason, :string
      add :completed_sha, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:board_execution_items, [:board_execution_id, :task_id])

    alter table(:runs) do
      add :board_execution_id,
          references(:board_executions, type: :binary_id, on_delete: :restrict)
    end

    create index(:runs, [:board_execution_id])
  end
end
