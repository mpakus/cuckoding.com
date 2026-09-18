defmodule Cuckoding.Plugins.Registry do
  @moduledoc "Durable plugin registry and audited, permission-narrowing activation service."

  use GenServer

  import Ecto.Query

  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Identifier
  alias Cuckoding.Plugins.Activation
  alias Cuckoding.Plugins.Discovery
  alias Cuckoding.Plugins.Plugin
  alias Cuckoding.Projects.Project
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.RoleAssignment
  alias Cuckoding.Workflows.Task

  @network_rank %{"none" => 0, "loopback" => 1, "external" => 2}
  @permission_fields ~w(host_process network read_paths write_paths secrets)

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @impl true
  def init(options) do
    if Keyword.get(options, :enabled, true),
      do: {:ok, options, {:continue, :discover}},
      else: {:ok, options}
  end

  @impl true
  def handle_continue(:discover, options) do
    discover(options)
    {:noreply, options}
  end

  @impl true
  def handle_call(:refresh, _from, options), do: {:reply, discover(options), options}

  def refresh, do: GenServer.call(__MODULE__, :refresh, 30_000)

  def discover(options \\ []) do
    result = Discovery.scan(options)

    plugins =
      Enum.map(result.manifests, fn {manifest, detection} -> upsert(manifest, detection) end)

    %{plugins: plugins, errors: result.errors}
  end

  def list do
    Repo.all(from(plugin in Plugin, order_by: [asc: plugin.name, asc: plugin.key]))
    |> Repo.preload(
      activations: from(activation in Activation, order_by: [activation.scope_type])
    )
  end

  def get(id), do: Repo.get(Plugin, id)

  def enable(plugin_id, scope_type, scope_id, attrs) when is_map(attrs) do
    with %Plugin{health: "available"} = plugin <- Repo.get(Plugin, plugin_id),
         {:ok, context} <- scope_context(scope_type, blank_to_nil(scope_id)),
         :ok <- allowed_scope(plugin, context.scope_type),
         {:ok, permissions} <- normalize_permissions(attrs["permissions"] || attrs[:permissions]),
         {:ok, ceiling} <- permission_ceiling(plugin, context),
         :ok <- narrowed(permissions, ceiling),
         {:ok, actor} <- required_text(attrs["actor"] || attrs[:actor], :actor_required),
         {:ok, reason} <- required_text(attrs["reason"] || attrs[:reason], :reason_required),
         :ok <-
           approval_matches(
             permissions["network"],
             attrs["approval_kind"] || attrs[:approval_kind]
           ) do
      persist_activation(plugin, context, true, permissions, attrs, actor, reason)
    else
      %Plugin{} -> {:error, :plugin_unavailable}
      nil -> {:error, :plugin_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def enable(_plugin_id, _scope_type, _scope_id, _attrs), do: {:error, :invalid_activation}

  def disable(plugin_id, scope_type, scope_id, actor, reason) do
    with %Plugin{} = plugin <- Repo.get(Plugin, plugin_id),
         {:ok, context} <- scope_context(scope_type, blank_to_nil(scope_id)),
         :ok <- allowed_scope(plugin, context.scope_type),
         {:ok, actor} <- required_text(actor, :actor_required),
         {:ok, reason} <- required_text(reason, :reason_required) do
      existing = activation(plugin.id, context.scope_type, context.scope_id)

      permissions =
        if existing, do: existing.permissions_json, else: plugin.manifest_json["permissions"]

      persist_activation(
        plugin,
        context,
        false,
        permissions,
        %{"approval_kind" => "standard", "config" => %{}},
        actor,
        reason
      )
    else
      nil -> {:error, :plugin_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def mark_unhealthy(plugin_id, error) do
    case Repo.get(Plugin, plugin_id) do
      %Plugin{} = plugin ->
        Repo.update(Plugin.health_changeset(plugin, %{health: "unhealthy", last_error: error}))

      nil ->
        {:error, :plugin_not_found}
    end
  end

  defp upsert(manifest, detection) do
    plugin = Repo.get_by(Plugin, key: manifest.data["key"]) || %Plugin{id: Identifier.generate()}

    attrs = %{
      key: manifest.data["key"],
      name: manifest.data["name"],
      kind: manifest.data["kind"],
      version: manifest.data["version"],
      source: manifest.source,
      manifest_path: manifest.path,
      manifest_hash: manifest.hash,
      manifest_json: manifest.data,
      detected_binaries_json: detection.binaries,
      health: detection.health,
      detected_at: Cuckoding.Clock.wall_now(),
      last_error: detection.last_error
    }

    {:ok, stored} = plugin |> Plugin.changeset(attrs) |> Repo.insert_or_update()
    stored
  end

  defp scope_context("global", nil),
    do: {:ok, %{scope_type: "global", scope_id: nil, ancestors: []}}

  defp scope_context("project", id) do
    case Repo.get(Project, id) do
      %Project{} -> {:ok, %{scope_type: "project", scope_id: id, ancestors: [{"global", nil}]}}
      nil -> {:error, :activation_scope_not_found}
    end
  end

  defp scope_context("board", id) do
    case Repo.get(Board, id) do
      %Board{} = board ->
        {:ok,
         %{
           scope_type: "board",
           scope_id: id,
           ancestors: [{"project", board.project_id}, {"global", nil}]
         }}

      nil ->
        {:error, :activation_scope_not_found}
    end
  end

  defp scope_context("role", id) do
    with %RoleAssignment{} = role <- Repo.get(RoleAssignment, id),
         %Board{} = board <- Repo.get(Board, role.board_id) do
      {:ok,
       %{
         scope_type: "role",
         scope_id: id,
         ancestors: [
           {"board", board.id},
           {"project", board.project_id},
           {"global", nil}
         ]
       }}
    else
      nil -> {:error, :activation_scope_not_found}
    end
  end

  defp scope_context("stage", id) do
    with %StageAttempt{} = stage <- Repo.get(StageAttempt, id),
         %Run{} = run <- Repo.get(Run, stage.run_id),
         %Task{} = task <- Repo.get(Task, run.task_id),
         %Board{} = board <- Repo.get(Board, task.board_id) do
      {:ok,
       %{
         scope_type: "stage",
         scope_id: id,
         ancestors: [
           {"board", board.id},
           {"project", board.project_id},
           {"global", nil}
         ]
       }}
    else
      nil -> {:error, :activation_scope_not_found}
    end
  end

  defp scope_context(_scope_type, _scope_id), do: {:error, :invalid_activation_scope}

  defp allowed_scope(_plugin, "global"), do: :ok

  defp allowed_scope(plugin, scope_type) do
    if scope_type in plugin.manifest_json["scopes"],
      do: :ok,
      else: {:error, :scope_not_supported}
  end

  defp permission_ceiling(plugin, context) do
    case Enum.find_value(context.ancestors, &parent_limit(plugin.id, &1)) do
      {:blocked, scope_type} -> {:error, {:disabled_by_parent_scope, scope_type}}
      {:ceiling, permissions} -> {:ok, permissions}
      nil -> {:ok, plugin.manifest_json["permissions"]}
    end
  end

  defp parent_limit(plugin_id, {scope_type, scope_id}) do
    case activation(plugin_id, scope_type, scope_id) do
      %Activation{enabled: false} -> {:blocked, scope_type}
      %Activation{enabled: true} = activation -> {:ceiling, activation.permissions_json}
      nil -> false
    end
  end

  defp activation(plugin_id, scope_type, scope_id) do
    find_activation(Repo, plugin_id, scope_type, scope_id)
  end

  defp normalize_permissions(permissions) when is_map(permissions) do
    permissions = Map.new(permissions, fn {key, value} -> {to_string(key), value} end)

    with [] <- Map.keys(permissions) -- @permission_fields,
         [] <- @permission_fields -- Map.keys(permissions),
         true <- is_boolean(permissions["host_process"]),
         true <- Map.has_key?(@network_rank, permissions["network"]),
         true <- Enum.all?(~w(read_paths write_paths secrets), &string_list?(permissions[&1])) do
      {:ok, permissions}
    else
      _other -> {:error, :invalid_activation_permissions}
    end
  end

  defp normalize_permissions(_permissions), do: {:error, :invalid_activation_permissions}

  defp narrowed(requested, ceiling) do
    allowed =
      (not requested["host_process"] or ceiling["host_process"]) and
        @network_rank[requested["network"]] <= @network_rank[ceiling["network"]] and
        Enum.all?(~w(read_paths write_paths secrets), fn field ->
          MapSet.subset?(MapSet.new(requested[field]), MapSet.new(ceiling[field]))
        end)

    if allowed, do: :ok, else: {:error, :permission_expansion}
  end

  defp approval_matches("none", "standard"), do: :ok
  defp approval_matches("loopback", "loopback_network"), do: :ok
  defp approval_matches("external", "external_network"), do: :ok
  defp approval_matches(_network, _approval), do: {:error, :network_approval_mismatch}

  defp persist_activation(plugin, context, enabled, permissions, attrs, actor, reason) do
    now = Cuckoding.Clock.wall_now()

    approval_kind =
      if enabled, do: attrs["approval_kind"] || attrs[:approval_kind], else: "standard"

    network = permissions["network"]
    config = attrs["config"] || attrs[:config] || %{}

    activation_attrs = %{
      plugin_id: plugin.id,
      scope_type: context.scope_type,
      scope_id: context.scope_id,
      enabled: enabled,
      permissions_json: permissions,
      config_json: config,
      network: network,
      approval_kind: approval_kind,
      approved_by: actor,
      approval_reason: reason,
      approved_at: now
    }

    event_attrs = %{
      event_type: event_type(enabled, network),
      public_summary: summary(plugin.key, context, enabled),
      payload: %{
        "plugin_id" => plugin.id,
        "plugin_key" => plugin.key,
        "manifest_hash" => plugin.manifest_hash,
        "scope_type" => context.scope_type,
        "scope_id" => context.scope_id,
        "enabled" => enabled,
        "network" => network,
        "approval_kind" => approval_kind,
        "approved_by" => actor,
        "approval_reason" => reason,
        "permissions_hash" => digest(permissions)
      }
    }

    projection = fn repo, _sequence ->
      upsert_activation(repo, plugin.id, context, activation_attrs)
    end

    case EventStore.append("plugin:#{plugin.id}", event_attrs, projection) do
      {:ok, {_event, activation}} -> {:ok, activation}
      {:error, {:projection_failed, error}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end

  defp upsert_activation(repo, plugin_id, context, attrs) do
    current =
      find_activation(repo, plugin_id, context.scope_type, context.scope_id) ||
        %Activation{id: Identifier.generate()}

    current |> Activation.changeset(attrs) |> repo.insert_or_update()
  end

  defp event_type(false, _network), do: "plugin.disabled"
  defp event_type(true, "none"), do: "plugin.enabled"
  defp event_type(true, "loopback"), do: "plugin.loopback_enabled"
  defp event_type(true, "external"), do: "plugin.external_enabled"

  defp summary(key, context, enabled) do
    action = if enabled, do: "enabled", else: "disabled"
    "Plugin #{key} #{action} for #{context.scope_type} scope"
  end

  defp string_list?(values) do
    is_list(values) and Enum.uniq(values) == values and Enum.all?(values, &is_binary/1)
  end

  defp required_text(value, _error) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: {:error, :blank_approval}, else: {:ok, String.slice(value, 0, 500)}
  end

  defp required_text(_value, error), do: {:error, error}

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp find_activation(repo, plugin_id, scope_type, nil) do
    repo.one(
      from(activation in Activation,
        where:
          activation.plugin_id == ^plugin_id and activation.scope_type == ^scope_type and
            is_nil(activation.scope_id)
      )
    )
  end

  defp find_activation(repo, plugin_id, scope_type, scope_id) do
    repo.get_by(Activation,
      plugin_id: plugin_id,
      scope_type: scope_type,
      scope_id: scope_id
    )
  end

  defp digest(value) do
    value |> Jason.encode!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end
end
