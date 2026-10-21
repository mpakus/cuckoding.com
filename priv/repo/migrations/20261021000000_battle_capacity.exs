defmodule Cuckoding.Repo.Migrations.BattleCapacity do
  use Ecto.Migration

  def up do
    execute "CREATE INDEX battle_attempts_running ON battle_attempts(state) WHERE state = 'running'"
    execute """
    CREATE INDEX battle_attempts_uncertain_connection
    ON battle_attempts(json_extract(request, '$.role.agent_id'))
    WHERE role IS NOT NULL AND coalesce(json_extract(result, '$.cleanup_verified'), 0) != 1
    """
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
