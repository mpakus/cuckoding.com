defmodule Boss.DataDirectory do
  @moduledoc "Acquires a data-directory lock held until the application has stopped."
  alias Exqlite.Sqlite3

  def acquire(directory) do
    with :ok <- File.mkdir_p(directory),
         {:ok, lock} <- Sqlite3.open(Path.join(directory, ".owner.sqlite3")) do
      case prepare(directory, lock) do
        :ok ->
          {:ok, lock}

        {:error, reason} ->
          Sqlite3.close(lock)

          {:error,
           "BOSS data directory is already in use or cannot be opened: #{directory} (#{inspect(reason)})"}
      end
    else
      {:error, reason} ->
        {:error, "Cannot open BOSS data directory #{directory}: #{inspect(reason)}"}
    end
  end

  def release(lock), do: Sqlite3.close(lock)

  defp prepare(directory, lock) do
    with :ok <- Sqlite3.set_busy_timeout(lock, 0),
         :ok <- Sqlite3.execute(lock, "BEGIN EXCLUSIVE"),
         :ok <- File.chmod(directory, 0o700) do
      initialize_database(Path.join(directory, "boss.db"))
    end
  end

  # Set WAL before the Repo pool opens concurrent connections to a new database.
  defp initialize_database(path) do
    with {:ok, database} <- Sqlite3.open(path) do
      try do
        Sqlite3.execute(database, "PRAGMA journal_mode=WAL")
      after
        Sqlite3.close(database)
      end
    end
  end
end
