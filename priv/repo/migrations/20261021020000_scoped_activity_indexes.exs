defmodule Cuckoding.Repo.Migrations.ScopedActivityIndexes do
  use Ecto.Migration

  def up do
    execute "CREATE INDEX events_tabula_sequence ON events(json_extract(data, '$.tabula_id'), id) WHERE json_extract(data, '$.arena_id') IS NULL"
    execute "CREATE INDEX events_scoped_command_sequence ON events(command_id, id) WHERE json_extract(data, '$.arena_id') IS NULL AND json_extract(data, '$.tabula_id') IS NULL"
    execute "CREATE INDEX commands_arena ON commands(json_extract(payload, '$.arena_id'), id)"
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
