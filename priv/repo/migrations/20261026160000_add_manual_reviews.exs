defmodule Boss.Repo.Migrations.AddManualReviews do
  use Ecto.Migration

  def up do
    alter table(:agent_runs) do
      add :review_report, :map, null: false, default: %{}
    end

    execute("DROP TRIGGER agent_checks_parent")
    check_provenance("NEW.adapter NOT IN ('check','review')")

    execute("""
    CREATE TRIGGER agent_reviews_parent BEFORE INSERT ON agent_runs
    WHEN NEW.adapter = 'review' AND NOT EXISTS (
      SELECT 1 FROM agent_runs p WHERE p.id=NEW.parent_run_id
        AND p.adapter='check' AND p.status='finished' AND p.cleanup='group_empty'
        AND p.project_id=NEW.project_id AND p.task_id=NEW.task_id
        AND p.spec_revision_id=NEW.spec_revision_id AND p.candidate_commit=NEW.candidate_commit
        AND p.config_hash=NEW.config_hash AND p.check_config=NEW.check_config
        AND p.workspace=NEW.workspace AND p.workspace!='{}')
    BEGIN SELECT RAISE(ABORT, 'invalid review provenance'); END
    """)

    for action <- ["INSERT", "UPDATE"] do
      execute("""
      CREATE TRIGGER agent_reviews_complete_#{String.downcase(action)} BEFORE #{action} ON agent_runs
      WHEN (NEW.adapter = 'review' AND NEW.status = 'finished' AND
        (NEW.candidate_commit IS NULL OR NEW.cleanup != 'group_empty'
         OR NEW.exit_kind IS NOT 'exit' OR NEW.exit_code IS NOT 0
         OR json_type(NEW.review_report, '$.summary') IS NOT 'text'
         OR json_type(NEW.review_report, '$.acceptance') IS NOT 'array'
         OR json_type(NEW.review_report, '$.issues') IS NOT 'array'
         OR COALESCE(json_extract(NEW.review_report, '$.verdict'), '')
           NOT IN ('approved','changes_requested','needs_spec_revision')))
        OR (NEW.review_report != '{}' AND (NEW.adapter != 'review' OR NEW.status != 'finished'))
      BEGIN SELECT RAISE(ABORT, 'review report requires a complete receipt'); END
      """)
    end
  end

  def down do
    case repo().query!("SELECT COUNT(*) FROM agent_runs WHERE adapter = 'review'").rows do
      [[0]] -> :ok
      _ -> raise "Refusing to discard review history"
    end

    execute("DROP TRIGGER agent_reviews_parent")
    execute("DROP TRIGGER agent_reviews_complete_insert")
    execute("DROP TRIGGER agent_reviews_complete_update")
    execute("DROP TRIGGER agent_checks_parent")
    check_provenance("NEW.adapter != 'check'")

    alter table(:agent_runs) do
      remove :review_report
    end
  end

  defp check_provenance(other_adapter) do
    execute("""
    CREATE TRIGGER agent_checks_parent BEFORE INSERT ON agent_runs
    WHEN (NEW.adapter = 'check' AND (NEW.config_hash IS NULL OR NEW.check_config = '{}'
      OR NOT EXISTS (SELECT 1 FROM agent_runs p WHERE p.id=NEW.parent_run_id
        AND p.adapter='codex' AND p.status='finished' AND p.cleanup='group_empty'
        AND p.project_id=NEW.project_id AND p.task_id=NEW.task_id
        AND p.spec_revision_id=NEW.spec_revision_id)))
      OR (#{other_adapter} AND (NEW.parent_run_id IS NOT NULL
        OR NEW.config_hash IS NOT NULL OR NEW.check_config != '{}'))
    BEGIN SELECT RAISE(ABORT, 'invalid check provenance'); END
    """)
  end
end
