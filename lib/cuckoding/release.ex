defmodule Cuckoding.Release do
  @moduledoc false

  @app :cuckoding
  @missing_migration "** FILE NOT FOUND **"

  def migrate do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _result, _apps} =
        Ecto.Migrator.with_repo(
          repo,
          fn repository ->
            statuses = Ecto.Migrator.migrations(repository)
            ensure_migration_safe!(statuses)

            pending = Enum.count(statuses, &match?({:down, _, _}, &1))
            IO.puts("MIGRATION pending=#{pending}")
            migrated = Ecto.Migrator.run(repository, :up, all: true)
            IO.puts("MIGRATION complete=#{length(migrated)}")
            migrated
          end,
          pool_size: 1
        )
    end
  end

  def rollback_pending(reason \\ "candidate_health_failed") when is_binary(reason) do
    Application.load(@app)

    pending =
      case Cuckoding.Updates.pending() do
        {:ok, pending} -> pending
        {:error, reason} -> raise "pending update unavailable: #{inspect(reason)}"
      end

    details =
      with {:ok, details, _apps} <-
             Ecto.Migrator.with_repo(
               Cuckoding.Repo,
               fn _repo -> rollback_details!(pending["attempt_id"]) end,
               pool_size: 1
             ) do
        details
      end

    :ok =
      Cuckoding.Updates.Snapshot.restore(
        details.backup_path,
        details.manifest_hash
      )

    {:ok, _attempt, _apps} =
      Ecto.Migrator.with_repo(
        Cuckoding.Repo,
        fn _repo ->
          {:ok, attempt} = Cuckoding.Updates.mark_rolled_back(details.attempt.id, reason)
          :ok = Cuckoding.Updates.clear_pending(attempt.id)
          attempt
        end,
        pool_size: 1
      )

    :ok
  end

  def migration_plan(statuses) when is_list(statuses) do
    cond do
      Enum.any?(statuses, &match?({:up, _, @missing_migration}, &1)) ->
        {:error, :database_newer_than_application}

      Enum.any?(statuses, &match?({:up, _, _}, &1)) and
          Enum.any?(statuses, &match?({:down, _, _}, &1)) ->
        :backup_required

      Enum.any?(statuses, &match?({:down, _, _}, &1)) ->
        :clean_install

      true ->
        :current
    end
  end

  defp ensure_migration_safe!(statuses) do
    case migration_plan(statuses) do
      {:error, :database_newer_than_application} ->
        raise "database schema is newer than this application"

      :backup_required ->
        case Cuckoding.Updates.pending() do
          {:ok, _pending} -> :ok
          {:error, _reason} -> raise "pending migrations require an update snapshot"
        end

      _plan ->
        :ok
    end
  end

  defp rollback_details!(attempt_id) do
    case Cuckoding.Updates.rollback_details(attempt_id) do
      {:ok, details} -> details
      {:error, reason} -> raise "rollback metadata unavailable: #{inspect(reason)}"
    end
  end
end
