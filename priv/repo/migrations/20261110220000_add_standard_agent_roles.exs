defmodule Boss.Repo.Migrations.AddStandardAgentRoles do
  use Ecto.Migration

  def change do
    alter table(:agent_roles) do
      add :kind, :string
    end

    create unique_index(:agent_roles, [:kind],
             where: "kind IS NOT NULL",
             name: :agent_roles_kind_index
           )

    execute(
      """
      CREATE TRIGGER agent_role_kind_insert BEFORE INSERT ON agent_roles
      WHEN NEW.kind IS NOT NULL AND NEW.kind NOT IN ('reviewer','implementer','analytic')
      BEGIN SELECT RAISE(ABORT, 'unknown role kind'); END
      """,
      "DROP TRIGGER agent_role_kind_insert"
    )

    execute(
      """
      CREATE TRIGGER agent_role_kind_update BEFORE UPDATE OF kind ON agent_roles
      WHEN NEW.kind IS NOT NULL AND NEW.kind NOT IN ('reviewer','implementer','analytic')
      BEGIN SELECT RAISE(ABORT, 'unknown role kind'); END
      """,
      "DROP TRIGGER agent_role_kind_update"
    )

    execute(
      """
      CREATE TRIGGER agent_role_standard_delete BEFORE DELETE ON agent_roles
      WHEN OLD.kind IS NOT NULL
      BEGIN SELECT RAISE(ABORT, 'standard role is permanent'); END
      """,
      "DROP TRIGGER agent_role_standard_delete"
    )

    execute(
      """
      CREATE TRIGGER agent_role_standard_rename BEFORE UPDATE OF name ON agent_roles
      WHEN OLD.kind IS NOT NULL AND NEW.name != OLD.name
      BEGIN SELECT RAISE(ABORT, 'standard role name is fixed'); END
      """,
      "DROP TRIGGER agent_role_standard_rename"
    )
  end
end
