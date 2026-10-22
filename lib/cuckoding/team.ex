defmodule Cuckoding.Team do
  @moduledoc "Revisioned default/scoped teams. Saving never authorizes execution."
  import Ecto.Query

  alias Cuckoding.{
    Agents,
    Arena,
    Command,
    Foundation,
    Repo,
    Tabula,
    TeamAdoption,
    TeamAssignments,
    TeamRevision
  }

  @required ~w(speculator implementor secutor summa_rudis)
  @fields ~w(id name instructions agent model_id)
  @parallel_fields ~w(parallel_agent parallel_model_id)
  @scoped_commands ~w(save_scoped_team disconnect_scoped_agent_roles)

  def current, do: Repo.one!(from t in defaults(), order_by: [desc: t.id], limit: 1)
  def history(scope \\ nil)
  def history(nil), do: Repo.all(from t in defaults(), order_by: [desc: t.id], limit: 5)

  def history(scope) do
    with {:ok, ids} <- scope_ids(scope),
         %{} = saved <- scope_record(ids) do
      adoptions = from a in TeamAdoption, where: a.arena_id == ^ids["arena_id"]

      adoptions =
        if ids["tabula_id"],
          do: where(adoptions, [a], a.tabula_id == ^ids["tabula_id"]),
          else: where(adoptions, [a], is_nil(a.tabula_id))

      Repo.all(
        from t in TeamRevision,
          where:
            t.id == ^saved.team_revision_id or
              t.id in subquery(from a in adoptions, select: a.team_revision_id),
          order_by: [desc: t.id],
          limit: 5
      )
    else
      _ -> []
    end
  end

  defp defaults do
    from t in TeamRevision,
      left_join: c in Command,
      on: c.id == t.command_id,
      where: is_nil(t.command_id) or c.kind not in ^@scoped_commands
  end

  def editable(team),
    do: Enum.map(team.definition["roles"], &Map.take(&1, @fields ++ @parallel_fields))

  def required?(id), do: id in @required

  def additional(role) do
    role
    |> Map.take(~w(id name instructions))
    |> Map.merge(%{
      "name" => role["name"] <> " · worker 2",
      "agent" => role["parallel_agent"] || "",
      "model_id" => role["parallel_model_id"] || ""
    })
    |> then(fn worker ->
      if Map.has_key?(role, "parallel_model"),
        do: Map.put(worker, "model", role["parallel_model"]),
        else: worker
    end)
  end

  def bindings(roles),
    do:
      Enum.flat_map(roles, fn role ->
        worker = additional(role)
        primary = Map.drop(role, @parallel_fields ++ ["parallel_model"])
        [primary] ++ if(worker["agent"] == "", do: [], else: [worker])
      end)

  def uses_agent?(roles, agent_id), do: Enum.any?(bindings(roles), &(&1["agent"] == agent_id))

  def custom_role do
    %{
      "id" => Ecto.UUID.generate(),
      "name" => "",
      "instructions" => "",
      "agent" => "",
      "model_id" => ""
    }
  end

  def catalog do
    catalogs =
      Map.new(
        [Agents.get("codex") | Enum.reject(Agents.list(), &(&1.id == "codex"))],
        &{&1.id, catalog(&1.id)}
      )

    Map.put(catalogs["codex"], :agents, catalogs)
  end

  def catalog(agent_id) do
    connection = Foundation.workspace(agent_id).connection

    status =
      case Foundation.verified_executable(agent_id) do
        {:ok, identity} ->
          catalog_status(connection, identity)

        _ ->
          :version_required
      end

    models = connection["models"] || []
    saved = Foundation.saved_agent_models(agent_id)

    selectable =
      if saved do
        Enum.filter(models, fn model ->
          Enum.any?(
            saved.payload["models"],
            &(&1["id"] == model["id"] and &1["model"] == model["model"])
          )
        end)
      else
        if agent_id == "codex", do: models, else: []
      end

    %{
      status: status,
      reusable: Foundation.reusable_catalog?(connection),
      models: models,
      selectable_models: selectable,
      check: connection["model_check"] || %{}
    }
  end

  defp catalog_status(connection, identity) do
    cond do
      connection["identity"] != identity -> :version_required
      connection["status"] != "checked" -> :connection_required
      connection["authorization"] not in ~w(chatgpt cursor) -> :sign_in_required
      Foundation.catalog_status(connection) != "fresh" -> :catalog_stale
      true -> :available
    end
  end

  def binding_status(%{"agent" => ""}, _), do: :unassigned
  def binding_status(%{"model_id" => ""}, _), do: :unassigned

  def binding_status(role, %{agents: catalogs}) do
    binding_status(role, Map.get(catalogs, role["agent"], %{status: :connection_required}))
  end

  def binding_status(role, %{status: :catalog_stale, reusable: true} = catalog),
    do: binding_status(role, %{catalog | status: :available})

  def binding_status(_, %{status: status}) when status != :available, do: status

  def binding_status(role, catalog) do
    case Enum.find(catalog.models, &(&1["id"] == role["model_id"])) do
      nil -> :model_missing
      model -> binding_match(role, model, catalog.check)
    end
  end

  defp binding_match(role, model, check) do
    cond do
      role["model"] && role["model"] != model["model"] ->
        :model_changed

      check["status"] == "passed" and check["requested_model"] == model["model"] and
          check["observed_model"] == model["model"] ->
        :check_passed

      true ->
        :untested
    end
  end

  def save(key, expected, roles, removal_confirmed \\ false, scope \\ nil) do
    with {:ok, id} <- Ecto.UUID.cast(key),
         true <- is_integer(expected) and expected > 0,
         {:ok, ids} <- scope_ids(scope),
         :ok <- validate_roles(roles) do
      payload =
        Map.merge(
          %{"roles" => roles, "removal_confirmed" => removal_confirmed == true},
          ids || %{}
        )

      kind = if ids, do: "save_scoped_team", else: "save_team"

      result =
        Repo.transaction(fn -> save_command(id, expected, payload, kind) end, mode: :immediate)

      if match?({:ok, _}, result), do: Foundation.broadcast()

      case result do
        {:ok, %Command{state: "completed"} = command} ->
          {:ok, Repo.get_by!(TeamRevision, command_id: command.id)}

        {:ok, %Command{result: reason}} ->
          {:error, reason}

        error ->
          error
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_command}
    end
  end

  defp scope_ids(nil), do: {:ok, nil}
  defp scope_ids(%Arena{id: id}), do: scope_ids(id, nil)
  defp scope_ids(%Tabula{id: id, arena_id: arena}), do: scope_ids(arena, id)
  defp scope_ids(_), do: {:error, :invalid_scope}

  defp scope_ids(arena, tabula) do
    with {:ok, arena} <- Ecto.UUID.cast(arena),
         {:ok, tabula} <- if(is_nil(tabula), do: {:ok, nil}, else: Ecto.UUID.cast(tabula)) do
      {:ok, %{"arena_id" => arena, "tabula_id" => tabula}}
    else
      _ -> {:error, :invalid_scope}
    end
  end

  defp scope_record(%{"arena_id" => arena, "tabula_id" => nil}), do: Repo.get(Arena, arena)

  defp scope_record(%{"arena_id" => arena, "tabula_id" => board}),
    do: Repo.get_by(Tabula, id: board, arena_id: arena)

  defp save_command(id, expected, payload, kind) do
    case Repo.get(Command, id) do
      nil -> persist(id, expected, payload, kind)
      %Command{kind: ^kind, expected_revision: ^expected, payload: ^payload} = c -> c
      _ -> Repo.rollback(:key_conflict)
    end
  end

  defp persist(id, expected, payload, kind) do
    {scope, previous} = previous_team(kind, payload)
    removed = removed(previous, payload["roles"])
    result = resolve(previous, scope, expected, payload, removed)

    reason =
      case result do
        {:error, reason} -> reason
        _ -> nil
      end

    command =
      Repo.insert!(%Command{
        id: id,
        kind: kind,
        expected_revision: expected,
        payload: payload,
        state: if(reason, do: "rejected", else: "completed"),
        result: reason
      })

    record_result(result, command, scope, removed)
    command
  end

  defp previous_team("save_team", _), do: {nil, current()}

  defp previous_team("save_scoped_team", payload) do
    scope = scope_record(payload)
    {scope, scope && TeamAssignments.assigned(scope)}
  end

  defp removed(nil, _), do: []

  defp removed(previous, roles),
    do: Enum.map(editable(previous), & &1["id"]) -- Enum.map(roles, & &1["id"])

  defp record_result({:ok, roles}, command, scope, removed) do
    version = if Enum.any?(roles, &Map.has_key?(&1, "parallel_agent")), do: 2, else: 1

    revision =
      Repo.insert!(%TeamRevision{
        command_id: command.id,
        inserted_at: DateTime.utc_now(),
        definition: %{"version" => version, "execution" => "disabled", "roles" => roles}
      })

    if scope do
      Repo.insert!(%TeamAdoption{
        arena_id: command.payload["arena_id"],
        tabula_id: command.payload["tabula_id"],
        team_revision_id: revision.id,
        command_id: command.id,
        inserted_at: DateTime.utc_now()
      })
    end

    Foundation.record(
      if(scope, do: "team.scoped_saved", else: "team.saved"),
      %{
        "revision" => revision.id,
        "previous_revision" => command.expected_revision,
        "role_count" => length(roles),
        "removed_role_ids" => removed
      }
      |> Map.merge(Map.take(command.payload, ~w(arena_id tabula_id))),
      command.id
    )
  end

  defp record_result({:error, reason}, command, _, _) do
    Foundation.record(
      "team.rejected",
      Map.put(Map.take(command.payload, ~w(arena_id tabula_id)), "reason", reason),
      command.id
    )
  end

  defp resolve(nil, _, _, _, _), do: {:error, "scope_missing"}

  defp resolve(previous, scope, expected, payload, removed) do
    cond do
      scope && TeamAssignments.busy?(scope) ->
        {:error, "planning_active"}

      previous.id != expected ->
        {:error, "stale_team"}

      removed != [] and not payload["removal_confirmed"] ->
        {:error, "removal_confirmation_required"}

      true ->
        resolve_bindings(payload["roles"], previous.definition["roles"], catalog())
    end
  end

  defp resolve_bindings(roles, previous, catalog) do
    Enum.reduce_while(roles, {:ok, []}, fn role, {:ok, acc} ->
      old = Enum.find(previous, &(&1["id"] == role["id"]))

      with {:ok, resolved} <- resolve_binding(role, old, catalog),
           {:ok, resolved} <- resolve_additional(resolved, old, catalog) do
        {:cont, {:ok, acc ++ [resolved]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp resolve_binding(role, old, catalog) do
    selected =
      Map.get(catalog.agents, role["agent"], %{
        status: :connection_required,
        selectable_models: []
      })

    model = Enum.find(selected.selectable_models, &(&1["id"] == role["model_id"]))

    cond do
      role["agent"] != "" and is_nil(Agents.get(role["agent"])) ->
        {:error, "model_refresh_required"}

      role["model_id"] == "" ->
        {:ok, Map.put(role, "model", "")}

      old && Map.take(old, ~w(agent model_id)) == Map.take(role, ~w(agent model_id)) ->
        {:ok, Map.put(role, "model", old["model"])}

      selected.status == :available and model != nil ->
        {:ok, Map.put(role, "model", model["model"])}

      true ->
        {:error, "model_refresh_required"}
    end
  end

  defp resolve_additional(role, old, catalog) do
    # A legacy save omitting the new fields preserves an already assigned worker.
    if Map.has_key?(role, "parallel_agent") do
      with {:ok, worker} <- resolve_binding(additional(role), old && additional(old), catalog) do
        {:ok, Map.put(role, "parallel_model", worker["model"])}
      end
    else
      preserved = Map.merge(role, Map.take(old || %{}, @parallel_fields ++ ["parallel_model"]))

      if valid_additional?(preserved),
        do: {:ok, preserved},
        else: {:error, "worker_connection_conflict"}
    end
  end

  defp validate_roles(roles) when is_list(roles) and length(roles) in 4..12 do
    if Enum.all?(roles, &valid_role?/1) do
      ids = Enum.map(roles, & &1["id"])
      names = Enum.map(roles, &String.downcase(String.trim(&1["name"])))

      if length(Enum.uniq(ids)) == length(ids) and length(Enum.uniq(names)) == length(names) and
           Enum.take(ids, 4) == @required do
        :ok
      else
        {:error, :invalid_roles}
      end
    else
      {:error, :invalid_roles}
    end
  end

  defp validate_roles(_), do: {:error, :invalid_roles}

  defp valid_role?(role) when is_map(role) do
    valid_role_shape?(role) and
      (role["id"] in @required or match?({:ok, _}, Ecto.UUID.cast(role["id"]))) and
      valid_text?(role["name"], 1, 60, false) and
      valid_text?(role["instructions"], 0, 2_000, true) and
      valid_agent_id?(role["agent"]) and
      valid_text?(role["model_id"], 0, 200, false) and
      (role["agent"] != "" or role["model_id"] == "")
  end

  defp valid_role?(_), do: false

  defp valid_role_shape?(role),
    do:
      Map.keys(role) -- (@fields ++ @parallel_fields) == [] and
        Enum.all?(@fields, &Map.has_key?(role, &1)) and valid_additional?(role)

  defp valid_additional?(role) do
    if Map.has_key?(role, "parallel_agent") or Map.has_key?(role, "parallel_model_id") do
      required?(role["id"]) and valid_agent_id?(role["parallel_agent"]) and
        valid_text?(role["parallel_model_id"], 0, 200, false) and
        (role["parallel_agent"] != "" or role["parallel_model_id"] == "") and
        (role["parallel_agent"] == "" or role["parallel_agent"] != role["agent"])
    else
      true
    end
  end

  defp valid_agent_id?(id), do: id in ["", "codex"] or match?({:ok, _}, Ecto.UUID.cast(id))

  defp valid_text?(value, min, max, multiline) when is_binary(value) do
    String.valid?(value) and String.length(value) in min..max and
      (min == 0 or String.trim(value) != "") and
      not Regex.match?(
        if(multiline, do: ~r/[\x00-\x08\x0B-\x1F\x7F]/, else: ~r/[\x00-\x1F\x7F]/),
        value
      )
  end

  defp valid_text?(_, _, _, _), do: false
end
