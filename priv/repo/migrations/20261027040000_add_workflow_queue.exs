defmodule Boss.Repo.Migrations.AddWorkflowQueue do
  use Ecto.Migration
  @active "status IN ('planning','implementing','testing','reviewing','integrating')"
  @manual "status IN ('preparing','launching','running','stopping') OR cleanup='unknown'"

  def up do
    create table(:delivery_requests, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, references(:projects, on_delete: :restrict), null: false
      add :task_id, references(:tasks, on_delete: :restrict), null: false
      add :spec_revision_id, references(:spec_revisions, on_delete: :restrict), null: false
      add :delivery_id, references(:deliveries, type: :string, on_delete: :restrict)
      add :command_id, :string, null: false
      add :admitted_version, :integer, null: false
      add :check_config, :map, null: false
      add :config_hash, :string, null: false
      add :reviewer, :string, null: false
      add :status, :string, null: false, default: "queued"
      add :reason, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:delivery_requests, [:task_id, :command_id])
    create unique_index(:delivery_requests, [:delivery_id])
    create index(:delivery_requests, [:status, :inserted_at, :id])

    execute(
      "CREATE UNIQUE INDEX delivery_requests_pending ON delivery_requests(task_id) WHERE status IN ('queued','paused')"
    )

    execute("""
    CREATE TRIGGER delivery_request_pin BEFORE INSERT ON delivery_requests
    WHEN NEW.status!='queued' OR NEW.delivery_id IS NOT NULL OR NEW.reason IS NOT NULL
      OR NEW.reviewer NOT IN ('codex','claude') OR NOT EXISTS (
        SELECT 1 FROM tasks t JOIN specs s ON s.id=t.spec_id WHERE t.id=NEW.task_id
        AND s.project_id=NEW.project_id AND t.spec_revision_id=NEW.spec_revision_id
        AND t.state_version=NEW.admitted_version AND t.state IN ('new','failed','cancelled','blocked','needs_input','interrupted'))
      OR EXISTS (SELECT 1 FROM deliveries WHERE task_id=NEW.task_id AND (command_id=NEW.command_id OR #{@active} OR cleanup='unknown'))
      OR EXISTS (SELECT 1 FROM agent_runs WHERE task_id=NEW.task_id AND (#{@manual}))
      OR (SELECT COUNT(*) FROM delivery_requests WHERE status IN ('queued','paused'))>=32
    BEGIN SELECT RAISE(ABORT, 'invalid queued authorization'); END
    """)

    execute("""
    CREATE TRIGGER delivery_request_immutable BEFORE UPDATE ON delivery_requests
    WHEN OLD.id!=NEW.id OR OLD.project_id!=NEW.project_id OR OLD.task_id!=NEW.task_id
      OR OLD.spec_revision_id!=NEW.spec_revision_id OR OLD.admitted_version!=NEW.admitted_version
      OR OLD.command_id!=NEW.command_id OR OLD.check_config!=NEW.check_config
      OR OLD.config_hash!=NEW.config_hash OR OLD.reviewer!=NEW.reviewer OR OLD.inserted_at!=NEW.inserted_at
      OR OLD.status IN ('started','cancelled','stale')
      OR NEW.status NOT IN ('queued','paused','started','cancelled','stale')
      OR (NEW.status='started' AND OLD.status!='queued')
      OR (NEW.status!='started' AND NEW.delivery_id IS NOT NULL)
      OR (NEW.status='started' AND NOT EXISTS (SELECT 1 FROM deliveries d WHERE d.id=NEW.delivery_id
        AND d.project_id=NEW.project_id AND d.task_id=NEW.task_id AND d.spec_revision_id=NEW.spec_revision_id
        AND d.admitted_version=NEW.admitted_version AND d.command_id=NEW.command_id
        AND d.check_config=NEW.check_config AND d.config_hash=NEW.config_hash AND d.reviewer=NEW.reviewer))
    BEGIN SELECT RAISE(ABORT, 'queued authorization is immutable'); END
    """)

    execute(
      "CREATE TRIGGER delivery_requests_no_delete BEFORE DELETE ON delivery_requests BEGIN SELECT RAISE(ABORT, 'queue history is immutable'); END"
    )

    execute("""
    CREATE TRIGGER queued_task_revision BEFORE UPDATE OF spec_revision_id ON tasks
    WHEN OLD.spec_revision_id!=NEW.spec_revision_id AND EXISTS
      (SELECT 1 FROM delivery_requests WHERE task_id=OLD.id AND status IN ('queued','paused'))
    BEGIN SELECT RAISE(ABORT, 'queued source is pinned'); END
    """)

    execute("""
    CREATE TRIGGER queued_manual_guard BEFORE INSERT ON agent_runs
    WHEN EXISTS (SELECT 1 FROM delivery_requests WHERE task_id=NEW.task_id AND status IN ('queued','paused'))
    BEGIN SELECT RAISE(ABORT, 'queued workflow owns task'); END
    """)

    execute("""
    CREATE TRIGGER queued_delivery_guard BEFORE INSERT ON deliveries
    WHEN EXISTS (SELECT 1 FROM delivery_requests WHERE task_id=NEW.task_id AND (status IN ('queued','paused') OR command_id=NEW.command_id))
      AND NOT EXISTS (SELECT 1 FROM delivery_requests q WHERE q.task_id=NEW.task_id AND q.status='queued'
        AND q.project_id=NEW.project_id AND q.command_id=NEW.command_id
        AND q.spec_revision_id=NEW.spec_revision_id AND q.admitted_version=NEW.admitted_version
        AND q.check_config=NEW.check_config AND q.config_hash=NEW.config_hash AND q.reviewer=NEW.reviewer)
    BEGIN SELECT RAISE(ABORT, 'queued workflow owns task'); END
    """)

    execute("DROP INDEX deliveries_one_open")
    execute("DROP TRIGGER delivery_guard_insert")
    execute("DROP TRIGGER delivery_guard_update")
    # Only acquisitions are guarded: a running peer must never prevent recording unknown cleanup.
    for {operation, acquisition} <- [
          {"INSERT", "NEW.#{@active}"},
          {"UPDATE",
           "(NEW.#{@active} AND NOT (OLD.#{@active})) OR (NEW.status='integrating' AND OLD.status!='integrating')"}
        ] do
      execute("""
      CREATE TRIGGER delivery_guard_#{String.downcase(operation)} BEFORE #{operation} ON deliveries
      WHEN (#{acquisition}) AND (
        EXISTS (SELECT 1 FROM agent_runs WHERE #{@manual})
        OR EXISTS (SELECT 1 FROM deliveries d WHERE d.id!=NEW.id AND (d.cleanup='unknown' OR d.status='integrating'))
        OR (SELECT COUNT(*) FROM deliveries d WHERE d.id!=NEW.id AND d.#{@active})>=2
        OR (NEW.status='integrating' AND EXISTS (SELECT 1 FROM deliveries d WHERE d.id!=NEW.id AND d.#{@active})))
      BEGIN SELECT RAISE(ABORT, 'execution capacity unavailable'); END
      """)
    end
  end

  def down do
    if repo().aggregate("delivery_requests", :count) > 0,
      do: raise("Refusing to discard queue history")

    if repo().query!("SELECT COUNT(*) FROM deliveries WHERE #{@active} OR cleanup='unknown'").rows
       |> hd()
       |> hd() > 1,
       do: raise("Refusing to discard concurrent delivery capacity")

    for name <-
          ~w(queued_task_revision queued_manual_guard queued_delivery_guard delivery_guard_insert delivery_guard_update),
        do: execute("DROP TRIGGER #{name}")

    drop table(:delivery_requests)

    execute(
      "CREATE UNIQUE INDEX deliveries_one_open ON deliveries ((1)) WHERE #{@active} OR cleanup='unknown'"
    )

    for operation <- ["INSERT", "UPDATE"] do
      execute("""
      CREATE TRIGGER delivery_guard_#{String.downcase(operation)} BEFORE #{operation} ON deliveries
      WHEN (NEW.#{@active} OR NEW.cleanup='unknown') AND EXISTS (SELECT 1 FROM agent_runs WHERE #{@manual})
      BEGIN SELECT RAISE(ABORT, 'another run owns execution'); END
      """)
    end
  end
end
