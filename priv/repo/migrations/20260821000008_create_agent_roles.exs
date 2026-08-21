defmodule AgentDesk.Repo.Migrations.CreateAgentRoles do
  use Ecto.Migration

  def change do
    create table(:agent_roles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :text, null: false
      add :description, :text, null: false, default: ""
      add :prompt, :text, null: false, default: ""
      add :permission_profile, :text, null: false, default: "default"
      add :skills, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_roles, [:project_id, :name])
  end
end
