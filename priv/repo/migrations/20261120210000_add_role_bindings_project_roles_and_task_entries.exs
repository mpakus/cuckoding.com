defmodule Boss.Repo.Migrations.AddRoleBindingsProjectRolesAndTaskEntries do
  use Ecto.Migration

  def up do
    drop_if_exists index(:agent_role_members, [:role_id, :agent_id])
    create index(:agent_role_members, [:role_id])

    execute("""
    CREATE UNIQUE INDEX agent_role_members_binding_index
    ON agent_role_members (
      role_id,
      agent_id,
      COALESCE(model_id, '__default__'),
      COALESCE(reasoning_effort, '__default__')
    )
    """)

    create table(:project_role_bindings) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :role_kind, :string, null: false
      add :member_id, references(:agent_role_members, on_delete: :nilify_all)
      add :agent_id, :string, null: false
      add :model_id, :string
      add :reasoning_effort, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:project_role_bindings, [:project_id, :role_kind])
    create index(:project_role_bindings, [:member_id])

    execute("""
    CREATE TRIGGER project_role_binding_valid_insert BEFORE INSERT ON project_role_bindings
    WHEN NEW.role_kind NOT IN ('reviewer','implementer','analytic')
      OR NEW.agent_id NOT IN ('codex','claude','cursor','opencode')
    BEGIN SELECT RAISE(ABORT, 'invalid project role binding'); END
    """)

    execute("""
    CREATE TRIGGER project_role_binding_valid_update BEFORE UPDATE ON project_role_bindings
    WHEN NEW.project_id != OLD.project_id
      OR NEW.role_kind != OLD.role_kind
      OR NEW.agent_id NOT IN ('codex','claude','cursor','opencode')
    BEGIN SELECT RAISE(ABORT, 'invalid project role binding'); END
    """)

    create table(:task_entries) do
      add :project_id, references(:projects, on_delete: :restrict), null: false
      add :task_id, references(:tasks, on_delete: :restrict), null: false
      add :delivery_id, :string
      add :spec_revision_id, references(:spec_revisions, on_delete: :restrict)
      add :author_role, :string, null: false
      add :agent_id, :string
      add :model_id, :string
      add :kind, :string, null: false
      add :cycle, :integer
      add :stage, :string
      add :summary, :string, null: false
      add :body, :text, null: false, default: ""
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:task_entries, [:project_id, :task_id, :id])
    create index(:task_entries, [:delivery_id])

    execute("""
    CREATE TRIGGER task_entries_valid_insert BEFORE INSERT ON task_entries
    WHEN NEW.author_role NOT IN ('analytic','implementer','reviewer','owner','system')
      OR NEW.kind NOT IN ('comment','spec_update','stage_log')
      OR (NEW.agent_id IS NOT NULL AND NEW.agent_id NOT IN ('codex','claude','cursor','hermes','pi','opencode'))
      OR length(trim(NEW.summary)) = 0
      OR octet_length(NEW.summary) > 240
      OR octet_length(NEW.body) > 8192
      OR NOT EXISTS (
        SELECT 1 FROM tasks t
        JOIN specs s ON s.id = t.spec_id
        WHERE t.id = NEW.task_id AND s.project_id = NEW.project_id
      )
    BEGIN SELECT RAISE(ABORT, 'invalid task entry'); END
    """)

    execute("""
    CREATE TRIGGER task_entries_no_update BEFORE UPDATE ON task_entries
    BEGIN SELECT RAISE(ABORT, 'task entries are immutable'); END
    """)

    execute("""
    CREATE TRIGGER task_entries_no_delete BEFORE DELETE ON task_entries
    BEGIN SELECT RAISE(ABORT, 'task entries are immutable'); END
    """)
  end

  def down do
    flush()

    if repo().aggregate("task_entries", :count) > 0 do
      raise Ecto.MigrationError, "cannot discard retained task entries"
    end

    case repo().query!("""
         SELECT COUNT(*) FROM (
           SELECT role_id, agent_id
           FROM agent_role_members
           GROUP BY role_id, agent_id
           HAVING COUNT(*) > 1
         )
         """).rows do
      [[0]] -> :ok
      _ -> raise Ecto.MigrationError, "cannot collapse multiple model bindings per role agent"
    end

    execute("DROP TRIGGER IF EXISTS task_entries_no_delete")
    execute("DROP TRIGGER IF EXISTS task_entries_no_update")
    execute("DROP TRIGGER IF EXISTS task_entries_valid_insert")
    drop table(:task_entries)

    execute("DROP TRIGGER IF EXISTS project_role_binding_valid_update")
    execute("DROP TRIGGER IF EXISTS project_role_binding_valid_insert")
    drop table(:project_role_bindings)

    execute("DROP INDEX IF EXISTS agent_role_members_binding_index")
    drop_if_exists index(:agent_role_members, [:role_id])
    create unique_index(:agent_role_members, [:role_id, :agent_id])
  end
end
