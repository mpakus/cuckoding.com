defmodule Cuckoding.Repo.Migrations.AddProjectCompletionMode do
  use Ecto.Migration

  def change do
    alter table(:project_autopilots) do
      add :completion_mode, :string,
        null: false,
        default: "manual",
        check: %{
          name: "project_completion_mode_valid",
          expr: "completion_mode IN ('manual', 'local')"
        }
    end
  end
end
