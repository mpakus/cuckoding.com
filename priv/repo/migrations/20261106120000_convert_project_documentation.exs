defmodule Boss.Repo.Migrations.ConvertProjectDocumentation do
  use Ecto.Migration

  def up do
    Boss.Repo.Migrations.DocumentationConversionSchema.up()
    flush()

    execute("""
    CREATE VIEW documentation_conversion_busy_projects AS
    SELECT p.id AS project_id FROM projects p WHERE
      EXISTS (SELECT 1 FROM agent_runs WHERE status IN ('preparing','launching','running','stopping') OR cleanup='unknown')
      OR EXISTS (SELECT 1 FROM deliveries WHERE status IN ('planning','implementing','testing','reviewing','integrating') OR cleanup='unknown')
      OR EXISTS (SELECT 1 FROM project_intakes WHERE status='planning' OR cleanup='unknown')
      OR EXISTS (SELECT 1 FROM delivery_requests WHERE status IN ('queued','paused'))
      OR EXISTS (SELECT 1 FROM autopilots WHERE status IN ('running','paused'))
      OR EXISTS (SELECT 1 FROM deliveries d WHERE d.project_id=p.id AND (d.status='ready_to_merge'
        OR (d.status!='done' AND (d.integration_intent!='{}' OR d.integration_command_id IS NOT NULL))))
      OR EXISTS (SELECT 1 FROM tasks t JOIN specs s ON s.id=t.spec_id WHERE s.project_id=p.id
        AND t.state IN ('planning','ready','implementing','testing','reviewing','approved','ready_to_merge','integrating'))
    """)

    execute("""
    CREATE TRIGGER documentation_conversion_insert BEFORE INSERT ON project_documentation_conversions
    WHEN length(NEW.id)!=36 OR length(NEW.command_id)!=36
      OR typeof(NEW.source_count)!='integer' OR NEW.source_count NOT BETWEEN 0 AND 256
      OR NOT EXISTS (SELECT 1 FROM projects p WHERE p.id=NEW.project_id AND p.intake_mode='specs'
        AND p.root_path=NEW.root_path AND p.git_common_dir=NEW.git_common_dir
        AND p.specs_path=NEW.specs_path AND p.base_branch IS NEW.base_branch)
      OR EXISTS (SELECT 1 FROM documentation_conversion_busy_projects WHERE project_id=NEW.project_id)
      OR (SELECT count(*) FROM specs WHERE project_id=NEW.project_id)!=NEW.source_count
      OR (SELECT count(*) FROM specs s JOIN tasks t ON t.spec_id=s.id
        JOIN spec_revisions r ON r.id=t.spec_revision_id AND r.spec_id=s.id
        WHERE s.project_id=NEW.project_id)!=NEW.source_count
      OR EXISTS (SELECT 1 FROM project_intakes WHERE project_id=NEW.project_id)
    BEGIN SELECT RAISE(ABORT, 'documentation conversion requires an idle complete source snapshot'); END
    """)

    execute("""
    CREATE TRIGGER documentation_source_insert BEFORE INSERT ON project_documentation_sources
    WHEN NOT EXISTS (SELECT 1 FROM project_documentation_conversions c
      JOIN projects p ON p.id=c.project_id JOIN specs s ON s.project_id=p.id
      JOIN tasks t ON t.spec_id=s.id JOIN spec_revisions pin ON pin.id=t.spec_revision_id AND pin.spec_id=s.id
      WHERE c.id=NEW.conversion_id AND p.intake_mode='specs' AND s.id=NEW.spec_id AND t.id=NEW.task_id
        AND NEW.spec_revision_id=t.spec_revision_id AND NEW.state_version=t.state_version AND NEW.state=t.state
        AND NEW.latest_revision_id=(SELECT id FROM spec_revisions WHERE spec_id=s.id ORDER BY number DESC LIMIT 1)
        AND NEW.identity_key=s.identity_key AND NEW.relative_path=s.relative_path AND NEW.missing=s.missing
        AND (SELECT count(*) FROM project_documentation_sources WHERE conversion_id=c.id)<c.source_count)
    BEGIN SELECT RAISE(ABORT, 'documentation sources require exact conversion pins'); END
    """)

    execute("""
    CREATE TRIGGER documentation_conversion_capture AFTER INSERT ON project_documentation_conversions
    BEGIN
      INSERT INTO project_documentation_sources
        (conversion_id,spec_id,task_id,spec_revision_id,latest_revision_id,state_version,state,identity_key,relative_path,missing)
      SELECT NEW.id,s.id,t.id,t.spec_revision_id,
        (SELECT id FROM spec_revisions WHERE spec_id=s.id ORDER BY number DESC LIMIT 1),
        t.state_version,t.state,s.identity_key,s.relative_path,s.missing
      FROM specs s JOIN tasks t ON t.spec_id=s.id WHERE s.project_id=NEW.project_id;
      UPDATE projects SET intake_mode='documentation' WHERE id=NEW.project_id;
    END
    """)

    execute("""
    CREATE TRIGGER documentation_project_mode BEFORE UPDATE ON projects
    WHEN (NEW.intake_mode IS NOT OLD.intake_mode AND NOT (
      OLD.intake_mode='specs' AND NEW.intake_mode='documentation'
      AND EXISTS (SELECT 1 FROM project_documentation_conversions c WHERE c.project_id=OLD.id
        AND c.source_count=(SELECT count(*) FROM project_documentation_sources WHERE conversion_id=c.id)
        AND c.source_count=(SELECT count(*) FROM specs WHERE project_id=OLD.id))))
      OR (EXISTS (SELECT 1 FROM project_documentation_conversions WHERE project_id=OLD.id)
        AND (NEW.id IS NOT OLD.id OR NEW.root_path IS NOT OLD.root_path OR NEW.git_common_dir IS NOT OLD.git_common_dir
          OR NEW.specs_path IS NOT OLD.specs_path OR NEW.base_branch IS NOT OLD.base_branch))
    BEGIN SELECT RAISE(ABORT, 'documentation conversion identity and mode are pinned'); END
    """)

    for table <- ~w(project_documentation_conversions project_documentation_sources),
        event <- ~w(UPDATE DELETE) do
      execute("""
      CREATE TRIGGER #{table}_immutable_#{String.downcase(event)} BEFORE #{event} ON #{table}
      BEGIN SELECT RAISE(ABORT, 'documentation conversion history is immutable'); END
      """)
    end

    for table <- ~w(deliveries delivery_requests agent_runs) do
      execute("""
      CREATE TRIGGER #{table}_reference_insert BEFORE INSERT ON #{table}
      WHEN EXISTS (SELECT 1 FROM project_documentation_sources WHERE task_id=NEW.task_id)
      BEGIN SELECT RAISE(ABORT, 'documentation references cannot execute'); END
      """)
    end

    execute("""
    CREATE TRIGGER documentation_reference_integration BEFORE UPDATE ON deliveries
    WHEN NEW.integration_command_id IS NOT OLD.integration_command_id
      AND EXISTS (SELECT 1 FROM project_documentation_sources WHERE task_id=OLD.task_id)
    BEGIN SELECT RAISE(ABORT, 'documentation references cannot integrate'); END
    """)

    for {table, column} <- [{"tasks", "task_id"}, {"specs", "spec_id"}],
        event <- ~w(UPDATE DELETE) do
      execute("""
      CREATE TRIGGER #{table}_reference_#{String.downcase(event)} BEFORE #{event} ON #{table}
      WHEN EXISTS (SELECT 1 FROM project_documentation_sources WHERE #{column}=OLD.id)
      BEGIN SELECT RAISE(ABORT, 'documentation reference history is immutable'); END
      """)
    end

    for {table, column} <- [{"task_events", "task_id"}, {"spec_revisions", "spec_id"}] do
      execute("""
      CREATE TRIGGER #{table}_reference_insert BEFORE INSERT ON #{table}
      WHEN EXISTS (SELECT 1 FROM project_documentation_sources WHERE #{column}=NEW.#{column})
      BEGIN SELECT RAISE(ABORT, 'documentation reference history is immutable'); END
      """)
    end

    execute("""
    CREATE TRIGGER documentation_intake_insert BEFORE INSERT ON project_intakes
    WHEN EXISTS (SELECT 1 FROM project_documentation_conversions c WHERE c.project_id=NEW.project_id)
      AND (NOT EXISTS (SELECT 1 FROM projects WHERE id=NEW.project_id AND intake_mode='documentation')
        OR EXISTS (SELECT 1 FROM specs s WHERE s.project_id=NEW.project_id
          AND NOT EXISTS (SELECT 1 FROM project_documentation_sources refs WHERE refs.spec_id=s.id))
        OR EXISTS (SELECT 1 FROM project_intakes WHERE project_id=NEW.project_id AND status='finished'))
    BEGIN SELECT RAISE(ABORT, 'converted documentation permits one complete generated plan'); END
    """)

    rewrite(
      "view",
      "autopilot_recovery_candidates",
      "WHERE s.missing=0",
      "WHERE s.missing=0 AND #{not_reference()}"
    )

    rewrite("trigger", "autopilot_insert", "s.missing=0", "s.missing=0 AND #{not_reference()}")
  end

  def down do
    unless repo().query!("SELECT count(*) FROM project_documentation_conversions").rows == [[0]],
      do: raise("Refusing to discard documentation conversion history")

    rewrite("trigger", "autopilot_insert", "s.missing=0 AND #{not_reference()}", "s.missing=0")

    rewrite(
      "view",
      "autopilot_recovery_candidates",
      "WHERE s.missing=0 AND #{not_reference()}",
      "WHERE s.missing=0"
    )

    for name <-
          ~w(documentation_conversion_insert documentation_source_insert documentation_conversion_capture
      documentation_project_mode documentation_reference_integration documentation_intake_insert) do
      execute("DROP TRIGGER #{name}")
    end

    for table <- ~w(project_documentation_conversions project_documentation_sources),
        event <- ~w(update delete),
        do: execute("DROP TRIGGER #{table}_immutable_#{event}")

    for table <- ~w(deliveries delivery_requests agent_runs task_events spec_revisions),
        do: execute("DROP TRIGGER #{table}_reference_insert")

    for table <- ~w(tasks specs),
        event <- ~w(update delete),
        do: execute("DROP TRIGGER #{table}_reference_#{event}")

    execute("DROP VIEW documentation_conversion_busy_projects")
    Boss.Repo.Migrations.DocumentationConversionSchema.down()
  end

  defp not_reference,
    do: "NOT EXISTS (SELECT 1 FROM project_documentation_sources refs WHERE refs.task_id=t.id)"

  defp rewrite(type, name, old, new) do
    flush()

    case repo().query!("SELECT sql FROM sqlite_master WHERE type=? AND name=?", [type, name]).rows do
      [[sql]] ->
        unless String.contains?(sql, old), do: raise("Unexpected #{name} boundary")
        execute("DROP #{String.upcase(type)} #{name}")
        execute(String.replace(sql, old, new))
        flush()

      [] ->
        :ok
    end
  end
end

# Independent empty metadata schema for historical-schema migration fixtures.
defmodule Boss.Repo.Migrations.DocumentationConversionSchema do
  use Ecto.Migration

  def up do
    create table(:project_documentation_conversions, primary_key: false) do
      add :id, :text, primary_key: true
      add :project_id, references(:projects, on_delete: :restrict), null: false
      add :command_id, :text, null: false
      add :source_count, :integer, null: false
      add :root_path, :text, null: false
      add :git_common_dir, :text, null: false
      add :specs_path, :text, null: false
      add :base_branch, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:project_documentation_conversions, [:project_id])
    create unique_index(:project_documentation_conversions, [:project_id, :command_id])

    create table(:project_documentation_sources, primary_key: false) do
      add :conversion_id,
          references(:project_documentation_conversions, type: :text, on_delete: :restrict),
          null: false

      add :spec_id, references(:specs, on_delete: :restrict), primary_key: true
      add :task_id, references(:tasks, on_delete: :restrict), null: false
      add :spec_revision_id, references(:spec_revisions, on_delete: :restrict), null: false
      add :latest_revision_id, references(:spec_revisions, on_delete: :restrict), null: false
      add :state_version, :integer, null: false
      add :state, :text, null: false
      add :identity_key, :text, null: false
      add :relative_path, :text, null: false
      add :missing, :boolean, null: false
    end

    create unique_index(:project_documentation_sources, [:task_id])
  end

  def down do
    unless repo().query!("SELECT count(*) FROM project_documentation_conversions").rows == [[0]],
      do: raise("Refusing to discard documentation conversion history")

    drop table(:project_documentation_sources)
    drop table(:project_documentation_conversions)
  end
end
