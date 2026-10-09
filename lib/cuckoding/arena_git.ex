defmodule Cuckoding.GitAdapter do
  @moduledoc false
  @callback run(map()) :: map()
end

defmodule Cuckoding.LocalGit do
  @moduledoc "Fixed native Git setup with scoped preview and mutation consent."
  @behaviour Cuckoding.GitAdapter
  alias Cuckoding.{GitPreview, NativeHelper}

  @statuses ~w(missing unborn initialized cancelled timeout cleanup_uncertain unavailable invalid_request folder_changed git_unavailable invalid_repository metadata_limit nested_repository unsupported_layout unsafe_config repository_busy repository_changed recheck_required invalid_selection selection_limit unsafe_file preview_changed initial_only index_present commit_incomplete unsafe_tree tree_limit worktree_incomplete worktree_exists worktree_mismatch)

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
      ] ++ extra(command),
      20_000,
      &decode/1
    )
  end

  defp extra(%{payload: %{"operation" => "preview", "paths" => paths}}),
    do: [Jason.encode!(%{"paths" => paths})]

  defp extra(%{id: key, payload: %{"operation" => "commit"} = payload}),
    do: [
      Jason.encode!(%{
        "key" => key,
        "preview_id" => payload["observation_id"],
        "preview" => payload["preview"]
      })
    ]

  defp extra(%{id: key, payload: %{"operation" => "worktree", "head" => head}}),
    do: [Jason.encode!(%{"key" => key, "head" => head})]

  defp extra(%{payload: %{"operation" => "inspect_worktree", "preparation" => receipt}}),
    do: [Jason.encode!(receipt)]

  defp extra(_), do: []

  defp decode(bytes) do
    case Jason.decode(bytes) do
      {:ok, result} -> normalize(result)
      _ -> %{"status" => "unavailable"}
    end
  end

  def normalize(%{"status" => "previewed", "preview" => preview}) do
    case GitPreview.normalize(preview) do
      nil -> %{"status" => "invalid_repository"}
      valid -> %{"status" => "previewed", "preview" => valid}
    end
  end

  def normalize(%{"status" => "committed"} = result) do
    if GitPreview.hash?(result["head"], 40) and GitPreview.hash?(result["tree"], 40) and
         match?({:ok, _}, Ecto.UUID.cast(result["preview_id"])),
       do: Map.take(result, ~w(status head tree preview_id)),
       else: %{"status" => "invalid_repository"}
  end

  def normalize(%{"status" => status} = result)
      when status in ~w(prepared worktree_unchanged worktree_changed) do
    if GitPreview.hash?(result["head"], 40) and
         match?({:ok, _}, Ecto.UUID.cast(result["key"])) and
         is_binary(result["path"]) and byte_size(result["path"]) <= 4096 and
         is_integer(result["device"]) and result["device"] >= 0 and
         is_integer(result["inode"]) and result["inode"] > 0,
       do: Map.take(result, ~w(status key head path device inode)),
       else: %{"status" => "invalid_repository"}
  end

  def normalize(%{"status" => "existing"} = result) do
    if GitPreview.hash?(result["head"], 40),
      do: Map.take(result, ~w(status head)),
      else: %{"status" => "invalid_repository"}
  end

  def normalize(%{"status" => status}) when status in @statuses, do: %{"status" => status}

  def normalize(_), do: %{"status" => "unavailable"}
end

defmodule Cuckoding.ArenaGit do
  @moduledoc "Durable, consented Arena Git setup; no remote or agent execution grants."
  import Ecto.Query
  alias Cuckoding.{Arena, Arenas, Command, Foundation, GitPreview, LocalGit, Repo}

  @kinds ~w(inspect_arena_git init_arena_git preview_arena_git commit_arena_git worktree_arena_git inspect_worktree_arena_git)
  @success %{
    "inspect" => ~w(missing unborn existing),
    "init" => ~w(initialized),
    "preview" => ~w(previewed),
    "commit" => ~w(committed),
    "worktree" => ~w(prepared),
    "inspect_worktree" => ~w(worktree_unchanged worktree_changed)
  }

  def latest(arena_id) do
    Repo.one(
      from c in Command,
        where:
          c.kind in @kinds and c.kind not in ~w(worktree_arena_git inspect_worktree_arena_git) and
            fragment("json_extract(?, '$.arena_id')", c.payload) == ^arena_id,
        order_by: [desc: c.inserted_at],
        limit: 1
    )
  end

  def worktrees(arena_id) do
    Repo.all(
      from c in Command,
        where:
          c.kind == "worktree_arena_git" and
            fragment("json_extract(?, '$.arena_id')", c.payload) == ^arena_id,
        order_by: [desc: c.inserted_at],
        limit: 10
    )
  end

  def worktree_inspections(arena_id, preparations) do
    Map.new(preparations, fn preparation ->
      command =
        Repo.one(
          from c in Command,
            where:
              c.kind == "inspect_worktree_arena_git" and
                fragment("json_extract(?, '$.arena_id')", c.payload) == ^arena_id and
                fragment("json_extract(?, '$.observation_id')", c.payload) == ^preparation.id,
            order_by: [desc: c.inserted_at, desc: c.id],
            limit: 1
        )

      {preparation.id, command}
    end)
  end

  def worktree_path(key),
    do:
      Path.join([
        Application.fetch_env!(:cuckoding, :data_dir),
        "runtime-home",
        "worktrees",
        key,
        "checkout"
      ])

  def can_prepare?(command, now \\ DateTime.utc_now())

  def can_prepare?(%Command{state: "completed", kind: kind, result: result} = command, now)
      when kind in ~w(inspect_arena_git commit_arena_git) and result in ~w(existing committed),
      do:
        DateTime.diff(now, command.updated_at) in 0..299 and
          GitPreview.hash?(command.payload["observation"]["head"], 40)

  def can_prepare?(_, _), do: false

  def can_initialize?(command, now \\ DateTime.utc_now())

  def can_initialize?(
        %Command{kind: "inspect_arena_git", state: "completed", result: "missing"} = command,
        now
      ),
      do: DateTime.diff(now, command.updated_at) in 0..299

  def can_initialize?(_, _), do: false

  def can_commit?(command, now \\ DateTime.utc_now())

  def can_commit?(
        %Command{kind: "preview_arena_git", state: "completed", result: "previewed"} = command,
        now
      ),
      do:
        DateTime.diff(now, command.updated_at) in 0..299 and
          not is_nil(GitPreview.normalize(command.payload["observation"]["preview"]))

  def can_commit?(_, _), do: false

  def preview(key, arena_id, paths) do
    with {:ok, key} <- Ecto.UUID.cast(key),
         {:ok, arena_id} <- Ecto.UUID.cast(arena_id),
         true <- GitPreview.valid_paths?(paths) do
      transaction(fn -> enqueue(key, arena_id, "preview", nil, %{"paths" => paths}) end)
    else
      _ -> {:error, "invalid_selection"}
    end
  end

  def request(key, arena_id, operation, observation_id \\ nil, confirmed \\ false) do
    with {:ok, key} <- Ecto.UUID.cast(key),
         {:ok, arena_id} <- Ecto.UUID.cast(arena_id),
         true <- operation in ~w(inspect init commit worktree inspect_worktree),
         true <-
           (operation == "inspect" and is_nil(observation_id)) or
             (operation == "inspect_worktree" and match?({:ok, _}, Ecto.UUID.cast(observation_id))) or
             (operation in ~w(init commit worktree) and confirmed == true and
                match?({:ok, _}, Ecto.UUID.cast(observation_id))) do
      transaction(fn -> enqueue(key, arena_id, operation, observation_id) end)
    else
      _ -> {:error, "confirmation_required"}
    end
  end

  defp enqueue(key, arena_id, operation, observation_id, options \\ %{}) do
    kind = "#{operation}_arena_git"

    case Repo.get(Command, key) do
      nil ->
        new_command(key, arena_id, kind, operation, observation_id, options)

      %Command{
        kind: ^kind,
        payload: %{"arena_id" => ^arena_id, "observation_id" => ^observation_id}
      } = command ->
        if Map.take(command.payload, Map.keys(options)) == options,
          do: command,
          else: Repo.rollback(:key_conflict)

      _ ->
        Repo.rollback(:key_conflict)
    end
  end

  defp new_command(key, arena_id, kind, operation, observation_id, options) do
    arena = Repo.get(Arena, arena_id)
    reason = rejection(arena, operation, observation_id)

    payload =
      Map.merge(options, %{
        "arena_id" => arena_id,
        "operation" => operation,
        "observation_id" => observation_id
      })

    payload =
      if operation == "commit" and is_nil(reason),
        do: Map.put(payload, "preview", latest(arena.id).payload["observation"]["preview"]),
        else: payload

    payload =
      if operation == "worktree" and is_nil(reason),
        do:
          Map.merge(payload, %{
            "head" => latest(arena.id).payload["observation"]["head"],
            "worktree_path" => worktree_path(key)
          }),
        else: payload

    payload =
      if operation == "inspect_worktree" and is_nil(reason),
        do: Map.put(payload, "preparation", preparation(arena.id, observation_id)),
        else: payload

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

      operation == "inspect_worktree" and is_nil(preparation(arena.id, observation_id)) ->
        "recheck_required"

      operation in ~w(init commit worktree) and
          not current_consent?(previous, operation, observation_id) ->
        "recheck_required"

      true ->
        nil
    end
  end

  defp preparation(arena_id, id) do
    case Repo.get(Command, id) do
      %Command{
        kind: "worktree_arena_git",
        state: "completed",
        result: "prepared",
        payload: %{"arena_id" => ^arena_id, "observation" => receipt}
      } = command ->
        public = LocalGit.normalize(receipt)

        if public["status"] == "prepared" and matching_worktree?(public, command),
          do: Map.take(public, ~w(key head path device inode))

      _ ->
        nil
    end
  end

  defp current_consent?(%Command{id: id} = previous, operation, id) do
    case operation do
      "init" -> can_initialize?(previous)
      "commit" -> can_commit?(previous)
      "worktree" -> can_prepare?(previous)
    end
  end

  defp current_consent?(_, _, _), do: false

  def execute(command) do
    with %Arena{} = arena <- Repo.get(Arena, command.payload["arena_id"]),
         {:ok, current} <- Arenas.inspect_folder(arena.path),
         true <- Enum.all?(~w(path device inode), &(current[&1] == command.payload[&1])),
         true <- Foundation.probe_active?(command),
         true <- worktree_current?(command) do
      LocalGit.run(command)
    else
      _ -> %{"status" => "folder_changed"}
    end
  end

  defp worktree_current?(%{kind: "worktree_arena_git"} = command) do
    previous = latest(command.payload["arena_id"])

    can_prepare?(previous) and previous.id == command.payload["observation_id"] and
      is_integer(command.lease_until) and command.lease_until > System.system_time(:millisecond)
  end

  defp worktree_current?(_), do: true

  def finish(claim, result) do
    transaction(fn ->
      current = Repo.get!(Command, claim.id)

      unless current.kind in @kinds and current.state in ~w(running cancelling) and
               current.attempts == claim.attempts,
             do: Repo.rollback(:lost_claim)

      if current.kind in ~w(worktree_arena_git inspect_worktree_arena_git) and
           current.state == "running" and
           (is_nil(current.lease_until) or current.lease_until <= System.system_time(:millisecond)),
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
    public = LocalGit.normalize(result) |> bind_receipt(command)

    public =
      case {command.kind, command.state, public["status"]} do
        {_, "cancelling", status} when status != "cleanup_uncertain" ->
          %{"status" => "cancelled"}

        _ ->
          public
      end

    elapsed = result["elapsed_ms"]

    if is_integer(elapsed) and elapsed in 0..25_000,
      do: Map.put(public, "elapsed_ms", elapsed),
      else: public
  end

  defp bind_receipt(
         %{"status" => "prepared"} = public,
         %{kind: "worktree_arena_git", payload: %{"operation" => "worktree"}} = command
       ) do
    if matching_worktree?(public, command), do: public, else: %{"status" => "recheck_required"}
  end

  defp bind_receipt(%{"status" => "prepared"}, _), do: %{"status" => "recheck_required"}

  defp bind_receipt(%{"status" => status} = public, command)
       when status in ~w(worktree_unchanged worktree_changed) do
    if command.kind == "inspect_worktree_arena_git" and
         Map.take(public, ~w(key head path device inode)) == command.payload["preparation"],
       do: public,
       else: %{"status" => "recheck_required"}
  end

  defp bind_receipt(public, command) do
    success =
      public["status"] in ~w(missing unborn existing initialized previewed committed prepared worktree_unchanged worktree_changed)

    valid_operation = public["status"] in Map.fetch!(@success, command.payload["operation"])

    cond do
      success and not valid_operation ->
        %{"status" => "recheck_required"}

      public["status"] == "previewed" and
          Enum.map(public["preview"]["files"], & &1["path"]) != command.payload["paths"] ->
        %{"status" => "recheck_required"}

      public["status"] == "committed" and
          public["preview_id"] != command.payload["observation_id"] ->
        %{"status" => "recheck_required"}

      true ->
        public
    end
  end

  defp matching_worktree?(public, command) do
    Map.take(public, ~w(key head path)) == %{
      "key" => command.id,
      "head" => command.payload["head"],
      "path" => command.payload["worktree_path"]
    } and public["path"] == worktree_path(command.id)
  end

  defp result_state("cancelled"), do: "cancelled"

  defp result_state(status)
       when status in ~w(missing unborn existing initialized previewed committed prepared worktree_unchanged worktree_changed),
       do: "completed"

  defp result_state(_), do: "failed"

  defp transaction(fun) do
    result = Repo.transaction(fun, mode: :immediate)
    if match?({:ok, _}, result), do: Foundation.broadcast()
    result
  end
end
