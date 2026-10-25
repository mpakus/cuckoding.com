defmodule Boss.DataDirectory do
  @moduledoc "Holds the data directory's SQLite lock for the application's lifetime."
  use GenServer
  alias Exqlite.Sqlite3

  def start_link(opts) do
    GenServer.start_link(__MODULE__, Keyword.fetch!(opts, :directory),
      name: Keyword.get(opts, :name, __MODULE__)
    )
  end

  @impl true
  def init(directory) do
    Process.flag(:trap_exit, true)

    with :ok <- File.mkdir_p(directory),
         :ok <- File.chmod(directory, 0o700),
         {:ok, lock} <- Sqlite3.open(Path.join(directory, ".owner.sqlite3")) do
      :ok = Sqlite3.set_busy_timeout(lock, 0)

      case Sqlite3.execute(lock, "BEGIN EXCLUSIVE") do
        :ok ->
          {:ok, lock}

        {:error, reason} ->
          Sqlite3.close(lock)

          {:stop,
           "BOSS data directory is already in use or cannot be locked: #{directory} (#{inspect(reason)})"}
      end
    else
      {:error, reason} ->
        {:stop, "Cannot open BOSS data directory #{directory}: #{inspect(reason)}"}
    end
  end

  @impl true
  def terminate(_reason, lock), do: Sqlite3.close(lock)
end
