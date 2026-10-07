defmodule Cuckoding.PlanningDocuments do
  @moduledoc "Explicit local text snapshots; no provider or filesystem grant."
  import Ecto.Query
  alias Cuckoding.{Arena, Command, Foundation, GitPreview, NativeHelper, Repo, Tabulae}

  def latest(tabula_id) do
    Repo.one(
      from c in Command,
        where:
          c.kind == "preview_documents" and
            fragment("json_extract(?, '$.tabula_id')", c.payload) == ^tabula_id,
        order_by: [
          desc: fragment("? IN ('pending', 'running', 'cancelling')", c.state),
          desc: c.inserted_at
        ],
        limit: 1
    )
  end

  def valid_paths?(paths) when is_list(paths) and length(paths) in 1..4,
    do:
      GitPreview.valid_paths?(paths) and
        Enum.all?(paths, &(Path.extname(String.downcase(&1)) in ~w(.md .txt)))

  def valid_paths?(_), do: false

  def request(key, arena_id, tabula_id, paths) do
    with {:ok, key} <- Ecto.UUID.cast(key),
         %{} = board <- Tabulae.get(arena_id, tabula_id),
         true <- valid_paths?(paths) do
      input = %{"arena_id" => board.arena_id, "tabula_id" => board.id, "paths" => paths}

      transaction(fn -> enqueue(key, board, input) end)
    else
      _ -> {:error, "invalid_documents"}
    end
  end

  defp enqueue(key, board, input) do
    case Repo.get(Command, key) do
      nil ->
        arena = Repo.get!(Arena, board.arena_id)
        reason = if Foundation.pending?(), do: "profile_busy"

        command =
          Repo.insert!(%Command{
            id: key,
            kind: "preview_documents",
            expected_revision: 0,
            payload:
              Map.merge(input, %{
                "path" => arena.path,
                "device" => arena.device,
                "inode" => arena.inode
              }),
            state: if(reason, do: "rejected", else: "pending"),
            result: reason
          })

        Foundation.record("documents.#{command.state}", %{"tabula_id" => board.id}, key)
        command

      %Command{kind: "preview_documents"} = command ->
        if Map.take(command.payload, Map.keys(input)) == input,
          do: command,
          else: Repo.rollback(:key_conflict)

      _ ->
        Repo.rollback(:key_conflict)
    end
  end

  def execute(command) do
    p = command.payload
    home = Path.join(Application.fetch_env!(:cuckoding, :data_dir), "runtime-home")

    NativeHelper.request(
      command,
      [
        "--arena-git",
        "documents",
        p["path"],
        to_string(p["device"]),
        to_string(p["inode"]),
        home,
        Jason.encode!(%{"paths" => p["paths"]})
      ],
      20_000,
      &decode/1,
      32_768
    )
  end

  defp decode(bytes) do
    case Jason.decode(bytes) do
      {:ok, result} -> normalize(result)
      _ -> %{"status" => "invalid_documents"}
    end
  end

  def normalize(%{"status" => "previewed", "files" => files}) do
    if valid_files?(files),
      do: %{"status" => "previewed", "files" => files},
      else: %{"status" => "invalid_documents"}
  end

  def normalize(%{"status" => status})
      when status in ~w(cancelled timeout cleanup_uncertain unavailable folder_changed repository_busy invalid_selection selection_limit unsafe_file preview_changed invalid_text),
      do: %{"status" => status}

  def normalize(_), do: %{"status" => "invalid_documents"}

  def valid_files?(files) when is_list(files) and length(files) in 1..4 do
    Enum.all?(files, &valid_file?/1) and valid_paths?(Enum.map(files, & &1["path"])) and
      Enum.sum(Enum.map(files, & &1["bytes"])) <= 12_000
  end

  def valid_files?(_), do: false

  defp valid_file?(%{"path" => _, "text" => text, "bytes" => bytes, "sha256" => hash} = file)
       when map_size(file) == 4 and is_binary(text) and is_integer(bytes) and bytes in 0..4096 do
    String.valid?(text) and byte_size(text) == bytes and
      not Regex.match?(~r/[^\P{Cc}\n\r\t]/u, text) and
      Base.encode16(:crypto.hash(:sha256, text), case: :lower) == hash
  end

  defp valid_file?(_), do: false

  def selected(_board, nil), do: {:ok, []}

  def selected(board, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Command{kind: "preview_documents", state: "completed", result: "previewed"} = command <-
           Repo.get(Command, id),
         true <- command.payload["arena_id"] == board.arena_id,
         true <- command.payload["tabula_id"] == board.id,
         true <- DateTime.diff(DateTime.utc_now(), command.updated_at) in 0..299,
         files when is_list(files) <- get_in(command.payload, ["observation", "files"]),
         true <- valid_files?(files) do
      {:ok, files}
    else
      _ -> {:error, "documents_expired"}
    end
  end

  def finish(claim, result) do
    transaction(fn ->
      current = Repo.get!(Command, claim.id)

      unless current.kind == "preview_documents" and current.state in ~w(running cancelling) and
               current.attempts == claim.attempts,
             do: Repo.rollback(:lost_claim)

      public = observation(current, result)

      state =
        case public["status"] do
          "previewed" -> "completed"
          "cancelled" -> "cancelled"
          _ -> "failed"
        end

      updated =
        Repo.update!(
          Ecto.Changeset.change(current,
            state: state,
            result: public["status"],
            payload: Map.put(current.payload, "observation", public),
            lease_until: nil
          )
        )

      Foundation.record(
        "documents.#{state}",
        %{
          "tabula_id" => current.payload["tabula_id"],
          "status" => public["status"],
          "elapsed_ms" => public["elapsed_ms"],
          "file_count" => length(public["files"] || [])
        },
        claim.id
      )

      updated
    end)
  end

  defp observation(current, result) do
    public = normalize(result)

    public =
      cond do
        current.state == "cancelling" and public["status"] != "cleanup_uncertain" ->
          %{"status" => "cancelled"}

        public["status"] == "previewed" and
            Enum.map(public["files"], & &1["path"]) != current.payload["paths"] ->
          %{"status" => "invalid_documents"}

        true ->
          public
      end

    elapsed = result["elapsed_ms"]

    if is_integer(elapsed) and elapsed in 0..25_000,
      do: Map.put(public, "elapsed_ms", elapsed),
      else: public
  end

  defp transaction(fun) do
    result = Repo.transaction(fun, mode: :immediate)
    if match?({:ok, _}, result), do: Foundation.broadcast()
    result
  end
end
