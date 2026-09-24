defmodule CuckodingWeb.ProjectEditLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.PolicyComponents

  alias Cuckoding.Adapters
  alias Cuckoding.Adapters.RuntimeConfiguration
  alias Cuckoding.AgentRuntime
  alias Cuckoding.ProjectAutopilot
  alias Cuckoding.ProjectOnboarding
  alias Cuckoding.Projects
  alias Cuckoding.ProjectWorkflow
  alias Cuckoding.Workflows
  alias CuckodingWeb.PublicError

  @default_role_keys MapSet.new(~w(spec_writer implementer reviewer))

  @impl true
  def mount(%{"id" => project_id}, _session, socket) do
    with project when not is_nil(project) <- Projects.get_project(project_id),
         config when not is_nil(config) <- Projects.latest_config_version(project_id) do
      if connected?(socket) do
        Cuckoding.ActivityStream.subscribe(:all)
        Process.send_after(self(), :refresh_project, 5_000)
      end

      autopilot = ProjectAutopilot.settings(project.id)

      {:ok,
       socket
       |> assign(
         page_title: "Edit #{project.name}",
         project: project,
         revision: config.revision,
         config: edit_config(config.config_json),
         saved_config: edit_config(config.config_json),
         runtime_options: RuntimeConfiguration.options(),
         boards: Workflows.list_boards(project.id),
         board_form: %{"name" => "Product", "description" => "", "concurrency_limit" => "1"},
         autopilot: autopilot,
         autopilot_counts: ProjectAutopilot.task_counts(project.id),
         critical_blockers: ProjectAutopilot.critical_blocker_count(project.id),
         autopilot_form: %{
           "max_active_runs" => to_string(autopilot.max_active_runs),
           "critical_blocker_limit" => to_string(autopilot.critical_blocker_limit),
           "completion_mode" => autopilot.completion_mode
         },
         notice: nil,
         error: nil
       )
       |> refresh_saved_agents()}
    else
      nil -> raise Phoenix.Router.NoRouteError, conn: socket, router: CuckodingWeb.Router
    end
  end

  @impl true
  def handle_info({:activity_event, _stream_id, _sequence}, socket),
    do: {:noreply, refresh_autopilot(socket)}

  def handle_info(:refresh_project, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh_project, 5_000)
    {:noreply, refresh_autopilot(socket)}
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
      "model" => "",
      "reasoning_effort" => "",
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
        "model" => settings["model"] || "",
        "reasoning_effort" => settings["reasoning_effort"] || "",
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
          do:
            "#{updated.label} authorization checked. Each run checks its own access before starting.",
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
         saved_config: edit_config(version.config_json),
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
           saved_config: edit_config(version.config_json),
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
    result =
      if socket.assigns.config != socket.assigns.saved_config,
        do: {:error, :unsaved_configuration},
        else: ProjectWorkflow.create_board(socket.assigns.project.id, attrs)

    case result do
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

  def handle_event("connect-board-agents", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.boards, &(&1.id == id)) and
         socket.assigns.config == socket.assigns.saved_config do
      case ProjectWorkflow.apply_project_roles(id, socket.assigns.revision) do
        {:ok, _board} ->
          {:noreply,
           assign(socket,
             notice:
               "Agents assigned to the board. Future runs use them, and compatible queued runs are connected without rewriting their snapshots.",
             error: nil
           )}

        {:error, _reason} ->
          {:noreply,
           assign(socket,
             error:
               "Board roles could not be updated. Assign a saved agent to every required project role, save, and retry."
           )}
      end
    else
      {:noreply, assign(socket, error: "Save project settings before connecting this board.")}
    end
  end

  def handle_event("start-project", %{"autopilot" => attrs}, socket) do
    case ProjectAutopilot.start(socket.assigns.project.id, attrs) do
      {:ok, _control} ->
        {:noreply,
         socket
         |> assign(
           autopilot_form: attrs,
           notice: "Project started. Ready tasks will launch as capacity allows.",
           error: nil
         )
         |> refresh_autopilot()}

      {:error, reason} ->
        {:noreply,
         assign(socket, autopilot_form: attrs, notice: nil, error: autopilot_error(reason))}
    end
  end

  def handle_event("pause-project", _params, socket) do
    case ProjectAutopilot.pause(socket.assigns.project.id) do
      {:ok, _control} ->
        {:noreply,
         socket
         |> assign(notice: "New task starts paused. Already running tasks continue.", error: nil)
         |> refresh_autopilot()}

      {:error, _reason} ->
        {:noreply,
         assign(socket, notice: nil, error: "Project could not be paused. Reload and try again.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="projects">
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
            Create a board and tasks, then assign saved agents to project roles.
            Assign updated agents to an existing board before starting new runs.
          </p>
        </header>
        <.link
          navigate={~p"/settings/agents"}
          class="inline-flex min-h-11 items-center rounded-md border border-slate-400 bg-white px-4 underline underline-offset-4"
        >Manage shared agents and sign-in</.link>

        <nav aria-label="Project sections" class="grid gap-3 sm:grid-cols-3">
          <a
            href="#agents-heading"
            class="rounded-lg border border-slate-300 bg-white p-4 underline underline-offset-4"
          >1. Connect agents</a>
          <a
            href="#roles-heading"
            class="rounded-lg border border-slate-300 bg-white p-4 underline underline-offset-4"
          >2. Assign roles</a>
          <a
            href="#boards-heading"
            class="rounded-lg border border-slate-300 bg-white p-4 underline underline-offset-4"
          >3. Open or create a board ({length(@boards)})</a>
        </nav>
        <p
          id="project-save-state"
          role="status"
          class="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-700"
        >
          {if @config != @saved_config,
            do:
              "Unsaved changes. Save agents and roles before leaving this page or creating a board.",
            else: "Project settings are saved. New boards will use these agents and roles."}
        </p>

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

        <details
          :if={@saved_agents != []}
          id="saved-agents-panel"
          open={@config["agent_connections"] == []}
          aria-labelledby="saved-agents-heading"
          class="space-y-4"
        >
          <summary id="saved-agents-heading" class="min-h-6 font-semibold text-slate-950">
            Saved agents ({length(@saved_agents)}) · reuse or check sign-in
          </summary>
          <div>
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
                  <p class="mt-1 text-sm text-slate-600">{runtime_label(account.adapter_key)}</p>
                  <p class={
                    if account.status == "authenticated",
                      do: "text-sm font-semibold text-emerald-800",
                      else: "text-sm font-semibold text-amber-800"
                  }>
                    {authorization_status(account.status)}
                  </p>
                  <p class="text-sm text-slate-600">
                    Model: {account.capabilities_json["settings"]["model"] || "Runtime default"}
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
                :if={is_nil(account.authorization_account_id) && account.status != "authenticated"}
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
                  phx-disable-with="Checking authorization…"
                  phx-value-id={account.id}
                  class="min-h-10 rounded-md bg-slate-950 px-4 text-sm font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  Check authorization
                </button>
              </div>

              <.link
                :if={is_nil(account.authorization_account_id) && account.status == "authenticated"}
                navigate={"/settings/agents#agent-#{account.id}"}
                class="inline-flex min-h-10 items-center text-sm underline"
              >Re-authorize agent</.link>

              <p :if={account.authorization_account_id} class="text-sm text-slate-700">
                Uses an existing provider sign-in.
                <.link
                  navigate={"/settings/agents#agent-#{account.authorization_account_id}"}
                  class="underline"
                >
                  Manage shared sign-in
                </.link>
              </p>

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
                Cursor uses this agent's Cuckoding profile across projects. Sign-in and
                provider history are shared; task permissions stay run-specific.
              </p>
            </article>
          </div>
        </details>

        <form id="project-config-form" phx-change="sync" phx-submit="save" class="space-y-8">
          <section aria-labelledby="agents-heading" class="space-y-4">
            <div class="flex flex-wrap items-end justify-between gap-3">
              <div>
                <h2 id="agents-heading" class="text-xl font-semibold text-slate-950">Agents</h2>
                <p class="mt-1 text-sm text-slate-700">
                  Save each connection here, then assign it to roles below. To sign in, expand Saved agents above. Cuckoding does not copy credentials.
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
                <p class="text-sm text-slate-600">
                  {if connection["persisted"],
                    do: "Saved connection · edits need Update agent or Save agents and roles.",
                    else: "Not saved yet · enter the settings, then choose Save agent."}
                </p>
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
                <input
                  type="hidden"
                  name={"config[agent_connections][#{index}][reasoning_effort]"}
                  value={connection["reasoning_effort"] || ""}
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
                  <span class="text-sm font-normal text-slate-600">Full path to the agent's command-line program, not its desktop app.</span>
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
                <label class="grid gap-2 text-sm font-medium text-slate-800">
                  Model ID
                  <span class="text-sm font-normal text-slate-600">Leave blank for the runtime default. New agents reuse a compatible saved sign-in; manage separate accounts in Agents.</span>
                  <input
                    name={"config[agent_connections][#{index}][model]"}
                    value={connection["model"]}
                    list={"agent-models-#{index}"}
                    maxlength="128"
                    class="min-h-11 min-w-0 rounded border border-slate-400 px-3 font-mono text-sm"
                  />
                  <datalist id={"agent-models-#{index}"}>
                    <option
                      :for={{label, value} <- RuntimeConfiguration.models(connection["adapter_key"])}
                      value={value}
                    >
                      {label}
                    </option>
                  </datalist>
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
                  data-confirm="Remove this connection from the project form and clear its role assignments? Save agents and roles to apply. The saved agent and existing runs are kept."
                  phx-value-index={index}
                  aria-label={"Remove #{connection["label"] |> blank_to("new agent")}"}
                  class="min-h-10 rounded-md border border-red-300 px-3 text-sm font-medium text-red-900 focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  Remove agent
                </button>
                <button
                  type="button"
                  phx-click="save-agent"
                  phx-disable-with="Saving agent…"
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
                  A role is a job: Speculator writes specs, Implementor writes code and tests, and Reviewer checks the result. One agent can fill several roles. Save assignments below before creating a board.
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
            <button
              phx-disable-with="Saving agents and roles…"
              class="min-h-11 rounded-md bg-slate-950 px-5 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
            >
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
          <p :if={@boards == []} class="text-sm text-slate-700">
            No boards yet. Create one now; agents and roles can be assigned later.
          </p>

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
              <button
                type="button"
                phx-click="connect-board-agents"
                phx-value-id={board.id}
                data-confirm="Assign the current project agents to this board? Future runs use them, and compatible queued runs receive audited bindings without changing their snapshots."
                class="mt-3 min-h-11 rounded-md border border-slate-400 px-4 text-sm"
              >
                Assign agents to board
              </button>
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
              <span class="text-sm font-normal text-slate-600">Maximum tasks allowed to run together on this board.</span>
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
              <button
                phx-disable-with="Creating board…"
                class="min-h-11 rounded-md bg-slate-950 px-5 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                Create board
              </button>
            </div>
          </form>
        </section>
        <section
          id="project-operation"
          aria-labelledby="project-operation-heading"
          class="space-y-5 border-t border-slate-200 pt-8"
        >
          <div>
            <h2 id="project-operation-heading" class="text-2xl font-semibold text-slate-950">
              Project operation
            </h2>
            <p class="mt-2 max-w-3xl text-sm leading-6 text-slate-700">
              Start eligible Ready tasks automatically, up to the limits below. Choose what happens after review passes. Draft proposals still need review and import. Pause stops new starts, not running work.
            </p>
          </div>
          <div
            id="project-operation-status"
            role="status"
            aria-live="polite"
            class="rounded-xl border border-slate-200 bg-white p-5"
          >
            <p class="font-semibold text-slate-950">{autopilot_state(@autopilot.state)}</p>
            <p class="mt-1 text-sm text-slate-700">{progress_summary(@autopilot_counts)}</p>
            <p class="mt-1 text-sm text-slate-700">
              Critical blockers: {@critical_blockers} / {@autopilot.critical_blocker_limit}
            </p>
            <p class="mt-1 text-sm text-slate-700">
              After review: {if @autopilot.completion_mode == "local",
                do: "Complete locally",
                else: "Wait for my decision"}.
              Push and pull requests require approval.
            </p>
            <p :if={@autopilot.last_issue} class="mt-2 text-sm text-amber-900">
              {ProjectAutopilot.issue_message(@autopilot.last_issue)}
            </p>
          </div>
          <form
            :if={@autopilot.state != "running"}
            id="start-project-form"
            phx-submit="start-project"
            class="grid gap-4 rounded-xl border border-slate-200 bg-white p-5 sm:grid-cols-2"
          >
            <label class="grid gap-2 text-sm font-medium text-slate-800">
              Concurrent project runs
              <span class="text-sm font-normal text-slate-600">The board, trusted policy, and machine may set lower limits.</span>
              <input
                name="autopilot[max_active_runs]"
                type="number"
                min="1"
                max="32"
                required
                value={@autopilot_form["max_active_runs"]}
                class="min-h-11 rounded-md border border-slate-400 px-3"
              />
            </label>
            <label class="grid gap-2 text-sm font-medium text-slate-800">
              Stop at this many critical blockers
              <input
                name="autopilot[critical_blocker_limit]"
                type="number"
                min="1"
                max="100"
                required
                value={@autopilot_form["critical_blocker_limit"]}
                class="min-h-11 rounded-md border border-slate-400 px-3"
              />
            </label>
            <label class="grid gap-2 text-sm font-medium text-slate-800 sm:col-span-2">
              After a passing review
              <select
                name="autopilot[completion_mode]"
                class="min-h-11 rounded-md border border-slate-400 bg-white px-3"
              >
                <option value="manual" selected={@autopilot_form["completion_mode"] != "local"}>
                  Wait for my decision
                </option>
                <option value="local" selected={@autopilot_form["completion_mode"] == "local"}>
                  Complete locally automatically
                </option>
              </select>
              <span class="font-normal text-slate-600">
                Starting with automatic local completion authorizes Cuckoding to mark reviewed cards Done and retain their branches and evidence. It does not authorize a push, pull request or merge.
              </span>
            </label>
            <div class="sm:col-span-2">
              <button
                phx-disable-with="Starting project…"
                class="min-h-11 rounded-md bg-slate-950 px-5 font-medium text-white"
              >Start project</button>
            </div>
          </form>
          <button
            :if={@autopilot.state == "running"}
            type="button"
            phx-click="pause-project"
            class="min-h-11 rounded-md border border-slate-400 bg-white px-5 font-medium text-slate-950"
          >Pause new starts</button>
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
            "model" => settings["model"] || "",
            "reasoning_effort" => Map.get(settings, "reasoning_effort", ""),
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
          connection
          |> Map.put(
            "executable_path",
            RuntimeConfiguration.default_executable(connection["adapter_key"])
          )
          |> Map.put("reasoning_effort", "")
        else
          connection
        end

      connection =
        if connection["model"] != previous["model"],
          do: Map.put(connection, "reasoning_effort", ""),
          else: connection

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
    do: PublicError.changeset("Project settings could not be saved", changeset)

  defp error_message(_reason),
    do:
      PublicError.unexpected(
        "Project settings could not be saved",
        "Reload the project, review the agent and role assignments, and try again."
      )

  defp authorization_error(%Cuckoding.Adapters.Types.Error{code: :executable_not_found}),
    do: "The saved runtime executable no longer exists. Update the agent path and try again."

  defp authorization_error(%Cuckoding.Adapters.Types.Error{}),
    do: "Authorization could not be checked. Verify the executable and try again."

  defp authorization_error(_reason),
    do: "Authorization could not be checked. Verify the agent settings and try again."

  defp board_error(:roles_not_configured),
    do: "Save your project settings, then try creating the board again."

  defp board_error(:unsaved_configuration),
    do:
      "Save your agents and roles before creating a board. This keeps the board from using older settings."

  defp board_error(%Ecto.Changeset{} = changeset),
    do: PublicError.changeset("Board could not be created", changeset)

  defp board_error(_reason),
    do:
      PublicError.unexpected(
        "Board could not be created",
        "Review the board details and current role assignments, then try again."
      )

  defp default_role?(key), do: MapSet.member?(@default_role_keys, key)

  defp refresh_autopilot(socket) do
    project_id = socket.assigns.project.id

    assign(socket,
      autopilot: ProjectAutopilot.settings(project_id),
      autopilot_counts: ProjectAutopilot.task_counts(project_id),
      critical_blockers: ProjectAutopilot.critical_blocker_count(project_id)
    )
  end

  defp autopilot_state("running"), do: "Running automatically"
  defp autopilot_state("attention"), do: "Needs attention"
  defp autopilot_state("done"), do: "All tasks complete"
  defp autopilot_state(_state), do: "Paused"

  defp progress_summary(counts) do
    total = Enum.sum(Map.values(counts))

    "#{Map.get(counts, "done", 0)} of #{total} tasks done · #{Map.get(counts, "running", 0)} running · #{Map.get(counts, "ready", 0)} ready"
  end

  defp autopilot_error(:no_ready_tasks),
    do:
      "No Ready tasks can start. Create tasks on a board, review any proposals, and move at least one task to Ready."

  defp autopilot_error(:roles_not_configured),
    do:
      "Assign saved agents to every required project role, save, and apply the roles to each board with Ready tasks."

  defp autopilot_error(%Ecto.Changeset{} = changeset),
    do: PublicError.changeset("Project could not start", changeset)

  defp autopilot_error(_reason),
    do:
      "Project could not start. Check the repository, agent sign-in, and Ready tasks, then retry."

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
