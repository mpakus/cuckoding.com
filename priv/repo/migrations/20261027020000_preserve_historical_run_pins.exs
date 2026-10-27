defmodule Boss.Repo.Migrations.PreserveHistoricalRunPins do
  use Ecto.Migration

  def up do
    execute("DROP TRIGGER agent_runs_pin")

    execute("""
    CREATE TRIGGER agent_runs_pin BEFORE INSERT ON agent_runs
    WHEN NOT EXISTS (SELECT 1 FROM tasks t JOIN specs s ON s.id=t.spec_id
      JOIN spec_revisions r ON r.id=NEW.spec_revision_id AND r.spec_id=t.spec_id
      WHERE t.id=NEW.task_id AND t.state_version=NEW.admitted_version AND s.project_id=NEW.project_id
        AND ((NEW.adapter='codex' AND t.spec_revision_id=NEW.spec_revision_id)
          OR NEW.adapter IN ('check','review')))
    BEGIN SELECT RAISE(ABORT, 'run snapshot mismatch'); END
    """)
  end

  def down do
    case repo().query!("""
         SELECT EXISTS(SELECT 1 FROM task_events WHERE action='adopt_revision')
           OR EXISTS(SELECT 1 FROM agent_runs r JOIN tasks t ON t.id=r.task_id
             WHERE r.adapter IN ('check','review') AND r.spec_revision_id!=t.spec_revision_id)
         """).rows do
      [[0]] -> :ok
      _ -> raise Ecto.MigrationError, "cannot invalidate historical verification pins"
    end

    execute("DROP TRIGGER agent_runs_pin")

    execute("""
    CREATE TRIGGER agent_runs_pin BEFORE INSERT ON agent_runs
    WHEN NOT EXISTS (SELECT 1 FROM tasks t JOIN specs s ON s.id=t.spec_id
      WHERE t.id=NEW.task_id AND t.spec_revision_id=NEW.spec_revision_id
        AND t.state_version=NEW.admitted_version AND s.project_id=NEW.project_id)
    BEGIN SELECT RAISE(ABORT, 'run snapshot mismatch'); END
    """)
  end
end
