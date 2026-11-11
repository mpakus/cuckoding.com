defmodule Boss.Repo.Migrations.CreateAgentRoles do
  use Ecto.Migration

  def change do
    create table(:agent_roles) do
      add :name, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_roles, [:name])

    create table(:agent_role_members) do
      add :role_id, references(:agent_roles, on_delete: :delete_all), null: false
      add :agent_id, :string, null: false
    end

    create unique_index(:agent_role_members, [:role_id, :agent_id])
    create index(:agent_role_members, [:agent_id])

    execute(
      """
      CREATE TRIGGER agent_role_member_known BEFORE INSERT ON agent_role_members
      WHEN NEW.agent_id NOT IN ('codex','claude','cursor','hermes','pi','opencode')
      BEGIN SELECT RAISE(ABORT, 'unknown agent'); END
      """,
      "DROP TRIGGER agent_role_member_known"
    )
  end
end
