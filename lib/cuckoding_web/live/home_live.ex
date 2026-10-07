defmodule CuckodingWeb.HomeLive do
  use CuckodingWeb, :live_view
  alias Cuckoding.Foundation

  @tools [
    {"codex", "Codex"},
    {"claude", "Claude Code"},
    {"cursor", "Cursor"},
    {"hermes", "Hermes"},
    {"rtk", "RTK"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
      Process.send_after(self(), :clock, 1_000)
    end

    {:ok,
     socket
     |> assign(:tools, @tools)
     |> assign(:command_key, Ecto.UUID.generate())
     |> assign(:codex_path, nil)
     |> assign(:probe_error, nil)
     |> assign(:connection_error, nil)
     |> assign(:auth_error, nil)
     |> assign(:model_id, "")
     |> assign(:model_error, nil)
     |> assign(:model_confirmed, false)
     |> assign(:confirmed, false)
     |> reload()}
  end

  @impl true
  def handle_event("discover", _, socket) do
    case Foundation.discover(socket.assigns.command_key, socket.assigns.workspace.revision) do
      {:ok, _} -> {:noreply, socket |> assign(:command_key, Ecto.UUID.generate()) |> reload()}
      _ -> {:noreply, put_flash(socket, :error, "Setup could not be checked. Try again.")}
    end
  end

  def handle_event("edit_codex", params, socket) do
    previous =
      socket.assigns.codex_path || socket.assigns.workspace.codex["path"] ||
        get_in(socket.assigns.workspace.tools, ["codex", "path"]) || ""

    {:noreply,
     assign(socket,
       codex_path: params["path"],
       confirmed: params["path"] == previous and params["confirmed"] == "true"
     )}
  end

  def handle_event("check_codex", params, socket) do
    case Foundation.check_codex(
           socket.assigns.command_key,
           socket.assigns.workspace.revision,
           params["path"],
           params["confirmed"] == "true"
         ) do
      {:ok, command} ->
        error = if command.state == "rejected", do: "Setup changed. Check the path and try again."

        {:noreply,
         socket
         |> assign(command_key: Ecto.UUID.generate(), probe_error: error, confirmed: false)
         |> reload()}

      {:error, :confirmation_required} ->
        {:noreply,
         assign(socket, :probe_error, "Confirm that you trust this executable before running it.")}

      _ ->
        {:noreply,
         assign(
           socket,
           :probe_error,
           "Choose an absolute path to an executable file on this Mac."
         )}
    end
  end

  def handle_event("cancel_probe", %{"id" => id}, socket) do
    Foundation.cancel_probe(id)
    {:noreply, reload(socket)}
  end

  def handle_event("inspect_codex", params, socket) do
    case Foundation.inspect_codex(
           socket.assigns.command_key,
           socket.assigns.workspace.revision,
           params["profile_confirmed"] == "true"
         ) do
      {:ok, command} ->
        error =
          if command.state == "rejected", do: "Setup changed. Check the version and try again."

        {:noreply,
         socket |> assign(command_key: Ecto.UUID.generate(), connection_error: error) |> reload()}

      {:error, :confirmation_required} ->
        {:noreply,
         assign(socket, :connection_error, "Confirm the private profile check before continuing.")}

      _ ->
        {:noreply,
         assign(
           socket,
           :connection_error,
           "Run a supported version check for the current executable first."
         )}
    end
  end

  def handle_event("authorize_codex", %{"operation" => operation} = params, socket)
      when operation in ["login", "logout"] do
    operation = if operation == "login", do: :login, else: :logout

    case Foundation.authorize_codex(
           socket.assigns.command_key,
           socket.assigns.workspace.revision,
           operation,
           params["auth_confirmed"] == "true"
         ) do
      {:ok, command} ->
        error =
          if command.state == "rejected",
            do: "Another setup operation is active or setup changed. Wait, then try again."

        {:noreply,
         socket |> assign(command_key: Ecto.UUID.generate(), auth_error: error) |> reload()}

      {:error, :confirmation_required} ->
        {:noreply,
         assign(socket, :auth_error, "Confirm the private-profile sign-in or sign-out first.")}

      _ ->
        {:noreply, assign(socket, :auth_error, "Check the current executable version first.")}
    end
  end

  def handle_event("edit_model", params, socket) do
    {:noreply,
     assign(socket,
       model_id: params["model_id"],
       model_confirmed:
         params["model_id"] == socket.assigns.model_id and params["model_confirmed"] == "true"
     )}
  end

  def handle_event("check_model", params, socket) do
    case Foundation.check_model(
           socket.assigns.command_key,
           socket.assigns.workspace.revision,
           params["model_id"],
           params["model_confirmed"] == "true"
         ) do
      {:ok, command} ->
        error =
          if command.state == "rejected",
            do:
              "Setup changed or another operation is active. Refresh the connection and try again."

        {:noreply,
         socket
         |> assign(command_key: Ecto.UUID.generate(), model_error: error, model_confirmed: false)
         |> reload()}

      {:error, :confirmation_required} ->
        {:noreply,
         assign(
           socket,
           :model_error,
           "Confirm the model check and possible provider usage first."
         )}

      _ ->
        {:noreply,
         assign(
           socket,
           :model_error,
           "Sign in, refresh the connection and select an available model first."
         )}
    end
  end

  @impl true
  def handle_info(:updated, socket), do: {:noreply, reload(socket)}
  def handle_info(:session_expired, socket), do: {:noreply, redirect(socket, to: "/locked")}

  def handle_info(:clock, socket) do
    Process.send_after(self(), :clock, 1_000)

    {:noreply,
     assign(socket,
       now: DateTime.utc_now(),
       login_ready: Foundation.login_link(socket.assigns.auth_command) != nil
     )}
  end

  defp reload(socket) do
    auth = Foundation.pending_probe(["login_codex", "logout_codex"])
    workspace = Foundation.workspace()
    previous = socket.assigns[:workspace]

    socket
    |> assign(
      :model_confirmed,
      socket.assigns.model_confirmed and not is_nil(previous) and
        previous.connection == workspace.connection
    )
    |> assign(:workspace, workspace)
    |> assign(:pending, Foundation.pending?())
    |> assign(:discovering, Foundation.pending_probe("discover_tools") != nil)
    |> assign(:auth_command, auth)
    |> assign(:last_auth, Foundation.last_probe(["login_codex", "logout_codex"]))
    |> assign(:login_ready, Foundation.login_link(auth) != nil)
    |> assign(:events, Foundation.events())
    |> assign(:probe, Foundation.pending_probe())
    |> assign(:last_probe, Foundation.last_probe())
    |> assign(:model_check, Foundation.pending_probe("check_codex_model"))
    |> assign(:last_model_check, Foundation.last_probe("check_codex_model"))
    |> assign(:connection_check, Foundation.pending_probe("inspect_codex"))
    |> assign(:last_connection_check, Foundation.last_probe("inspect_codex"))
    |> assign(:now, DateTime.utc_now())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="app-shell">
      <a class="skip-link" href="#main">Skip to content</a>
      <aside class="sidebar" aria-label="Workspace navigation">
        <.link navigate={~p"/"} class="brand" aria-label="Cuckoding home"><img
          src={~p"/favicon.svg"}
          class="brand-mark"
          width="43"
          height="43"
          alt=""
        /><span>Cuckoding</span></.link>
        <nav aria-label="Main">
          <.link
            navigate={~p"/"}
            class={["nav-link", @live_action == :home && "active"]}
            aria-current={if @live_action == :home, do: "page"}
          ><span aria-hidden="true">▦</span> Tabula Gladiatorum</.link>
          <span class="nav-link muted" aria-disabled="true"><span aria-hidden="true">◇</span>
          Arenas <small>Next</small></span>
          <.link
            navigate={~p"/settings"}
            class={["nav-link", @live_action == :settings && "active"]}
            aria-current={if @live_action == :settings, do: "page"}
          ><span aria-hidden="true">⌘</span> Agents &amp; roles</.link>
          <.link
            navigate={~p"/about"}
            class={["nav-link", @live_action == :about && "active"]}
            aria-current={if @live_action == :about, do: "page"}
          ><span aria-hidden="true">⚙</span> Settings</.link>
        </nav>
        <div class="sidebar-foot">
          <span class="status-dot" aria-hidden="true"></span>
          Local workspace <small>Foundation preview · 0.1.0</small>
        </div>
      </aside>
      <main id="main" class="main">
        <header class="page-header">
          <p class="eyebrow">YOUR AGENTS. YOUR ARENA.</p>
          <h1>{title(@live_action)}</h1>
          <p class="subtle">A quiet place to turn a plan into finished work.</p>
        </header>
        <div :if={@flash["error"]} role="alert" class="notice">{@flash["error"]}</div>

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
          <.link navigate={~p"/settings"} class="button primary">Check your setup
          <span aria-hidden="true">↗</span></.link>
          <p class="fine-print">Start with a check of the tools installed on this Mac.</p>
        </section>

        <section :if={@live_action == :settings} class="panel" aria-labelledby="tools-title">
          <div class="panel-heading">
            <div>
              <p class="eyebrow">LOCAL TOOLS</p><h2 id="tools-title">Your starting lineup.</h2>
            </div>
            <button
              class="button primary"
              phx-click="discover"
              phx-disable-with="Checking…"
              disabled={@pending}
            >{if @discovering, do: "Checking…", else: "Check setup"}</button>
          </div>
          <p class="subtle">
            This checks executable locations. It does not run tools or sign you in.
          </p>
          <ul class="tool-list">
            <li :for={{key, label} <- @tools}>
              <span class="tool-name">{label}</span>
              <span class={[
                "tool-status",
                @workspace.tools[key] && @workspace.tools[key]["status"] == "found" && "found"
              ]}>{tool_status(key, @workspace.tools[key])}</span>
              <details
                :if={@workspace.tools[key] && @workspace.tools[key]["path"]}
                id={"tool-location-#{key}"}
                phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
              >
                <summary>Location</summary><code>{@workspace.tools[key]["path"]}</code>
              </details>
            </li>
          </ul>
          <p role="status" aria-live="polite" class="fine-print">
            {if @discovering, do: "Checking installed tools…", else: checked_at(@workspace.checked_at)}
          </p>
          <div class="defaults">
            <span>RTK <b>Required</b></span><span>Ponytail <b>Full</b></span>
          </div>
        </section>

        <section
          :if={@live_action == :settings}
          class="panel codex-setup"
          aria-labelledby="codex-title"
        >
          <p class="eyebrow">CODEX / VERSION READINESS</p>
          <h2 id="codex-title">Choose your executable.</h2>
          <p class="subtle">
            Check the executable first, then inspect Cuckoding's private Codex profile.
          </p>
          <form id="codex-check" phx-change="edit_codex" phx-submit="check_codex">
            <label for="codex-path">Codex executable</label>
            <input
              id="codex-path"
              name="path"
              type="text"
              required
              maxlength="4096"
              value={
                @codex_path || @workspace.codex["path"] || get_in(@workspace.tools, ["codex", "path"]) ||
                  ""
              }
              placeholder="/absolute/path/to/codex"
              spellcheck="false"
              autocomplete="off"
              aria-describedby="codex-execution-note"
            />
            <p id="codex-execution-note" class="fine-print">
              This runs the selected program with <code>--version</code>
              on your Mac. Only select an executable you trust.
            </p>
            <label class="confirm-executable"><input
              name="confirmed"
              type="checkbox"
              value="true"
              checked={@confirmed}
              required
            /> I trust this executable. Run the version check.</label>
            <p :if={@probe_error} id="codex-error" role="alert" class="notice">{@probe_error}</p>
            <button class="button primary" disabled={@pending} phx-disable-with="Checking…">Check Codex version</button>
          </form>
          <div :if={@probe} class="probe-progress" role="status">
            <p>Codex · setup · {@probe.state} · {max(0, DateTime.diff(@now, @probe.updated_at))} s</p>
            <button class="button" phx-click="cancel_probe" phx-value-id={@probe.id}>Cancel check</button>
          </div>
          <p
            :if={@last_probe && @last_probe.state in ["failed", "cancelled"]}
            role="status"
            class="fine-print"
          >
            {if @last_probe.state == "cancelled",
              do: "Check cancelled.",
              else: "Check interrupted. Confirm the path to run a new check."}
          </p>
          <div :if={@workspace.codex != %{}} id="codex-result" role="status" class="probe-result">
            <p>{codex_status(@workspace.codex["status"])}</p>
            <p :if={@workspace.codex["version"]} class="fine-print">
              Observed version: {@workspace.codex["version"]} · Account status is checked separately
            </p>
            <details id="codex-evidence" phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}>
              <summary>Last check details</summary>
              <code>{@workspace.codex["path"]}</code>
              <p class="fine-print">
                {@workspace.codex["checked_at"]} · {@workspace.codex["elapsed_ms"] || 0} ms
              </p>
            </details>
          </div>
          <div
            :if={@workspace.codex["status"] == "supported"}
            class="probe-result"
            aria-labelledby="connection-title"
          >
            <h3 id="connection-title">Your private Codex connection.</h3>
            <p class="subtle">
              Check account status and refresh its model catalog in a Cuckoding-owned profile. Personal Codex settings and sign-ins stay separate. No task runs.
            </p>
            <p class="fine-print">Verified executable: <code>{@workspace.codex["path"]}</code></p>
            <p :if={@auth_error} class="notice" role="alert">{@auth_error}</p>
            <form id="codex-login" phx-submit="authorize_codex">
              <input type="hidden" name="operation" value="login" />
              <label class="confirm-executable"><input
                id={"login-consent-#{@command_key}"}
                type="checkbox"
                name="auth_confirmed"
                value="true"
                required
              /> Use this executable to sign in to Cuckoding's private Codex profile.</label>
              <button class="button primary" disabled={@pending} phx-disable-with="Starting…">Sign in with ChatGPT</button>
            </form>
            <div :if={@auth_command} id="codex-auth-progress" class="probe-progress" role="status">
              <p>
                Codex · account setup · {if @auth_command.kind == "login_codex",
                  do: "sign-in",
                  else: "sign-out"} · {@auth_command.state} · {max(
                  0,
                  DateTime.diff(@now, @auth_command.inserted_at)
                )} s
              </p>
              <a
                :if={@login_ready}
                id="codex-login-link"
                class="button primary"
                href={~p"/codex/login/#{@auth_command.id}"}
                target="_blank"
                rel="noopener noreferrer"
                referrerpolicy="no-referrer"
              >Continue on OpenAI ↗</a>
              <p :if={@auth_command.result == "awaiting_login"} class="fine-print">
                Finish sign-in in the OpenAI tab, then return here. This request expires after ten minutes.
                Your credentials go directly to OpenAI. You can close this tab and return while the app stays open.
              </p>
              <button
                class="button"
                phx-click="cancel_probe"
                phx-value-id={@auth_command.id}
                disabled={@auth_command.state == "cancelling"}
              >{if @auth_command.state == "cancelling",
                do: "Stopping…",
                else: "Cancel account operation"}</button>
            </div>
            <p
              :if={@last_auth && @last_auth.state in ["failed", "cancelled"]}
              class="notice"
              role="status"
            >
              Account operation {if @last_auth.state == "cancelled",
                do: "cancelled",
                else: "interrupted"}.
              Check the connection before trying again; a sign-in may have completed just before cancellation.
            </p>
            <details id="codex-signout" phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}>
              <summary>Sign out of this private profile</summary>
              <p class="fine-print">
                This disconnects Cuckoding's Codex profile and clears its saved model list.
                Personal Codex sign-ins stay separate. No roles or battles are enabled yet.
              </p>
              <form id="codex-logout" phx-submit="authorize_codex">
                <input type="hidden" name="operation" value="logout" />
                <label class="confirm-executable"><input
                  id={"logout-consent-#{@command_key}"}
                  type="checkbox"
                  name="auth_confirmed"
                  value="true"
                  required
                /> Sign out of Cuckoding's private Codex profile.</label>
                <button class="button" disabled={@pending} phx-disable-with="Signing out…">Sign out of Codex</button>
              </form>
            </details>
            <form id="connection-check" phx-submit="inspect_codex">
              <label class="confirm-executable"><input
                id={"profile-consent-#{@command_key}"}
                name="profile_confirmed"
                type="checkbox"
                value="true"
                required
              /> Check this private profile with the verified executable.</label>
              <p :if={@connection_error} role="alert" class="notice">{@connection_error}</p>
              <button class="button primary" disabled={@pending} phx-disable-with="Checking…">Check Codex connection</button>
            </form>
            <div :if={@connection_check} role="status" class="probe-progress">
              <p>
                Codex · connection setup · {@connection_check.state} · {max(
                  0,
                  DateTime.diff(@now, @connection_check.updated_at)
                )} s
              </p>
              <button class="button" phx-click="cancel_probe" phx-value-id={@connection_check.id}>Cancel connection check</button>
            </div>
            <p
              :if={@last_connection_check && @last_connection_check.state in ["failed", "cancelled"]}
              role="status"
              class="fine-print"
            >
              {if @last_connection_check.state == "cancelled",
                do: "Connection check cancelled.",
                else: "Connection check interrupted. Confirm a fresh check to retry."}
            </p>
            <div
              :if={@workspace.connection != %{} && !@auth_command}
              id="connection-result"
              role="status"
            >
              <p>{connection_status(@workspace.connection)}</p>
              <p :if={@workspace.connection["checked_at"]} class="fine-print">
                Updated: {@workspace.connection["checked_at"]}
                <span :if={is_integer(@workspace.connection["elapsed_ms"])}>
                  · {@workspace.connection["elapsed_ms"]} ms
                </span>
              </p>
              <p :if={@workspace.connection["authorization_checked_at"]} class="fine-print">
                Account observation: {@workspace.connection["authorization_checked_at"]}
              </p>
              <p
                :if={
                  @workspace.connection["models"] not in [nil, []] &&
                    Foundation.catalog_status(@workspace.connection, @now) == "stale"
                }
                class="notice"
              >
                The saved catalog is stale. Refresh it to check available models; cached entries do not establish current access.
              </p>
              <details
                :if={@workspace.connection["models"] not in [nil, []]}
                id="codex-models"
                phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
              >
                <summary>
                  {length(@workspace.connection["models"])} cached models · {Foundation.catalog_status(
                    @workspace.connection,
                    @now
                  )}
                </summary>
                <p class="fine-print">
                  Source: {@workspace.connection["source"]} · Fetched: {@workspace.connection[
                    "fetched_at"
                  ]}. Catalog metadata is not an entitlement check.
                </p>
                <ul class="tool-list">
                  <li :for={model <- @workspace.connection["models"]}>
                    <span>{model["name"]} <small :if={model["default"]}>Runtime default</small></span>
                    <code>{model["model"]}</code>
                    <span class="fine-print">Effort: {Enum.join(model["efforts"], ", ")} · Inputs: {Enum.join(
                      model["input_modalities"],
                      ", "
                    )}</span>
                  </li>
                </ul>
              </details>
            </div>
            <section class="probe-result" aria-labelledby="model-check-title">
              <h3 id="model-check-title">Try a model.</h3>
              <p class="subtle">
                A catalog lists models. This sends one fixed connection prompt to check whether a selected model responds.
                It can consume provider usage. Repository tasks are not enabled.
              </p>
              <p :if={@model_error} role="alert" class="notice">{@model_error}</p>
              <form
                :if={
                  @workspace.connection["authorization"] == "chatgpt" &&
                    Foundation.catalog_status(@workspace.connection, @now) == "fresh"
                }
                id="model-check"
                phx-change="edit_model"
                phx-submit="check_model"
              >
                <label for="model-id">Model</label>
                <select id="model-id" name="model_id" required>
                  <option value="" selected={@model_id == ""}>Choose a model</option>
                  <option
                    :for={model <- @workspace.connection["models"] || []}
                    value={model["id"]}
                    selected={@model_id == model["id"]}
                  >
                    {model["name"]} · {model["model"]}
                  </option>
                </select>
                <p class="fine-print">
                  Two-minute limit. Uses the lowest advertised reasoning effort, a private scratch folder and restricted runtime permissions.
                  Only a fixed acknowledgement is accepted; raw responses are discarded.
                </p>
                <label class="confirm-executable">
                  <input
                    type="checkbox"
                    name="model_confirmed"
                    value="true"
                    checked={@model_confirmed}
                    required
                  />
                  Run one model check using my connected account. This may use my provider allowance.
                </label>
                <button class="button primary" disabled={@pending} phx-disable-with="Starting…">Check model access</button>
              </form>
              <p
                :if={
                  @workspace.connection["authorization"] != "chatgpt" ||
                    Foundation.catalog_status(@workspace.connection, @now) != "fresh"
                }
                class="fine-print"
              >
                Sign in and refresh the connection to choose a model from its current catalog.
              </p>
              <div :if={@model_check} id="model-check-progress" role="status" class="probe-progress">
                <p>
                  Codex · connection test · {@model_check.payload["model"]} · {@model_check.state} · {max(
                    0,
                    DateTime.diff(@now, @model_check.inserted_at)
                  )} s
                </p>
                <button
                  class="button"
                  phx-click="cancel_probe"
                  phx-value-id={@model_check.id}
                  disabled={@model_check.state == "cancelling"}
                >{if @model_check.state == "cancelling", do: "Stopping…", else: "Cancel model check"}</button>
              </div>
              <p
                :if={@last_model_check && @last_model_check.state in ["failed", "cancelled"]}
                class="notice"
                role="status"
              >
                Model check {@last_model_check.state}. It will not run again automatically. Provider usage may already have occurred.
              </p>
              <div
                :if={@workspace.connection["model_check"] && !@model_check}
                id="model-check-result"
                role="status"
              >
                <p>{model_check_status(@workspace.connection["model_check"]["status"])}</p>
                <p class="fine-print">
                  Requested: {@workspace.connection["model_check"]["requested_model"]}
                  <span :if={@workspace.connection["model_check"]["observed_model"]}> · Runtime model: {@workspace.connection[
                    "model_check"
                  ]["observed_model"]}</span>
                  · {@workspace.connection["model_check"]["checked_at"]}
                  <span :if={is_integer(@workspace.connection["model_check"]["elapsed_ms"])}> · {@workspace.connection[
                    "model_check"
                  ]["elapsed_ms"]} ms</span>
                </p>
                <p class="fine-print">
                  This is a point-in-time connection result, not a grant to run repository tasks.
                </p>
              </div>
            </section>
            <p class="fine-print">
              One private profile serves this workspace. Cuckoding keeps public account status and model metadata;
              Codex manages its own credentials. A model catalog does not prove model access. Only the fixed model check can run; repository tasks are not enabled.
            </p>
          </div>
        </section>

        <section :if={@live_action == :about} class="panel" aria-labelledby="about-title">
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
        <footer class="main-foot">
          <span>Speculator → Implementor → Secutor</span><span>Coordinated by Summa Rudis</span>
        </footer>
      </main>
    </div>
    """
  end

  defp title(:home), do: "Tabula Gladiatorum"
  defp title(:settings), do: "Agents & roles"
  defp title(:about), do: "Settings"
  defp tool_status(_, nil), do: "Not checked"
  defp tool_status("rtk", %{"status" => "found"}), do: "Found"
  defp tool_status(_, %{"status" => "found"}), do: "Found · authorization separate"
  defp tool_status(_, _), do: "Not found"
  defp checked_at(nil), do: "No setup check yet."
  defp checked_at(time), do: "Last checked " <> Calendar.strftime(time, "%H:%M UTC")
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

  defp model_check_status(_),
    do: "Model access was not verified. Check the connection and try again."

  defp codex_status("supported"), do: "Version matches the verified Codex baseline."

  defp codex_status("unsupported"),
    do: "This version has not been verified. The current baseline is 0.146.0."

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

  defp connection_status(%{"status" => "checked", "authorization" => "not_connected"}),
    do: "Not signed in to Cuckoding's private Codex profile."

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
