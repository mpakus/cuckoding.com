defmodule Boss.Repo.Migrations.AddTaskRevisionAdoption do
  use Ecto.Migration

  def up do
    alter table(:task_events) do
      add :target_spec_revision_id, references(:spec_revisions, on_delete: :restrict)
    end

    execute("""
    CREATE TRIGGER task_adoption_receipt BEFORE INSERT ON task_events
    WHEN (NEW.action='adopt_revision' AND (NEW.target_spec_revision_id IS NULL
      OR NEW.reason IS NOT NULL OR NEW.to_state!='new'
      OR NEW.from_state NOT IN ('new','ready','failed','interrupted','cancelled','blocked','needs_input','ready_to_merge')
      OR NOT EXISTS (SELECT 1 FROM tasks t
        JOIN spec_revisions old ON old.id=NEW.spec_revision_id AND old.spec_id=t.spec_id
        JOIN spec_revisions target ON target.id=NEW.target_spec_revision_id AND target.spec_id=t.spec_id
        WHERE t.id=NEW.task_id AND t.spec_revision_id=target.id AND target.number>old.number
          AND t.state_version=NEW.version AND t.state='new')))
      OR (NEW.action!='adopt_revision' AND NEW.target_spec_revision_id IS NOT NULL)
    BEGIN SELECT RAISE(ABORT, 'invalid adoption receipt'); END
    """)
  end

  def down do
    case repo().query!("SELECT COUNT(*) FROM task_events").rows do
      [[0]] -> :ok
      _ -> raise Ecto.MigrationError, "cannot discard retained task events"
    end

    execute("DROP TRIGGER task_adoption_receipt")

    alter table(:task_events) do
      remove :target_spec_revision_id
    end
  end
end
