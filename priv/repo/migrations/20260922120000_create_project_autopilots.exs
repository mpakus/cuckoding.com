defmodule Cuckoding.Repo.Migrations.CreateProjectAutopilots do
  use Ecto.Migration

  def change do
    create table(:project_autopilots, primary_key: false) do
      add :project_id, references(:projects, type: :binary_id, on_delete: :restrict),
        primary_key: true

      add :state, :string,
        null: false,
        default: "paused",
        check: %{
          name: "project_autopilots_state_valid",
          expr: "state IN ('paused', 'running', 'attention', 'done')"
        }

      add :max_active_runs, :integer,
        null: false,
        default: 2,
        check: %{
          name: "project_autopilots_max_runs_valid",
          expr: "max_active_runs BETWEEN 1 AND 32"
        }

      add :critical_blocker_limit, :integer,
        null: false,
        default: 1,
        check: %{
          name: "project_autopilots_blocker_limit_valid",
          expr: "critical_blocker_limit BETWEEN 1 AND 100"
        }

      add :last_issue, :string
      timestamps(type: :utc_datetime_usec)
    end
  end
end
