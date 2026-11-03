defmodule Boss.Repo.Migrations.AddProjectIntake do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE projects ADD COLUMN intake_mode TEXT NOT NULL DEFAULT 'specs'
    CHECK (intake_mode IN ('specs','documentation'))
    """)

    create table(:project_intakes, primary_key: false) do
      add :id, :text, primary_key: true
      add :project_id, references(:projects, on_delete: :restrict), null: false
      add :command_id, :text, null: false
      add :check_text, :text, null: false
      add :check_config, :map, null: false
      add :config_hash, :text, null: false
      add :reviewer, :text, null: false
      add :workspace, :map, null: false, default: %{}
      add :status, :text, null: false
      add :cleanup, :text, null: false
      add :reason, :text
      add :batch_id, references(:autopilots, type: :text, on_delete: :restrict)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:project_intakes, [:project_id, :command_id])
    create unique_index(:project_intakes, [:status], where: "status='planning'")
    create unique_index(:project_intakes, [:project_id], where: "status='finished'")
    create unique_index(:project_intakes, [:batch_id])

    execute("""
    CREATE TRIGGER project_intake_immutable BEFORE UPDATE ON project_intakes
    WHEN OLD.status!='planning' OR NEW.id IS NOT OLD.id OR NEW.project_id IS NOT OLD.project_id
      OR NEW.command_id IS NOT OLD.command_id OR NEW.check_text IS NOT OLD.check_text
      OR NEW.check_config IS NOT OLD.check_config
      OR NEW.config_hash IS NOT OLD.config_hash OR NEW.reviewer IS NOT OLD.reviewer
      OR (OLD.workspace!='{}' AND NEW.workspace IS NOT OLD.workspace)
    BEGIN SELECT RAISE(ABORT, 'project intake inputs or terminal receipt are immutable'); END
    """)
  end

  def down do
    unless repo().query!("SELECT count(*) FROM projects WHERE intake_mode='documentation'").rows ==
             [[0]],
           do: raise("Refusing to discard documentation project history")

    drop table(:project_intakes)
    execute("ALTER TABLE projects DROP COLUMN intake_mode")
  end
end
