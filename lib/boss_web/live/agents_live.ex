defmodule BossWeb.AgentsLive do
  use BossWeb, :live_view
  alias Boss.Agents.{Authorizer, Detections, Metadata, ModelDiscovery, Roles}

  @agents [
    %{
      id: :codex,
      name: "Codex",
      docs: "https://developers.openai.com/codex/cli",
      login: "codex login",
      billing_hint: "ChatGPT Plus/Pro Subscription or OpenAI API"
    },
    %{
      id: :claude,
      name: "Claude Code",
      docs: "https://code.claude.com/docs/en/setup",
      login: "claude auth login",
      billing_hint: "Claude Max/Pro Subscription or Anthropic API"
    },
    %{
      id: :cursor,
      name: "Cursor Agent",
      docs: "https://cursor.com/docs/cli/overview",
      login: "agent login",
      billing_hint: "Cursor Pro/Business Subscription or Usage API"
    },
    %{
      id: :opencode,
      name: "OpenCode",
      docs: "https://opencode.ai/docs/cli/",
      login: "opencode auth login",
      billing_hint: "Included Free Tier or Provider API"
    },
    %{
      id: :hermes,
      name: "Hermes",
      docs: "https://hermes-agent.nousresearch.com/docs/getting-started/installation",
      login: "hermes model",
      billing_hint: "Provider API"
    },
    %{
      id: :pi,
      name: "Pi",
      docs: "https://pi.dev/docs/latest/quickstart",
      login: "pi, then /login",
      billing_hint: "Provider API"
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

  @role_order %{"analytic" => 0, "implementer" => 1, "reviewer" => 2}

  @impl true
  def mount(_params, _session, socket) do
    saved = Detections.load_state()
    roles = ordered_standard_roles()
    has_authorized? = Enum.any?(saved.results, fn {_, r} -> authorized?(r) end)

    {:ok,
     socket
     |> assign(
       page_title: "Agents & Roles · BOSS",
       agents: @agents,
       roles: roles,
       role_error: nil,
       saved_role: nil,
       results: saved.results,
       detecting: false,
       checked_at: saved.checked_at,
       agent_busy: %{},
       agent_notices: %{},
       connect_open: not has_authorized?,
       connect_agent: default_connect_agent(saved.results),
       expanded_models: MapSet.new(),
       binding_drafts: init_binding_drafts(roles, saved.results),
       error: nil
     )}
  end

  @impl true
  def handle_event("toggle_connect", _, socket) do
    {:noreply, assign(socket, connect_open: not socket.assigns.connect_open)}
  end

  def handle_event("open_connect", %{"agent" => raw_id}, socket) do
    case parse_agent_id(raw_id) do
      {:ok, id} -> {:noreply, assign(socket, connect_open: true, connect_agent: id)}
      :error -> {:noreply, assign(socket, connect_open: true)}
    end
  end

  def handle_event("open_connect", _, socket) do
    {:noreply, assign(socket, connect_open: true)}
  end

  def handle_event("close_connect", _, socket) do
    {:noreply, assign(socket, connect_open: false)}
  end

  def handle_event("select_connect_agent", %{"agent" => raw_id}, socket) do
    case parse_agent_id(raw_id) do
      {:ok, id} -> {:noreply, assign(socket, connect_agent: id, connect_open: true)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("toggle_agent_models", %{"agent" => raw_id}, socket) do
    case parse_agent_id(raw_id) do
      {:ok, id} ->
        set = socket.assigns.expanded_models

        next =
          if MapSet.member?(set, id),
            do: MapSet.delete(set, id),
            else: MapSet.put(set, id)

        {:noreply, assign(socket, expanded_models: next)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "toggle_model",
        %{"agent" => raw_id, "model_id" => model_id} = params,
        socket
      ) do
    enabled? = params["enabled"] == "true"

    with {:ok, id} <- parse_agent_id(raw_id),
         {:ok, updated_view} <- Detections.set_model_enabled(id, model_id, enabled?) do
      results = Map.put(socket.assigns.results, id, updated_view)
      roles = ordered_standard_roles()

      {:noreply,
       assign(socket,
         results: results,
         roles: roles,
         binding_drafts: sync_binding_drafts(socket.assigns.binding_drafts, roles, results)
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(
        "update_role_binding",
        %{"binding_id" => binding_id, "role_kind" => kind} = params,
        socket
      )
      when kind in ~w(analytic implementer reviewer) do
    existing = find_binding_in_roles(socket.assigns.roles, binding_id)
    agent_id = params["agent"] || (existing && existing.agent_id) || ""
    models = Roles.models_for_agent(agent_id)

    agent_changed? =
      params["_target"] == ["agent"] or (existing != nil and agent_id != existing.agent_id)

    next_model =
      cond do
        agent_changed? ->
          case models do
            [first | _] -> first.id
            [] -> nil
          end

        params["model_id"] in ["", "__default__", nil] ->
          nil

        is_binary(params["model_id"]) ->
          params["model_id"]

        existing != nil ->
          existing.model_id

        true ->
          nil
      end

    selected_model = if next_model, do: Enum.find(models, &(&1.id == next_model))
    efforts = if selected_model, do: selected_model.reasoning_efforts, else: []

    model_changed? =
      agent_changed? or params["_target"] == ["model_id"] or
        (existing != nil and next_model != existing.model_id)

    next_effort =
      cond do
        efforts == [] ->
          nil

        model_changed? ->
          if existing && existing.reasoning_effort in efforts do
            existing.reasoning_effort
          else
            selected_model.default_effort
          end

        is_binary(params["reasoning_effort"]) and params["reasoning_effort"] in efforts ->
          params["reasoning_effort"]

        true ->
          nil
      end

    selection = %{
      "model_id" => next_model,
      "reasoning_effort" => next_effort
    }

    apply_role_save_result(
      socket,
      kind,
      Roles.update_binding(binding_id, agent_id, selection)
    )
  end

  def handle_event("auto_create_role_binding", %{"role_kind" => kind} = params, socket)
      when kind in ~w(analytic implementer reviewer) do
    current = Map.get(socket.assigns.binding_drafts, kind, %{})
    agent_id = params["agent"] || current[:agent_id] || ""
    models = Roles.models_for_agent(agent_id)

    agent_changed? = params["_target"] == ["agent"] or agent_id != current[:agent_id]

    next_model =
      cond do
        agent_changed? ->
          case models do
            [first | _] -> first.id
            [] -> nil
          end

        params["model_id"] in ["", "__default__", nil] ->
          if models != [], do: hd(models).id, else: nil

        is_binary(params["model_id"]) and Enum.any?(models, &(&1.id == params["model_id"])) ->
          params["model_id"]

        models != [] ->
          hd(models).id

        true ->
          nil
      end

    selected_model = if next_model, do: Enum.find(models, &(&1.id == next_model))
    efforts = if selected_model, do: selected_model.reasoning_efforts, else: []

    next_effort =
      cond do
        efforts == [] ->
          nil

        agent_changed? or params["_target"] == ["model_id"] ->
          selected_model.default_effort

        is_binary(params["reasoning_effort"]) and params["reasoning_effort"] in efforts ->
          params["reasoning_effort"]

        true ->
          selected_model && selected_model.default_effort
      end

    apply_role_save_result(
      socket,
      kind,
      Roles.add_binding(kind, agent_id, %{
        "model_id" => next_model,
        "reasoning_effort" => next_effort
      })
    )
  end

  def handle_event("add_next_role_binding", %{"role_kind" => kind}, socket)
      when kind in ~w(analytic implementer reviewer) do
    eligible_ids =
      eligible_agents_for_role(kind, socket.assigns.results)
      |> Enum.map(&Atom.to_string(&1.id))

    case Roles.add_next_binding(kind, eligible_ids) do
      {:ok, _} ->
        roles = ordered_standard_roles()

        {:noreply,
         assign(socket,
           roles: roles,
           saved_role: kind,
           role_error: nil,
           binding_drafts:
             sync_binding_drafts(socket.assigns.binding_drafts, roles, socket.assigns.results)
         )}

      {:error, :all_combinations_bound} ->
        {:noreply,
         assign(socket,
           role_error:
             "All enabled Agent + Model combinations are already bound to #{String.capitalize(kind)}."
         )}

      other ->
        apply_role_save_result(socket, kind, other)
    end
  end

  def handle_event("remove_role_binding", %{"binding_id" => id} = params, socket) do
    _ = Roles.remove_binding(id)
    roles = ordered_standard_roles()

    {:noreply,
     assign(socket,
       roles: roles,
       saved_role: params["role_kind"],
       role_error: nil,
       binding_drafts:
         sync_binding_drafts(socket.assigns.binding_drafts, roles, socket.assigns.results)
     )}
  end

  def handle_event("detect", _, %{assigns: assigns} = socket)
      when assigns.detecting or map_size(assigns.agent_busy) > 0,
      do: {:noreply, socket}

  def handle_event("detect", _, socket) do
    detector = Application.get_env(:boss, :agent_detector, Boss.Agents.Detector)
    discovery = Application.get_env(:boss, :agent_model_discovery, ModelDiscovery)

    {:noreply,
     socket
     |> assign(detecting: true, error: nil)
     |> start_async(:detect, fn -> run_full_scan(detector, discovery) end)}
  end

  def handle_event("authorize_agent", %{"agent" => raw_id}, socket) do
    with {:ok, id} <- parse_agent_id(raw_id),
         false <- socket.assigns.detecting or Map.has_key?(socket.assigns.agent_busy, id) do
      authorizer = Application.get_env(:boss, :agent_authorizer, Authorizer)

      {:noreply,
       socket
       |> assign(connect_open: true, connect_agent: id)
       |> put_agent_busy(id, :authorizing)
       |> put_agent_notice(id, nil)
       |> start_async({:agent_action, id}, fn ->
         {:authorize, authorizer.authorize(id, :terminal)}
       end)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("verify_agent", %{"agent" => raw_id}, socket) do
    with {:ok, id} <- parse_agent_id(raw_id),
         false <- socket.assigns.detecting or Map.has_key?(socket.assigns.agent_busy, id) do
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
         false <- socket.assigns.detecting or Map.has_key?(socket.assigns.agent_busy, id) do
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
    latest = Detections.load_state()
    state = if latest.checked_at, do: latest, else: state
    roles = ordered_standard_roles()

    {:noreply,
     assign(socket,
       results: state.results,
       roles: roles,
       binding_drafts: sync_binding_drafts(socket.assigns.binding_drafts, roles, state.results),
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
    merged_results = Map.merge(socket.assigns.results, saved.results)
    roles = ordered_standard_roles()

    socket =
      socket
      |> assign(
        results: merged_results,
        checked_at: saved.checked_at || socket.assigns.checked_at,
        roles: roles,
        binding_drafts: sync_binding_drafts(socket.assigns.binding_drafts, roles, merged_results)
      )

    socket =
      case outcome do
        {:authorize, {:ok, :terminal_opened}} ->
          put_agent_notice(
            socket,
            id,
            "Opened login in macOS Terminal. Complete sign-in there, then choose Verify & fetch models."
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
          notice =
            if Enum.any?(view.errors, &(&1.stage == :models)),
              do: "Sign-in confirmed. The model catalog could not be refreshed.",
              else: "Authorized · #{length(view.models)} models loaded."

          next_results = Map.put(socket.assigns.results, id, view)
          next_roles = ordered_standard_roles()

          socket
          |> assign(
            results: next_results,
            roles: next_roles,
            binding_drafts:
              sync_binding_drafts(socket.assigns.binding_drafts, next_roles, next_results)
          )
          |> put_agent_notice(id, notice)

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
          next_results = Map.put(socket.assigns.results, id, view)

          socket
          |> assign(
            results: next_results,
            roles: ordered_standard_roles(),
            binding_drafts:
              sync_binding_drafts(
                socket.assigns.binding_drafts,
                socket.assigns.roles,
                next_results
              )
          )
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
    started_at = DateTime.utc_now()

    with {:ok, rows} <- detector.scan() do
      rows = Enum.map(rows, &Authorizer.enrich(&1, discovery))
      {:ok, Detections.save_scan(rows, started_at)}
    end
  end

  defp ordered_standard_roles do
    Roles.standard_list()
    |> Enum.sort_by(&Map.get(@role_order, &1.kind, 99))
  end

  defp authorized?(%{probe_status: :ok, auth_status: :configured}), do: true
  defp authorized?(_), do: false

  defp default_connect_agent(results) do
    unconfigured =
      Enum.find(@agents, fn a ->
        case results[a.id] do
          %{probe_status: :ok, auth_status: status} when status != :configured -> true
          _ -> false
        end
      end)

    missing =
      Enum.find(@agents, fn a ->
        not authorized?(results[a.id])
      end)

    cond do
      unconfigured -> unconfigured.id
      missing -> missing.id
      true -> :codex
    end
  end

  defp init_binding_drafts(roles, results) do
    Map.new(roles, fn role ->
      eligible = eligible_agents_for_role(role.kind, results)

      first_agent =
        case eligible do
          [a | _] -> Atom.to_string(a.id)
          [] -> nil
        end

      models = if first_agent, do: Roles.models_for_agent(first_agent), else: []

      first_model =
        case models do
          [m | _] -> m
          [] -> nil
        end

      {role.kind,
       %{
         agent_id: first_agent,
         model_id: if(first_model, do: first_model.id, else: "__default__"),
         reasoning_effort: (first_model && first_model.default_effort) || ""
       }}
    end)
  end

  defp sync_binding_drafts(drafts, roles, results) do
    defaults = init_binding_drafts(roles, results)

    Map.new(roles, fn role ->
      kind = role.kind
      eligible_ids = eligible_agents_for_role(kind, results) |> Enum.map(&Atom.to_string(&1.id))
      current = Map.get(drafts, kind)

      if is_map(current) and current[:agent_id] in eligible_ids do
        models = Roles.models_for_agent(current[:agent_id])
        model_ids = Enum.map(models, & &1.id)

        model_id =
          if current[:model_id] in model_ids or models == [],
            do: current[:model_id] || "__default__",
            else: hd(models).id

        selected = Enum.find(models, &(&1.id == model_id))
        efforts = if selected, do: selected.reasoning_efforts, else: []

        effort =
          if current[:reasoning_effort] in efforts,
            do: current[:reasoning_effort],
            else: (selected && selected.default_effort) || ""

        {kind, %{agent_id: current[:agent_id], model_id: model_id, reasoning_effort: effort}}
      else
        {kind, defaults[kind]}
      end
    end)
  end

  defp eligible_agents_for_role(role_kind, results) do
    Enum.filter(@agents, fn agent ->
      id_str = Atom.to_string(agent.id)
      authorized?(results[agent.id]) and Roles.runner_allowed?(role_kind, id_str)
    end)
  end

  defp find_binding_in_roles(roles, raw_id) do
    id_str = to_string(raw_id)

    Enum.find_value(roles, fn r ->
      Enum.find(r.bindings, &(to_string(&1.id) == id_str))
    end)
  end

  defp apply_role_save_result(socket, kind, {:ok, _}) do
    roles = ordered_standard_roles()

    {:noreply,
     assign(socket,
       roles: roles,
       saved_role: kind,
       role_error: nil,
       binding_drafts:
         sync_binding_drafts(socket.assigns.binding_drafts, roles, socket.assigns.results)
     )}
  end

  defp apply_role_save_result(socket, _kind, {:error, :agent_not_authorized}) do
    {:noreply,
     assign(socket,
       roles: ordered_standard_roles(),
       role_error: "Roles connect only to detected and authorized agents."
     )}
  end

  defp apply_role_save_result(socket, _kind, {:error, :model_not_supported}) do
    {:noreply,
     assign(socket,
       roles: ordered_standard_roles(),
       role_error: "Choose a supported model fetched for that authorized agent."
     )}
  end

  defp apply_role_save_result(socket, _kind, {:error, :invalid_reasoning_effort}) do
    {:noreply,
     assign(socket,
       roles: ordered_standard_roles(),
       role_error: "Choose a reasoning effort supported by the selected model."
     )}
  end

  defp apply_role_save_result(socket, _kind, {:error, _}) do
    {:noreply, assign(socket, role_error: "Could not save this role binding.")}
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
      Enum.filter(assigns.agents, fn agent -> authorized?(assigns.results[agent.id]) end)

    selected_meta =
      Enum.find(assigns.agents, List.first(assigns.agents), &(&1.id == assigns.connect_agent))

    assigns =
      assigns
      |> assign(:authorized_agents, authorized_agents)
      |> assign(:selected_meta, selected_meta)
      |> assign(:selected_result, assigns.results[selected_meta.id])

    ~H"""
    <header class="flex flex-col gap-3 border-b border-line pb-4 sm:flex-row sm:items-center sm:justify-between">
      <div class="min-w-0">
        <p class="app-eyebrow">Local CLI Hub</p>
        <div class="flex flex-wrap items-baseline gap-3">
          <h1 class="text-2xl font-semibold tracking-tight text-ink">Agents &amp; Roles</h1>
          <span id="agents-status" role="status" class="text-xs text-muted">
            <%= cond do %>
              <% @detecting -> %>
                Detecting local CLIs…
              <% @checked_at && is_nil(@error) -> %>
                Detection complete · {length(@authorized_agents)} connected
              <% true -> %>
                {length(@authorized_agents)} connected
            <% end %>
          </span>
          <time
            :if={@checked_at}
            id="agents-checked-at"
            datetime={DateTime.to_iso8601(@checked_at)}
            class="font-mono text-[11px] text-muted"
          >
            {Calendar.strftime(@checked_at, "%H:%M:%S UTC")}
          </time>
        </div>
        <p id="agents-help" class="mt-1 text-xs text-muted">
          Connect authorized local CLIs, choose models with API vs Subscription pricing, and bind them to Analytic, Implementer, and Reviewer. Metadata discovery makes no paid call and does not verify provider access.
        </p>
      </div>
      <div class="flex shrink-0 flex-wrap items-center gap-2">
        <button
          id="detect-agents"
          type="button"
          phx-click="detect"
          disabled={@detecting or map_size(@agent_busy) > 0}
          class="app-button-secondary px-3.5 py-2 text-xs font-semibold disabled:opacity-50"
        >
          {if @detecting, do: "Scanning…", else: "Scan CLIs"}
        </button>
        <button
          id="open-connect-agent"
          type="button"
          phx-click="toggle_connect"
          aria-expanded={to_string(@connect_open)}
          aria-controls="connect-agent-panel"
          class="app-button-primary px-3.5 py-2 text-xs font-semibold"
        >
          {if @connect_open, do: "Hide connect panel", else: "+ Connect agent"}
        </button>
      </div>
    </header>

    <p
      :if={@error}
      id="agents-error"
      role="alert"
      class="mt-3 rounded-sm border border-danger-line bg-danger-soft px-3 py-2 text-xs text-danger"
    >
      {@error}
      <span :if={@checked_at}> Showing the last completed scan.</span>
    </p>

    <div class={[
      "mt-5 grid items-start gap-5",
      @connect_open && "lg:grid-cols-[minmax(0,1fr)_24rem]"
    ]}>
      <div class="min-w-0 space-y-6">
        <section id="connected-agents" aria-labelledby="connected-agents-heading">
          <div class="flex items-center justify-between gap-2">
            <h2
              id="connected-agents-heading"
              class="text-sm font-semibold uppercase tracking-wider text-muted"
            >
              Connected &amp; authorized agents ({length(@authorized_agents)})
            </h2>
            <button
              :if={!@connect_open}
              type="button"
              phx-click="open_connect"
              class="text-xs font-medium text-forest underline underline-offset-4"
            >
              + Connect another agent
            </button>
          </div>

          <div
            :if={@authorized_agents == []}
            id="connected-agents-empty"
            class="mt-3 rounded-sm border border-line bg-surface p-4 text-sm text-muted"
          >
            No local agents are connected and authorized yet. Use <strong>+ Connect agent</strong>
            on the right or <strong>Scan CLIs</strong>
            to detect installed CLIs, sign in, and load models.
          </div>

          <div
            :if={@authorized_agents != []}
            class="mt-3 grid gap-3 sm:grid-cols-2"
          >
            <article
              :for={agent <- @authorized_agents}
              id={"connected-agent-#{agent.id}"}
              class="rounded-sm border border-line bg-surface p-3.5"
            >
              <% res = @results[agent.id] %>
              <% busy = @agent_busy[agent.id] %>
              <% notice = @agent_notices[agent.id] %>
              <% models = Enum.map(res.models || [], &Roles.present_model(agent.id, &1)) %>
              <% enabled_count = Enum.count(models, & &1.enabled) %>
              <% expanded? = MapSet.member?(@expanded_models, agent.id) %>

              <div class="flex flex-wrap items-start justify-between gap-2">
                <div class="min-w-0">
                  <div class="flex flex-wrap items-center gap-2">
                    <h3 class="text-sm font-semibold text-ink">{agent.name}</h3>
                    <span class="rounded-sm border border-forest/30 bg-sage px-1.5 py-0.5 text-[11px] font-medium text-forest">
                      Authorized
                    </span>
                    <span :if={res.version} class="font-mono text-[11px] text-muted">
                      v{res.version}
                    </span>
                  </div>
                  <p class="mt-0.5 truncate font-mono text-[11px] text-muted" title={res.path}>
                    {res.path}
                  </p>
                </div>
                <div class="flex shrink-0 items-center gap-1.5">
                  <button
                    id={"refresh-models-#{agent.id}"}
                    type="button"
                    phx-click="fetch_models"
                    phx-value-agent={agent.id}
                    disabled={@detecting or busy != nil}
                    class="app-button-secondary px-2 py-1 text-[11px] disabled:opacity-50"
                  >
                    {if busy == :fetching_models, do: "Loading…", else: "Refresh"}
                  </button>
                  <button
                    id={"manage-agent-#{agent.id}"}
                    type="button"
                    phx-click="open_connect"
                    phx-value-agent={agent.id}
                    class="app-button-secondary px-2 py-1 text-[11px]"
                  >
                    Auth
                  </button>
                </div>
              </div>

              <div class="mt-2.5 flex flex-wrap items-center justify-between gap-2 border-t border-line pt-2 text-xs">
                <span class="text-body">
                  <strong>{enabled_count}</strong>
                  / {length(models)} models enabled
                  <span class="text-muted">· {agent.billing_hint}</span>
                </span>
                <button
                  :if={models != []}
                  id={"toggle-models-#{agent.id}"}
                  type="button"
                  phx-click="toggle_agent_models"
                  phx-value-agent={agent.id}
                  class="font-medium text-forest underline underline-offset-4"
                >
                  {if expanded?, do: "Compact", else: "Select models"}
                </button>
              </div>

              <p :if={notice} role="status" class="mt-2 text-xs text-forest">
                {notice}
              </p>

              <div
                :if={models != []}
                id={"agent-models-#{agent.id}"}
                class={["mt-2 space-y-1", !expanded? && "max-h-36 overflow-y-auto pr-1"]}
              >
                <label
                  :for={m <- if(expanded?, do: models, else: Enum.take(models, 4))}
                  class="flex cursor-pointer items-center justify-between gap-2 rounded-sm border border-line/70 bg-paper px-2 py-1.5 text-xs hover:border-forest/50"
                >
                  <span class="flex min-w-0 items-center gap-2">
                    <input
                      type="checkbox"
                      checked={m.enabled}
                      phx-click="toggle_model"
                      phx-value-agent={agent.id}
                      phx-value-model_id={m.id}
                      phx-value-enabled={to_string(!m.enabled)}
                      class="h-3.5 w-3.5 accent-forest"
                    />
                    <span
                      title={m.name}
                      class={[
                        "truncate font-medium",
                        m.enabled && "text-ink",
                        !m.enabled && "text-muted line-through"
                      ]}
                    >
                      {m.name}
                    </span>
                    <span
                      :if={m.reasoning_efforts != []}
                      title={"Reasoning efforts: #{Enum.join(m.reasoning_efforts, ", ")}"}
                      class="hidden shrink-0 font-mono text-[10px] text-muted 2xl:inline"
                    >
                      · reasoning
                    </span>
                  </span>
                  <span class="flex shrink-0 items-center gap-1.5">
                    <span class="font-mono text-[11px] text-muted">{m.price_label}</span>
                    <span class={billing_badge_class(m.billing)}>
                      {m.billing_label}
                    </span>
                  </span>
                </label>
                <p :if={!expanded? and length(models) > 4} class="pt-0.5 text-[11px] text-muted">
                  +{length(models) - 4} more models — choose “Select models” to view all
                </p>
              </div>
            </article>
          </div>
        </section>

        <section
          id="agent-roles"
          aria-labelledby="agent-roles-heading"
          class="border-t border-line pt-5"
        >
          <div class="flex flex-wrap items-baseline justify-between gap-2">
            <div>
              <h2
                id="agent-roles-heading"
                class="text-sm font-semibold uppercase tracking-wider text-muted"
              >
                Three workflow roles (Agent + Model + Role bindings)
              </h2>
              <p class="mt-1 text-xs text-muted">
                Bind connected agents and models to <strong>Analytic</strong>, <strong>Implementer</strong>, and <strong>Reviewer</strong>. Projects pick one binding from each role.
              </p>
            </div>
          </div>

          <p
            :if={@role_error}
            id="agent-roles-error"
            role="alert"
            class="mt-3 rounded-sm border border-danger-line bg-danger-soft px-3 py-2 text-xs text-danger"
          >
            {@role_error}
          </p>

          <div class="mt-3 grid gap-4 xl:grid-cols-3">
            <article
              :for={role <- @roles}
              id={"role-#{role.id}"}
              class="flex flex-col justify-between rounded-sm border border-line bg-surface p-4"
            >
              <% eligible = eligible_agents_for_role(role.kind, @results) %>
              <% eligible_ids = Enum.map(eligible, &Atom.to_string(&1.id)) %>

              <div>
                <div class="flex items-center justify-between gap-2">
                  <div class="flex items-center gap-2">
                    <h3 id={"role-#{role.id}-title"} class="text-base font-semibold text-ink">
                      {role.name}
                    </h3>
                    <span
                      :if={@saved_role == role.kind}
                      id={"role-saved-#{role.kind}"}
                      role="status"
                      class="rounded-sm border border-forest/30 bg-sage px-1.5 py-0.5 text-[10px] font-medium text-forest"
                    >
                      Auto-saved
                    </span>
                  </div>
                  <span class="rounded-sm border border-line bg-paper px-2 py-0.5 font-mono text-[11px] text-muted">
                    {length(role.bindings)} bound
                  </span>
                </div>
                <p id={"role-#{role.id}-purpose"} class="mt-1.5 text-xs leading-5 text-body">
                  {role.purpose}
                </p>

                <div class="mt-3 space-y-2">
                  <p
                    :if={role.bindings == [] and eligible == []}
                    id={"role-#{role.id}-empty"}
                    class="rounded-sm border border-dashed border-line bg-paper px-2.5 py-2 text-xs text-muted"
                  >
                    No Agent + Model bound yet.
                  </p>

                  <form
                    :for={binding <- role.bindings}
                    id={"role-binding-#{binding.id}"}
                    phx-change="update_role_binding"
                    class="space-y-2 rounded-sm border border-line bg-paper p-2.5 text-xs"
                  >
                    <input type="hidden" name="binding_id" value={binding.id} />
                    <input type="hidden" name="role_kind" value={role.kind} />

                    <% row_models = Roles.models_for_agent(binding.agent_id) %>
                    <% row_model_ids = Enum.map(row_models, & &1.id) %>
                    <% row_selected_model =
                      if binding.model_id, do: Enum.find(row_models, &(&1.id == binding.model_id)) %>
                    <% row_efforts =
                      if row_selected_model, do: row_selected_model.reasoning_efforts, else: [] %>

                    <div class="flex items-center justify-between gap-2">
                      <div class="flex min-w-0 flex-wrap items-center gap-1.5">
                        <span
                          class="truncate font-mono text-[11px] font-semibold text-forest"
                          title={binding.tag}
                        >
                          {binding.tag}
                        </span>
                        <span class="font-mono text-[10px] text-muted">
                          {binding.price_label}
                        </span>
                        <span class={billing_badge_class(binding.billing)}>
                          {binding.billing_label}
                        </span>
                        <span :if={!binding.authorized} class="text-[10px] text-warning">
                          Offline
                        </span>
                      </div>
                      <button
                        id={"remove-binding-#{binding.id}"}
                        type="button"
                        phx-click="remove_role_binding"
                        phx-value-binding_id={binding.id}
                        phx-value-role_kind={role.kind}
                        aria-label={"Remove #{binding.tag}"}
                        class="shrink-0 rounded-sm px-1.5 py-0.5 text-muted hover:bg-danger-soft hover:text-danger"
                      >
                        ✕
                      </button>
                    </div>

                    <div class={[
                      "grid gap-1.5",
                      row_efforts != [] && "sm:grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)_5.5rem]",
                      row_efforts == [] && "sm:grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)]"
                    ]}>
                      <div>
                        <label
                          for={"binding-agent-#{binding.id}"}
                          class="block text-[10px] font-medium text-muted"
                        >
                          Agent
                        </label>
                        <select
                          id={"binding-agent-#{binding.id}"}
                          name="agent"
                          class="app-field mt-0.5 w-full px-2 py-1 text-xs"
                        >
                          <option
                            :if={binding.agent_id not in eligible_ids}
                            value={binding.agent_id}
                            selected
                            disabled
                          >
                            {binding.agent_name} (offline)
                          </option>
                          <option
                            :for={a <- eligible}
                            value={a.id}
                            selected={binding.agent_id == Atom.to_string(a.id)}
                          >
                            {a.name}
                          </option>
                        </select>
                      </div>

                      <div>
                        <label
                          for={"binding-model-#{binding.id}"}
                          class="block text-[10px] font-medium text-muted"
                        >
                          Model
                        </label>
                        <select
                          id={"binding-model-#{binding.id}"}
                          name="model_id"
                          class="app-field mt-0.5 w-full px-2 py-1 text-xs"
                        >
                          <option
                            :if={binding.model_id == nil or row_models == []}
                            value=""
                            selected={binding.model_id == nil}
                          >
                            CLI default
                          </option>
                          <option
                            :if={
                              is_binary(binding.model_id) and binding.model_id not in row_model_ids
                            }
                            value={binding.model_id}
                            selected
                            disabled
                          >
                            {binding.model_name} (disabled)
                          </option>
                          <option
                            :for={m <- row_models}
                            value={m.id}
                            selected={binding.model_id == m.id}
                          >
                            {m.name} · {m.billing_label} ({m.price_label})
                          </option>
                        </select>
                      </div>

                      <div :if={row_efforts != []}>
                        <label
                          for={"binding-effort-#{binding.id}"}
                          class="block text-[10px] font-medium text-muted"
                        >
                          Effort
                        </label>
                        <select
                          id={"binding-effort-#{binding.id}"}
                          name="reasoning_effort"
                          class="app-field mt-0.5 w-full px-2 py-1 text-xs"
                        >
                          <option value="" selected={binding.reasoning_effort in [nil, ""]}>
                            Default
                          </option>
                          <option
                            :for={eff <- row_efforts}
                            value={eff}
                            selected={binding.reasoning_effort == eff}
                          >
                            {eff}
                          </option>
                        </select>
                      </div>
                    </div>
                  </form>
                </div>
              </div>

              <% draft = Map.get(@binding_drafts, role.kind, %{}) %>
              <% draft_models =
                if draft[:agent_id], do: Roles.models_for_agent(draft[:agent_id]), else: [] %>
              <% selected_m = Enum.find(draft_models, &(&1.id == draft[:model_id])) %>
              <% draft_efforts = if selected_m, do: selected_m.reasoning_efforts, else: [] %>

              <div class="mt-3 border-t border-line pt-3">
                <p
                  :if={eligible == []}
                  id={"role-#{role.id}-empty-authorized"}
                  class="text-xs text-muted"
                >
                  Connect and authorize an execution agent to bind models to {role.name}.
                </p>

                <form
                  :if={eligible != [] and role.bindings == []}
                  id={"role-bind-form-#{role.kind}"}
                  phx-change="auto_create_role_binding"
                  phx-submit="auto_create_role_binding"
                  class="space-y-2"
                >
                  <input type="hidden" name="role_kind" value={role.kind} />
                  <div class="grid gap-1.5 sm:grid-cols-2">
                    <div>
                      <label
                        for={"role-#{role.kind}-agent"}
                        class="block text-[11px] font-medium text-muted"
                      >
                        Agent
                      </label>
                      <select
                        id={"role-#{role.kind}-agent"}
                        name="agent"
                        class="app-field mt-0.5 w-full px-2 py-1.5 text-xs"
                      >
                        <option
                          :for={a <- eligible}
                          value={a.id}
                          selected={draft[:agent_id] == Atom.to_string(a.id)}
                        >
                          {a.name}
                        </option>
                      </select>
                    </div>
                    <div>
                      <label
                        for={"role-#{role.kind}-model"}
                        class="block text-[11px] font-medium text-muted"
                      >
                        Model
                      </label>
                      <select
                        id={"role-#{role.kind}-model"}
                        name="model_id"
                        class="app-field mt-0.5 w-full px-2 py-1.5 text-xs"
                      >
                        <option :if={draft_models == []} value="__default__" selected>
                          CLI default
                        </option>
                        <option
                          :for={m <- draft_models}
                          value={m.id}
                          selected={draft[:model_id] == m.id}
                        >
                          {m.name} · {m.billing_label} ({m.price_label})
                        </option>
                      </select>
                    </div>
                  </div>

                  <div class="flex items-end justify-between gap-2">
                    <div :if={draft_efforts != []} class="min-w-0 flex-1">
                      <label
                        for={"role-#{role.kind}-effort"}
                        class="block text-[11px] font-medium text-muted"
                      >
                        Effort
                      </label>
                      <select
                        id={"role-#{role.kind}-effort"}
                        name="reasoning_effort"
                        class="app-field mt-0.5 w-full px-2 py-1.5 text-xs"
                      >
                        <option value="" selected={draft[:reasoning_effort] in [nil, ""]}>
                          Default
                        </option>
                        <option
                          :for={eff <- draft_efforts}
                          value={eff}
                          selected={draft[:reasoning_effort] == eff}
                        >
                          {eff}
                        </option>
                      </select>
                    </div>
                    <button
                      id={"add-binding-#{role.kind}"}
                      type="submit"
                      class="app-button-secondary ml-auto shrink-0 px-3 py-1.5 text-xs font-semibold"
                    >
                      + Bind to {role.name}
                    </button>
                  </div>
                </form>

                <div
                  :if={eligible != [] and role.bindings != []}
                  class="flex items-center justify-between gap-2"
                >
                  <span class="text-[11px] text-muted">Changes save automatically</span>
                  <button
                    id={"add-binding-#{role.kind}"}
                    type="button"
                    phx-click="add_next_role_binding"
                    phx-value-role_kind={role.kind}
                    class="app-button-secondary shrink-0 px-2.5 py-1 text-xs font-semibold"
                  >
                    + Add agent · model
                  </button>
                </div>
              </div>
            </article>
          </div>
        </section>
      </div>

      <aside
        :if={@connect_open}
        id="connect-agent-panel"
        aria-labelledby="connect-agent-heading"
        class="rounded-sm border border-line bg-surface p-4 lg:sticky lg:top-6"
      >
        <div class="flex items-center justify-between gap-2 border-b border-line pb-3">
          <div>
            <p class="app-eyebrow">Local CLI Setup</p>
            <h2 id="connect-agent-heading" class="text-base font-semibold text-ink">
              Connect &amp; authorize agent
            </h2>
          </div>
          <button
            id="close-connect-agent"
            type="button"
            phx-click="close_connect"
            aria-label="Close connect agent panel"
            class="rounded-sm px-2 py-1 text-xs text-muted hover:bg-paper hover:text-ink"
          >
            ✕
          </button>
        </div>

        <div class="mt-3">
          <p class="text-xs font-medium text-muted">1. Choose local CLI agent</p>
          <div class="mt-1.5 grid grid-cols-2 gap-1.5">
            <button
              :for={agent <- @agents}
              id={"pick-agent-#{agent.id}"}
              type="button"
              phx-click="select_connect_agent"
              phx-value-agent={agent.id}
              class={[
                "flex items-center justify-between rounded-sm border px-2.5 py-2 text-left text-xs transition",
                @selected_meta.id == agent.id && "border-forest bg-sage/60 font-semibold text-ink",
                @selected_meta.id != agent.id &&
                  "border-line bg-paper text-body hover:border-forest/50"
              ]}
            >
              <span class="truncate">{agent.name}</span>
              <span class={[
                "ml-1 h-2 w-2 shrink-0 rounded-full",
                connect_dot_class(@results[agent.id])
              ]}></span>
            </button>
          </div>
        </div>

        <.connect_agent_detail
          agent={@selected_meta}
          result={@selected_result}
          busy={@agent_busy[@selected_meta.id]}
          notice={@agent_notices[@selected_meta.id]}
          detecting={@detecting}
        />
      </aside>
    </div>
    """
  end

  attr :agent, :map, required: true
  attr :result, :any, default: nil
  attr :busy, :any, default: nil
  attr :notice, :any, default: nil
  attr :detecting, :boolean, default: false

  defp connect_agent_detail(assigns) do
    models =
      if assigns.result && is_list(assigns.result.models) do
        Enum.map(assigns.result.models, &Roles.present_model(assigns.agent.id, &1))
      else
        []
      end

    assigns = assign(assigns, :models, models)

    ~H"""
    <div id={"agent-#{@agent.id}"} class="mt-4 space-y-3 border-t border-line pt-3 text-xs">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h3 class="text-sm font-semibold text-ink">{@agent.name}</h3>
        <span class="rounded-sm border border-line bg-paper px-2 py-0.5 font-medium text-body">
          {status_label(@result)}
        </span>
      </div>

      <dl class="space-y-1 text-muted">
        <div class="flex justify-between gap-2">
          <dt>Sign-in status</dt>
          <dd class="font-medium text-ink">{auth_label(@result)}</dd>
        </div>
        <div :if={@result && @result.version} class="flex justify-between gap-2">
          <dt>Version</dt>
          <dd class="font-mono text-ink">{@result.version}</dd>
        </div>
        <div :if={@result && @result.path} class="flex justify-between gap-2">
          <dt>Executable</dt>
          <dd class="truncate font-mono text-ink" title={@result.path}>{@result.path}</dd>
        </div>
        <div class="flex justify-between gap-2">
          <dt>Access mode</dt>
          <dd class="text-right text-ink">{@agent.billing_hint}</dd>
        </div>
      </dl>

      <div
        id={"agent-auth-box-#{@agent.id}"}
        class="space-y-2 rounded-sm border border-line bg-paper p-3"
      >
        <p class="font-medium text-ink">2. Connect &amp; authorize CLI</p>
        <p class="text-muted">
          Sign-in command: <code class="font-mono text-ink">{@agent.login}</code>
          ·
          <a
            href={@agent.docs}
            target="_blank"
            rel="noopener noreferrer"
            class="text-forest underline underline-offset-2"
          >
            Setup docs
          </a>
        </p>
        <div class="flex flex-wrap gap-2 pt-1">
          <button
            id={"authorize-#{@agent.id}"}
            type="button"
            phx-click="authorize_agent"
            phx-value-agent={@agent.id}
            disabled={@detecting or @busy != nil}
            class="app-button-secondary px-2.5 py-1.5 text-xs font-semibold disabled:opacity-50"
          >
            {if @busy == :authorizing, do: "Opening Terminal…", else: "Authorize in Terminal"}
          </button>
          <button
            id={"verify-auth-#{@agent.id}"}
            type="button"
            phx-click="verify_agent"
            phx-value-agent={@agent.id}
            disabled={@detecting or @busy != nil}
            class="app-button-primary px-2.5 py-1.5 text-xs font-semibold disabled:opacity-50"
          >
            {if @busy == :verifying, do: "Verifying…", else: "Verify & load models"}
          </button>
        </div>
      </div>

      <p
        :if={@notice}
        id={"agent-notice-#{@agent.id}"}
        role="status"
        class="rounded-sm border border-line bg-sage/50 px-2.5 py-2 text-ink"
      >
        {@notice}
      </p>

      <ul :if={@result && @result.errors != []} class="space-y-1 text-warning">
        <li :for={err <- @result.errors}>{error_label(err)}</li>
      </ul>

      <div :if={@models != []} class="space-y-1.5 border-t border-line pt-3">
        <div class="flex items-center justify-between">
          <p class="font-medium text-ink">
            3. Available models ({Enum.count(@models, & &1.enabled)}/{length(@models)} active)
          </p>
        </div>
        <div class="max-h-60 space-y-1 overflow-y-auto pr-1">
          <label
            :for={m <- @models}
            class="flex cursor-pointer items-center justify-between gap-2 rounded-sm border border-line bg-paper px-2 py-1.5 hover:border-forest/50"
          >
            <span class="flex min-w-0 items-center gap-2">
              <input
                type="checkbox"
                checked={m.enabled}
                phx-click="toggle_model"
                phx-value-agent={@agent.id}
                phx-value-model_id={m.id}
                phx-value-enabled={to_string(!m.enabled)}
                class="h-3.5 w-3.5 accent-forest"
              />
              <span class="truncate font-medium text-ink">{m.name}</span>
            </span>
            <span class="flex shrink-0 items-center gap-1.5">
              <span class="font-mono text-[10px] text-muted">{m.price_label}</span>
              <span class={billing_badge_class(m.billing)}>{m.billing_label}</span>
            </span>
          </label>
        </div>
      </div>

      <details :if={@result} class="border-t border-line pt-2 text-muted">
        <summary class="cursor-pointer font-medium text-body">CLI capabilities</summary>
        <dl class="mt-1.5 grid grid-cols-2 gap-1">
          <div :for={{key, label} <- capabilities()} data-capability={key}>
            <dt class="inline">{label}:</dt>
            <dd class="inline font-medium text-ink">
              {capability_label(@result.capabilities[key])}
            </dd>
          </div>
        </dl>
      </details>
    </div>
    """
  end

  defp capabilities, do: @capabilities

  defp connect_dot_class(%{probe_status: :ok, auth_status: :configured}), do: "bg-forest"
  defp connect_dot_class(%{probe_status: :ok}), do: "bg-warning"

  defp connect_dot_class(%{probe_status: status})
       when status in [:missing, :failed, :unsupported],
       do: "bg-danger"

  defp connect_dot_class(_), do: "bg-line"

  defp billing_badge_class("free"),
    do:
      "rounded-sm border border-forest/30 bg-sage px-1.5 py-0.5 text-[10px] font-medium text-forest"

  defp billing_badge_class("subscription"),
    do:
      "rounded-sm border border-forest/30 bg-sage/60 px-1.5 py-0.5 text-[10px] font-medium text-ink"

  defp billing_badge_class("subscription_or_api"),
    do: "rounded-sm border border-line bg-surface px-1.5 py-0.5 text-[10px] font-medium text-body"

  defp billing_badge_class(_),
    do:
      "rounded-sm border border-warning-line/60 bg-peach/50 px-1.5 py-0.5 text-[10px] font-medium text-ink"

  defp status_label(nil), do: "Not checked"
  defp status_label(%{probe_status: :ok}), do: "CLI metadata recognized"
  defp status_label(%{probe_status: :missing}), do: "Not found on PATH"
  defp status_label(%{probe_status: :unsupported}), do: "CLI metadata unsupported"
  defp status_label(%{probe_status: :failed}), do: "Detection incomplete"

  defp auth_label(nil), do: "Not checked"
  defp auth_label(%{auth_status: :configured}), do: "CLI reports credentials configured"
  defp auth_label(%{auth_status: :stale}), do: "Session expired — sign in again"
  defp auth_label(%{auth_status: :not_configured}), do: "CLI reports no credentials configured"
  defp auth_label(_), do: "Unknown"

  defp capability_label(:advertised), do: "Advertised"
  defp capability_label(:not_advertised), do: "Not advertised"
  defp capability_label(_), do: "Unknown"

  defp error_label(%{stage: :version, reason: :unrecognized}),
    do: "Version check returned unrecognized output."

  defp error_label(%{stage: :help, reason: :timeout}), do: "Help check timed out."

  defp error_label(%{stage: :auth, reason: :unsupported}),
    do: "Sign-in check is not supported."

  defp error_label(%{stage: :auth, reason: :output_limit}),
    do: "Sign-in check exceeded its output limit."

  defp error_label(%{stage: :models}),
    do: "Model catalog could not be read from this CLI."

  defp error_label(_), do: "Probe step did not complete."

  defp scan_error(:busy), do: "Another detection is running."
  defp scan_error(:unavailable), do: "Agent detection is unavailable."
  defp scan_error(_), do: "Detection was interrupted."
end
