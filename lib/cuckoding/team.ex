defmodule Cuckoding.Team do
  @moduledoc "Revisioned default-team configuration. Saving never authorizes execution."
  import Ecto.Query
  alias Cuckoding.{Command, Foundation, Repo, TeamRevision}

  @required ~w(speculator implementor secutor summa_rudis)
  @fields ~w(id name instructions agent model_id)

  def current, do: Repo.one!(from t in TeamRevision, order_by: [desc: t.id], limit: 1)
  def history, do: Repo.all(from t in TeamRevision, order_by: [desc: t.id], limit: 5)
  def editable(team), do: Enum.map(team.definition["roles"], &Map.take(&1, @fields))
  def required?(id), do: id in @required

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
    connection = Foundation.workspace().connection

    status =
      case Foundation.verified_executable() do
        {:ok, identity} ->
          catalog_status(connection, identity)

        _ ->
          :version_required
      end

    models = connection["models"] || []
    saved = Foundation.saved_agent_models()

    selectable =
      if saved do
        Enum.filter(models, fn model ->
          Enum.any?(
            saved.payload["models"],
            &(&1["id"] == model["id"] and &1["model"] == model["model"])
          )
        end)
      else
        models
      end

    %{
      status: status,
      models: models,
      selectable_models: selectable,
      check: connection["model_check"] || %{}
    }
  end

  defp catalog_status(connection, identity) do
    cond do
      connection["identity"] != identity -> :version_required
      connection["status"] != "checked" -> :connection_required
      connection["authorization"] != "chatgpt" -> :sign_in_required
      Foundation.catalog_status(connection) != "fresh" -> :catalog_stale
      true -> :available
    end
  end

  def binding_status(%{"agent" => ""}, _), do: :unassigned
  def binding_status(%{"model_id" => ""}, _), do: :unassigned
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

  def save(key, expected, roles, removal_confirmed \\ false) do
    with {:ok, id} <- Ecto.UUID.cast(key),
         true <- is_integer(expected) and expected > 0,
         :ok <- validate_roles(roles) do
      payload = %{"roles" => roles, "removal_confirmed" => removal_confirmed == true}

      result = Repo.transaction(fn -> save_command(id, expected, payload) end, mode: :immediate)
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

  defp save_command(id, expected, payload) do
    case Repo.get(Command, id) do
      nil -> persist(id, expected, payload)
      %Command{kind: "save_team", expected_revision: ^expected, payload: ^payload} = c -> c
      _ -> Repo.rollback(:key_conflict)
    end
  end

  defp persist(id, expected, payload) do
    previous = current()
    removed = Enum.map(editable(previous), & &1["id"]) -- Enum.map(payload["roles"], & &1["id"])
    result = resolve(previous, expected, payload, removed)

    reason =
      case result do
        {:error, reason} -> reason
        _ -> nil
      end

    command =
      Repo.insert!(%Command{
        id: id,
        kind: "save_team",
        expected_revision: expected,
        payload: payload,
        state: if(reason, do: "rejected", else: "completed"),
        result: reason
      })

    case result do
      {:ok, roles} ->
        revision =
          Repo.insert!(%TeamRevision{
            command_id: id,
            inserted_at: DateTime.utc_now(),
            definition: %{"version" => 1, "execution" => "disabled", "roles" => roles}
          })

        Foundation.record(
          "team.saved",
          %{
            "revision" => revision.id,
            "role_count" => length(roles),
            "removed_role_ids" => removed
          },
          id
        )

      {:error, reason} ->
        Foundation.record("team.rejected", %{"reason" => reason}, id)
    end

    command
  end

  defp resolve(previous, expected, payload, removed) do
    cond do
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
      model = Enum.find(catalog.selectable_models, &(&1["id"] == role["model_id"]))

      cond do
        role["model_id"] == "" ->
          {:cont, {:ok, acc ++ [Map.put(role, "model", "")]}}

        old && Map.take(old, ~w(agent model_id)) == Map.take(role, ~w(agent model_id)) ->
          {:cont, {:ok, acc ++ [Map.put(role, "model", old["model"])]}}

        catalog.status == :available and model != nil ->
          {:cont, {:ok, acc ++ [Map.put(role, "model", model["model"])]}}

        true ->
          {:halt, {:error, "model_refresh_required"}}
      end
    end)
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
    Enum.sort(Map.keys(role)) == Enum.sort(@fields) and
      (role["id"] in @required or match?({:ok, _}, Ecto.UUID.cast(role["id"]))) and
      valid_text?(role["name"], 1, 60, false) and
      valid_text?(role["instructions"], 0, 2_000, true) and
      role["agent"] in ["", "codex"] and valid_text?(role["model_id"], 0, 200, false) and
      (role["agent"] != "" or role["model_id"] == "")
  end

  defp valid_role?(_), do: false

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
