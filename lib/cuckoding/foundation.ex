defmodule Cuckoding.Foundation do
  @moduledoc "Idempotent setup commands and their committed public event stream."
  import Ecto.Query
  alias Cuckoding.{Codex, Command, Event, Repo, Workspace}
  @auth_kinds ~w(login_codex logout_codex)
  @exclusive_kinds @auth_kinds ++
                     [
                       "plan_tabula",
                       "preview_documents",
                       "accept_spec",
                       "check_codex_model",
                       "choose_arena_folder",
                       "inspect_arena_git",
                       "init_arena_git",
                       "preview_arena_git",
                       "commit_arena_git",
                       "worktree_arena_git"
                     ]

  def workspace, do: Repo.get!(Workspace, 1)
  def catalog_status(connection, now \\ DateTime.utc_now())

  def catalog_status(%{"catalog_status" => "fresh", "fetched_at" => fetched}, now)
      when is_binary(fetched) do
    with {:ok, time, _} <- DateTime.from_iso8601(fetched),
         age when age in 0..86_399 <- DateTime.diff(now, time) do
      "fresh"
    else
      _ -> "stale"
    end
  end

  def catalog_status(connection, _), do: connection["catalog_status"] || "not_requested"
  def events, do: Repo.all(from e in Event, order_by: [desc: e.id], limit: 10)

  def pending?,
    do: Repo.exists?(from c in Command, where: c.state in ["pending", "running", "cancelling"])

  def pending_probe(kind \\ "probe_codex") do
    kinds = List.wrap(kind)

    Repo.one(
      from c in Command,
        where: c.kind in ^kinds and c.state in ["pending", "running", "cancelling"],
        order_by: c.inserted_at,
        limit: 1
    )
  end

  def last_probe(kind \\ "probe_codex") do
    kinds = List.wrap(kind)

    Repo.one(
      from c in Command, where: c.kind in ^kinds, order_by: [desc: c.inserted_at], limit: 1
    )
  end

  def login_link(
        %Command{kind: "login_codex", state: "running", result: "awaiting_login"} = command
      ) do
    if probe_active?(command), do: Codex.login_link(command.id)
  end

  def login_link(_), do: nil

  def login_redirect(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Command{} = command <- Repo.get(Command, id) do
      login_link(command)
    else
      _ -> nil
    end
  end

  def login_waiting(claim) do
    case Repo.transaction(
           fn -> mark_login_waiting(claim) end,
           mode: :immediate
         ) do
      {:ok, _} -> :ok
      _ -> :error
    end
  end

  defp mark_login_waiting(claim) do
    current = Repo.get!(Command, claim.id)

    if current.kind != "login_codex" or not probe_active?(claim) or
         workspace().revision != claim.expected_revision,
       do: Repo.rollback(:lost_claim)

    unless current.result == "awaiting_login" do
      Repo.update!(Ecto.Changeset.change(current, result: "awaiting_login"))
      record("login.awaiting_browser", %{}, claim.id)
    end
  end

  def probe_active?(claim) do
    now = System.system_time(:millisecond)

    Repo.exists?(
      from c in Command,
        where: c.id == ^claim.id and c.state == "running" and c.attempts == ^claim.attempts,
        where: c.kind != "worktree_arena_git" or c.lease_until > ^now
    )
  end

  def check_codex(key, expected, path, confirmed) do
    with true <- confirmed == true,
         {:ok, identity} <- Codex.executable(path) do
      command(key, expected, "probe_codex", identity)
    else
      false -> {:error, :confirmation_required}
      error -> error
    end
  end

  def cancel_probe(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Repo.transaction(fn -> cancel_command(Repo.get(Command, id)) end, mode: :immediate)
        |> tap(fn _ -> broadcast() end)

      _ ->
        {:error, :invalid_command}
    end
  end

  defp cancel_command(%Command{kind: kind, state: "running"} = command)
       when kind in @exclusive_kinds do
    Repo.update!(Ecto.Changeset.change(command, state: "cancelling", result: "awaiting_cleanup"))
    record(prefix(kind) <> "cancelling", %{}, command.id)
  end

  defp cancel_command(%Command{kind: kind, state: state} = command)
       when kind in [
              "probe_codex",
              "inspect_codex",
              "login_codex",
              "logout_codex",
              "plan_tabula",
              "preview_documents",
              "accept_spec",
              "check_codex_model",
              "choose_arena_folder",
              "inspect_arena_git",
              "init_arena_git",
              "preview_arena_git",
              "commit_arena_git",
              "worktree_arena_git"
            ] and
              state in ["pending", "running"] do
    Repo.update!(
      Ecto.Changeset.change(command, state: "cancelled", result: "cancelled", lease_until: nil)
    )

    record(prefix(kind) <> "cancelled", %{}, command.id)
  end

  defp cancel_command(_), do: :ok

  def inspect_codex(key, expected, confirmed) do
    profile_command(key, expected, confirmed, "inspect_codex")
  end

  def authorize_codex(key, expected, operation, confirmed) when operation in [:login, :logout] do
    profile_command(key, expected, confirmed, "#{operation}_codex")
  end

  defp profile_command(key, expected, confirmed, kind) do
    with true <- confirmed == true,
         {:ok, identity} <- verified_executable() do
      command(key, expected, kind, identity)
    else
      false -> {:error, :confirmation_required}
      error -> error
    end
  end

  def verified_executable do
    with %{"status" => "supported", "command_id" => id, "path" => path} <- workspace().codex,
         %Command{kind: "probe_codex", state: "completed", payload: identity} <-
           Repo.get(Command, id),
         {:ok, ^identity} <- Codex.executable(path) do
      {:ok, identity}
    else
      _ -> {:error, :version_required}
    end
  end

  def check_model(key, expected, model_id, confirmed) do
    connection = workspace().connection

    with true <- confirmed == true,
         {:ok, identity} <- verified_executable(),
         %{} = model <- Enum.find(connection["models"] || [], &(&1["id"] == model_id)) do
      # The least advertised effort is enough for the fixed diagnostic response.
      effort =
        Enum.find(~w(none minimal low medium high xhigh max), &(&1 in model["efforts"])) ||
          model["default_effort"]

      command(key, expected, "check_codex_model", %{
        "identity" => identity,
        "model_id" => model_id,
        "model" => model["model"],
        "effort" => effort,
        "connection_command_id" => connection["command_id"],
        "fetched_at" => connection["fetched_at"],
        "grant" => "scratch-read-only-v1"
      })
    else
      false -> {:error, :confirmation_required}
      {:error, _} = error -> error
      _ -> {:error, :model_refresh_required}
    end
  end

  def model_check_current?(payload) do
    connection = workspace().connection

    connection["status"] == "checked" and connection["authorization"] == "chatgpt" and
      catalog_status(connection) == "fresh" and connection["identity"] == payload["identity"] and
      connection["command_id"] == payload["connection_command_id"] and
      connection["fetched_at"] == payload["fetched_at"] and
      model_available?(connection, payload)
  end

  defp model_available?(connection, payload) do
    Enum.any?(connection["models"] || [], fn model ->
      model["id"] == payload["model_id"] and model["model"] == payload["model"] and
        payload["effort"] in model["efforts"]
    end)
  end

  def discover(key, expected_revision) do
    command(key, expected_revision, "discover_tools", %{})
  end

  defp command(key, expected_revision, kind, payload) do
    with {:ok, id} <- Ecto.UUID.cast(key),
         true <- is_integer(expected_revision) and expected_revision >= 0 do
      result =
        Repo.transaction(
          fn -> find_or_enqueue(id, expected_revision, kind, payload) end,
          mode: :immediate
        )

      if match?({:ok, _}, result), do: broadcast()
      result
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp find_or_enqueue(id, expected, kind, payload) do
    case Repo.get(Command, id) do
      nil -> enqueue(id, expected, kind, payload)
      %Command{expected_revision: ^expected, kind: ^kind, payload: ^payload} = command -> command
      _ -> Repo.rollback(:key_conflict)
    end
  end

  defp enqueue(id, expected, kind, payload) do
    reason = rejection_reason(expected, kind, payload)
    state = if reason, do: "rejected", else: "pending"

    command =
      Repo.insert!(%Command{
        id: id,
        kind: kind,
        payload: payload,
        expected_revision: expected,
        state: state,
        result: reason
      })

    record(prefix(kind) <> state, %{}, id)

    if state == "pending" and kind in @auth_kinds do
      Repo.update!(
        Ecto.Changeset.change(workspace(),
          connection: %{
            "status" => "needs_recheck",
            "authorization" => "unknown",
            "models" => [],
            "catalog_status" => "not_requested",
            "command_id" => id,
            "identity" => payload
          }
        )
      )
    end

    if state == "pending" and kind == "check_codex_model" do
      Repo.update!(
        Ecto.Changeset.change(workspace(),
          connection: Map.delete(workspace().connection, "model_check")
        )
      )
    end

    command
  end

  defp rejection_reason(expected, kind, payload) do
    cond do
      workspace().revision != expected ->
        "stale_revision"

      (kind in @exclusive_kinds and pending?()) or pending_probe(@exclusive_kinds) != nil ->
        "profile_busy"

      kind == "check_codex_model" and not model_check_current?(payload) ->
        "model_refresh_required"

      true ->
        nil
    end
  end

  def claim(now \\ System.system_time(:millisecond)) do
    Repo.transaction(
      fn ->
        command =
          Repo.one(
            from c in Command,
              where:
                c.state == "pending" or
                  (c.state in ["running", "cancelling"] and c.lease_until < ^now),
              order_by: c.inserted_at,
              limit: 1
          )

        case command do
          nil ->
            nil

          %{kind: kind, state: state} = command
          when kind in [
                 "probe_codex",
                 "inspect_codex",
                 "login_codex",
                 "logout_codex",
                 "plan_tabula",
                 "preview_documents",
                 "accept_spec",
                 "check_codex_model",
                 "choose_arena_folder",
                 "inspect_arena_git",
                 "init_arena_git",
                 "preview_arena_git",
                 "commit_arena_git",
                 "worktree_arena_git"
               ] and
                 state in ["running", "cancelling"] ->
            failed =
              Repo.update!(
                Ecto.Changeset.change(command,
                  state: "failed",
                  result: "interrupted",
                  lease_until: nil
                )
              )

            record(prefix(kind) <> "interrupted", %{}, command.id)
            failed

          %{attempts: count} = command when count >= 3 ->
            failed =
              Repo.update!(
                Ecto.Changeset.change(command,
                  state: "failed",
                  result: "retry_limit",
                  lease_until: nil
                )
              )

            record("discovery.failed", %{"reason" => "retry_limit"}, command.id)
            failed

          command ->
            claimed =
              Repo.update!(
                Ecto.Changeset.change(command,
                  state: "running",
                  attempts: command.attempts + 1,
                  lease_until: now + lease_duration(command.kind)
                )
              )

            record(
              prefix(claimed.kind) <> "started",
              %{"attempt" => claimed.attempts},
              claimed.id
            )

            claimed
        end
      end,
      mode: :immediate
    )
    |> tap(fn result -> if match?({:ok, %Command{}}, result), do: broadcast() end)
  end

  defp lease_duration(kind)
       when kind in ~w(inspect_arena_git init_arena_git preview_arena_git commit_arena_git worktree_arena_git),
       do: 25_000

  defp lease_duration("login_codex"), do: 630_000
  defp lease_duration("choose_arena_folder"), do: 135_000
  defp lease_duration("preview_documents"), do: 25_000
  defp lease_duration("plan_tabula"), do: 140_000
  defp lease_duration("check_codex_model"), do: 140_000
  defp lease_duration(kind) when kind in ["inspect_codex", "logout_codex"], do: 20_000
  defp lease_duration(_), do: 10_000

  def finish(%Command{kind: "preview_documents"} = claim, result),
    do: Cuckoding.PlanningDocuments.finish(claim, result)

  def finish(%Command{kind: "accept_spec"} = claim, result),
    do: Cuckoding.Specifications.finish(claim, result)

  def finish(%Command{kind: "plan_tabula"} = claim, result),
    do: Cuckoding.Planning.finish(claim, result)

  def finish(%Command{kind: kind} = claim, result)
      when kind in ~w(inspect_arena_git init_arena_git preview_arena_git commit_arena_git worktree_arena_git),
      do: Cuckoding.ArenaGit.finish(claim, result)

  def finish(%Command{kind: "choose_arena_folder"} = claim, result),
    do: Cuckoding.Arenas.finish(claim, result)

  def finish(%Command{} = claim, tools) when is_map(tools) do
    result =
      Repo.transaction(
        fn ->
          current = Repo.get!(Command, claim.id)

          unless current.state in ["running", "cancelling"] and current.attempts == claim.attempts do
            Repo.rollback(:lost_claim)
          end

          workspace = workspace()

          if workspace.revision != claim.expected_revision do
            command =
              Repo.update!(
                Ecto.Changeset.change(current,
                  state: "rejected",
                  result: "stale_revision",
                  lease_until: nil
                )
              )

            record(prefix(claim.kind) <> "rejected", %{"reason" => "stale_revision"}, claim.id)
            command
          else
            complete_command(current, claim, workspace, tools)
          end
        end,
        mode: :immediate
      )

    if match?({:ok, _}, result), do: broadcast()
    result
  end

  defp complete_command(current, claim, workspace, tools) do
    cancelled = current.state == "cancelling"
    state = if cancelled, do: "cancelled", else: "completed"
    {fields, data} = projection(claim, if(cancelled, do: cancelled_result(tools), else: tools))
    Repo.update!(Ecto.Changeset.change(workspace, [{:revision, workspace.revision + 1} | fields]))

    command =
      Repo.update!(
        Ecto.Changeset.change(current,
          state: state,
          result: if(cancelled, do: "recheck_required", else: "checked"),
          lease_until: nil
        )
      )

    record(prefix(claim.kind) <> state, data, claim.id)
    command
  end

  defp cancelled_result(tools) do
    status = if tools["status"] == "cleanup_uncertain", do: "cleanup_uncertain", else: "cancelled"
    tools |> Map.take(~w(pid spawned_at_ms elapsed_ms)) |> Map.put("status", status)
  end

  def record(kind, data \\ %{}, command_id \\ nil) do
    Repo.insert!(%Event{
      kind: kind,
      data: data,
      command_id: command_id,
      occurred_at: DateTime.utc_now()
    })
  end

  defp projection(%{kind: "discover_tools"}, tools) do
    {[tools: tools, checked_at: DateTime.utc_now()],
     %{"found" => Enum.count(tools, fn {_, value} -> value["status"] == "found" end)}}
  end

  defp projection(%{kind: "probe_codex"} = claim, result) do
    result = Map.take(result, ~w(status version pid spawned_at_ms elapsed_ms))

    public =
      Map.merge(result, %{
        "path" => claim.payload["path"],
        "checked_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "authorization" => "not_connected",
        "command_id" => claim.id
      })

    fields =
      if workspace().connection["identity"] == claim.payload, do: [], else: [connection: %{}]

    {[{:codex, public} | fields],
     Map.take(public, ~w(status version pid spawned_at_ms elapsed_ms))}
  end

  defp projection(%{kind: "check_codex_model"} = claim, result) do
    result = result |> Jason.encode!() |> Codex.normalize_model_check()

    result =
      if result["status"] == "passed" and
           (result["requested_model"] != claim.payload["model"] or
              result["observed_model"] != claim.payload["model"] or
              result["effort"] != claim.payload["effort"] or
              not model_check_current?(claim.payload)),
         do: %{"status" => "model_mismatch"},
         else: result

    public =
      Map.merge(result, %{
        "requested_model" => claim.payload["model"],
        "checked_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "command_id" => claim.id
      })

    {[connection: Map.put(workspace().connection, "model_check", public)], public}
  end

  defp projection(%{kind: kind} = claim, result)
       when kind in ["inspect_codex", "login_codex", "logout_codex"] do
    result = result |> Jason.encode!() |> Codex.normalize_connection()
    now = DateTime.to_iso8601(DateTime.utc_now())
    previous = Map.delete(workspace().connection, "model_check")

    previous =
      if kind == "inspect_codex" and previous["identity"] == claim.payload,
        do: previous,
        else: %{}

    public =
      Map.merge(
        previous,
        Map.merge(result, %{
          "identity" => claim.payload,
          "checked_at" => now,
          "command_id" => claim.id
        })
      )

    public =
      cond do
        result["catalog_status"] == "fresh" ->
          Map.merge(public, %{
            "fetched_at" => now,
            "source" => "codex-app-server/model/list",
            "catalog_error" => nil
          })

        result["catalog_status"] == "not_requested" ->
          Map.merge(public, %{
            "models" => [],
            "fetched_at" => nil,
            "source" => nil,
            "catalog_error" => nil
          })

        true ->
          Map.put(public, "catalog_status", "stale")
      end

    public =
      if result["authorization"],
        do: Map.put(public, "authorization_checked_at", now),
        else: public

    data = Map.take(result, ~w(status authorization catalog_status pid spawned_at_ms elapsed_ms))
    {[connection: public], Map.put(data, "model_count", length(result["models"] || []))}
  end

  defp prefix(kind)
       when kind in ~w(inspect_arena_git init_arena_git preview_arena_git commit_arena_git worktree_arena_git),
       do: "arena_git."

  defp prefix("preview_documents"), do: "documents."
  defp prefix("accept_spec"), do: "spec."
  defp prefix("discover_tools"), do: "discovery."
  defp prefix("choose_arena_folder"), do: "arena_folder."
  defp prefix("probe_codex"), do: "codex."
  defp prefix("inspect_codex"), do: "connection."
  defp prefix("login_codex"), do: "login."
  defp prefix("logout_codex"), do: "logout."
  defp prefix("plan_tabula"), do: "planning."
  defp prefix("check_codex_model"), do: "model_check."

  def broadcast, do: Phoenix.PubSub.broadcast(Cuckoding.PubSub, "foundation", :updated)
end
