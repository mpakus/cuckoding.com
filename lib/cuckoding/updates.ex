defmodule Cuckoding.Updates do
  @moduledoc "Durable update preparation, snapshot, health, and rollback state."

  import Ecto.Query

  alias Cuckoding.Execution.Run
  alias Cuckoding.Repo
  alias Cuckoding.Shell
  alias Cuckoding.Updates.Attempt
  alias Cuckoding.Updates.Event
  alias Cuckoding.Updates.Snapshot

  @active_states ~w(queued running waiting paused)

  def prepare(target_version, schema_change, options \\ [])

  def prepare(target_version, schema_change, options)
      when is_binary(target_version) and is_boolean(schema_change) do
    current_version = Keyword.get(options, :current_version, current_version())
    snapshot = Keyword.get(options, :snapshot, &Snapshot.create/3)
    id = Ecto.UUID.generate()
    active_run_ids = active_run_ids()

    with :ok <- valid_upgrade?(current_version, target_version),
         :ok <- hibernate(options),
         [] <- active_run_ids(),
         {:ok, attempt} <-
           create_attempt(id, current_version, target_version, schema_change, active_run_ids),
         {:ok, backup} <-
           snapshot.(
             id,
             %{
               "from_version" => current_version,
               "to_version" => target_version,
               "schema_change" => schema_change,
               "active_run_ids" => active_run_ids
             },
             Keyword.get(
               options,
               :snapshot_options,
               Application.get_env(:cuckoding, :update_snapshot_options, [])
             )
           ),
         :ok <- write_pending(attempt, backup, options),
         {:ok, prepared} <-
           transition(attempt, "prepared", %{
             backup_path: backup.path,
             backup_manifest_hash: backup.manifest_hash
           }) do
      {:ok, prepared}
    else
      [_run_id | _rest] ->
        {:error, :active_runs_remain}

      {:error, reason} = error ->
        fail_if_created(id, reason)
        error
    end
  end

  def prepare(_target_version, _schema_change, _options), do: {:error, :invalid_update}

  def mark_installing(id) when is_binary(id) do
    case Repo.get(Attempt, id) do
      %Attempt{state: "prepared"} = attempt -> transition(attempt, "installing", %{})
      %Attempt{} -> {:error, :update_not_prepared}
      nil -> {:error, :update_not_found}
    end
  end

  def mark_healthy_pending(options \\ []) do
    with {:ok, pending} <- read_pending(options),
         %Attempt{} = attempt <- Repo.get(Attempt, pending["attempt_id"]),
         {:ok, healthy} <- mark_healthy(attempt),
         :ok <- clear_pending(attempt.id, options) do
      {:ok, healthy}
    else
      nil -> {:error, :update_not_found}
      {:error, :enoent} -> {:error, :update_not_pending}
      {:error, _reason} = error -> error
    end
  end

  def mark_failed(id, reason, options \\ []) when is_binary(id) and is_binary(reason) do
    with %Attempt{} = attempt <- Repo.get(Attempt, id),
         true <- attempt.state in ~w(prepared installing failed),
         {:ok, failed} <- mark_failed_attempt(attempt, reason),
         :ok <- clear_pending(id, options) do
      {:ok, failed}
    else
      nil -> {:error, :update_not_found}
      false -> {:error, :update_not_pending}
      {:error, _reason} = error -> error
    end
  end

  def pending(options \\ []), do: read_pending(options)

  def rollback_details(id) when is_binary(id) do
    case Repo.get(Attempt, id) do
      %Attempt{backup_path: path, backup_manifest_hash: hash} = attempt
      when is_binary(path) and is_binary(hash) ->
        {:ok, %{attempt: attempt, backup_path: path, manifest_hash: hash}}

      %Attempt{} ->
        {:error, :update_backup_missing}

      nil ->
        {:error, :update_not_found}
    end
  end

  def mark_rolled_back(id, reason) when is_binary(id) and is_binary(reason) do
    case Repo.get(Attempt, id) do
      %Attempt{} = attempt -> transition(attempt, "rolled_back", %{failure_reason: reason})
      nil -> {:error, :update_not_found}
    end
  end

  def clear_pending(id, options \\ []) when is_binary(id) do
    with {:ok, %{"attempt_id" => ^id}} <- read_pending(options),
         :ok <- File.rm(pending_path(options)) do
      :ok
    else
      {:error, :update_not_pending} -> :ok
      {:error, :enoent} -> :ok
      {:error, _reason} = error -> error
      _other -> {:error, :pending_update_mismatch}
    end
  end

  defp create_attempt(id, from, to, schema_change, active_run_ids) do
    Repo.transaction(fn ->
      attempt =
        %Attempt{}
        |> Attempt.create_changeset(%{
          id: id,
          from_version: from,
          to_version: to,
          schema_change: schema_change,
          state: "preparing",
          active_run_ids_json: active_run_ids
        })
        |> Repo.insert!()

      insert_event!(attempt.id, "update.preparing", %{
        "from_version" => from,
        "to_version" => to,
        "schema_change" => schema_change,
        "confirmed_by" => "local_shell_user",
        "active_run_ids" => active_run_ids
      })

      attempt
    end)
  end

  defp transition(attempt, state, attrs) do
    Repo.transaction(fn ->
      updated =
        attempt
        |> Ecto.Changeset.change(Map.merge(attrs, %{state: state}))
        |> Repo.update!()

      insert_event!(attempt.id, "update.#{state}", stringify(attrs))
      updated
    end)
  end

  defp insert_event!(attempt_id, event_type, details) do
    now = DateTime.utc_now()

    %Event{}
    |> Event.create_changeset(%{
      id: Ecto.UUID.generate(),
      update_attempt_id: attempt_id,
      event_type: event_type,
      command_key: "#{event_type}:#{attempt_id}",
      details_json: details,
      occurred_at: now
    })
    |> Repo.insert!()
  end

  defp fail_if_created(id, reason) do
    case Repo.get(Attempt, id) do
      %Attempt{} = attempt -> transition(attempt, "failed", %{failure_reason: inspect(reason)})
      nil -> :ok
    end
  end

  defp mark_healthy(%Attempt{state: "healthy"} = attempt), do: {:ok, attempt}

  defp mark_healthy(%Attempt{state: state} = attempt) when state in ~w(prepared installing),
    do: transition(attempt, "healthy", %{})

  defp mark_healthy(_attempt), do: {:error, :update_not_pending}

  defp mark_failed_attempt(%Attempt{state: "failed"} = attempt, _reason), do: {:ok, attempt}

  defp mark_failed_attempt(attempt, reason),
    do: transition(attempt, "failed", %{failure_reason: reason})

  defp hibernate(options) do
    policy = Keyword.get(options, :policy)
    if policy, do: Shell.shutdown(policy: policy), else: Shell.shutdown()
  end

  defp active_run_ids do
    Repo.all(
      from(run in Run,
        where: run.state in ^@active_states,
        order_by: run.id,
        select: run.id
      )
    )
  end

  defp valid_upgrade?(current, target) do
    with {:ok, current} <- Version.parse(current),
         {:ok, target} <- Version.parse(target),
         :gt <- Version.compare(target, current) do
      :ok
    else
      _other -> {:error, :invalid_update_version}
    end
  end

  defp write_pending(attempt, backup, options) do
    encoded =
      Jason.encode!(%{
        "version" => 1,
        "attempt_id" => attempt.id,
        "from_version" => attempt.from_version,
        "to_version" => attempt.to_version,
        "backup_path" => backup.path,
        "manifest_hash" => backup.manifest_hash
      }) <> "\n"

    path = pending_path(options)
    temporary = path <> ".tmp-#{System.unique_integer([:positive])}"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(temporary, encoded, [:binary, :exclusive]),
         :ok <- File.chmod(temporary, 0o600),
         :ok <- File.rename(temporary, path) do
      :ok
    else
      {:error, _reason} = error ->
        File.rm(temporary)
        error
    end
  end

  defp read_pending(options) do
    with {:ok, %{type: :regular, mode: mode, size: size}} when size <= 8_192 <-
           File.lstat(pending_path(options)),
         true <- Bitwise.band(mode, 0o077) == 0,
         {:ok, encoded} <- File.read(pending_path(options)),
         {:ok, %{"version" => 1} = pending} <- Jason.decode(encoded) do
      {:ok, pending}
    else
      {:error, :enoent} -> {:error, :update_not_pending}
      _other -> {:error, :invalid_pending_update}
    end
  end

  defp pending_path(options) do
    Keyword.get_lazy(options, :pending_path, fn ->
      Application.get_env(:cuckoding, :update_pending_path) ||
        Repo.config()[:database]
        |> Path.expand()
        |> Path.dirname()
        |> Path.join("pending-update.json")
    end)
  end

  defp current_version, do: Application.spec(:cuckoding, :vsn) |> to_string()

  defp stringify(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
