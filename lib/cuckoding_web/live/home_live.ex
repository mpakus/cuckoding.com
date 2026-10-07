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
    if connected?(socket), do: Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")

    {:ok,
     socket |> assign(:tools, @tools) |> assign(:command_key, Ecto.UUID.generate()) |> reload()}
  end

  @impl true
  def handle_event("discover", _, socket) do
    case Foundation.discover(socket.assigns.command_key, socket.assigns.workspace.revision) do
      {:ok, _} -> {:noreply, socket |> assign(:command_key, Ecto.UUID.generate()) |> reload()}
      _ -> {:noreply, put_flash(socket, :error, "Setup could not be checked. Try again.")}
    end
  end

  @impl true
  def handle_info(:updated, socket), do: {:noreply, reload(socket)}
  def handle_info(:session_expired, socket), do: {:noreply, redirect(socket, to: "/locked")}

  defp reload(socket) do
    socket
    |> assign(:workspace, Foundation.workspace())
    |> assign(:pending, Foundation.pending?())
    |> assign(:events, Foundation.events())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="app-shell">
      <a class="skip-link" href="#main">Skip to content</a>
      <aside class="sidebar" aria-label="Workspace navigation">
        <.link navigate={~p"/"} class="brand" aria-label="CCoding home"><img
          src={~p"/favicon.svg"}
          class="brand-mark"
          width="43"
          height="43"
          alt=""
        /><span>CCODING</span></.link>
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
          <p class="fine-print">
            Provider authorization and model selection arrive in the next build.
          </p>
        </section>

        <section :if={@live_action == :about} class="panel" aria-labelledby="about-title">
          <p class="eyebrow">WORKSPACE SETTINGS</p><h2 id="about-title">Local by design.</h2>
          <dl class="facts">
            <div>
              <dt>CCoding</dt><dd>0.1.0 · foundation preview</dd>
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
  defp tool_status(_, %{"status" => "found"}), do: "Found · not authorized"
  defp tool_status(_, _), do: "Not found"
  defp checked_at(nil), do: "No setup check yet."
  defp checked_at(time), do: "Last checked " <> Calendar.strftime(time, "%H:%M UTC")
  defp event_label("shell.authorized"), do: "Menu bar connected"
  defp event_label("browser.authorized"), do: "Browser opened"
  defp event_label("shell.quit_requested"), do: "Quit requested"
  defp event_label("shell.disconnected"), do: "Menu bar disconnected"
  defp event_label("discovery." <> status), do: "Setup check: " <> status
  defp event_label(_), do: "Workspace updated"
end
