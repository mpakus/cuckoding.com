defmodule Cuckoding.DefaultTeam do
  @moduledoc "Revisioned defaults copied into new projects; saving never authorizes execution."
  use Ecto.Schema
  import Ecto.Query
  alias Cuckoding.{Adapters, AgentBindings, ProjectOnboarding, Repo}
  alias Cuckoding.Adapters.RuntimeConfiguration
  alias Cuckoding.Execution.EventStore

  @primary_key {:revision, :integer, autogenerate: false}
  schema "default_teams" do
    field :config_json, :map
    field :source_hash, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @limits %{
    "tasks" => 20,
    "revisions" => 3,
    "retries" => 2,
    "continuations" => 3,
    "provider_waits" => 6,
    "wall_minutes" => 120
  }
  @ranges %{
    "tasks" => 1..20,
    "revisions" => 0..3,
    "retries" => 0..2,
    "continuations" => 0..10,
    "provider_waits" => 0..10,
    "wall_minutes" => 1..1440
  }

  def limits, do: @limits
  def latest, do: Repo.one(from t in __MODULE__, order_by: [desc: t.revision], limit: 1)

  def save(expected_revision, attrs) when is_integer(expected_revision) and is_map(attrs) do
    EventStore.transaction(fn ->
      current = latest()
      revision = if current, do: current.revision, else: 0

      with true <- revision == expected_revision,
           {:ok, config} <- configuration(attrs) do
        persist(current, config, revision + 1)
      else
        false -> Repo.rollback(:stale_default_team)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def save(_revision, _attrs), do: {:error, :invalid_default_team}

  defp persist(%{config_json: config} = current, config, _revision), do: current

  defp persist(_current, config, revision) do
    team =
      Repo.insert!(%__MODULE__{
        revision: revision,
        config_json: config,
        source_hash: :crypto.hash(:sha256, Jason.encode!(config)) |> Base.encode16(case: :lower)
      })

    {:ok, _} =
      EventStore.append_in_transaction("default_team", %{
        event_type: "default_team.saved",
        public_summary: "Default team saved for new projects",
        payload: %{"revision" => team.revision, "source_hash" => team.source_hash}
      })

    team
  end

  def inherit(expected_revision \\ nil) do
    case latest() do
      nil when expected_revision in [nil, 0] ->
        {:ok, %{}}

      nil ->
        {:error, :stale_default_team}

      team when not is_nil(expected_revision) and team.revision != expected_revision ->
        {:error, :stale_default_team}

      team ->
        if Enum.all?(team.config_json["agent_connections"], &compatible_connection?/1) do
          {:ok, Map.put(team.config_json, "default_team_revision", team.revision)}
        else
          {:error, :default_team_agent_changed}
        end
    end
  end

  defp compatible_connection?(connection),
    do:
      AgentBindings.compatible(
        connection["adapter_key"],
        connection["settings"],
        connection["provider_account_id"]
      ) == :ok

  defp configuration(attrs) do
    with {:ok, roles, connections} <- roles(attrs["roles"]),
         {:ok, profile} <- profile(Map.get(attrs, "limits", %{})) do
      {:ok,
       %{
         "default_roles" => roles,
         "agent_connections" => connections,
         "execution_profile" => profile
       }}
    end
  end

  defp roles(attrs) when is_map(attrs) do
    Enum.reduce_while(ProjectOnboarding.default_roles(), {:ok, [], []}, fn role,
                                                                           {:ok, roles,
                                                                            connections} ->
      params = Map.get(attrs, role["key"], %{})

      with true <- is_map(params),
           account when not is_nil(account) <-
             Adapters.get_provider_account(params["provider_account_id"]),
           true <- account.adapter_key in ~w(codex claude_code cursor_agent),
           {:ok, runtime} <-
             RuntimeConfiguration.validate(
               Map.put(
                 account.capabilities_json["settings"] || %{},
                 "runtime",
                 account.adapter_key
               )
             ),
           instructions when is_binary(instructions) <-
             Map.get(params, "instructions", role["instructions"]),
           true <- String.trim(instructions) != "" and byte_size(instructions) <= 4_000 do
        key = "agent-" <> account.id

        connection = %{
          "key" => key,
          "label" => account.label,
          "adapter_key" => account.adapter_key,
          "provider_account_id" => account.id,
          "settings" => runtime.settings
        }

        role =
          Map.merge(role, %{
            "agent_connection_key" => key,
            "instructions" => String.trim(instructions),
            "delivery_phase" => "builtin",
            "permissions" =>
              if(role["key"] == "implementer", do: "workspace_write", else: "read_only")
          })

        {:cont, {:ok, roles ++ [role], Enum.uniq_by(connections ++ [connection], & &1["key"])}}
      else
        _ -> {:halt, {:error, {:invalid_default_role, role["key"]}}}
      end
    end)
  end

  defp roles(_), do: {:error, :invalid_default_team}

  defp profile(attrs) when is_map(attrs) do
    profile =
      Map.new(@limits, fn {key, default} -> {key, integer(Map.get(attrs, key, default))} end)

    if Enum.all?(profile, fn {key, value} -> is_integer(value) and value in @ranges[key] end),
      do: {:ok, profile},
      else: {:error, :invalid_execution_limits}
  end

  defp profile(_), do: {:error, :invalid_execution_limits}
  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {value, ""} -> value
      _ -> nil
    end
  end

  defp integer(_), do: nil
end
