defmodule AgentDesk.Backup do
  @moduledoc """
  SQLite snapshot copies. Rollback is restore-from-copy, never an edited migration.
  """

  alias AgentDesk.Storage

  @spec snapshot() :: {:ok, String.t()} | {:error, term()}
  def snapshot do
    src = repo_path()
    dir = Storage.backup_dir()
    File.mkdir_p!(dir)
    dest = Path.join(dir, "agentdesk-#{System.system_time(:microsecond)}.sqlite3")

    cond do
      is_nil(src) ->
        {:error, :no_database}

      not File.exists?(src) ->
        {:error, :enoent}

      true ->
        case File.cp(src, dest) do
          :ok -> {:ok, dest}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp repo_path do
    config = Application.get_env(:agent_desk, AgentDesk.Repo, [])
    config[:database]
  end
end
