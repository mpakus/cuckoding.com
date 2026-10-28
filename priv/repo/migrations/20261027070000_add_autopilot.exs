defmodule Boss.Repo.Migrations.AddAutopilot do
  use Ecto.Migration

  def up do
    create table(:autopilots, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, references(:projects, on_delete: :restrict), null: false
      add :command_id, :string, null: false
      add :task_ids, {:array, :integer}, null: false
      add :check_config, :map, null: false
      add :config_hash, :string, null: false
      add :reviewer, :string, null: false
      add :status, :string, null: false, default: "running"
      add :reason, :text
      add :version, :integer, null: false, default: 0
      add :last_action, :string
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:autopilots, [:project_id, :command_id])

    execute(
      "CREATE UNIQUE INDEX autopilots_one_open ON autopilots((1)) WHERE status IN ('running','paused')"
    )

    create table(:autopilot_items, primary_key: false) do
      add :request_id, references(:delivery_requests, type: :string, on_delete: :restrict),
        primary_key: true

      add :autopilot_id, references(:autopilots, type: :string, on_delete: :restrict), null: false
      add :position, :integer, null: false
      add :integration_command_id, :string, null: false
    end

    create unique_index(:autopilot_items, [:autopilot_id, :position])
    create unique_index(:autopilot_items, [:integration_command_id])

    execute("DROP TRIGGER delivery_request_pin")

    execute("""
    CREATE TRIGGER delivery_request_pin BEFORE INSERT ON delivery_requests
    WHEN NEW.status!='queued' OR NEW.delivery_id IS NOT NULL OR NEW.reason IS NOT NULL
      OR NEW.reviewer NOT IN ('codex','claude') OR NOT EXISTS (
        SELECT 1 FROM tasks t JOIN specs s ON s.id=t.spec_id WHERE t.id=NEW.task_id
        AND s.project_id=NEW.project_id AND t.spec_revision_id=NEW.spec_revision_id
        AND t.state_version=NEW.admitted_version AND t.state IN ('new','failed','cancelled','blocked','needs_input','interrupted'))
      OR EXISTS (SELECT 1 FROM deliveries WHERE task_id=NEW.task_id AND (command_id=NEW.command_id OR status IN ('planning','implementing','testing','reviewing','integrating') OR cleanup='unknown'))
      OR EXISTS (SELECT 1 FROM agent_runs WHERE task_id=NEW.task_id AND (status IN ('preparing','launching','running','stopping') OR cleanup='unknown'))
      OR (SELECT COUNT(*) FROM delivery_requests q WHERE status IN ('queued','paused') AND NOT EXISTS (SELECT 1 FROM autopilot_items i WHERE i.request_id=q.id))>=32
    BEGIN SELECT RAISE(ABORT, 'invalid queued authorization'); END
    """)

    execute("""
    CREATE TRIGGER autopilot_insert BEFORE INSERT ON autopilots
    WHEN NEW.status!='running' OR NEW.reason IS NOT NULL OR NEW.version!=0 OR NEW.last_action IS NOT NULL OR NEW.reviewer NOT IN ('codex','claude')
      OR json_type(NEW.task_ids)!='array' OR json_array_length(NEW.task_ids) NOT BETWEEN 1 AND 256
      OR EXISTS (SELECT 1 FROM json_each(NEW.task_ids) WHERE type!='integer' OR value<=0)
      OR (SELECT COUNT(DISTINCT value) FROM json_each(NEW.task_ids))!=json_array_length(NEW.task_ids)
      OR (SELECT COUNT(*) FROM tasks t JOIN specs s ON s.id=t.spec_id WHERE s.project_id=NEW.project_id AND s.missing=0 AND t.state='new')!=json_array_length(NEW.task_ids)
      OR EXISTS (SELECT 1 FROM json_each(NEW.task_ids) j WHERE NOT EXISTS (SELECT 1 FROM tasks t JOIN specs s ON s.id=t.spec_id
        WHERE t.id=j.value AND s.project_id=NEW.project_id AND s.missing=0 AND t.state='new'))
      OR EXISTS (SELECT 1 FROM autopilots WHERE id=NEW.id OR (project_id=NEW.project_id AND command_id=NEW.command_id) OR status IN ('running','paused'))
    BEGIN SELECT RAISE(ABORT, 'invalid autopilot authorization'); END
    """)

    execute("""
    CREATE TRIGGER autopilot_update BEFORE UPDATE ON autopilots
    WHEN OLD.id!=NEW.id OR OLD.project_id!=NEW.project_id OR OLD.command_id!=NEW.command_id
      OR OLD.task_ids!=NEW.task_ids OR OLD.check_config!=NEW.check_config
      OR OLD.config_hash!=NEW.config_hash OR OLD.reviewer!=NEW.reviewer OR OLD.inserted_at!=NEW.inserted_at
      OR NEW.version!=OLD.version+1 OR OLD.status NOT IN ('running','paused') OR NEW.status NOT IN ('running','paused','cancelled','blocked','completed')
      OR (NEW.status='completed' AND ((SELECT COUNT(*) FROM autopilot_items WHERE autopilot_id=NEW.id)!=json_array_length(NEW.task_ids)
        OR EXISTS (SELECT 1 FROM autopilot_items i JOIN delivery_requests r ON r.id=i.request_id
          LEFT JOIN deliveries d ON d.id=r.delivery_id WHERE i.autopilot_id=NEW.id AND (d.id IS NULL OR d.status!='done'))))
    BEGIN SELECT RAISE(ABORT, 'autopilot authorization is immutable'); END
    """)

    execute("""
    CREATE TRIGGER autopilot_item_insert BEFORE INSERT ON autopilot_items
    WHEN NEW.position NOT BETWEEN 0 AND 255 OR length(NEW.integration_command_id)!=36
      OR EXISTS (SELECT 1 FROM autopilot_items WHERE request_id=NEW.request_id OR integration_command_id=NEW.integration_command_id
        OR (autopilot_id=NEW.autopilot_id AND position=NEW.position))
      OR NOT EXISTS (SELECT 1 FROM autopilots b JOIN delivery_requests r ON r.id=NEW.request_id
        WHERE b.id=NEW.autopilot_id AND b.status='running' AND r.status='queued'
        AND b.project_id=r.project_id AND b.check_config=r.check_config AND b.config_hash=r.config_hash AND b.reviewer=r.reviewer
        AND json_extract(b.task_ids,'$[' || NEW.position || ']')=r.task_id)
    BEGIN SELECT RAISE(ABORT, 'invalid autopilot item'); END
    """)

    for {table, operations} <- [
          {"autopilots", ["DELETE"]},
          {"autopilot_items", ["UPDATE", "DELETE"]}
        ] do
      for operation <- operations do
        execute(
          "CREATE TRIGGER #{table}_no_#{String.downcase(operation)} BEFORE #{operation} ON #{table} BEGIN SELECT RAISE(ABORT, 'autopilot history is immutable'); END"
        )
      end
    end

    execute("""
    CREATE TRIGGER autopilot_request_replace BEFORE INSERT ON delivery_requests
    WHEN EXISTS (SELECT 1 FROM delivery_requests WHERE id=NEW.id OR (task_id=NEW.task_id AND command_id=NEW.command_id)
      OR (task_id=NEW.task_id AND status IN ('queued','paused') AND NEW.status IN ('queued','paused'))
      OR (NEW.delivery_id IS NOT NULL AND delivery_id=NEW.delivery_id))
    BEGIN SELECT RAISE(ABORT, 'queue history is immutable'); END
    """)

    execute("""
    CREATE TRIGGER autopilot_manual_guard BEFORE INSERT ON agent_runs
    WHEN EXISTS (SELECT 1 FROM autopilots WHERE status='running')
    BEGIN SELECT RAISE(ABORT, 'autopilot owns execution'); END
    """)

    execute("""
    CREATE TRIGGER autopilot_delivery_guard BEFORE INSERT ON deliveries
    WHEN (EXISTS (SELECT 1 FROM autopilots WHERE status='running')
      AND NOT EXISTS (SELECT 1 FROM autopilot_items i JOIN autopilots b ON b.id=i.autopilot_id JOIN delivery_requests r ON r.id=i.request_id
        WHERE b.status='running' AND r.task_id=NEW.task_id AND r.command_id=NEW.command_id))
      OR EXISTS (SELECT 1 FROM autopilot_items i JOIN autopilots b ON b.id=i.autopilot_id JOIN delivery_requests r ON r.id=i.request_id
        WHERE r.task_id=NEW.task_id AND r.command_id=NEW.command_id AND (b.status!='running'
          OR (SELECT COUNT(*) FROM autopilot_items WHERE autopilot_id=b.id)!=json_array_length(b.task_ids)
          OR EXISTS (SELECT 1 FROM autopilot_items j JOIN delivery_requests q ON q.id=j.request_id JOIN deliveries d ON d.id=q.delivery_id
            WHERE j.autopilot_id=b.id AND d.status!='done')))
    BEGIN SELECT RAISE(ABORT, 'autopilot sequence unavailable'); END
    """)

    execute("""
    CREATE TRIGGER autopilot_integration_guard BEFORE UPDATE OF status ON deliveries
    WHEN NEW.status='integrating' AND OLD.status!='integrating' AND (
      (EXISTS (SELECT 1 FROM autopilots WHERE status='running') AND NOT EXISTS
        (SELECT 1 FROM autopilot_items i JOIN autopilots b ON b.id=i.autopilot_id JOIN delivery_requests r ON r.id=i.request_id
          WHERE b.status='running' AND r.delivery_id=NEW.id AND i.integration_command_id=NEW.integration_command_id
            AND (SELECT COUNT(*) FROM autopilot_items WHERE autopilot_id=b.id)=json_array_length(b.task_ids)))
      OR EXISTS (SELECT 1 FROM autopilot_items i JOIN autopilots b ON b.id=i.autopilot_id JOIN delivery_requests r ON r.id=i.request_id
        WHERE r.delivery_id=NEW.id AND b.status='paused'))
    BEGIN SELECT RAISE(ABORT, 'autopilot integration not authorized'); END
    """)
  end

  def down do
    if repo().aggregate("autopilots", :count) > 0,
      do: raise("Refusing to discard Autopilot history")

    for name <-
          ~w(autopilot_manual_guard autopilot_delivery_guard autopilot_integration_guard autopilot_request_replace),
        do: execute("DROP TRIGGER #{name}")

    execute("DROP TRIGGER delivery_request_pin")

    execute("""
    CREATE TRIGGER delivery_request_pin BEFORE INSERT ON delivery_requests
    WHEN NEW.status!='queued' OR NEW.delivery_id IS NOT NULL OR NEW.reason IS NOT NULL
      OR NEW.reviewer NOT IN ('codex','claude') OR NOT EXISTS (
        SELECT 1 FROM tasks t JOIN specs s ON s.id=t.spec_id WHERE t.id=NEW.task_id
        AND s.project_id=NEW.project_id AND t.spec_revision_id=NEW.spec_revision_id
        AND t.state_version=NEW.admitted_version AND t.state IN ('new','failed','cancelled','blocked','needs_input','interrupted'))
      OR EXISTS (SELECT 1 FROM deliveries WHERE task_id=NEW.task_id AND (command_id=NEW.command_id OR status IN ('planning','implementing','testing','reviewing','integrating') OR cleanup='unknown'))
      OR EXISTS (SELECT 1 FROM agent_runs WHERE task_id=NEW.task_id AND (status IN ('preparing','launching','running','stopping') OR cleanup='unknown'))
      OR (SELECT COUNT(*) FROM delivery_requests WHERE status IN ('queued','paused'))>=32
    BEGIN SELECT RAISE(ABORT, 'invalid queued authorization'); END
    """)

    drop table(:autopilot_items)
    drop table(:autopilots)
  end
end
