defmodule AgentDesk.Repo.Migrations.CreateSearchProjection do
  use Ecto.Migration

  def change do
    create table(:search_documents, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :source, :text, null: false
      add :source_id, :text, null: false
      add :title, :text, null: false
      add :passage, :text, null: false
      add :path, :text
      add :content_hash, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:search_documents, [:project_id, :source])
    create unique_index(:search_documents, [:project_id, :source, :source_id])

    create table(:search_memories, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :namespace, :text, null: false
      add :text, :text, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:search_memories, [:project_id, :namespace])

    create table(:search_index_states, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :status, :text, null: false
      add :adapter, :text, null: false
      add :last_indexed_at, :utc_datetime_usec
      add :error, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:search_index_states, [:project_id])
  end
end
