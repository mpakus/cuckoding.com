defmodule Boss.Repo.Migrations.PinDocumentationStart do
  use Ecto.Migration

  @converted_guard """
    EXISTS (SELECT 1 FROM project_documentation_conversions WHERE project_id=NEW.project_id)
    AND (NOT EXISTS (SELECT 1 FROM projects WHERE id=NEW.project_id AND intake_mode='documentation')
      OR EXISTS (SELECT 1 FROM specs s WHERE s.project_id=NEW.project_id
        AND NOT EXISTS (SELECT 1 FROM project_documentation_sources refs WHERE refs.spec_id=s.id))
      OR EXISTS (SELECT 1 FROM project_intakes WHERE project_id=NEW.project_id AND status='finished'))
  """

  def up do
    execute("""
    ALTER TABLE project_intakes ADD COLUMN start_policy TEXT CHECK (start_policy IS NULL OR
      (json_valid(start_policy) AND json_extract(start_policy,'$.version') IS 1
      AND coalesce(json_type(start_policy,'$.spec_loop') IN ('true','false'),0)
      AND coalesce(json_type(start_policy,'$.parallel') IN ('true','false'),0)
      AND coalesce(json_type(start_policy,'$.previous_intake_id'),'null') IN ('text','null')))
    """)

    create table(:project_brief_tasks, primary_key: false) do
      add :task_id, references(:tasks, on_delete: :restrict), primary_key: true
      add :intake_id, references(:project_intakes, type: :text, on_delete: :restrict), null: false
      add :source_revision_id, references(:spec_revisions, on_delete: :restrict), null: false
      add :documents, :map, null: false
    end

    create unique_index(:project_brief_tasks, [:intake_id])

    create table(:spec_rework_revisions, primary_key: false) do
      add :revision_id, references(:spec_revisions, on_delete: :restrict), primary_key: true
      add :source_revision_id, references(:spec_revisions, on_delete: :restrict), null: false
    end

    execute("""
    CREATE TRIGGER spec_rework_revisions_insert BEFORE INSERT ON spec_rework_revisions
    WHEN NOT EXISTS (SELECT 1 FROM spec_revisions derived JOIN spec_revisions source
        ON source.spec_id=derived.spec_id AND source.number<derived.number
        WHERE derived.id=NEW.revision_id AND source.id=NEW.source_revision_id)
      OR EXISTS (SELECT 1 FROM spec_rework_revisions WHERE revision_id IN (NEW.revision_id, NEW.source_revision_id)
        OR source_revision_id=NEW.revision_id)
    BEGIN SELECT RAISE(ABORT, 'rework requires an earlier source revision of the same spec'); END
    """)

    execute("""
    CREATE TRIGGER project_brief_tasks_insert BEFORE INSERT ON project_brief_tasks
    WHEN NOT EXISTS (SELECT 1 FROM tasks t JOIN specs s ON s.id=t.spec_id JOIN project_intakes i ON i.project_id=s.project_id
        WHERE t.id=NEW.task_id AND t.spec_revision_id=NEW.source_revision_id AND i.id=NEW.intake_id
          AND i.status='planning' AND i.start_policy IS NOT NULL AND i.stop_requested=0)
      OR json_type(NEW.documents) IS NOT 'object' OR NOT EXISTS (SELECT 1 FROM json_each(NEW.documents))
      OR EXISTS (SELECT 1 FROM json_each(NEW.documents) WHERE type!='text')
      OR EXISTS (SELECT 1 FROM project_brief_tasks WHERE intake_id=NEW.intake_id OR task_id=NEW.task_id)
    BEGIN SELECT RAISE(ABORT, 'brief acceptance requires original documents and an owned task revision'); END
    """)

    for table <- ~w(project_brief_tasks spec_rework_revisions), op <- ~w(update delete) do
      execute("""
      CREATE TRIGGER #{table}_no_#{op} BEFORE #{op} ON #{table}
      BEGIN SELECT RAISE(ABORT, 'source evidence is immutable'); END
      """)
    end

    execute("""
    CREATE VIEW project_brief_replan_sources AS
    SELECT i.id AS intake_id, i.project_id FROM project_intakes i
    JOIN projects p ON p.id=i.project_id AND p.intake_mode='documentation'
    JOIN project_brief_tasks a ON a.intake_id=i.id
    JOIN tasks gate ON gate.id=a.task_id AND gate.state='done'
    WHERE i.status='finished' AND i.start_policy IS NOT NULL
      AND EXISTS (SELECT 1 FROM deliveries d JOIN delivery_steps post ON post.delivery_id=d.id
        WHERE d.project_id=i.project_id AND d.task_id=gate.id AND d.spec_revision_id=gate.spec_revision_id
          AND d.status='done' AND d.cleanup='group_empty' AND post.kind='post_check' AND post.status='finished'
          AND json_extract(post.receipt,'$.candidate_commit')=json_extract(d.integration_intent,'$.candidate_commit'))
      AND NOT EXISTS (SELECT 1 FROM project_intakes successor WHERE successor.status='finished'
        AND json_extract(successor.start_policy,'$.previous_intake_id')=i.id)
      AND NOT EXISTS (SELECT 1 FROM tasks t JOIN specs s ON s.id=t.spec_id
        WHERE s.project_id=i.project_id AND t.state!='done'
        AND NOT EXISTS (SELECT 1 FROM project_documentation_sources refs WHERE refs.task_id=t.id))
    """)

    drop index(:project_intakes, [:project_id])

    execute("""
    CREATE UNIQUE INDEX project_intake_first_finished ON project_intakes(project_id)
      WHERE status='finished' AND json_extract(start_policy,'$.previous_intake_id') IS NULL
    """)

    execute("""
    CREATE UNIQUE INDEX project_intake_finished_successor ON project_intakes(json_extract(start_policy,'$.previous_intake_id'))
      WHERE status='finished' AND json_extract(start_policy,'$.previous_intake_id') IS NOT NULL
    """)

    execute("DROP TRIGGER documentation_intake_insert")
    converted_guard("json_extract(NEW.start_policy,'$.previous_intake_id') IS NULL AND")

    execute("""
    CREATE TRIGGER project_intake_policy_insert BEFORE INSERT ON project_intakes
    WHEN EXISTS (SELECT 1 FROM project_intakes WHERE id=NEW.id OR (project_id=NEW.project_id AND command_id=NEW.command_id))
      OR (NEW.start_policy IS NOT NULL AND coalesce(json_array_length(NEW.check_config,'$.argv'),0)=0)
      OR (json_extract(NEW.start_policy,'$.previous_intake_id') IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM project_brief_replan_sources v WHERE v.project_id=NEW.project_id
        AND v.intake_id=json_extract(NEW.start_policy,'$.previous_intake_id')))
    BEGIN SELECT RAISE(ABORT, 'invalid documentation Start authorization'); END
    """)

    execute("""
    CREATE TRIGGER project_intake_policy_update BEFORE UPDATE ON project_intakes
    WHEN NEW.start_policy IS NOT OLD.start_policy OR
      (NEW.start_policy IS NOT NULL AND NEW.status='finished' AND (
        NOT EXISTS (SELECT 1 FROM project_brief_tasks a JOIN autopilot_items item ON item.autopilot_id=NEW.batch_id
          JOIN delivery_requests r ON r.id=item.request_id AND r.task_id=a.task_id WHERE a.intake_id=NEW.id)
        OR json_extract(NEW.start_policy,'$.spec_loop') IS NOT coalesce((
          SELECT spec_loop_enabled FROM autopilot_loop_configs WHERE autopilot_id=NEW.batch_id),0)
        OR json_extract(NEW.start_policy,'$.parallel') IS NOT coalesce((
          SELECT parallel_enabled FROM autopilot_loop_configs WHERE autopilot_id=NEW.batch_id),0)))
    BEGIN SELECT RAISE(ABORT, 'documentation batch must preserve whole-brief and loop authorization'); END
    """)
  end

  def down do
    for sql <- [
          "SELECT 1 FROM project_intakes WHERE start_policy IS NOT NULL LIMIT 1",
          "SELECT 1 FROM spec_rework_revisions LIMIT 1"
        ] do
      if repo().query!(sql).rows != [],
        do: raise("Refusing to discard documentation or spec rework evidence")
    end

    execute("DROP TRIGGER project_intake_policy_update")
    execute("DROP TRIGGER project_intake_policy_insert")
    execute("DROP TRIGGER documentation_intake_insert")
    converted_guard("")
    execute("DROP INDEX project_intake_finished_successor")
    execute("DROP INDEX project_intake_first_finished")
    create unique_index(:project_intakes, [:project_id], where: "status='finished'")
    execute("DROP VIEW project_brief_replan_sources")
    drop table(:spec_rework_revisions)
    drop table(:project_brief_tasks)
    execute("ALTER TABLE project_intakes DROP COLUMN start_policy")
  end

  defp converted_guard(prefix) do
    execute("""
    CREATE TRIGGER documentation_intake_insert BEFORE INSERT ON project_intakes
    WHEN #{prefix} #{@converted_guard}
    BEGIN SELECT RAISE(ABORT, 'converted documentation requires a validated planning source'); END
    """)
  end
end
