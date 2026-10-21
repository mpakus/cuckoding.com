defmodule Cuckoding.Repo.Migrations.DashboardObservations do
  use Ecto.Migration

  def up do
    create index(:battles, [:arena_id, :inserted_at, :id])
    create index(:tabulae, [:arena_id, :inserted_at, :id])
    execute "CREATE INDEX events_arena_sequence ON events(json_extract(data, '$.arena_id'), id)"
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
