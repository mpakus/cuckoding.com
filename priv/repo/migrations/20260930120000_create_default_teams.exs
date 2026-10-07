defmodule Cuckoding.Repo.Migrations.CreateDefaultTeams do
  use Ecto.Migration

  def up do
    create table(:default_teams, primary_key: false) do
      add :revision, :integer, primary_key: true
      add :config_json, :map, null: false
      add :source_hash, :string, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    for operation <- ~w(UPDATE DELETE) do
      execute("""
      CREATE TRIGGER default_teams_no_#{String.downcase(operation)}
      BEFORE #{operation} ON default_teams
      BEGIN SELECT RAISE(ABORT, 'default teams are immutable'); END
      """)
    end
  end

  def down, do: raise("released migrations are forward-only")
end
