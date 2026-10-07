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

  @impl true
  def handle_info(:updated, socket), do: {:noreply, reload(socket)}
  def handle_info(:session_expired, socket), do: {:noreply, redirect(socket, to: "/locked")}

  def handle_info(:clock, socket) do
    Process.send_after(self(), :clock, 1_000)
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  defp reload(socket) do
    socket
    |> assign(:workspace, Foundation.workspace())
    |> assign(:pending, Foundation.pending?())
    |> assign(:events, Foundation.events())
    |> assign(:probe, Foundation.pending_probe())
    |> assign(:last_probe, Foundation.last_probe())
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
            >{if @pending, do: "Checking…", else: "Check setup"}</button>
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
            {if @pending, do: "Checking installed tools…", else: checked_at(@workspace.checked_at)}
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
            <div :if={@workspace.connection != %{}} id="connection-result" role="status">
              <p>{connection_status(@workspace.connection)}</p>
              <p class="fine-print">
                Last check: {@workspace.connection["checked_at"]} · {@workspace.connection[
                  "elapsed_ms"
                ] || 0} ms
              </p>
              <p :if={@workspace.connection["authorization_checked_at"]} class="fine-print">
                Account observation: {@workspace.connection["authorization_checked_at"]}
              </p>
              <p
                :if={Foundation.catalog_status(@workspace.connection, @now) == "stale"}
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
            <p class="fine-print">
              Sign-in and sign-out controls are the next connection step. This preview does not import credentials or start an authorization flow.
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
  defp event_label(_), do: "Workspace updated"

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
    do: "Codex reported a ChatGPT account in this profile. Model access still needs a real turn."

  defp connection_status(%{"status" => "checked", "authorization" => "unsupported_account"}),
    do: "This profile uses an account type not supported by this preview."

  defp connection_status(%{"status" => "executable_changed"}),
    do: "The executable changed. Run a new version check first."

  defp connection_status(%{"status" => "timeout"}),
    do: "The connection check timed out. Try again."

  defp connection_status(%{"status" => status})
       when status in ~w(unsafe_profile profile_mismatch unsupported_profile),
       do:
         "The private profile could not be verified. Check its storage and managed Codex configuration."

  defp connection_status(_),
    do:
      "The connection check failed. Previous observations are retained; confirm a fresh check to retry."
end
