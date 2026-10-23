defmodule Cuckoding.Repo.Migrations.WriterCheckpoints do
  use Ecto.Migration

  def up do
    # Older bundles must refuse workflows whose writer/capture continuation they cannot interpret.
    execute "CREATE INDEX battle_attempts_writer_checkpoint ON battle_attempts(battle_id, task_id, json_extract(request, '$.task_context.preparation.key'), stage) WHERE state = 'completed'"
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
