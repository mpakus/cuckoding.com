defmodule Cuckoding.Repo.Migrations.ProjectChecks do
  use Ecto.Migration

  def up do
    create table(:check_revisions) do
      add :arena_id, references(:arenas, type: :binary_id), null: false
      add :command_id, references(:commands, type: :binary_id), null: false
      add :revision, :integer, null: false
      add :definition, :map, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:check_revisions, [:arena_id, :revision])
    create unique_index(:check_revisions, [:command_id])

    for action <- ~w(UPDATE DELETE) do
      execute "CREATE TRIGGER check_revisions_no_#{String.downcase(action)} BEFORE #{action} ON check_revisions BEGIN SELECT RAISE(ABORT, 'immutable check revision'); END"
    end

    execute "CREATE TRIGGER check_revisions_sequence BEFORE INSERT ON check_revisions WHEN NEW.revision != COALESCE((SELECT MAX(revision) FROM check_revisions WHERE arena_id = NEW.arena_id), 0) + 1 BEGIN SELECT RAISE(ABORT, 'invalid check revision'); END"
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
