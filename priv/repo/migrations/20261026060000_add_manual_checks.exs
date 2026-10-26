defmodule Boss.Repo.Migrations.AddManualChecks do
  use Ecto.Migration

  def up do
    alter table(:agent_runs) do
      add :parent_run_id, references(:agent_runs, type: :string, on_delete: :restrict)
      add :check_config, :map, null: false, default: %{}
      add :config_hash, :string
      add :candidate_commit, :string
    end

    execute("""
    CREATE TRIGGER agent_checks_parent BEFORE INSERT ON agent_runs
    WHEN (NEW.adapter = 'check' AND (NEW.config_hash IS NULL OR NEW.check_config = '{}'
      OR NOT EXISTS (SELECT 1 FROM agent_runs p WHERE p.id=NEW.parent_run_id
        AND p.adapter='codex' AND p.status='finished' AND p.cleanup='group_empty'
        AND p.project_id=NEW.project_id AND p.task_id=NEW.task_id
        AND p.spec_revision_id=NEW.spec_revision_id)))
      OR (NEW.adapter != 'check' AND (NEW.parent_run_id IS NOT NULL
        OR NEW.config_hash IS NOT NULL OR NEW.check_config != '{}'))
    BEGIN SELECT RAISE(ABORT, 'invalid check provenance'); END
    """)

    execute("""
    CREATE TRIGGER agent_checks_immutable BEFORE UPDATE ON agent_runs
    WHEN OLD.parent_run_id IS NOT NEW.parent_run_id OR OLD.check_config != NEW.check_config
      OR OLD.config_hash IS NOT NEW.config_hash
      OR (OLD.candidate_commit IS NOT NULL AND OLD.candidate_commit IS NOT NEW.candidate_commit)
    BEGIN SELECT RAISE(ABORT, 'check provenance is immutable'); END
    """)

    for action <- ["INSERT", "UPDATE"] do
      execute("""
      CREATE TRIGGER agent_checks_complete_#{String.downcase(action)} BEFORE #{action} ON agent_runs
      WHEN NEW.adapter = 'check' AND NEW.status = 'finished' AND
        (NEW.candidate_commit IS NULL OR length(NEW.candidate_commit) NOT IN (40,64)
         OR NEW.candidate_commit GLOB '*[^0-9a-f]*' OR NEW.cleanup != 'group_empty'
         OR NEW.exit_kind IS NOT 'exit' OR NEW.exit_code IS NOT 0)
      BEGIN SELECT RAISE(ABORT, 'passing checks require a complete candidate receipt'); END
      """)
    end
  end

  def down do
    case repo().query!("SELECT COUNT(*) FROM agent_runs WHERE adapter = 'check'").rows do
      [[0]] -> :ok
      _ -> raise "Refusing to discard check history"
    end

    execute("DROP TRIGGER agent_checks_parent")
    execute("DROP TRIGGER agent_checks_immutable")
    execute("DROP TRIGGER agent_checks_complete_insert")
    execute("DROP TRIGGER agent_checks_complete_update")

    alter table(:agent_runs) do
      remove :parent_run_id
      remove :check_config
      remove :config_hash
      remove :candidate_commit
    end
  end
end
