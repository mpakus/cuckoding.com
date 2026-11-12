defmodule BossWeb.AgentsLive do
  use BossWeb, :live_view
  alias Boss.Agents.{Authorizer, Detections, Metadata, ModelDiscovery, Roles}

  @agents [
    %{
      id: :codex,
      name: "Codex",
      docs: "https://developers.openai.com/codex/cli",
      login: "codex login"
    },
    %{
      id: :claude,
      name: "Claude Code",
      docs: "https://code.claude.com/docs/en/setup",
      login: "claude auth login"
    },
    %{
      id: :cursor,
      name: "Cursor Agent",
      docs: "https://cursor.com/docs/cli/overview",
      login: "agent login"
    },
    %{
      id: :hermes,
      name: "Hermes",
      docs: "https://hermes-agent.nousresearch.com/docs/getting-started/installation",
      login: "hermes auth add"
    },
    %{
      id: :pi,
      name: "Pi",
      docs: "https://pi.dev/docs/latest/quickstart",
      login: "pi auth login"
    },
    %{
      id: :opencode,
      name: "OpenCode",
      docs: "https://opencode.ai/docs/cli/",
      login: "opencode auth login"
    }
  ]
  @capabilities [
    headless: "Headless mode",
    streaming: "Streaming output",
    session_resume: "Session resume",
    structured_output: "Structured output",
    approval_support: "Approval controls",
    usage_reporting: "Usage reporting"
  ]

  @impl true
  def mount(_params, _session, socket) do
    saved = Detections.load_state()

    {:ok,
     assign(socket,
       page_title: "Agents · BOSS",
       agents: @agents,
       roles: Roles.list(),
       role_name: "",
       role_error: nil,
       results: saved.results,
       detecting: false,
       checked_at: saved.checked_at,
       agent_busy: %{},
       agent_notices: %{},
       error: nil
     )}
  end

  @impl true
  def handle_event("detect", _, %{assigns: %{detecting: true}} = socket), do: {:noreply, socket}

  def handle_event("create_role", %{"name" => name}, socket) do
    case Roles.create(name) do
      {:ok, _} ->
        {:noreply, assign(socket, roles: Roles.list(), role_name: "", role_error: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, role_name: name || "", role_error: role_error(changeset))}
    end
  end

  def handle_event("update_role", %{"role_id" => id, "name" => name}, socket) do
    case Roles.update(id, name) do
      {:ok, _} ->
        {:noreply, assign(socket, roles: Roles.list(), role_error: nil)}

      {:error, :not_found} ->
        {:noreply,
         assign(socket, roles: Roles.list(), role_error: "That role is no longer available.")}

      {:error, :standard} ->
        {:noreply, assign(socket, role_error: standard_message())}

      {:error, changeset} ->
        {:noreply, assign(socket, role_error: role_error(changeset))}
    end
  end

  def handle_event("delete_role", %{"role_id" => id}, socket) do
    case Roles.delete(id) do
      {:ok, _} ->
        {:noreply, assign(socket, roles: Roles.list(), role_error: nil)}

      {:error, :standard} ->
        {:noreply, assign(socket, role_error: standard_message())}

      {:error, :not_found} ->
        {:noreply, assign(socket, roles: Roles.list(), role_error: nil)}
    end
  end

  def handle_event("assign_role", %{"role_id" => id} = params, socket) do
    agents =
      case params["agents"] do
        list when is_list(list) -> list
        _ -> []
      end

    models = if is_map(params["models"]), do: params["models"], else: %{}
    efforts = if is_map(params["efforts"]), do: params["efforts"], else: %{}

    selections =
      Map.new(agents, fn agent_id ->
        {agent_id,
         %{
           "model_id" => Map.get(models, agent_id),
           "reasoning_effort" => Map.get(efforts, agent_id)
         }}
      end)

    case Roles.assign(id, agents, selections) do
      {:ok, _} ->
        {:noreply, assign(socket, roles: Roles.list(), role_error: nil)}

      {:error, :not_found} ->
        {:noreply,
         assign(socket, roles: Roles.list(), role_error: "That role is no longer available.")}

      {:error, :agent_not_authorized} ->
        {:noreply,
         assign(socket,
           roles: Roles.list(),
           role_error: "Roles connect only to detected and authorized agents."
         )}

      {:error, :model_not_supported} ->
        {:noreply,
         assign(socket,
           roles: Roles.list(),
           role_error: "Choose a supported model fetched for that authorized agent."
         )}

      {:error, :invalid_reasoning_effort} ->
        {:noreply,
         assign(socket,
           roles: Roles.list(),
           role_error: "Choose a reasoning effort supported by the selected model."
         )}

      {:error, :unknown_agent} ->
        {:noreply, assign(socket, role_error: "Choose an agent from the installed list.")}
    end
  end

  def handle_event("detect", _, socket) do
    detector = Application.get_env(:boss, :agent_detector, Boss.Agents.Detector)
    discovery = Application.get_env(:boss, :agent_model_discovery, ModelDiscovery)

    {:noreply,
     socket
     |> assign(detecting: true, error: nil)
     |> start_async(:detect, fn -> run_full_scan(detector, discovery) end)}
  end

  def handle_event("authorize_agent", %{"agent" => raw_id} = params, socket) do
    with {:ok, id} <- parse_agent_id(raw_id),
         false <- Map.has_key?(socket.assigns.agent_busy, id) do
      mode = if params["mode"] == "terminal", do: :terminal, else: :auto
      authorizer = Application.get_env(:boss, :agent_authorizer, Authorizer)

      {:noreply,
       socket
       |> put_agent_busy(id, :authorizing)
       |> put_agent_notice(id, nil)
       |> start_async({:agent_action, id}, fn -> {:authorize, authorizer.authorize(id, mode)} end)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("verify_agent", %{"agent" => raw_id}, socket) do
    with {:ok, id} <- parse_agent_id(raw_id),
         false <- Map.has_key?(socket.assigns.agent_busy, id) do
      authorizer = Application.get_env(:boss, :agent_authorizer, Authorizer)

      {:noreply,
       socket
       |> put_agent_busy(id, :verifying)
       |> put_agent_notice(id, nil)
       |> start_async({:agent_action, id}, fn -> {:verify, authorizer.verify_and_fetch(id)} end)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("fetch_models", %{"agent" => raw_id}, socket) do
    with {:ok, id} <- parse_agent_id(raw_id),
         false <- Map.has_key?(socket.assigns.agent_busy, id) do
      authorizer = Application.get_env(:boss, :agent_authorizer, Authorizer)

      {:noreply,
       socket
       |> put_agent_busy(id, :fetching_models)
       |> put_agent_notice(id, nil)
       |> start_async({:agent_action, id}, fn -> {:models, authorizer.fetch_models(id)} end)}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:detect, {:ok, {:ok, state}}, socket) do
    {:noreply,
     assign(socket,
       results: state.results,
       roles: Roles.list(),
       detecting: false,
       checked_at: state.checked_at,
       error: nil
     )}
  end

  def handle_async(:detect, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, detecting: false, error: scan_error(reason))}

  def handle_async(:detect, _failure, socket),
    do: {:noreply, assign(socket, detecting: false, error: scan_error(:cancelled))}

  def handle_async({:agent_action, id}, {:ok, outcome}, socket) do
    socket = clear_agent_busy(socket, id)
    saved = Detections.load_state()

    socket =
      socket
      |> assign(
        results: Map.merge(socket.assigns.results, saved.results),
        checked_at: saved.checked_at || socket.assigns.checked_at,
        roles: Roles.list()
      )

    socket =
      case outcome do
        {:authorize, {:ok, :terminal_opened}} ->
          put_agent_notice(
            socket,
            id,
            "Opened login in macOS Terminal. Complete sign-in there, then choose Verify & fetch models."
          )

        {:authorize, {:ok, %{auth_status: :configured} = view}} ->
          socket
          |> put_agent_result(id, view)
          |> put_agent_notice(
            id,
            "Authorization verified (#{length(view.models || [])} supported models loaded)."
          )

        {:authorize, {:ok, view}} ->
          socket
          |> put_agent_result(id, view)
          |> put_agent_notice(
            id,
            "Sign-in is still unconfirmed. Complete login in your browser or Terminal, then Verify."
          )

        {:authorize, {:error, :not_installed}} ->
          put_agent_notice(socket, id, "CLI executable was not found on PATH.")

        {:authorize, {:error, _}} ->
          put_agent_notice(
            socket,
            id,
            "Could not launch interactive login automatically. Run the login command in your terminal, then Verify."
          )

        {:verify, {:ok, %{auth_status: :configured} = view}} ->
          socket
          |> put_agent_result(id, view)
          |> put_agent_notice(
            id,
            "Authorized · #{length(view.models || [])} supported models fetched."
          )

        {:verify, {:ok, %{auth_status: :stale} = view}} ->
          socket
          |> put_agent_result(id, view)
          |> put_agent_notice(
            id,
            "Session token is expired or rejected by the CLI. Authorize again to fetch models."
          )

        {:verify, {:ok, view}} ->
          socket
          |> put_agent_result(id, view)
          |> put_agent_notice(id, "CLI does not report active authorization yet.")

        {:verify, {:error, reason}} ->
          put_agent_notice(socket, id, scan_error(reason))

        {:models, {:ok, view}} ->
          socket
          |> put_agent_result(id, view)
          |> put_agent_notice(id, "Loaded #{length(view.models || [])} supported models.")

        {:models, {:error, {:auth_required, view}}} ->
          socket
          |> put_agent_result(id, view)
          |> put_agent_notice(
            id,
            "CLI rejected authentication while listing models. Authorize again."
          )

        {:models, {:error, :not_authorized}} ->
          put_agent_notice(socket, id, "Authorize this agent before fetching models.")

        {:models, {:error, _}} ->
          put_agent_notice(socket, id, "Model list could not be fetched from the CLI.")
      end

    {:noreply, socket}
  end

  def handle_async({:agent_action, id}, _failure, socket) do
    {:noreply,
     socket
     |> clear_agent_busy(id)
     |> put_agent_notice(id, "Action was interrupted. Try again.")}
  end

  defp run_full_scan(detector, discovery) do
    checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, rows} <- detector.scan() do
      saved = Detections.save_scan(rows, checked_at)

      updated_results =
        Enum.reduce(rows, saved.results, fn row, acc ->
          if row.probe_status == :ok and row.auth_status == :configured do
            case discovery.fetch(row.id, row.path) do
              {:ok, models} ->
                view =
                  Detections.save_models(row.id, models, checked_at) ||
                    Map.put(Map.get(acc, row.id, row), :models, models)

                Map.put(acc, row.id, view)

              {:error, :auth_required} ->
                view =
                  Detections.mark_auth_status(row.id, :stale) ||
                    %{Map.get(acc, row.id, row) | auth_status: :stale, models: []}

                Map.put(acc, row.id, view)

              _ ->
                acc
            end
          else
            acc
          end
        end)

      {:ok, %{results: updated_results, checked_at: checked_at}}
    end
  end

  defp parse_agent_id(raw) when is_binary(raw) do
    case Enum.find(Metadata.ids(), &(Atom.to_string(&1) == raw)) do
      nil -> :error
      id -> {:ok, id}
    end
  end

  defp parse_agent_id(_), do: :error

  defp put_agent_busy(socket, id, kind),
    do: assign(socket, agent_busy: Map.put(socket.assigns.agent_busy, id, kind))

  defp clear_agent_busy(socket, id),
    do: assign(socket, agent_busy: Map.delete(socket.assigns.agent_busy, id))

  defp put_agent_notice(socket, id, nil),
    do: assign(socket, agent_notices: Map.delete(socket.assigns.agent_notices, id))

  defp put_agent_notice(socket, id, text),
    do: assign(socket, agent_notices: Map.put(socket.assigns.agent_notices, id, text))

  defp put_agent_result(socket, id, view),
    do: assign(socket, results: Map.put(socket.assigns.results, id, view))

  @impl true
  def render(assigns) do
    authorized_agents =
      Enum.filter(assigns.agents, fn agent ->
        case assigns.results[agent.id] do
          %{probe_status: :ok, auth_status: :configured} -> true
          _ -> false
        end
      end)

    assigns = assign(assigns, :authorized_agents, authorized_agents)

    ~H"""
    <header class="app-page-header flex flex-col items-start gap-5 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <p class="app-eyebrow">Local tools</p>
        <h1 class="app-page-title">Agents</h1>
        <p class="app-page-description">
          Detect local CLIs, authorize accounts, inspect supported models with pricing and reasoning, and wire roles.
        </p>
      </div>
      <button
        id="detect-agents"
        type="button"
        phx-click="detect"
        disabled={@detecting}
        aria-describedby="agents-help"
        class="app-button-primary shrink-0 px-5 py-3 font-semibold disabled:opacity-50"
      >{if @detecting, do: "Detecting…", else: "Detect agents"}</button>
    </header>

    <div class="mt-6 border-y border-line py-5">
      <p id="agents-help" class="max-w-3xl text-sm leading-6 text-body">
        Detect checks the CLIs installed on this computer, saves the detection state locally, and
        fetches supported models for authorized agents. Detection makes no paid inference call and
        does not verify provider access or remaining quota; BOSS does not read credential files.
      </p>
      <p id="agents-status" role="status" class="mt-3 min-h-5 text-sm font-medium text-ink">
        <%= cond do %>
          <% @detecting -> %>
            Detecting agents and refreshing authorized model catalogs…
          <% @checked_at && is_nil(@error) -> %>
            Detection complete · {length(@authorized_agents)} of {length(@agents)} agents authorized.
          <% true -> %>
            Choose Detect agents to check installed CLIs.
        <% end %>
      </p>
      <p :if={@checked_at} class="mt-2 text-sm text-muted">
        Saved scan:
        <time id="agents-checked-at" datetime={DateTime.to_iso8601(@checked_at)}>
          {Calendar.strftime(@checked_at, "%Y-%m-%d %H:%M:%S UTC")}
        </time>
      </p>
    </div>

    <div
      :if={@error}
      id="agents-error"
      role="alert"
      class="mt-4 rounded-sm border border-warning-line bg-warning-soft px-4 py-3 text-sm text-warning"
    >
      <p>Latest scan failed. {@error}</p>
      <p :if={@checked_at} class="mt-1">Showing the last completed scan.</p>
    </div>

    <div
      id="agents"
      aria-busy={@detecting}
      class="mt-6 grid min-w-0 gap-6 md:grid-cols-2"
    >
      <.agent
        :for={agent <- @agents}
        agent={agent}
        result={@results[agent.id]}
        busy={@agent_busy[agent.id]}
        notice={@agent_notices[agent.id]}
      />
    </div>

    <section id="roles" aria-labelledby="roles-title" class="mt-10 border-t border-line pt-8">
      <h2 id="roles-title" class="app-panel-heading">Roles</h2>
      <p id="roles-help" class="mt-2 max-w-3xl text-sm leading-6 text-body">
        Reviewer, Implementer, and Analytic are permanent standard roles. Roles can connect <strong>only to detected and authorized agents and their supported models</strong>.
      </p>
      <form id="create-role" phx-submit="create_role" class="mt-4 flex flex-wrap items-end gap-3">
        <div class="min-w-0 flex-1">
          <label for="role-name" class="block text-sm font-medium">New role</label>
          <input
            id="role-name"
            name="name"
            value={@role_name}
            required
            maxlength="80"
            autocomplete="off"
            class="app-field mt-1 w-full min-w-0 px-3 py-2 text-sm"
          />
        </div>
        <button type="submit" class="app-button-secondary px-4 py-2 text-sm font-semibold">
          Create role
        </button>
      </form>
      <p :if={@role_error} id="role-error" role="alert" class="mt-3 text-sm text-warning">
        {@role_error}
      </p>
      <div class="mt-4 grid min-w-0 gap-4">
        <article :for={role <- @roles} id={"role-#{role.id}"} class="app-panel">
          <div :if={role.standard}>
            <h3 id={"role-#{role.id}-title"} class="text-base font-semibold">{role.name}</h3>
            <p id={"role-#{role.id}-purpose"} class="mt-1 text-sm leading-6 text-body">
              {role.purpose}
            </p>
          </div>
          <form
            :if={!role.standard}
            id={"role-#{role.id}-name"}
            phx-submit="update_role"
            class="flex flex-wrap items-end gap-3"
          >
            <input type="hidden" name="role_id" value={role.id} />
            <div class="min-w-0 flex-1">
              <label for={"role-#{role.id}-name-input"} class="block text-sm font-medium">
                Role name
              </label>
              <input
                id={"role-#{role.id}-name-input"}
                name="name"
                value={role.name}
                required
                maxlength="80"
                autocomplete="off"
                class="app-field mt-1 w-full min-w-0 px-3 py-2 text-sm"
              />
            </div>
            <button type="submit" class="app-button-secondary px-4 py-2 text-sm font-semibold">
              Save name
            </button>
            <button
              type="button"
              id={"role-#{role.id}-delete"}
              phx-click="delete_role"
              phx-value-role_id={role.id}
              class="app-button-danger px-4 py-2 text-sm font-semibold"
            >
              Remove role
            </button>
          </form>

          <form id={"role-#{role.id}-agents"} phx-change="assign_role" class="mt-4">
            <input type="hidden" name="role_id" value={role.id} />
            <fieldset>
              <legend class="text-sm font-medium">
                Detected &amp; authorized agent models in this role
              </legend>

              <p
                :if={@authorized_agents == []}
                id={"role-#{role.id}-empty-authorized"}
                class="mt-2 rounded-sm border border-dashed border-line bg-paper px-3 py-2.5 text-xs text-muted"
              >
                No detected and authorized agents yet. Detect and authorize an agent above to connect its models to this role.
              </p>

              <div :if={@authorized_agents != []} class="mt-3 space-y-2.5">
                <div
                  :for={agent <- @authorized_agents}
                  class="rounded-sm border border-line bg-paper p-3 text-sm"
                >
                  <% id_str = Atom.to_string(agent.id) %>
                  <% checked? = id_str in role.agent_ids %>
                  <% sel =
                    Map.get(role.selections || %{}, id_str, %{model_id: nil, reasoning_effort: nil}) %>
                  <% models = (@results[agent.id] && @results[agent.id].models) || [] %>
                  <% efforts = efforts_for_selection(models, sel.model_id) %>

                  <div class="flex flex-wrap items-center justify-between gap-3">
                    <label class="flex items-center gap-2 font-medium text-ink">
                      <input
                        id={"role-#{role.id}-agent-#{agent.id}"}
                        type="checkbox"
                        name="agents[]"
                        value={agent.id}
                        checked={checked?}
                      />
                      <span>{agent.name}</span>
                      <span class="app-badge">Authorized</span>
                    </label>
                    <span class="font-mono text-xs text-muted">
                      {length(models)} {if length(models) == 1, do: "model", else: "models"}
                    </span>
                  </div>

                  <div
                    :if={checked?}
                    class="mt-3 grid gap-3 border-t border-line pt-3 sm:grid-cols-2"
                  >
                    <div class="min-w-0">
                      <label
                        for={"role-#{role.id}-model-#{agent.id}"}
                        class="block text-xs font-medium text-muted"
                      >
                        Model
                      </label>
                      <select
                        id={"role-#{role.id}-model-#{agent.id}"}
                        name={"models[#{agent.id}]"}
                        class="app-field mt-1 w-full min-w-0 px-2.5 py-1.5 text-xs"
                      >
                        <option value="__default__" selected={is_nil(sel.model_id)}>
                          {if agent.id == :cursor,
                            do: "Agent default (Auto)",
                            else: "Agent default / policy routing"}
                        </option>
                        <option
                          :for={m <- models}
                          value={m["id"]}
                          selected={sel.model_id == m["id"]}
                        >
                          {model_option_label(m)}
                        </option>
                      </select>
                    </div>
                    <div class="min-w-0">
                      <label
                        for={"role-#{role.id}-effort-#{agent.id}"}
                        class="block text-xs font-medium text-muted"
                      >
                        Reasoning effort
                      </label>
                      <select
                        id={"role-#{role.id}-effort-#{agent.id}"}
                        name={"efforts[#{agent.id}]"}
                        disabled={efforts == []}
                        class="app-field mt-1 w-full min-w-0 px-2.5 py-1.5 text-xs disabled:opacity-50"
                      >
                        <option value="default" selected={is_nil(sel.reasoning_effort)}>
                          {if efforts == [], do: "Standard (no effort levels)", else: "Model default"}
                        </option>
                        <option
                          :for={eff <- efforts}
                          value={eff}
                          selected={sel.reasoning_effort == eff}
                        >
                          {eff}
                        </option>
                      </select>
                    </div>
                  </div>
                </div>
              </div>

              <% inactive_ids =
                role.agent_ids -- Enum.map(@authorized_agents, &Atom.to_string(&1.id)) %>
              <p
                :if={inactive_ids != []}
                id={"role-#{role.id}-inactive-warning"}
                class="mt-3 text-xs text-warning"
              >
                Previously saved ({Enum.join(inactive_ids, ", ")}) is not currently detected &amp; authorized and will be skipped until authorized above.
              </p>
            </fieldset>
          </form>
        </article>
      </div>
    </section>
    """
  end

  attr :agent, :map, required: true
  attr :result, :any, required: true
  attr :busy, :any, default: nil
  attr :notice, :any, default: nil

  defp agent(assigns) do
    models = (assigns.result && Map.get(assigns.result, :models)) || []
    detected? = match?(%{probe_status: :ok}, assigns.result)
    authorized? = match?(%{probe_status: :ok, auth_status: :configured}, assigns.result)

    assigns =
      assign(assigns,
        capabilities: @capabilities,
        models: models,
        detected?: detected?,
        authorized?: authorized?
      )

    ~H"""
    <section
      id={"agent-#{@agent.id}"}
      aria-labelledby={"agent-title-#{@agent.id}"}
      class="app-panel flex min-w-0 flex-col"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h2 id={"agent-title-#{@agent.id}"} class="app-panel-heading">{@agent.name}</h2>
        <div class="flex flex-wrap items-center gap-1.5">
          <span
            :if={@detected?}
            class={[
              "inline-flex items-center rounded-[2px] px-2 py-1 text-[11px] font-semibold leading-tight",
              if(@authorized?,
                do: "bg-sage text-forest",
                else: "border border-warning-line bg-warning-soft text-warning"
              )
            ]}
          >
            {if @authorized?, do: "Authorized", else: "Authorization needed"}
          </span>
          <p class="app-badge">
            {if @result, do: probe_status(@result.probe_status), else: "Not checked"}
          </p>
        </div>
      </div>

      <div :if={@result} class="mt-4 space-y-4 text-sm">
        <dl class="space-y-3">
          <div>
            <dt class="text-muted">Version</dt>
            <dd class="mt-1 font-mono">{@result.version || "Not reported"}</dd>
          </div>
          <div>
            <dt class="text-muted">Executable</dt>
            <dd class="mt-1 break-all font-mono">{@result.path || "Not found on PATH"}</dd>
          </div>
          <div>
            <dt class="text-muted">Local sign-in report</dt>
            <dd class="mt-1">{auth_status(@result.auth_status)}</dd>
          </div>
        </dl>

        <div
          :if={@detected? && !@authorized?}
          id={"agent-auth-box-#{@agent.id}"}
          class="space-y-2.5 rounded-sm border border-warning-line bg-warning-soft/60 p-3"
        >
          <p class="text-xs font-medium text-warning">
            Authorize {@agent.name} to load its supported models and enable connecting it to roles.
          </p>
          <div class="flex flex-wrap gap-2">
            <button
              id={"authorize-#{@agent.id}"}
              type="button"
              phx-click="authorize_agent"
              phx-value-agent={@agent.id}
              phx-value-mode="auto"
              disabled={@busy != nil}
              class="app-button-primary px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
            >
              {if @busy == :authorizing, do: "Authorizing…", else: "Authorize #{@agent.name}"}
            </button>
            <button
              id={"terminal-auth-#{@agent.id}"}
              type="button"
              phx-click="authorize_agent"
              phx-value-agent={@agent.id}
              phx-value-mode="terminal"
              disabled={@busy != nil}
              class="app-button-secondary px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
            >
              Open login in Terminal
            </button>
            <button
              id={"verify-auth-#{@agent.id}"}
              type="button"
              phx-click="verify_agent"
              phx-value-agent={@agent.id}
              disabled={@busy != nil}
              class="app-button-secondary px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
            >
              {if @busy == :verifying, do: "Verifying…", else: "Verify & fetch models"}
            </button>
          </div>
        </div>

        <div
          :if={@authorized?}
          id={"agent-models-#{@agent.id}"}
          class="space-y-2.5 rounded-sm border border-line bg-paper p-3"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h3 class="text-xs font-semibold uppercase tracking-wider text-ink">
              Supported models ({length(@models)})
            </h3>
            <div class="flex flex-wrap gap-2">
              <button
                id={"fetch-models-#{@agent.id}"}
                type="button"
                phx-click="fetch_models"
                phx-value-agent={@agent.id}
                disabled={@busy != nil}
                class="app-button-secondary min-h-8 px-2.5 py-1 text-xs disabled:opacity-50"
              >
                {if @busy == :fetching_models, do: "Fetching…", else: "Refresh models"}
              </button>
              <button
                id={"authorize-#{@agent.id}"}
                type="button"
                phx-click="authorize_agent"
                phx-value-agent={@agent.id}
                phx-value-mode="auto"
                disabled={@busy != nil}
                class="app-button-secondary min-h-8 px-2.5 py-1 text-xs disabled:opacity-50"
              >
                {if @busy == :authorizing, do: "Authorizing…", else: "Re-authorize"}
              </button>
            </div>
          </div>

          <p :if={@models == []} class="text-xs text-muted">
            No model list reported yet. Choose Refresh models to query this CLI.
          </p>

          <div :if={@models != []} class="max-h-60 space-y-2 overflow-y-auto pr-1">
            <div
              :for={m <- @models}
              data-model-id={m["id"]}
              class="rounded-sm border border-line bg-surface px-2.5 py-2 text-xs"
            >
              <div class="flex flex-wrap items-baseline justify-between gap-2">
                <span class="font-semibold text-ink">{m["name"] || m["id"]}</span>
                <code class="break-all font-mono text-[11px] text-muted">{m["id"]}</code>
              </div>
              <div class="mt-1.5 flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-body">
                <span>
                  <strong class="font-medium text-muted">Pricing:</strong>
                  {format_pricing(m["pricing"])}
                </span>
                <span>
                  <strong class="font-medium text-muted">Reasoning:</strong>
                  {format_reasoning(m)}
                </span>
                <span :if={is_integer(m["context_window"])}>
                  <strong class="font-medium text-muted">Context:</strong>
                  {format_context(m["context_window"])}
                </span>
              </div>
            </div>
          </div>
        </div>

        <p :if={@notice} id={"agent-notice-#{@agent.id}"} role="status" class="text-xs text-body">
          {@notice}
        </p>

        <details class="border-t border-line pt-3">
          <summary class="cursor-pointer font-semibold focus-visible:outline-2 focus-visible:outline-forest">
            Capabilities advertised by CLI help
          </summary>
          <dl class="mt-3 space-y-2">
            <div
              :for={{key, label} <- @capabilities}
              data-capability={key}
              class="flex flex-wrap justify-between gap-2"
            >
              <dt class="text-muted">{label}</dt>
              <dd>{capability_status(@result.capabilities[key])}</dd>
            </div>
          </dl>
        </details>

        <ul
          :if={@result.errors != []}
          aria-label={"#{@agent.name} detection issues"}
          class="space-y-1 text-warning"
        >
          <li :for={error <- @result.errors}>{probe_error(error)}</li>
        </ul>
      </div>

      <div class="mt-6 space-y-3 border-t border-line pt-4 text-sm text-body">
        <.link
          href={@agent.docs}
          class="text-forest underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-forest"
        >
          Official {@agent.name} installation and setup
        </.link>
        <p>
          CLI sign-in command:
          <code class="break-all rounded bg-surface px-1 py-0.5 text-ink">{@agent.login}</code>
        </p>
      </div>
    </section>
    """
  end

  defp efforts_for_selection(models, nil) do
    models
    |> Enum.flat_map(&(&1["reasoning_efforts"] || []))
    |> Enum.uniq()
  end

  defp efforts_for_selection(models, model_id) do
    case Enum.find(models, &(&1["id"] == model_id)) do
      %{"reasoning_efforts" => list} when is_list(list) -> list
      _ -> []
    end
  end

  defp model_option_label(m) do
    name = m["name"] || m["id"]
    price = short_pricing(m["pricing"])
    reasoning = if m["reasoning"], do: "reasoning", else: "standard"
    "#{name} (#{reasoning} · #{price})"
  end

  defp short_pricing(%{"input" => inp, "output" => outp})
       when is_number(inp) and is_number(outp) and inp == 0 and outp == 0,
       do: "free"

  defp short_pricing(%{"input" => inp, "output" => outp})
       when is_number(inp) and is_number(outp) do
    "$#{fmt_usd(inp)}/$#{fmt_usd(outp)} per 1M"
  end

  defp short_pricing(%{"unit" => unit}) when is_binary(unit), do: unit
  defp short_pricing(_), do: "plan / API"

  defp format_pricing(%{"input" => inp, "output" => outp} = p)
       when is_number(inp) and is_number(outp) do
    if inp == 0 and outp == 0 do
      "Free ($0.00 / 1M tokens)"
    else
      cached =
        case p["cached_input"] do
          c when is_number(c) and c > 0 -> " · $#{fmt_usd(c)} cached"
          _ -> ""
        end

      "$#{fmt_usd(inp)} in · $#{fmt_usd(outp)} out#{cached} / 1M"
    end
  end

  defp format_pricing(%{"unit" => unit}) when is_binary(unit), do: unit
  defp format_pricing(_), do: "Subscription / usage-billed"

  defp fmt_usd(num) when is_number(num) do
    rounded = Float.round(num * 1.0, 3)

    cond do
      rounded == Float.round(rounded, 0) -> :erlang.float_to_binary(rounded, decimals: 2)
      rounded == Float.round(rounded, 2) -> :erlang.float_to_binary(rounded, decimals: 2)
      true -> :erlang.float_to_binary(rounded, decimals: 3)
    end
  end

  defp format_reasoning(%{"reasoning" => true, "reasoning_efforts" => efforts})
       when is_list(efforts) and efforts != [] do
    Enum.join(efforts, " · ")
  end

  defp format_reasoning(%{"reasoning" => true}), do: "Supported"
  defp format_reasoning(_), do: "Standard"

  defp format_context(ctx) when is_integer(ctx) and ctx >= 1_000_000 do
    "#{Float.round(ctx / 1_000_000, 1)}M"
  end

  defp format_context(ctx) when is_integer(ctx) and ctx >= 1_000 do
    "#{div(ctx, 1_000)}k"
  end

  defp format_context(ctx), do: to_string(ctx)

  defp probe_status(:ok), do: "CLI metadata recognized"
  defp probe_status(:missing), do: "Not found on PATH"
  defp probe_status(:unsupported), do: "CLI metadata unsupported"
  defp probe_status(_), do: "Detection incomplete"

  defp auth_status(:configured), do: "CLI reports credentials configured"

  defp auth_status(:stale),
    do: "CLI reports expired or unverified session — re-run login in your terminal"

  defp auth_status(:not_configured), do: "CLI reports no credentials configured"
  defp auth_status(_), do: "Unknown"

  defp capability_status(:advertised), do: "Advertised"
  defp capability_status(:not_advertised), do: "Not advertised"
  defp capability_status(_), do: "Unknown"

  defp probe_error(error) do
    stage = %{version: "Version", help: "Help", auth: "Sign-in"}[error.stage] || "CLI"

    reason =
      %{
        timeout: "timed out",
        output_limit: "exceeded its output limit",
        unrecognized: "returned unrecognized output",
        unsupported: "is not supported"
      }[error.reason] || "could not finish"

    "#{stage} check #{reason}."
  end

  defp standard_message, do: "Reviewer, Implementer, and Analytic stay in place."

  defp role_error(%Ecto.Changeset{} = changeset) do
    options = changeset.errors |> Keyword.get_values(:name) |> Enum.map(&elem(&1, 1))

    cond do
      Enum.any?(options, &(&1[:validation] == :required)) -> "Enter a role name."
      Enum.any?(options, &(&1[:constraint] == :unique)) -> "A role with that name already exists."
      Enum.any?(options, &(&1[:validation] == :length)) -> "Use 80 characters or fewer."
      true -> "The role could not be saved."
    end
  end

  defp scan_error(:busy), do: "Another detection is running. Try Detect agents again shortly."
  defp scan_error(:cancelled), do: "Detection was interrupted. Try again."
  defp scan_error(_), do: "Agent detection is unavailable. Try again."
end
