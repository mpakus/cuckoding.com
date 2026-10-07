defmodule Cuckoding.Repo.Migrations.TeamAdoptions do
  use Ecto.Migration

  def up do
    create table(:team_adoptions) do
      add :arena_id, references(:arenas, type: :binary_id), null: false
      add :tabula_id, references(:tabulae, type: :binary_id)
      add :team_revision_id, references(:team_revisions), null: false
      add :command_id, references(:commands, type: :binary_id), null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:team_adoptions, [:command_id])
    create index(:team_adoptions, [:arena_id, :tabula_id, :id])

    for action <- ~w(UPDATE DELETE) do
      execute "CREATE TRIGGER team_adoptions_no_#{String.downcase(action)} BEFORE #{action} ON team_adoptions BEGIN SELECT RAISE(ABORT, 'immutable team adoption'); END"
    end

    execute "CREATE TRIGGER team_adoptions_scope BEFORE INSERT ON team_adoptions WHEN NEW.tabula_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tabulae WHERE id = NEW.tabula_id AND arena_id = NEW.arena_id) BEGIN SELECT RAISE(ABORT, 'foreign Tabula'); END"
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
