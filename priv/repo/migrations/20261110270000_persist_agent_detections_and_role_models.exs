defmodule Boss.Repo.Migrations.PersistAgentDetectionsAndRoleModels do
  use Ecto.Migration

  def up do
    create table(:agent_detections, primary_key: false) do
      add :agent_id, :string, primary_key: true
      add :name, :string, null: false
      add :path, :string
      add :version, :string
      add :probe_status, :string, null: false
      add :auth_status, :string, null: false
      add :capabilities, :map, null: false, default: %{}
      add :errors, :map, null: false, default: %{"items" => []}
      add :models, :map, null: false, default: %{"items" => []}
      add :checked_at, :utc_datetime
      add :models_checked_at, :utc_datetime
      timestamps(type: :utc_datetime_usec)
    end

    execute("""
    CREATE TRIGGER agent_detection_valid_insert BEFORE INSERT ON agent_detections
    WHEN NEW.agent_id NOT IN ('codex','claude','cursor','hermes','pi','opencode')
      OR NEW.probe_status NOT IN ('ok','missing','unsupported','failed')
      OR NEW.auth_status NOT IN ('configured','stale','not_configured','unknown')
    BEGIN SELECT RAISE(ABORT, 'invalid agent detection state'); END
    """)

    execute("""
    CREATE TRIGGER agent_detection_valid_update BEFORE UPDATE ON agent_detections
    WHEN NEW.agent_id IS NOT OLD.agent_id
      OR NEW.probe_status NOT IN ('ok','missing','unsupported','failed')
      OR NEW.auth_status NOT IN ('configured','stale','not_configured','unknown')
    BEGIN SELECT RAISE(ABORT, 'invalid agent detection state'); END
    """)

    alter table(:agent_role_members) do
      add :model_id, :string
      add :reasoning_effort, :string
    end

    execute("""
    CREATE TRIGGER agent_role_member_authorized_insert BEFORE INSERT ON agent_role_members
    WHEN NOT EXISTS (
      SELECT 1 FROM agent_detections d
      WHERE d.agent_id = NEW.agent_id
        AND d.probe_status = 'ok'
        AND d.auth_status = 'configured'
    )
    OR (
      NEW.model_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM agent_detections d, json_each(d.models, '$.items') m
        WHERE d.agent_id = NEW.agent_id
          AND json_extract(m.value, '$.id') = NEW.model_id
      )
    )
    BEGIN SELECT RAISE(ABORT, 'role requires a detected and authorized agent model'); END
    """)

    execute("""
    CREATE TRIGGER agent_role_member_authorized_update BEFORE UPDATE ON agent_role_members
    WHEN NOT EXISTS (
      SELECT 1 FROM agent_detections d
      WHERE d.agent_id = NEW.agent_id
        AND d.probe_status = 'ok'
        AND d.auth_status = 'configured'
    )
    OR (
      NEW.model_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM agent_detections d, json_each(d.models, '$.items') m
        WHERE d.agent_id = NEW.agent_id
          AND json_extract(m.value, '$.id') = NEW.model_id
      )
    )
    BEGIN SELECT RAISE(ABORT, 'role requires a detected and authorized agent model'); END
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS agent_role_member_authorized_update")
    execute("DROP TRIGGER IF EXISTS agent_role_member_authorized_insert")

    alter table(:agent_role_members) do
      remove :reasoning_effort
      remove :model_id
    end

    execute("DROP TRIGGER IF EXISTS agent_detection_valid_update")
    execute("DROP TRIGGER IF EXISTS agent_detection_valid_insert")
    drop table(:agent_detections)
  end
end
