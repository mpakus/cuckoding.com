defmodule Cuckoding.Repo.Migrations.WorkflowRevisions do
  use Ecto.Migration

  def up do
    create table(:workflow_revisions) do
      add :tabula_id, references(:tabulae, type: :binary_id), null: false
      add :command_id, references(:commands, type: :binary_id), null: false
      add :revision, :integer, null: false
      add :definition, :map, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:workflow_revisions, [:tabula_id, :revision])
    create unique_index(:workflow_revisions, [:command_id])

    for action <- ~w(UPDATE DELETE) do
      execute "CREATE TRIGGER workflow_revisions_no_#{String.downcase(action)} BEFORE #{action} ON workflow_revisions BEGIN SELECT RAISE(ABORT, 'immutable workflow revision'); END"
    end

    execute "CREATE TRIGGER workflow_revisions_sequence BEFORE INSERT ON workflow_revisions WHEN NEW.revision != COALESCE((SELECT MAX(revision) FROM workflow_revisions WHERE tabula_id = NEW.tabula_id), 0) + 1 BEGIN SELECT RAISE(ABORT, 'invalid workflow revision'); END"
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
