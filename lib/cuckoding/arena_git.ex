defmodule Cuckoding.GitAdapter do
  @moduledoc false
  @callback run(map()) :: map()
end

defmodule Cuckoding.LocalGit do
  @moduledoc "Fixed native Git metadata inspection and consented initialization."
  @behaviour Cuckoding.GitAdapter
  alias Cuckoding.NativeHelper

  @statuses ~w(missing unborn existing initialized cancelled timeout cleanup_uncertain unavailable invalid_request folder_changed git_unavailable invalid_repository metadata_limit nested_repository unsupported_layout unsafe_config repository_busy repository_changed recheck_required)

  @impl true
  def run(command) do
    payload = command.payload
    home = Path.join(Application.fetch_env!(:cuckoding, :data_dir), "runtime-home")

    NativeHelper.request(
      command,
      [
        "--arena-git",
        payload["operation"],
        payload["path"],
        to_string(payload["device"]),
        to_string(payload["inode"]),
        home
      ],
      20_000,
      &decode/1
    )
  end

  defp decode(bytes) do
    case Jason.decode(bytes) do
      {:ok, result} -> normalize(result)
      _ -> %{"status" => "unavailable"}
    end
  end

  def normalize(%{"status" => status} = result) when status in @statuses do
    cond do
      status == "existing" and is_binary(result["head"]) and
          Regex.match?(~r/\A[0-9a-f]{40}\z/, result["head"]) ->
        Map.take(result, ~w(status head))

      status == "existing" ->
        %{"status" => "invalid_repository"}

      true ->
        Map.take(result, ~w(status))
    end
  end

  def normalize(_), do: %{"status" => "unavailable"}
end

defmodule Cuckoding.ArenaGit do
  @moduledoc "Durable, Arena-scoped Git setup; no staging, commits or execution grants."
  import Ecto.Query
  alias Cuckoding.{Arena, Arenas, Command, Foundation, LocalGit, Repo}
  @kinds ~w(inspect_arena_git init_arena_git)

  def latest(arena_id) do
    Repo.one(
      from c in Command,
        where:
          c.kind in @kinds and
            fragment("json_extract(?, '$.arena_id')", c.payload) == ^arena_id,
        order_by: [desc: c.inserted_at],
        limit: 1
    )
  end

  def can_initialize?(command, now \\ DateTime.utc_now())

  def can_initialize?(
        %Command{kind: "inspect_arena_git", state: "completed", result: "missing"} = command,
        now
      ),
      do: DateTime.diff(now, command.updated_at) in 0..299

  def can_initialize?(_, _), do: false

  def request(key, arena_id, operation, observation_id \\ nil, confirmed \\ false) do
    with {:ok, key} <- Ecto.UUID.cast(key),
         {:ok, arena_id} <- Ecto.UUID.cast(arena_id),
         true <- operation in ~w(inspect init),
         true <-
           (operation == "inspect" and is_nil(observation_id)) or
             (operation == "init" and confirmed == true and
                match?({:ok, _}, Ecto.UUID.cast(observation_id))) do
      transaction(fn -> enqueue(key, arena_id, operation, observation_id) end)
    else
      _ -> {:error, "confirmation_required"}
    end
  end

  defp enqueue(key, arena_id, operation, observation_id) do
    kind = "#{operation}_arena_git"

    case Repo.get(Command, key) do
      nil ->
        new_command(key, arena_id, kind, operation, observation_id)

      %Command{
        kind: ^kind,
        payload: %{"arena_id" => ^arena_id, "observation_id" => ^observation_id}
      } = command ->
        command

      _ ->
        Repo.rollback(:key_conflict)
    end
  end

  defp new_command(key, arena_id, kind, operation, observation_id) do
    arena = Repo.get(Arena, arena_id)
    reason = rejection(arena, operation, observation_id)

    payload = %{
      "arena_id" => arena_id,
      "operation" => operation,
      "observation_id" => observation_id
    }

    payload =
      if arena,
        do:
          Map.merge(
            payload,
            Map.take(Map.from_struct(arena), [:path, :device, :inode])
            |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
          ),
        else: payload

    command =
      Repo.insert!(%Command{
        id: key,
        kind: kind,
        payload: payload,
        expected_revision: 0,
        state: if(reason, do: "rejected", else: "pending"),
        result: reason
      })

    Foundation.record(
      "arena_git.#{command.state}",
      %{"arena_id" => arena_id, "operation" => operation, "reason" => reason},
      key
    )

    command
  end

  defp rejection(nil, _, _), do: "arena_missing"

  defp rejection(arena, operation, observation_id) do
    previous = latest(arena.id)

    cond do
      Foundation.pending?() ->
        "setup_busy"

      operation == "init" and (not can_initialize?(previous) or previous.id != observation_id) ->
        "recheck_required"

      true ->
        nil
    end
  end

  def execute(command) do
    with %Arena{} = arena <- Repo.get(Arena, command.payload["arena_id"]),
         {:ok, current} <- Arenas.inspect_folder(arena.path),
         true <- Enum.all?(~w(path device inode), &(current[&1] == command.payload[&1])),
         true <- Foundation.probe_active?(command) do
      LocalGit.run(command)
    else
      _ -> %{"status" => "folder_changed"}
    end
  end

  def finish(claim, result) do
    transaction(fn ->
      current = Repo.get!(Command, claim.id)

      unless current.kind in @kinds and current.state in ~w(running cancelling) and
               current.attempts == claim.attempts,
             do: Repo.rollback(:lost_claim)

      public = observation(current, result)
      state = result_state(public["status"])

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
        "arena_git.#{state}",
        Map.merge(
          Map.take(public, ~w(status elapsed_ms)),
          %{
            "arena_id" => current.payload["arena_id"],
            "operation" => current.payload["operation"]
          }
        ),
        claim.id
      )

      updated
    end)
  end

  defp observation(command, result) do
    public = LocalGit.normalize(result)

    public =
      case {command.kind, command.state, public["status"]} do
        {_, "cancelling", status} when status != "cleanup_uncertain" ->
          %{"status" => "cancelled"}

        {"inspect_arena_git", _, "initialized"} ->
          %{"status" => "recheck_required"}

        {"init_arena_git", _, status} when status in ~w(missing unborn existing) ->
          %{"status" => "recheck_required"}

        _ ->
          public
      end

    elapsed = result["elapsed_ms"]

    if is_integer(elapsed) and elapsed in 0..25_000,
      do: Map.put(public, "elapsed_ms", elapsed),
      else: public
  end

  defp result_state("cancelled"), do: "cancelled"

  defp result_state(status) when status in ~w(missing unborn existing initialized),
    do: "completed"

  defp result_state(_), do: "failed"

  defp transaction(fun) do
    result = Repo.transaction(fun, mode: :immediate)
    if match?({:ok, _}, result), do: Foundation.broadcast()
    result
  end
end
