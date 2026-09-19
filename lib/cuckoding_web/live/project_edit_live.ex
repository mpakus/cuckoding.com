defmodule CuckodingWeb.ProjectEditLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.PolicyComponents

  alias Cuckoding.Adapters
  alias Cuckoding.Adapters.RuntimeConfiguration
  alias Cuckoding.AgentRuntime
  alias Cuckoding.ProjectOnboarding
  alias Cuckoding.Projects
  alias Cuckoding.ProjectWorkflow
  alias Cuckoding.Workflows

  @default_role_keys MapSet.new(~w(spec_writer implementer reviewer))

  @impl true
  def mount(%{"id" => project_id}, _session, socket) do
    with project when not is_nil(project) <- Projects.get_project(project_id),
         config when not is_nil(config) <- Projects.latest_config_version(project_id) do
      {:ok,
       socket
       |> assign(
         page_title: "Edit #{project.name}",
         project: project,
         revision: config.revision,
         config: edit_config(config.config_json),
         runtime_options: RuntimeConfiguration.options(),
         boards: Workflows.list_boards(project.id),
         board_form: %{"name" => "Product", "description" => "", "concurrency_limit" => "1"},
         notice: nil,
         error: nil
       )
       |> refresh_saved_agents()}
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
      "provider_account_id" => "",
      "executable_path" => RuntimeConfiguration.default_executable("codex"),
      "api_key_helper" => "",
      "persisted" => false
    }

    {:noreply,
     socket
     |> update(:config, fn config ->
       Map.update!(config, "agent_connections", &(&1 ++ [connection]))
     end)
     |> assign(notice: nil, error: nil)}
  end

  def handle_event("use-saved-agent", %{"id" => id}, socket) do
    with account when not is_nil(account) <- Adapters.get_provider_account(id),
         false <- attached?(socket.assigns.config, account.id) do
      settings = account.capabilities_json["settings"] || %{}

      connection = %{
        "key" => next_key(socket.assigns.config["agent_connections"], "agent"),
        "label" => account.label,
        "adapter_key" => account.adapter_key,
        "provider_account_id" => account.id,
        "executable_path" => settings["executable_path"] || "",
        "api_key_helper" => settings["api_key_helper"] || "",
        "persisted" => false
      }

      {:noreply,
       socket
       |> update(:config, fn config ->
         Map.update!(config, "agent_connections", &(&1 ++ [connection]))
       end)
       |> assign(
         notice: "#{account.label} added. Save it to attach it to this project.",
         error: nil
       )}
    else
      true -> {:noreply, assign(socket, error: "That saved agent is already attached.")}
      nil -> {:noreply, assign(socket, error: "That saved agent no longer exists.")}
    end
  end

  def handle_event("check-agent-authorization", %{"id" => id}, socket) do
    with account when not is_nil(account) <- Adapters.get_provider_account(id),
         {:ok, updated} <- AgentRuntime.check_account(account) do
      notice =
        if updated.status == "authenticated",
          do: "#{updated.label} is authorized and ready for every project.",
          else: "#{updated.label} is not authorized yet. Run the command below, then check again."

      {:noreply, socket |> refresh_saved_agents() |> assign(notice: notice, error: nil)}
    else
      nil -> {:noreply, assign(socket, error: "That saved agent no longer exists.")}
      {:error, reason} -> {:noreply, assign(socket, error: authorization_error(reason))}
    end
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

  def handle_event("save-agent", %{"index" => index}, socket) do
    config = socket.assigns.config

    with {:ok, index} <- parse_index(index),
         connection when not is_nil(connection) <- Enum.at(config["agent_connections"], index),
         {:ok, version} <-
           ProjectOnboarding.save_connection(
             socket.assigns.project.id,
             socket.assigns.revision,
             connection
           ) do
      saved =
        version.config_json
        |> edit_config()
        |> Map.fetch!("agent_connections")
        |> Enum.find(&(&1["key"] == connection["key"]))

      updated = Map.update!(config, "agent_connections", &List.replace_at(&1, index, saved))

      {:noreply,
       socket
       |> assign(
         revision: version.revision,
         config: updated,
         notice: "#{saved["label"]} saved as configuration revision #{version.revision}.",
         error: nil
       )
       |> refresh_saved_agents()}
    else
      :error ->
        {:noreply,
         assign(socket, config: config, notice: nil, error: "That agent no longer exists.")}

      nil ->
        {:noreply,
         assign(socket, config: config, notice: nil, error: "That agent no longer exists.")}

      {:error, reason} ->
        {:noreply, assign(socket, config: config, notice: nil, error: error_message(reason))}
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
         socket
         |> assign(
           revision: version.revision,
           config: edit_config(version.config_json),
           notice: "Agent and role configuration saved as revision #{version.revision}.",
           error: nil
         )
         |> refresh_saved_agents()}

      {:error, reason} ->
        {:noreply, assign(socket, config: config, notice: nil, error: error_message(reason))}
    end
  end

  def handle_event("create-board", %{"board" => attrs}, socket) do
    case ProjectWorkflow.create_board(socket.assigns.project.id, attrs) do
      {:ok, board} ->
        {:noreply,
         socket
         |> put_flash(:info, "Board created with the current role assignments.")
         |> push_navigate(to: ~p"/boards/#{board.id}")}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           board_form: Map.merge(socket.assigns.board_form, attrs),
           notice: nil,
           error: board_error(reason)
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
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

        <section
          :if={@saved_agents != []}
          aria-labelledby="saved-agents-heading"
          class="space-y-4"
        >
          <div>
            <h2 id="saved-agents-heading" class="text-xl font-semibold text-slate-950">
              Saved agents
            </h2>
            <p class="mt-1 text-sm leading-6 text-slate-700">
              Reuse these machine-wide connections in any project. Credentials stay in the
              provider or macOS Keychain; Cuckoding stores only connection settings and status.
            </p>
          </div>

          <div class="grid gap-4 lg:grid-cols-2">
            <article
              :for={account <- @saved_agents}
              id={"saved-agent-#{account.id}"}
              class="space-y-4 rounded-xl border border-slate-200 bg-white p-5"
            >
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h3 class="font-semibold text-slate-950">{account.label}</h3>
                  <p class="mt-1 text-sm text-slate-600">
                    {runtime_label(account.adapter_key)} · {authorization_status(account.status)}
                  </p>
                </div>
                <button
                  type="button"
                  phx-click="use-saved-agent"
                  phx-value-id={account.id}
                  disabled={attached?(@config, account.id)}
                  class="min-h-10 rounded-md border border-slate-400 px-3 text-sm font-medium text-slate-950 disabled:cursor-not-allowed disabled:bg-slate-100 disabled:text-slate-500 focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  {if attached?(@config, account.id), do: "Attached", else: "Use in this project"}
                </button>
              </div>

              <div
                :for={setup <- List.wrap(@agent_setups[account.id])}
                id={"saved-agent-command-#{account.id}"}
                phx-hook="CopyCommand"
                class="space-y-2"
              >
                <label class="grid gap-2 text-sm font-medium text-slate-800">
                  One-time authorization command
                  <span class="flex gap-2">
                    <input
                      data-copy-source
                      readonly
                      value={setup.command}
                      class="min-h-11 min-w-0 flex-1 rounded-md border border-slate-400 px-3 font-mono text-xs text-slate-800"
                    />
                    <button
                      type="button"
                      data-copy-button
                      class="min-h-11 rounded-md border border-slate-400 px-4 text-sm font-medium focus-visible:outline-2 focus-visible:outline-offset-2"
                    >
                      Copy
                    </button>
                  </span>
                </label>
                <p
                  data-copy-status
                  role="status"
                  aria-live="polite"
                  class="min-h-5 text-sm text-slate-600"
                >
                </p>
                <button
                  type="button"
                  phx-click="check-agent-authorization"
                  phx-value-id={account.id}
                  class="min-h-10 rounded-md bg-slate-950 px-4 text-sm font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  Check authorization
                </button>
              </div>

              <p
                :if={account.adapter_key == "claude_code"}
                class="text-sm leading-6 text-slate-700"
              >
                The configured API-key helper is reused without storing its secret output.
              </p>
              <p
                :if={account.adapter_key == "cursor_agent"}
                class="text-sm leading-6 text-slate-700"
              >
                Cursor authorization remains run-specific because its CLI writes user-global
                session state.
              </p>
            </article>
          </div>
        </section>

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
                <input
                  type="hidden"
                  name={"config[agent_connections][#{index}][provider_account_id]"}
                  value={connection["provider_account_id"]}
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
                <button
                  type="button"
                  phx-click="save-agent"
                  phx-value-index={index}
                  class="min-h-10 rounded-md bg-slate-950 px-4 text-sm font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  {if connection["persisted"], do: "Update agent", else: "Save agent"}
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

        <section aria-labelledby="boards-heading" class="space-y-5 border-t border-slate-200 pt-8">
          <div>
            <h2 id="boards-heading" class="text-2xl font-semibold text-slate-950">Boards</h2>
            <p class="mt-2 max-w-3xl text-sm leading-6 text-slate-700">
              Each board copies the latest saved role assignments. Existing boards and runs keep
              their snapshots when project defaults change.
            </p>
          </div>

          <ul :if={@boards != []} class="grid gap-3 sm:grid-cols-2">
            <li
              :for={board <- @boards}
              id={"project-board-#{board.id}"}
              class="rounded-xl border border-slate-200 bg-white p-5"
            >
              <h3 class="font-semibold text-slate-950">{board.name}</h3>
              <p class="mt-1 text-sm text-slate-600">
                {String.capitalize(board.status)} · up to {board.concurrency_limit} active run{if board.concurrency_limit ==
                                                                                                    1,
                                                                                                  do:
                                                                                                    "",
                                                                                                  else:
                                                                                                    "s"}
              </p>
              <.link
                navigate={~p"/boards/#{board.id}"}
                class="mt-4 inline-flex min-h-10 items-center rounded-md border border-slate-400 px-4 text-sm font-medium focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                Open board
              </.link>
            </li>
          </ul>

          <form
            id="create-board-form"
            phx-submit="create-board"
            class="grid gap-4 rounded-xl border border-slate-200 bg-white p-5 sm:grid-cols-2"
          >
            <label class="grid gap-2 text-sm font-medium text-slate-800">
              Board name
              <input
                name="board[name]"
                value={@board_form["name"]}
                required
                maxlength="120"
                class="min-h-11 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
              />
            </label>
            <label class="grid gap-2 text-sm font-medium text-slate-800">
              Concurrent runs
              <input
                type="number"
                name="board[concurrency_limit]"
                value={@board_form["concurrency_limit"]}
                min="1"
                max="32"
                required
                class="min-h-11 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
              />
            </label>
            <label class="grid gap-2 text-sm font-medium text-slate-800 sm:col-span-2">
              Description <textarea
                name="board[description]"
                rows="3"
                maxlength="2000"
                class="rounded-md border border-slate-400 px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2"
              >{@board_form["description"]}</textarea>
            </label>
            <div class="sm:col-span-2">
              <button class="min-h-11 rounded-md bg-slate-950 px-5 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2">
                Create board
              </button>
            </div>
          </form>
        </section>
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
            "provider_account_id" => connection["provider_account_id"] || "",
            "executable_path" => settings["executable_path"] || "",
            "api_key_helper" => settings["api_key_helper"] || "",
            "persisted" => true
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
  defp error_message(:invalid_provider_account), do: "Choose a valid saved agent."

  defp error_message(:default_role_missing),
    do: "The built-in workflow roles must remain configured."

  defp error_message(%Ecto.Changeset{} = changeset),
    do: "Configuration could not be saved: #{inspect(changeset.errors)}"

  defp error_message(reason), do: "Configuration could not be saved: #{inspect(reason)}"

  defp authorization_error(%Cuckoding.Adapters.Types.Error{code: :executable_not_found}),
    do: "The saved runtime executable no longer exists. Update the agent path and try again."

  defp authorization_error(%Cuckoding.Adapters.Types.Error{code: code}),
    do: "Authorization could not be checked (#{code}). Verify the executable and try again."

  defp authorization_error(reason),
    do: "Authorization could not be checked: #{inspect(reason)}"

  defp board_error(:roles_not_configured),
    do: "Save an agent assignment for every built-in role before creating a board."

  defp board_error(%Ecto.Changeset{} = changeset),
    do: "Board could not be created: #{inspect(changeset.errors)}"

  defp board_error(reason), do: "Board could not be created: #{inspect(reason)}"

  defp default_role?(key), do: MapSet.member?(@default_role_keys, key)

  defp refresh_saved_agents(socket) do
    accounts = Adapters.list_provider_accounts()

    setups =
      Map.new(accounts, fn account ->
        case AgentRuntime.account_setup(account) do
          {:ok, %{command: _command} = setup} -> {account.id, setup}
          _other -> {account.id, nil}
        end
      end)

    assign(socket, saved_agents: accounts, agent_setups: setups)
  end

  defp attached?(config, account_id) do
    Enum.any?(config["agent_connections"], &(&1["provider_account_id"] == account_id))
  end

  defp authorization_status("authenticated"), do: "Authorized"
  defp authorization_status("authentication_required"), do: "Authorization required"
  defp authorization_status(_status), do: "Authorization not checked"

  defp runtime_label("codex"), do: "Codex"
  defp runtime_label("claude_code"), do: "Claude Code"
  defp runtime_label("cursor_agent"), do: "Cursor Agent"
  defp runtime_label("opencode"), do: "OpenCode"
  defp runtime_label("custom_agent"), do: "Custom Agent"
  defp runtime_label(runtime), do: humanize(runtime)

  defp blank_to(value, fallback) when value in [nil, ""], do: fallback
  defp blank_to(value, _fallback), do: value

  defp humanize(value) when is_binary(value),
    do: value |> String.replace(~r/[-_]+/, " ") |> String.capitalize()

  defp humanize(_value), do: "Agent"
end
