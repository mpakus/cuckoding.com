defmodule Boss.Repo.Migrations.TrackMissingSpecs do
  use Ecto.Migration

  def up do
    alter table(:specs) do
      add :missing, :boolean, null: false, default: false
    end

    drop index(:specs, [:project_id, :relative_path])
    create unique_index(:specs, [:project_id, :relative_path], where: "missing = 0")
  end

  def down do
    drop index(:specs, [:project_id, :relative_path])
    # Reused paths must make rollback fail atomically, never delete retained history.
    create unique_index(:specs, [:project_id, :relative_path])

    alter table(:specs) do
      remove :missing
    end
  end
end
