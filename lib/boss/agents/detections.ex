defmodule Boss.Agents.Detections do
  @moduledoc """
  Persists sanitized CLI detection, authorization status, and fetched model catalogs.
  Raw probe output, credentials, and session identifiers are never stored.
  """
  import Ecto.Query
  alias Boss.Agents.{Detection, Metadata}
  alias Boss.Repo

  @cap_keys ~w(headless streaming session_resume structured_output approval_support usage_reporting)a
  @cap_values %{
    "advertised" => :advertised,
    "not_advertised" => :not_advertised,
    "unknown" => :unknown
  }
  @probe_atoms %{
    "ok" => :ok,
    "missing" => :missing,
    "unsupported" => :unsupported,
    "failed" => :failed
  }
  @auth_atoms %{
    "configured" => :configured,
    "stale" => :stale,
    "not_configured" => :not_configured,
    "unknown" => :unknown
  }
  @stage_atoms %{"version" => :version, "help" => :help, "auth" => :auth}
  @reason_atoms %{
    "timeout" => :timeout,
    "output_limit" => :output_limit,
    "unrecognized" => :unrecognized,
    "unsupported" => :unsupported,
    "exit_status" => :exit_status,
    "spawn_failed" => :spawn_failed
  }

  def table_ready? do
    Repo.query!(
      "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE type='table' AND name='agent_detections')"
    ).rows == [[1]]
  rescue
    _ -> false
  end

  def any_saved? do
    table_ready?() and Repo.exists?(Detection)
  end

  def load_state do
    if table_ready?() do
      rows = Repo.all(from d in Detection, order_by: d.agent_id)

      checked_at =
        rows
        |> Enum.map(& &1.checked_at)
        |> Enum.reject(&is_nil/1)
        |> Enum.max(DateTime, fn -> nil end)

      results =
        Map.new(rows, fn row ->
          entry = to_view(row)
          {entry.id, entry}
        end)

      %{results: results, checked_at: checked_at}
    else
      %{results: %{}, checked_at: nil}
    end
  end

  def get_view(id) when is_atom(id), do: get_view(Atom.to_string(id))

  def get_view(id) when is_binary(id) do
    if table_ready?() do
      case Repo.get(Detection, id) do
        nil -> nil
        row -> to_view(row)
      end
    end
  end

  def authorized_map do
    if table_ready?() do
      Detection
      |> where([d], d.probe_status == "ok" and d.auth_status == "configured")
      |> Repo.all()
      |> Map.new(&{&1.agent_id, to_view(&1)})
    else
      %{}
    end
  end

  def save_scan(rows, checked_at \\ nil) when is_list(rows) do
    if table_ready?() do
      ts = checked_at || DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.transaction(fn ->
        Enum.each(rows, fn row -> upsert_row!(row, ts) end)
      end)

      load_state()
    else
      %{results: Map.new(rows, &{&1.id, Map.put_new(&1, :models, [])}), checked_at: checked_at}
    end
  end

  def save_agent(row, checked_at \\ nil) when is_map(row) do
    if table_ready?() do
      ts = checked_at || DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, saved} = Repo.transaction(fn -> upsert_row!(row, ts) end)
      to_view(saved)
    else
      Map.put_new(row, :models, [])
    end
  end

  def save_models(agent_id, models, checked_at \\ nil) when is_list(models) do
    id_str = to_string(agent_id)

    if table_ready?() do
      ts = checked_at || DateTime.utc_now() |> DateTime.truncate(:second)
      clean_models = Enum.map(models, &sanitize_model/1) |> Enum.reject(&is_nil/1)

      case Repo.get(Detection, id_str) do
        nil ->
          nil

        existing ->
          saved =
            existing
            |> Detection.changeset(%{
              models: %{"items" => clean_models},
              models_checked_at: ts
            })
            |> Repo.update!()

          to_view(saved)
      end
    end
  end

  def mark_auth_status(agent_id, status)
      when status in [:configured, :stale, :not_configured, :unknown] do
    id_str = to_string(agent_id)

    if table_ready?() do
      case Repo.get(Detection, id_str) do
        nil ->
          nil

        existing ->
          attrs =
            if status == :configured do
              %{auth_status: Atom.to_string(status)}
            else
              %{
                auth_status: Atom.to_string(status),
                models: %{"items" => []},
                models_checked_at: nil
              }
            end

          existing
          |> Detection.changeset(attrs)
          |> Repo.update!()
          |> to_view()
      end
    end
  end

  defp upsert_row!(row, ts) do
    id_str = to_string(row.id)
    existing = Repo.get(Detection, id_str)
    probe_str = Atom.to_string(row.probe_status)
    auth_str = Atom.to_string(row.auth_status)

    incoming_models =
      case Map.get(row, :models) do
        list when is_list(list) -> Enum.map(list, &sanitize_model/1) |> Enum.reject(&is_nil/1)
        _ -> nil
      end

    {models_map, models_ts} =
      cond do
        probe_str != "ok" or auth_str != "configured" ->
          {%{"items" => []}, nil}

        is_list(incoming_models) ->
          {%{"items" => incoming_models}, ts}

        existing != nil ->
          {existing.models || %{"items" => []}, existing.models_checked_at}

        true ->
          {%{"items" => []}, nil}
      end

    attrs = %{
      agent_id: id_str,
      name: row.name || default_name(id_str),
      path: sanitize_string(row.path, 1024),
      version: sanitize_string(row.version, 128),
      probe_status: probe_str,
      auth_status: auth_str,
      capabilities: sanitize_capabilities(row.capabilities || %{}),
      errors: %{"items" => sanitize_errors(row.errors || [])},
      models: models_map,
      checked_at: ts,
      models_checked_at: models_ts
    }

    case existing do
      nil ->
        %Detection{} |> Detection.changeset(attrs) |> Repo.insert!()

      record ->
        record |> Detection.changeset(attrs) |> Repo.update!()
    end
  end

  defp default_name(id_str) do
    Enum.find_value(Metadata.catalog(), id_str, fn a ->
      Atom.to_string(a.id) == id_str && a.name
    end)
  end

  defp sanitize_string(val, max) when is_binary(val) do
    if String.valid?(val) and byte_size(val) > 0 and byte_size(val) <= max do
      val
    end
  end

  defp sanitize_string(_, _), do: nil

  defp sanitize_capabilities(caps) when is_map(caps) do
    Map.new(@cap_keys, fn key ->
      val = Map.get(caps, key) || Map.get(caps, Atom.to_string(key)) || :unknown
      str = to_string(val)

      {Atom.to_string(key),
       if(str in ~w(advertised not_advertised unknown), do: str, else: "unknown")}
    end)
  end

  defp sanitize_errors(errors) when is_list(errors) do
    errors
    |> Enum.take(16)
    |> Enum.map(fn err ->
      %{
        "stage" => to_string(err[:stage] || err["stage"] || "cli"),
        "reason" => to_string(err[:reason] || err["reason"] || "failed")
      }
    end)
  end

  defp sanitize_model(model) when is_map(model) do
    id = model["id"] || model[:id]
    name = model["name"] || model[:name] || id

    if is_binary(id) and byte_size(id) in 1..160 and String.valid?(id) do
      efforts =
        (model["reasoning_efforts"] || model[:reasoning_efforts] || [])
        |> Enum.map(&to_string/1)
        |> Enum.filter(&(&1 in ~w(none low medium high xhigh max ultra)))
        |> Enum.uniq()

      reasoning =
        case model["reasoning"] || model[:reasoning] do
          val when is_boolean(val) -> val
          _ -> efforts != []
        end

      default_effort =
        case model["default_effort"] || model[:default_effort] do
          val when is_binary(val) -> val
          _ -> nil
        end

      ctx =
        case model["context_window"] || model[:context_window] do
          n when is_integer(n) and n > 0 -> n
          _ -> nil
        end

      pricing = sanitize_pricing(model["pricing"] || model[:pricing])

      %{
        "id" => id,
        "name" =>
          if(is_binary(name) and String.valid?(name), do: String.slice(name, 0, 160), else: id),
        "reasoning" => reasoning,
        "reasoning_efforts" => efforts,
        "default_effort" => default_effort,
        "context_window" => ctx,
        "pricing" => pricing
      }
    end
  end

  defp sanitize_model(_), do: nil

  defp sanitize_pricing(p) when is_map(p) do
    unit = p["unit"] || p[:unit] || "1M tokens"

    %{
      "input" => num_or_nil(p["input"] || p[:input]),
      "output" => num_or_nil(p["output"] || p[:output]),
      "cached_input" => num_or_nil(p["cached_input"] || p[:cached_input]),
      "unit" => if(is_binary(unit), do: String.slice(unit, 0, 40), else: "1M tokens")
    }
  end

  defp sanitize_pricing(_), do: nil

  defp num_or_nil(n) when is_number(n) and n >= 0, do: n * 1.0
  defp num_or_nil(_), do: nil

  defp to_view(%Detection{} = row) do
    id_atom =
      Enum.find(Metadata.ids(), &(Atom.to_string(&1) == row.agent_id)) || :codex

    caps =
      Map.new(@cap_keys, fn key ->
        raw = Map.get(row.capabilities || %{}, Atom.to_string(key), "unknown")
        {key, Map.get(@cap_values, raw, :unknown)}
      end)

    errs =
      for item <- Map.get(row.errors || %{}, "items", []), is_map(item) do
        %{
          stage: Map.get(@stage_atoms, item["stage"], :cli),
          reason: Map.get(@reason_atoms, item["reason"], :failed)
        }
      end

    models =
      for item <- Map.get(row.models || %{}, "items", []), is_map(item) do
        item
      end

    %{
      id: id_atom,
      name: row.name,
      path: row.path,
      version: row.version,
      probe_status: Map.get(@probe_atoms, row.probe_status, :failed),
      auth_status: Map.get(@auth_atoms, row.auth_status, :unknown),
      capabilities: caps,
      errors: errs,
      models: models,
      checked_at: row.checked_at,
      models_checked_at: row.models_checked_at
    }
  end
end
