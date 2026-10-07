defmodule Cuckoding.Arenas do
  @moduledoc "Local folder registration; no Git writes, content scans or execution grants."
  import Ecto.Query
  alias Cuckoding.{Arena, Command, Foundation, Repo, Team, TeamRevision}

  def list,
    do: Repo.all(from a in Arena, order_by: [desc: a.inserted_at], preload: :team_revision)

  def selection, do: Foundation.last_probe("choose_arena_folder")
  def team(%Command{expected_revision: id}), do: Repo.get!(TeamRevision, id)

  def choose(key) do
    with {:ok, id} <- Ecto.UUID.cast(key) do
      transaction(fn -> choose_command(id) end)
    end
  end

  defp choose_command(id) do
    case Repo.get(Command, id) do
      %Command{kind: "choose_arena_folder"} = command -> command
      nil -> enqueue(id)
      _ -> Repo.rollback(:key_conflict)
    end
  end

  defp enqueue(id) do
    busy = Foundation.pending?()

    command =
      Repo.insert!(%Command{
        id: id,
        kind: "choose_arena_folder",
        expected_revision: Team.current().id,
        state: if(busy, do: "rejected", else: "pending"),
        result: if(busy, do: "setup_busy")
      })

    Foundation.record("arena_folder.#{command.state}", %{}, id)
    command
  end

  def finish(claim, result) do
    transaction(fn ->
      current = Repo.get!(Command, claim.id)

      unless current.kind == "choose_arena_folder" and current.state in ["running", "cancelling"] and
               current.attempts == claim.attempts,
             do: Repo.rollback(:lost_claim)

      {state, status, folder} = outcome(current, result)

      elapsed = result["elapsed_ms"]
      elapsed = if is_integer(elapsed) and elapsed in 0..130_000, do: elapsed, else: nil

      updated =
        Repo.update!(
          Ecto.Changeset.change(current,
            state: state,
            result: status,
            lease_until: nil,
            payload: %{"folder" => folder, "elapsed_ms" => elapsed}
          )
        )

      Foundation.record(
        "arena_folder.#{state}",
        %{"status" => status, "elapsed_ms" => elapsed},
        claim.id
      )

      updated
    end)
  end

  defp outcome(_, %{"status" => "cleanup_uncertain"}), do: {"failed", "cleanup_uncertain", nil}
  defp outcome(%{state: "cancelling"}, _), do: {"cancelled", "cancelled", nil}

  defp outcome(_, result) do
    case observe(result) do
      {:ok, folder} -> {"completed", "selected", folder}
      {:error, "cancelled"} -> {"cancelled", "cancelled", nil}
      {:error, reason} -> {"failed", reason, nil}
    end
  end

  defp observe(%{"status" => "selected", "path" => path}), do: inspect_folder(path)

  defp observe(%{"status" => status})
       when status in ~w(cancelled timeout invalid_folder unavailable),
       do: {:error, status}

  defp observe(_), do: {:error, "unavailable"}

  def register(key, selection_id, name, confirmed) do
    with true <- confirmed == true,
         {:ok, key} <- Ecto.UUID.cast(key),
         {:ok, selection_id} <- Ecto.UUID.cast(selection_id),
         true <- valid_name?(name) do
      payload = %{"selection_id" => selection_id, "name" => String.trim(name)}

      transaction(fn -> register_command(key, payload) end) |> registered_result()
    else
      _ -> {:error, "invalid_registration"}
    end
  end

  defp registered_result({:ok, %Command{state: "completed"} = command}),
    do: {:ok, Repo.get_by!(Arena, command_id: command.id)}

  defp registered_result({:ok, %Command{result: reason}}), do: {:error, reason}
  defp registered_result(error), do: error

  defp register_command(id, payload) do
    case Repo.get(Command, id) do
      %Command{kind: "register_arena", payload: ^payload} = command -> command
      nil -> persist(id, payload)
      _ -> Repo.rollback(:key_conflict)
    end
  end

  defp persist(id, payload) do
    choice = Repo.get(Command, payload["selection_id"])
    result = registration_folder(choice)

    reason =
      case result do
        {:error, reason} -> reason
        _ -> nil
      end

    command =
      Repo.insert!(%Command{
        id: id,
        kind: "register_arena",
        payload: payload,
        expected_revision: if(choice, do: choice.expected_revision, else: 0),
        state: if(reason, do: "rejected", else: "completed"),
        result: reason
      })

    case result do
      {:ok, folder} ->
        arena =
          Repo.insert!(%Arena{
            command_id: id,
            selection_id: choice.id,
            name: payload["name"],
            team_revision_id: choice.expected_revision,
            path: folder["path"],
            device: folder["device"],
            inode: folder["inode"],
            git_entry: folder["git_entry"],
            inserted_at: DateTime.utc_now()
          })

        Foundation.record(
          "arena.registered",
          %{"arena_id" => arena.id, "team_revision" => choice.expected_revision},
          id
        )

      _ ->
        Foundation.record("arena.rejected", %{"reason" => reason}, id)
    end

    command
  end

  defp registration_folder(%Command{
         kind: "choose_arena_folder",
         state: "completed",
         result: "selected",
         payload: %{"folder" => folder}
       }) do
    with {:ok, current} <- inspect_folder(folder["path"]),
         true <-
           Map.take(current, ~w(path device inode)) == Map.take(folder, ~w(path device inode)) do
      if Repo.exists?(
           from a in Arena,
             where:
               a.path == ^current["path"] or
                 (a.device == ^current["device"] and a.inode == ^current["inode"])
         ), do: {:error, "already_registered"}, else: {:ok, current}
    else
      _ -> {:error, "folder_changed"}
    end
  end

  defp registration_folder(_), do: {:error, "selection_required"}

  # Metadata only. Native selection canonicalizes; recheck every component so a
  # replaced/symlinked path cannot silently become the registered directory.
  def inspect_folder(path) when is_binary(path) and byte_size(path) in 1..4096 do
    with true <- String.valid?(path) and not Regex.match?(~r/[\x00-\x1F\x7F]/, path),
         true <- Path.type(path) == :absolute and Path.expand(path) == path,
         true <- allowed_root?(path),
         true <- Enum.all?(components(path), &match?({:ok, %{type: :directory}}, File.lstat(&1))),
         {:ok, stat} <- File.stat(path),
         {:ok, git} <- git_entry(path) do
      {:ok,
       %{"path" => path, "device" => stat.major_device, "inode" => stat.inode, "git_entry" => git}}
    else
      _ -> {:error, "invalid_folder"}
    end
  end

  def inspect_folder(_), do: {:error, "invalid_folder"}

  defp allowed_root?(path) do
    home = Application.get_env(:cuckoding, :discovery_home)
    data = Application.fetch_env!(:cuckoding, :data_dir)
    denied = ~w(.ssh .aws .azure .gnupg .kube .config .codex .claude .cursor .hermes .git)

    is_binary(home) and not within?(home, path) and
      not within?(path, data) and not within?(data, path) and
      not Enum.any?(Path.split(path), &(&1 in denied)) and
      not Enum.any?(
        [
          Path.join(home, "Library"),
          "/System",
          "/Library",
          "/Applications",
          "/usr",
          "/bin",
          "/sbin",
          "/private/etc",
          "/private/var"
        ],
        &within?(path, &1)
      )
  end

  defp within?(path, root),
    do: path == root or String.starts_with?(path, String.trim_trailing(root, "/") <> "/")

  defp components(path), do: path |> Path.split() |> Enum.scan(&Path.join(&2, &1))

  defp git_entry(path) do
    case File.lstat(Path.join(path, ".git")) do
      {:ok, %{type: type}} when type in [:directory, :regular, :symlink] ->
        {:ok, "present_unverified"}

      {:error, :enoent} ->
        {:ok, "absent"}

      _ ->
        {:error, "invalid_folder"}
    end
  end

  defp valid_name?(name) when is_binary(name),
    do:
      String.valid?(name) and
        String.length(String.trim(name)) in 1..80 and not Regex.match?(~r/[\x00-\x1F\x7F]/, name)

  defp valid_name?(_), do: false

  defp transaction(fun) do
    result = Repo.transaction(fun, mode: :immediate)
    if match?({:ok, _}, result), do: Foundation.broadcast()
    result
  end
end
