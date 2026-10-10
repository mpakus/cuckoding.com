defmodule CuckodingWeb.HomeLive do
  use CuckodingWeb, :live_view
  alias Cuckoding.{Agents, Foundation, Team}
  alias CuckodingWeb.Layouts

  @operations ~w(probe_codex inspect_codex login_codex logout_codex check_codex_model probe_cursor inspect_cursor login_cursor logout_cursor)

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
      Process.send_after(self(), :clock, 1_000)
    end

    agent_id = params["id"] || "codex"
    agent = Agents.get(agent_id)
    kind = if(agent, do: agent.kind, else: "codex")
    workspace = Foundation.workspace(agent_id)
    saved = Foundation.saved_agent_models(agent_id)
    catalog = Team.catalog(agent_id)

    {:ok,
     socket
     |> assign(
       agent_id: agent_id,
       agent_kind: kind,
       agent_name: if(agent, do: agent.name, else: ""),
       new_agent: agent_id == "new",
       step: initial_step(saved, catalog, agent_id),
       command_key: Ecto.UUID.generate(),
       error: nil,
       awaiting: pending_id(agent_id),
       review: nil,
       saved: saved,
       selected_ids: if(saved, do: saved.payload["model_ids"], else: []),
       model_id: "",
       model_confirmed: false,
       codex_path: workspace.codex["path"] || default_path(kind),
       desktop_codex_path: Cuckoding.Tools.desktop_codex()
     )
     |> reload()
     |> then(fn socket ->
       if agent_id != "new" and is_nil(agent),
         do: redirect(socket, to: ~p"/agents"),
         else: socket
     end)}
  end

  defp pending_id(id) do
    case Foundation.pending_probe(@operations, id) do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp initial_step(_, _, "new"), do: 1
  defp initial_step(saved, _, _) when not is_nil(saved), do: 4
  defp initial_step(_, %{status: :available}, _), do: 3

  defp initial_step(_, _, id),
    do: if(match?({:ok, _}, Foundation.verified_executable(id)), do: 2, else: 1)

  @impl true
  def handle_event("edit_codex", params, socket) do
    kind =
      if socket.assigns.new_agent and params["agent"] in ~w(codex cursor),
        do: params["agent"],
        else: socket.assigns.agent_kind

    path = if kind != socket.assigns.agent_kind, do: default_path(kind), else: params["path"]

    {:noreply,
     assign(socket,
       codex_path: path,
       agent_kind: kind,
       agent_name: params["name"] || socket.assigns.agent_name,
       error: nil
     )}
  end

  def handle_event("choose_desktop_codex", _, socket),
    do: {:noreply, assign(socket, codex_path: Cuckoding.Tools.desktop_codex() || "", error: nil)}

  def handle_event("check_codex", params, %{assigns: %{new_agent: true}} = socket) do
    if current_form?(socket, params) do
      case Agents.add_and_probe(
             socket.assigns.command_key,
             socket.assigns.workspace.revision,
             params["name"],
             params["agent"],
             params["path"]
           ) do
        {:ok, %{state: "pending"} = command} ->
          {:noreply,
           push_navigate(socket, to: ~p"/agents/#{Foundation.agent_id(command.payload)}")}

        _ ->
          {:noreply,
           assign(socket,
             error: "Enter a name and a trusted executable. Wait for any active setup to finish."
           )}
      end
    else
      {:noreply,
       assign(socket, error: "This form is out of date. Review the connection and try again.")}
    end
  end

  def handle_event("check_codex", params, socket) do
    submit(socket, params, fn ->
      Foundation.check_codex(
        socket.assigns.command_key,
        socket.assigns.workspace.revision,
        params["path"],
        true,
        socket.assigns.agent_id
      )
    end)
  end

  def handle_event("inspect_codex", params, socket) do
    submit(socket, params, fn ->
      Foundation.inspect_codex(
        socket.assigns.command_key,
        socket.assigns.workspace.revision,
        true,
        socket.assigns.agent_id
      )
    end)
  end

  def handle_event("authorize_codex", %{"operation" => operation} = params, socket)
      when operation in ~w(login logout) do
    submit(socket, params, fn ->
      Foundation.authorize_codex(
        socket.assigns.command_key,
        socket.assigns.workspace.revision,
        if(operation == "login", do: :login, else: :logout),
        true,
        socket.assigns.agent_id
      )
    end)
  end

  def handle_event("cancel_probe", %{"id" => id}, socket) do
    Foundation.cancel_probe(id)
    {:noreply, reload(socket)}
  end

  def handle_event("step", %{"step" => step}, socket) when step in ~w(1 2 3) do
    step = String.to_integer(step)

    allowed =
      step == 1 or (step == 2 and socket.assigns.workspace.codex["status"] == "supported") or
        (step == 3 and socket.assigns.catalog.status == :available)

    if allowed and not socket.assigns.pending do
      {:noreply, assign(socket, step: step, review: nil, error: nil)}
    else
      {:noreply, assign(socket, error: "Connect Codex and refresh its model list first.")}
    end
  end

  def handle_event("select_models", params, socket) do
    if current_form?(socket, params) do
      {:noreply, assign(socket, selected_ids: model_ids(params), error: nil, review: nil)}
    else
      {:noreply,
       assign(socket, error: "Setup changed. Review the current model list and try again.")}
    end
  end

  def handle_event("review_models", params, socket) do
    ids = model_ids(params)
    models = Enum.filter(socket.assigns.catalog.models, &(&1["id"] in ids))

    if current_form?(socket, params) and socket.assigns.catalog.status == :available and
         not socket.assigns.pending and ids != [] and length(models) == length(ids) do
      {:noreply,
       assign(socket,
         step: 4,
         selected_ids: ids,
         error: nil,
         review: %{
           revision: socket.assigns.workspace.revision,
           connection_id: socket.assigns.workspace.connection["command_id"],
           models: models
         }
       )}
    else
      {:noreply,
       assign(socket, error: "Select at least one model from the current connected catalog.")}
    end
  end

  def handle_event("save_models", params, socket) do
    review = socket.assigns.review

    if review && current_form?(socket, params) &&
         review.revision == socket.assigns.workspace.revision do
      case Foundation.save_agent_models(
             socket.assigns.command_key,
             review.revision,
             review.connection_id,
             socket.assigns.selected_ids,
             socket.assigns.agent_id
           ) do
        {:ok, %{state: "completed"}} ->
          {:noreply, socket |> assign(review: nil, error: nil) |> reload()}

        _ ->
          {:noreply,
           assign(socket, error: "Setup changed. Go back and review your models before saving.")}
      end
    else
      {:noreply,
       assign(socket, error: "Setup changed. Go back and review your models before saving.")}
    end
  end

  def handle_event("edit_model", params, socket) do
    {:noreply,
     assign(socket,
       model_id: params["model_id"] || "",
       model_confirmed:
         current_form?(socket, params) and params["model_id"] == socket.assigns.model_id and
           params["model_confirmed"] == "true"
     )}
  end

  def handle_event("check_model", params, socket) do
    if params["model_confirmed"] == "true" do
      submit(socket, params, fn ->
        Foundation.check_model(
          socket.assigns.command_key,
          socket.assigns.workspace.revision,
          params["model_id"],
          true,
          socket.assigns.agent_id
        )
      end)
    else
      {:noreply,
       assign(socket, error: "Confirm the optional test and possible provider usage first.")}
    end
  end

  defp submit(socket, params, action) do
    if current_form?(socket, params) do
      case action.() do
        {:ok, %{state: "pending"} = command} ->
          {:noreply,
           socket
           |> assign(
             awaiting: command.id,
             error: nil,
             model_confirmed: false,
             command_key: Ecto.UUID.generate()
           )
           |> reload()}

        {:ok, %{state: "rejected"}} ->
          {:noreply,
           assign(socket,
             error: "Setup changed or another operation is active. Wait, then try again."
           )}

        {:error, :version_required} ->
          {:noreply,
           assign(socket, step: 1, error: "Choose the executable and check its version first.")}

        _ ->
          {:noreply,
           assign(socket, error: "Check the executable path and connection, then try again.")}
      end
    else
      {:noreply,
       assign(socket, error: "This form is out of date. Review the current step and try again.")}
    end
  end

  defp current_form?(socket, params),
    do:
      params["consent_key"] == socket.assigns.command_key and
        params["revision"] == to_string(socket.assigns.workspace.revision)

  defp model_ids(params),
    do: params |> Map.get("model_ids", []) |> List.wrap() |> Enum.reject(&(&1 == ""))

  @impl true
  def handle_info(:updated, socket), do: {:noreply, reload(socket)}
  def handle_info(:session_expired, socket), do: {:noreply, redirect(socket, to: "/locked")}

  def handle_info(:clock, socket) do
    Process.send_after(self(), :clock, 1_000)
    {:noreply, socket |> reload()}
  end

  defp reload(socket) do
    workspace = Foundation.workspace(socket.assigns.agent_id)
    previous = socket.assigns[:workspace]

    changed =
      previous &&
        (previous.revision != workspace.revision or previous.connection != workspace.connection)

    operation = Foundation.pending_probe(@operations, socket.assigns.agent_id)
    last = Foundation.last_probe(@operations, socket.assigns.agent_id)
    catalog = Team.catalog(socket.assigns.agent_id)

    assign(socket,
      workspace: workspace,
      pending: Foundation.pending?(),
      operation: operation,
      last_operation: last,
      events: Foundation.events(),
      catalog: catalog,
      saved: Foundation.saved_agent_models(socket.assigns.agent_id),
      step: next_step(socket, last, workspace, catalog),
      awaiting:
        if(last && last.state not in ~w(pending running cancelling),
          do: nil,
          else: socket.assigns.awaiting
        ),
      model_confirmed: socket.assigns.model_confirmed and not changed,
      command_key: if(changed, do: Ecto.UUID.generate(), else: socket.assigns.command_key),
      login_ready: Foundation.login_link(operation) != nil,
      now: DateTime.utc_now()
    )
  end

  defp next_step(socket, last, workspace, catalog) do
    case last do
      %{id: id, state: "completed", kind: kind} when id == socket.assigns.awaiting ->
        case {kind, workspace.codex["status"], catalog.status} do
          {kind, "supported", _} when kind in ~w(probe_codex probe_cursor) ->
            2

          {kind, _, :available}
          when kind in ~w(inspect_codex login_codex inspect_cursor login_cursor) ->
            3

          {kind, _, _} when kind in ~w(logout_codex logout_cursor) ->
            2

          _ ->
            socket.assigns.step
        end

      _ ->
        socket.assigns.step
    end
  end

  defp form_scope(assigns) do
    ~H"""
    <input type="hidden" name="consent_key" value={@key} />
    <input type="hidden" name="revision" value={@revision} />
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace active={@live_action} title={title(@live_action)} flash={@flash}>
      <section :if={@live_action == :home} class="panel welcome" aria-labelledby="welcome-title">
        <p class="eyebrow">01 / GET READY</p>
        <h2 id="welcome-title">Build your team.</h2>
        <p>Connect your agents, choose their roles, then give them an Arena.</p>
        <ol class="steps" aria-label="Setup journey">
          <li class="current"><b>01</b><span>Agents</span></li>
          <li><b>02</b><span>Team</span></li>
          <li><b>03</b><span>Arena</span></li>
          <li><b>04</b><span>Tabula</span></li>
          <li><b>05</b><span>Battle</span></li>
        </ol>
        <.link navigate={~p"/agents"} class="button primary">Check your setup
        <span aria-hidden="true">↗</span></.link>
        <.link navigate={~p"/team"} class="button">Choose your team</.link>
        <p class="fine-print">Start with a check of the tools installed on this Mac.</p>
      </section>

      <section
        :if={@live_action == :agents}
        class="panel codex-setup agent-wizard"
        aria-labelledby="wizard-title"
      >
        <.link navigate={~p"/agents"} class="text-link">← All agents</.link>
        <p class="eyebrow">{if @new_agent, do: "NEW AGENT", else: @agent_name}</p>
        <ol class="steps wizard-steps" aria-label="Connect an agent">
          <li
            :for={
              {label, step} <- [
                {"Choose Agent", 1},
                {"Connect and Authorize", 2},
                {"Select models", 3},
                {"Save", 4}
              ]
            }
            class={if @step == step, do: "current"}
            aria-current={if @step == step, do: "step"}
          >
            <b>0{step}</b><span>{label}</span>
          </li>
        </ol>
        <p :if={@error} id="wizard-error" class="notice" role="alert">{@error}</p>

        <div :if={@step == 1} id="wizard-choose">
          <h2 id="wizard-title">Choose your agent.</h2>
          <p class="subtle">Each connection has its own account and saved models.</p>
          <form id="codex-check" phx-change="edit_codex" phx-submit="check_codex">
            <.form_scope key={@command_key} revision={@workspace.revision} />
            <label :if={@new_agent} for="agent-name">Connection name</label>
            <input
              :if={@new_agent}
              id="agent-name"
              name="name"
              value={@agent_name}
              maxlength="60"
              required
              placeholder="e.g. Cursor for planning"
            />
            <label for="agent-choice">Agent</label>
            <select id="agent-choice" name="agent" disabled={!@new_agent}>
              <option value="codex" selected={@agent_kind == "codex"}>Codex</option>
              <option value="cursor" selected={@agent_kind == "cursor"}>Cursor</option>
              <option disabled>Claude Code — coming soon</option>
              <option disabled>Hermes — coming soon</option>
            </select>
            <details
              id="executable-details"
              phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
            >
              <summary>Executable details</summary>
              <label for="codex-path">{Agents.label(@agent_kind)} executable</label>
              <input
                id="codex-path"
                type="text"
                name="path"
                value={@codex_path}
                required
                autocomplete="off"
              />
              <button
                :if={@agent_kind == "codex" && @desktop_codex_path}
                type="button"
                class="button"
                phx-click="choose_desktop_codex"
              >Use desktop Codex</button>
              <p :if={@agent_kind == "codex"} class="fine-print">
                The desktop app and standalone CLI can offer different models.
              </p>
            </details>
            <p class="fine-print">
              Continue runs this executable with <code>--version</code>
              on your Mac. Only continue with an executable you trust.
            </p>
            <button class="button primary" disabled={@pending}>Continue with {Agents.label(
              @agent_kind
            )}</button>
          </form>
          <p :if={@workspace.codex["status"]} class="fine-print" role="status">
            {version_status(@agent_kind, @workspace.codex["status"])}
          </p>
        </div>

        <div :if={@step == 2} id="wizard-connect">
          <h2 id="wizard-title">Connect and authorize.</h2>
          <p class="subtle">Connect your account to this agent's private profile.</p>
          <p :if={@workspace.connection["status"]} id="connection-result" role="status">
            {connection_status(@workspace.connection)}
          </p>
          <form id="connection-check" phx-submit="inspect_codex">
            <.form_scope key={@command_key} revision={@workspace.revision} />
            <p class="fine-print">
              Check account status and fetch the models offered by {Agents.label(@agent_kind)}. No model usage.
            </p>
            <button
              class={"button " <> if(@catalog.status == :available, do: "", else: "primary")}
              disabled={@pending}
            >Refresh connection</button>
          </form>
          <form
            :if={@workspace.connection["authorization"] not in ~w(chatgpt cursor)}
            id="codex-login"
            phx-submit="authorize_codex"
          >
            <.form_scope key={@command_key} revision={@workspace.revision} />
            <input type="hidden" name="operation" value="login" />
            <p class="fine-print">
              Sign in opens {Agents.label(@agent_kind)} authorization using this executable. Your personal profile stays separate.
            </p>
            <button class="button primary" disabled={@pending}>Sign in with {if @agent_kind == "codex",
              do: "ChatGPT",
              else: "Cursor"}</button>
          </form>
          <div :if={@workspace.connection["authorization"] in ~w(chatgpt cursor)}>
            <button
              :if={@catalog.status == :available}
              class="button primary"
              phx-click="step"
              phx-value-step="3"
              disabled={@pending}
            >Select models</button>
            <details id="sign-out" phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}>
              <summary>Disconnect {Agents.label(@agent_kind)}</summary>
              <form id="codex-logout" phx-submit="authorize_codex">
                <.form_scope key={@command_key} revision={@workspace.revision} />
                <input type="hidden" name="operation" value="logout" />
                <p class="fine-print">
                  Sign out disconnects this private profile and clears its cached catalog. Saved roles stay unchanged.
                </p>
                <button class="button" disabled={@pending}>Sign out of {Agents.label(@agent_kind)}</button>
              </form>
            </details>
          </div>
          <button class="button" phx-click="step" phx-value-step="1" disabled={@pending}>Back</button>
        </div>

        <div :if={@step == 3} id="wizard-models">
          <h2 id="wizard-title">Select your models.</h2>
          <p class="subtle">Choose which models to use when building your team.</p>
          <p class="fine-print">
            {length(@catalog.models)} models from {Agents.label(@agent_kind)} · {Foundation.catalog_status(
              @workspace.connection
            )}. Availability comes from the agent; a catalog does not prove model access.
          </p>
          <p :if={@catalog.status != :available} class="notice" role="status">
            Refresh your connection before continuing.
          </p>
          <form id="model-selection" phx-change="select_models" phx-submit="review_models">
            <.form_scope key={@command_key} revision={@workspace.revision} />
            <input type="hidden" name="model_ids[]" value="" />
            <fieldset class="model-choices" disabled={@pending || @catalog.status != :available}>
              <legend class="sr-only">Available models</legend>
              <label :for={model <- @catalog.models} class="model-choice">
                <input
                  type="checkbox"
                  name="model_ids[]"
                  value={model["id"]}
                  checked={model["id"] in @selected_ids}
                />
                <span><b>{model["name"]}</b><small>{model["model"]}<span :if={model["hidden"]}> · additional model</span></small></span>
              </label>
            </fieldset>
            <div class="team-actions">
              <button
                type="button"
                class="button"
                phx-click="step"
                phx-value-step="2"
                disabled={@pending}
              >Back</button>
              <button class="button primary" disabled={@pending || @catalog.status != :available}>Review selection</button>
            </div>
          </form>
          <p :if={@agent_kind == "cursor"} class="fine-print">
            Cursor model selection is available. Model tests and task execution are not enabled yet.
          </p>
          <details
            :if={@agent_kind == "codex"}
            id="model-diagnostic"
            phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
          >
            <summary>Test a model (optional)</summary>
            <form id="model-check" phx-change="edit_model" phx-submit="check_model">
              <.form_scope key={@command_key} revision={@workspace.revision} />
              <label for="model-id">Model to test</label>
              <select id="model-id" name="model_id" required>
                <option value="">Choose a model</option>
                <option
                  :for={model <- @catalog.models}
                  value={model["id"]}
                  selected={model["id"] == @model_id}
                >
                  {model["name"]}
                </option>
              </select>
              <label class="confirm-executable"><input
                type="checkbox"
                name="model_confirmed"
                value="true"
                checked={@model_confirmed}
                required
              />Run one fixed test. This may use my provider allowance.</label>
              <button class="button" disabled={@pending || @catalog.status != :available}>Test model</button>
              <p class="fine-print">
                Two-minute limit. No tools or project access. A passing test does not authorize repository work.
              </p>
            </form>
            <div :if={@workspace.connection["model_check"]} id="model-check-result" role="status">
              <p>{model_check_status(@workspace.connection["model_check"]["status"])}</p>
              <p class="fine-print">
                Requested: {@workspace.connection["model_check"]["requested_model"]}
                <span :if={@workspace.connection["model_check"]["observed_model"]}>
                  · Runtime: {@workspace.connection["model_check"]["observed_model"]}
                </span>
                · {@workspace.connection[
                  "model_check"
                ]["checked_at"]}
                <span :if={is_integer(@workspace.connection["model_check"]["elapsed_ms"])}>
                  · {@workspace.connection["model_check"]["elapsed_ms"]} ms
                </span>
              </p>
            </div>
          </details>
        </div>

        <div :if={@step == 4} id="wizard-save">
          <h2 id="wizard-title">
            {if @review, do: "Save your agent.", else: "Your agent is saved."}
          </h2>
          <p class="subtle">
            Codex · {length(
              if @review, do: @review.models, else: (@saved && @saved.payload["models"]) || []
            )} selected models
          </p>
          <ul class="saved-models">
            <li :for={
              model <-
                if @review, do: @review.models, else: (@saved && @saved.payload["models"]) || []
            }>
              {model["name"]} <small>{model["model"]}</small>
            </li>
          </ul>
          <p class="fine-print">
            These are your choices for new Team assignments. Existing roles keep their saved models.
          </p>
          <p :if={!@review && @catalog.status != :available} class="notice" role="status">
            Your choices are saved. Reconnect this agent before assigning models to new roles.
          </p>
          <div class="team-actions">
            <button
              class="button"
              phx-click="step"
              phx-value-step={if @catalog.status == :available, do: "3", else: "2"}
              disabled={@pending}
            >{if @review, do: "Back", else: "Edit connection"}</button>
            <form :if={@review} id="save-models" phx-submit="save_models">
              <.form_scope key={@command_key} revision={@review.revision} />
              <button class="button primary" disabled={@pending}>Save</button>
            </form>
            <.link :if={!@review} navigate={~p"/team"} class="button primary">Choose team roles
            <span aria-hidden="true">↗</span></.link>
          </div>
        </div>

        <div :if={@operation} id="agent-progress" class="probe-progress" role="status">
          <p>
            {operation_label(@operation.kind)} · {DateTime.diff(@now, @operation.updated_at)} seconds
          </p>
          <p class="fine-print">
            Setup · {Agents.label(@agent_kind)}<span :if={@operation.payload["model"]}> · {@operation.payload[
              "model"
            ]}</span>
            · {@operation.state}
          </p>
          <.link
            :if={@login_ready}
            href={~p"/codex/login/#{@operation.id}"}
            target="_blank"
            rel="noopener noreferrer"
            class="button primary"
          >Continue at {if @agent_kind == "codex", do: "OpenAI", else: "Cursor"}</.link>
          <button
            class="button"
            phx-click="cancel_probe"
            phx-value-id={@operation.id}
            disabled={@operation.state == "cancelling"}
          >Cancel</button>
        </div>
        <p
          :if={@last_operation && @last_operation.state in ~w(failed cancelled)}
          class="notice"
          role="status"
        >
          Action {@last_operation.state}. It will not retry automatically.<span :if={
            @last_operation.kind == "check_codex_model"
          }> Provider usage may already have occurred.</span>
        </p>
      </section>
      <section :if={@live_action == :settings} class="panel" aria-labelledby="about-title">
        <p class="eyebrow">WORKSPACE SETTINGS</p><h2 id="about-title">Local by design.</h2>
        <dl class="facts">
          <div>
            <dt>Cuckoding</dt><dd>0.1.0 · foundation preview</dd>
          </div>
          <div>
            <dt>Data</dt><dd>A separate rebuild workspace; previous app data stays intact.</dd>
          </div>
          <div>
            <dt>Defaults</dt><dd>RTK required · Ponytail full</dd>
          </div>
          <div>
            <dt>Access</dt><dd>Menu bar authorization · 30-minute browser sessions</dd>
          </div>
        </dl>
        <details
          id="recent-activity"
          class="activity"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>Recent workspace activity</summary>
          <ol>
            <li :for={event <- @events}>
              <time>{Calendar.strftime(event.occurred_at, "%H:%M:%S UTC")}</time> {event_label(
                event.kind
              )}
            </li>
          </ol>
        </details>
      </section>
    </Layouts.workspace>
    """
  end

  defp default_path("codex"),
    do:
      Cuckoding.Tools.desktop_codex() || get_in(Cuckoding.Tools.discover(), ["codex", "path"]) ||
        ""

  defp default_path(kind), do: get_in(Cuckoding.Tools.discover(), [kind, "path"]) || ""
  defp version_status("cursor", "supported"), do: "Verified Cursor CLI version."
  defp version_status("cursor", _), do: "Check Cursor CLI version. Supported: 2026.09.15-d2fe57e."
  defp version_status(_, status), do: codex_status(status)
  defp title(:home), do: "Tabula Gladiatorum"
  defp title(:agents), do: "Agents"
  defp title(:settings), do: "Settings"
  defp operation_label("probe_cursor"), do: "Checking Cursor version"
  defp operation_label("inspect_cursor"), do: "Refreshing Cursor connection"
  defp operation_label("login_cursor"), do: "Signing in to Cursor"
  defp operation_label("logout_cursor"), do: "Signing out of Cursor"
  defp operation_label("probe_codex"), do: "Checking Codex version"
  defp operation_label("inspect_codex"), do: "Refreshing Codex connection"
  defp operation_label("login_codex"), do: "Signing in to Codex"
  defp operation_label("logout_codex"), do: "Signing out of Codex"
  defp operation_label("check_codex_model"), do: "Testing model access"
  defp event_label("agent_models." <> status), do: "Agent model choices: " <> status
  defp event_label("shell.authorized"), do: "Menu bar connected"
  defp event_label("browser.authorized"), do: "Browser opened"
  defp event_label("shell.quit_requested"), do: "Quit requested"
  defp event_label("shell.disconnected"), do: "Menu bar disconnected"
  defp event_label("discovery." <> status), do: "Setup check: " <> status
  defp event_label("codex." <> status), do: "Codex version check: " <> status
  defp event_label("connection." <> status), do: "Codex connection check: " <> status
  defp event_label("login." <> status), do: "Codex sign-in: " <> status
  defp event_label("logout." <> status), do: "Codex sign-out: " <> status
  defp event_label("model_check." <> status), do: "Codex model check: " <> status
  defp event_label("team." <> status), do: "Team: " <> status
  defp event_label(_), do: "Workspace updated"

  defp model_check_status("passed"), do: "Model responded to the fixed connection check."

  defp model_check_status("not_connected"),
    do: "The private profile is signed out. Sign in and refresh the connection."

  defp model_check_status("unsupported_grant"),
    do:
      "The runtime could not confirm the restricted permissions. No diagnostic turn was authorized."

  defp model_check_status("model_unavailable"),
    do: "This model or reasoning option is no longer available. Refresh the connection."

  defp model_check_status("model_mismatch"),
    do: "The runtime selected a different model or setup changed. No passing result was recorded."

  defp model_check_status("cancelled"), do: "Model check cancelled."

  defp model_check_status("timeout"),
    do: "Model check timed out. It will not retry automatically."

  defp model_check_status("cleanup_uncertain"),
    do: "The helper did not confirm cleanup. Inspect the app before trying again."

  defp model_check_status("unexpected_message"),
    do: "Codex returned an unsupported protocol message. Update Cuckoding before retrying."

  defp model_check_status("provider_error"),
    do:
      "Codex rejected the request. Refresh your connection and check your account's model access."

  defp model_check_status("turn_failed"),
    do: "Codex could not complete the test. Check your account access or try another model."

  defp model_check_status(_),
    do: "Model access was not verified. Check the connection and try again."

  defp codex_status("supported"), do: "Version matches a verified Codex baseline."

  defp codex_status("unsupported"),
    do:
      "This version has not been verified. Verified versions: 0.146.0, 0.162.0-alpha.2 and 0.162.0-alpha.17.2."

  defp codex_status("timeout"),
    do: "The version check timed out. Check the executable and try again."

  defp codex_status("executable_changed"),
    do: "The executable changed before launch. Confirm the path again."

  defp codex_status("helper_unavailable"),
    do: "Open this workspace from the Cuckoding menu bar app to check versions."

  defp codex_status("invalid_output"),
    do: "The executable did not return a recognized Codex version."

  defp codex_status("cancelled"), do: "Check cancelled."

  defp codex_status(_),
    do: "The version check could not start. Check the executable and try again."

  defp connection_status(%{"status" => "checked", "authorization" => "cursor"}),
    do: "Cursor account connected. Models come from this account’s catalog."

  defp connection_status(%{"status" => "checked", "authorization" => "not_connected"}),
    do: "Not signed in to this private profile."

  defp connection_status(%{"status" => "checked", "authorization" => "chatgpt"}),
    do: "Codex reported a ChatGPT account in this profile. Model checks are recorded separately."

  defp connection_status(%{"status" => "checked", "authorization" => "unsupported_account"}),
    do: "This profile uses an account type not supported by this preview."

  defp connection_status(%{"status" => "executable_changed"}),
    do: "The executable changed. Run a new version check first."

  defp connection_status(%{"status" => "timeout"}),
    do: "The connection check timed out. Try again."

  defp connection_status(%{"status" => "profile_busy"}),
    do: "Another operation owns this private profile. Wait for it to finish, then retry."

  defp connection_status(%{"status" => status})
       when status in ~w(needs_recheck cancelled cleanup_uncertain logout_unconfirmed),
       do: "Account status needs a fresh connection check. No saved model list is trusted."

  defp connection_status(%{"status" => status}) when status in ~w(invalid_login login_failed),
    do: "Sign-in did not finish. Check the connection, then retry sign-in if needed."

  defp connection_status(%{"status" => status})
       when status in ~w(unsafe_profile profile_mismatch unsupported_profile),
       do:
         "The private profile could not be verified. Check its storage and managed Codex configuration."

  defp connection_status(_),
    do:
      "The connection check failed. Previous observations are retained; confirm a fresh check to retry."
end
