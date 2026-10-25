defmodule Boss.Repo.Migrations.CreateSpecRevisions do
  use Ecto.Migration

  def change do
    create table(:specs) do
      add :project_id, references(:projects, on_delete: :restrict), null: false
      add :identity_key, :text, null: false
      add :relative_path, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:specs, [:project_id, :identity_key])
    create unique_index(:specs, [:project_id, :relative_path])

    create table(:spec_revisions) do
      add :spec_id, references(:specs, on_delete: :restrict), null: false
      add :number, :integer, null: false
      add :relative_path, :text, null: false
      add :content_hash, :string, null: false
      add :original_text, :text, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:spec_revisions, [:spec_id, :number])
    create unique_index(:spec_revisions, [:id, :spec_id])

    create table(:tasks) do
      add :spec_id, :bigint, null: false

      add :spec_revision_id,
          references(:spec_revisions, with: [spec_id: :spec_id], on_delete: :restrict),
          null: false

      add :title, :text, null: false
      add :state, :string, null: false, default: "new"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tasks, [:spec_id])

    for operation <- ["UPDATE", "DELETE"] do
      name = "spec_revisions_no_#{String.downcase(operation)}"

      execute(
        "CREATE TRIGGER #{name} BEFORE #{operation} ON spec_revisions BEGIN SELECT RAISE(ABORT, 'spec revisions are immutable'); END",
        "DROP TRIGGER #{name}"
      )
    end
  end
end
