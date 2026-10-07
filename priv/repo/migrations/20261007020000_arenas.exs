defmodule Cuckoding.Repo.Migrations.Arenas do
  use Ecto.Migration

  def up do
    create table(:arenas, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :command_id, references(:commands, type: :binary_id), null: false
      add :selection_id, references(:commands, type: :binary_id), null: false
      add :team_revision_id, references(:team_revisions), null: false
      add :name, :string, null: false
      add :path, :string, null: false
      add :device, :integer, null: false
      add :inode, :integer, null: false
      add :git_entry, :string, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:arenas, [:command_id])
    create unique_index(:arenas, [:selection_id])
    create unique_index(:arenas, [:path])
    create unique_index(:arenas, [:device, :inode])
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
