defmodule CuckodingWeb.ProjectEditLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.PolicyComponents

  alias Cuckoding.Adapters.RuntimeConfiguration
  alias Cuckoding.ProjectOnboarding
  alias Cuckoding.Projects

  @default_role_keys MapSet.new(~w(spec_writer implementer reviewer))

  @impl true
  def mount(%{"id" => project_id}, _session, socket) do
    with project when not is_nil(project) <- Projects.get_project(project_id),
         config when not is_nil(config) <- Projects.latest_config_version(project_id) do
      {:ok,
       assign(socket,
         page_title: "Edit #{project.name}",
         project: project,
         revision: config.revision,
         config: edit_config(config.config_json),
         runtime_options: RuntimeConfiguration.options(),
         notice: nil,
         error: nil
       )}
    else
      nil -> raise Phoenix.Router.NoRouteError, conn: socket, router: CuckodingWeb.Router
    end
  end

  @impl true
  def handle_event("sync", %{"config" => params}, socket) do
    {:noreply,
     assign(socket, config: merge_config(params, socket.assigns.config), notice: nil, error: nil)}
  end

  def handle_event("add_connection", _params, socket) do
    connection = %{
      "key" => next_key(socket.assigns.config["agent_connections"], "agent"),
      "label" => "",
      "adapter_key" => "codex",
      "executable_path" => RuntimeConfiguration.default_executable("codex"),
      "api_key_helper" => ""
    }

    {:noreply,
     socket
     |> update(:config, fn config ->
       Map.update!(config, "agent_connections", &(&1 ++ [connection]))
     end)
     |> assign(notice: nil, error: nil)}
  end

  def handle_event("remove_connection", %{"index" => index}, socket) do
    with {:ok, index} <- parse_index(index),
         connection when not is_nil(connection) <-
           Enum.at(socket.assigns.config["agent_connections"], index) do
      config =
        socket.assigns.config
        |> Map.update!("agent_connections", &List.delete_at(&1, index))
        |> Map.update!(
          "default_roles",
          &clear_connection_assignments(&1, connection["key"])
        )

      {:noreply, assign(socket, config: config, notice: nil, error: nil)}
    else
      _invalid -> {:noreply, assign(socket, error: "That agent connection no longer exists.")}
    end
  end

  def handle_event("add_role", _params, socket) do
    role = %{
      "key" => next_key(socket.assigns.config["default_roles"], "custom"),
      "name" => "",
      "instructions" => "",
      "agent_connection_key" => ""
    }

    {:noreply,
     socket
     |> update(:config, fn config ->
       Map.update!(config, "default_roles", &(&1 ++ [role]))
     end)
     |> assign(notice: nil, error: nil)}
  end

  def handle_event("remove_role", %{"index" => index}, socket) do
    with {:ok, index} <- parse_index(index),
         role when not is_nil(role) <- Enum.at(socket.assigns.config["default_roles"], index),
         false <- MapSet.member?(@default_role_keys, role["key"]) do
      {:noreply,
       socket
       |> update(:config, fn config ->
         Map.update!(config, "default_roles", &List.delete_at(&1, index))
       end)
       |> assign(notice: nil, error: nil)}
    else
      true -> {:noreply, assign(socket, error: "Built-in workflow roles cannot be removed.")}
      _invalid -> {:noreply, assign(socket, error: "That role no longer exists.")}
    end
  end

  def handle_event("save", %{"config" => params}, socket) do
    config = merge_config(params, socket.assigns.config)

    attrs = %{
      "agent_connections" => config["agent_connections"],
      "default_roles" => config["default_roles"]
    }

    case ProjectOnboarding.update_configuration(
           socket.assigns.project.id,
           socket.assigns.revision,
           attrs
         ) do
      {:ok, version} ->
        {:noreply,
         assign(socket,
           revision: version.revision,
           config: edit_config(version.config_json),
           notice: "Agent and role configuration saved as revision #{version.revision}.",
           error: nil
         )}

      {:error, reason} ->
        {:noreply, assign(socket, config: config, notice: nil, error: error_message(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app>
      <section aria-labelledby="project-edit-heading" class="mx-auto max-w-5xl space-y-8">
        <header class="space-y-3">
          <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">Project settings</p>
          <div class="flex flex-wrap items-start justify-between gap-4">
            <div>
              <h1
                id="project-edit-heading"
                class="text-3xl font-semibold tracking-tight text-slate-950"
              >
                {@project.name}
              </h1>
              <p class="mt-2 break-all font-mono text-sm text-slate-600">
                {@project.repo_path} · {@project.default_branch}
              </p>
            </div>
            <span class="rounded-full bg-slate-100 px-3 py-1 text-sm font-medium text-slate-700">
              Configuration revision {@revision}
            </span>
          </div>
          <p class="max-w-3xl text-base leading-7 text-slate-700">
            Connect local agent runtimes, then assign one connection to every project role.
            New boards copy these defaults; existing boards and runs keep their snapshots.
          </p>
        </header>

        <p
          id="project-edit-status"
          role="status"
          aria-live="polite"
          class="min-h-6 text-sm text-emerald-900"
        >
          {@notice || ""}
        </p>
        <p
          :if={@error}
          id="project-edit-error"
          role="alert"
          class="rounded-md border border-red-300 bg-red-50 p-4 text-sm text-red-950"
        >
          {@error}
        </p>

        <form id="project-config-form" phx-change="sync" phx-submit="save" class="space-y-8">
          <section aria-labelledby="agents-heading" class="space-y-4">
            <div class="flex flex-wrap items-end justify-between gap-3">
              <div>
                <h2 id="agents-heading" class="text-xl font-semibold text-slate-950">Agents</h2>
                <p class="mt-1 text-sm text-slate-700">
                  Paths are machine-local. Cuckoding does not copy runtime credentials.
                </p>
              </div>
              <button
                id="add-agent"
                type="button"
                phx-click="add_connection"
                class="min-h-11 rounded-md border border-slate-400 bg-white px-4 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                Add agent
              </button>
            </div>

            <p
              :if={@config["agent_connections"] == []}
              id="agents-empty"
              class="rounded-xl border border-dashed border-slate-300 bg-white p-6 text-sm text-slate-700"
            >
              No agents connected yet. Add an agent before saving role assignments.
            </p>

            <div class="grid gap-4 lg:grid-cols-2">
              <fieldset
                :for={{connection, index} <- Enum.with_index(@config["agent_connections"])}
                id={"agent-connection-#{index}"}
                class="space-y-4 rounded-xl border border-slate-200 bg-white p-5"
              >
                <legend class="px-2 font-semibold text-slate-950">
                  {connection["label"] |> blank_to("New agent")}
                </legend>
                <input
                  type="hidden"
                  name={"config[agent_connections][#{index}][key]"}
                  value={connection["key"]}
                />
                <label class="grid gap-2 text-sm font-medium text-slate-800">
                  Connection name
                  <input
                    name={"config[agent_connections][#{index}][label]"}
                    value={connection["label"]}
                    required
                    maxlength="120"
                    placeholder="Primary Codex"
                    class="min-h-11 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
                  />
                </label>
                <label class="grid gap-2 text-sm font-medium text-slate-800">
                  Runtime
                  <select
                    name={"config[agent_connections][#{index}][adapter_key]"}
                    class="min-h-11 rounded-md border border-slate-400 bg-white px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
                  >
                    <option
                      :for={{label, value} <- @runtime_options}
                      value={value}
                      selected={connection["adapter_key"] == value}
                    >
                      {label}
                    </option>
                  </select>
                </label>
                <p
                  :if={RuntimeConfiguration.warning(connection["adapter_key"])}
                  class="rounded-md border border-amber-300 bg-amber-50 p-3 text-sm leading-6 text-amber-950"
                >
                  {RuntimeConfiguration.warning(connection["adapter_key"])}
                </p>
                <label class="grid gap-2 text-sm font-medium text-slate-800">
                  Runtime executable
                  <input
                    name={"config[agent_connections][#{index}][executable_path]"}
                    value={connection["executable_path"]}
                    required
                    autocapitalize="none"
                    spellcheck="false"
                    placeholder="/absolute/path/to/agent"
                    class="min-h-11 rounded-md border border-slate-400 px-3 font-mono text-sm focus-visible:outline-2 focus-visible:outline-offset-2"
                  />
                </label>
                <label
                  :if={connection["adapter_key"] == "claude_code"}
                  class="grid gap-2 text-sm font-medium text-slate-800"
                >
                  Claude API-key helper
                  <input
                    name={"config[agent_connections][#{index}][api_key_helper]"}
                    value={connection["api_key_helper"]}
                    required
                    autocapitalize="none"
                    spellcheck="false"
                    placeholder="/absolute/path/to/helper"
                    class="min-h-11 rounded-md border border-slate-400 px-3 font-mono text-sm focus-visible:outline-2 focus-visible:outline-offset-2"
                  />
                </label>
                <button
                  type="button"
                  phx-click="remove_connection"
                  phx-value-index={index}
                  aria-label={"Remove #{connection["label"] |> blank_to("new agent")}"}
                  class="min-h-10 rounded-md border border-red-300 px-3 text-sm font-medium text-red-900 focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  Remove agent
                </button>
              </fieldset>
            </div>
          </section>

          <section aria-labelledby="roles-heading" class="space-y-4">
            <div class="flex flex-wrap items-end justify-between gap-3">
              <div>
                <h2 id="roles-heading" class="text-xl font-semibold text-slate-950">Roles</h2>
                <p class="mt-1 text-sm text-slate-700">
                  Built-in workflow roles remain available; custom roles can be added or removed.
                </p>
              </div>
              <button
                id="add-role"
                type="button"
                phx-click="add_role"
                class="min-h-11 rounded-md border border-slate-400 bg-white px-4 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                Add role
              </button>
            </div>

            <div class="grid gap-4 lg:grid-cols-2">
              <fieldset
                :for={{role, index} <- Enum.with_index(@config["default_roles"])}
                id={"project-role-#{role["key"]}"}
                class="space-y-4 rounded-xl border border-slate-200 bg-white p-5"
              >
                <legend class="px-2 font-semibold text-slate-950">
                  {role["name"] |> blank_to("New role")}
                </legend>
                <input
                  type="hidden"
                  name={"config[default_roles][#{index}][key]"}
                  value={role["key"]}
                />
                <label class="grid gap-2 text-sm font-medium text-slate-800">
                  Role name
                  <input
                    name={"config[default_roles][#{index}][name]"}
                    value={role["name"]}
                    required
                    maxlength="120"
                    class="min-h-11 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
                  />
                </label>
                <label class="grid gap-2 text-sm font-medium text-slate-800">
                  Assigned agent
                  <select
                    name={"config[default_roles][#{index}][agent_connection_key]"}
                    required
                    class="min-h-11 rounded-md border border-slate-400 bg-white px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
                  >
                    <option value="" selected={role["agent_connection_key"] in [nil, ""]}>
                      Choose agent
                    </option>
                    <option
                      :for={connection <- @config["agent_connections"]}
                      value={connection["key"]}
                      selected={role["agent_connection_key"] == connection["key"]}
                    >
                      {connection["label"] |> blank_to(connection["key"])}
                    </option>
                  </select>
                </label>
                <label class="grid gap-2 text-sm font-medium text-slate-800">
                  Instructions <textarea
                    name={"config[default_roles][#{index}][instructions]"}
                    rows="4"
                    required
                    maxlength="4000"
                    class="rounded-md border border-slate-400 px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2"
                  >{role["instructions"]}</textarea>
                </label>
                <button
                  :if={not default_role?(role["key"])}
                  type="button"
                  phx-click="remove_role"
                  phx-value-index={index}
                  aria-label={"Remove #{role["name"] |> blank_to("new role")}"}
                  class="min-h-10 rounded-md border border-red-300 px-3 text-sm font-medium text-red-900 focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  Remove role
                </button>
              </fieldset>
            </div>
          </section>

          <.host_runner_notice />

          <div class="flex flex-wrap items-center justify-between gap-3">
            <.link
              navigate={~p"/"}
              class="inline-flex min-h-11 items-center rounded-md border border-slate-400 bg-white px-5 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2"
            >
              Dashboard
            </.link>
            <button class="min-h-11 rounded-md bg-slate-950 px-5 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2">
              Save agents and roles
            </button>
          </div>
        </form>
      </section>
    </Layouts.app>
    """
  end

  defp edit_config(config) do
    %{
      "agent_connections" =>
        Enum.map(config["agent_connections"] || [], fn connection ->
          settings = connection["settings"] || %{}

          %{
            "key" => connection["key"],
            "label" => connection["label"] || humanize(connection["key"]),
            "adapter_key" => connection["adapter_key"],
            "executable_path" => settings["executable_path"] || "",
            "api_key_helper" => settings["api_key_helper"] || ""
          }
        end),
      "default_roles" => config["default_roles"] || ProjectOnboarding.default_roles()
    }
  end

  defp merge_config(params, current) do
    %{
      "agent_connections" =>
        merge_connections(params["agent_connections"], current["agent_connections"]),
      "default_roles" => merge_items(params["default_roles"], current["default_roles"])
    }
  end

  defp merge_connections(params, current) do
    params
    |> ordered_values()
    |> Enum.with_index()
    |> Enum.map(fn {params, index} ->
      previous = Enum.at(current, index, %{})
      connection = Map.merge(previous, params)

      connection =
        if connection["adapter_key"] != previous["adapter_key"] do
          Map.put(
            connection,
            "executable_path",
            RuntimeConfiguration.default_executable(connection["adapter_key"])
          )
        else
          connection
        end

      if connection["adapter_key"] == "claude_code",
        do: connection,
        else: Map.put(connection, "api_key_helper", "")
    end)
  end

  defp merge_items(params, current) do
    params
    |> ordered_values()
    |> Enum.with_index()
    |> Enum.map(fn {params, index} -> Map.merge(Enum.at(current, index, %{}), params) end)
  end

  defp ordered_values(values) when is_list(values), do: values

  defp ordered_values(values) when is_map(values) do
    values
    |> Enum.sort_by(fn {key, _value} -> parse_order(key) end)
    |> Enum.map(&elem(&1, 1))
  end

  defp ordered_values(_values), do: []

  defp parse_order(value) do
    case Integer.parse(to_string(value)) do
      {number, ""} -> number
      _invalid -> 0
    end
  end

  defp next_key(items, prefix) do
    used = MapSet.new(items, & &1["key"])

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(&"#{prefix}-#{&1}")
    |> Enum.find(&(not MapSet.member?(used, &1)))
  end

  defp clear_connection_assignments(roles, connection_key) do
    Enum.map(roles, fn role ->
      if role["agent_connection_key"] == connection_key,
        do: Map.put(role, "agent_connection_key", ""),
        else: role
    end)
  end

  defp parse_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {index, ""} when index >= 0 -> {:ok, index}
      _invalid -> :error
    end
  end

  defp parse_index(_value), do: :error

  defp error_message(:stale_configuration),
    do: "This project was changed in another window. Reload before saving."

  defp error_message(:invalid_runtime_executable),
    do: "Every agent needs an absolute path to an executable runtime."

  defp error_message(:unsupported_runtime), do: "Choose a supported runtime for every agent."
  defp error_message(:agent_label_required), do: "Every agent needs a connection name."
  defp error_message(:role_name_required), do: "Every role needs a name."
  defp error_message(:role_instructions_required), do: "Every role needs instructions."
  defp error_message(:role_agent_required), do: "Assign an agent to every role."

  defp error_message(:default_role_missing),
    do: "The built-in workflow roles must remain configured."

  defp error_message(%Ecto.Changeset{} = changeset),
    do: "Configuration could not be saved: #{inspect(changeset.errors)}"

  defp error_message(reason), do: "Configuration could not be saved: #{inspect(reason)}"

  defp default_role?(key), do: MapSet.member?(@default_role_keys, key)

  defp blank_to(value, fallback) when value in [nil, ""], do: fallback
  defp blank_to(value, _fallback), do: value

  defp humanize(value) when is_binary(value),
    do: value |> String.replace(~r/[-_]+/, " ") |> String.capitalize()

  defp humanize(_value), do: "Agent"
end
