defmodule AgentDeskWeb.WorkspacePanels do
  @moduledoc false
  use AgentDeskWeb, :html

  alias AgentDesk.Analytics

  attr :query, :string, required: true
  attr :filter, :string, required: true
  attr :agents, :list, required: true
  attr :docs_url, :string, required: true

  def registry(assigns) do
    ~H"""
    <section id="acp-registry" class="desk-registry">
      <header class="desk-registry-header">
        <div>
          <h2 class="desk-title text-xl">ACP Registry</h2>
          <p class="desk-muted mt-1 text-xs">
            Install external agents, then start a thread. Auth stays with the agent CLI.
          </p>
        </div>
        <a href={@docs_url} target="_blank" rel="noreferrer" class="btn btn-ghost btn-sm">
          Learn More <.icon name="hero-arrow-top-right-on-square" class="size-3.5" />
        </a>
      </header>

      <form id="registry-search" phx-change="registry_search" phx-submit="registry_search">
        <label class="sr-only" for="registry-query">Search agents</label>
        <input
          id="registry-query"
          type="search"
          name="q"
          value={@query}
          placeholder="Search agents"
          class="input input-bordered input-sm w-full"
          autocomplete="off"
        />
      </form>

      <div id="registry-filters" class="desk-filter-row" role="tablist" aria-label="Install filter">
        <button
          :for={filter <- ["all", "installed", "not_installed"]}
          type="button"
          id={"registry-filter-#{filter}"}
          phx-click="registry_filter"
          phx-value-filter={filter}
          class={["desk-filter", @filter == filter && "desk-filter-active"]}
        >
          {filter_label(filter)}
        </button>
        <button
          type="button"
          id="registry-refresh"
          phx-click="registry_refresh"
          class="btn btn-ghost btn-xs ml-auto"
        >
          Refresh
        </button>
      </div>

      <p :if={@agents == []} class="desk-empty">No agents match that search.</p>

      <article :for={agent <- @agents} id={"registry-agent-#{agent["id"]}"} class="desk-registry-card">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <h3 class="font-semibold">
              {agent["name"]}
              <span :if={agent["version"] != ""} class="desk-muted font-normal">
                v{agent["version"]}
              </span>
            </h3>
            <p class="desk-muted mt-1 text-sm">{agent["description"]}</p>
          </div>
          <div class="flex shrink-0 gap-1">
            <button
              :if={agent["installed"]}
              type="button"
              id={"registry-use-#{agent["id"]}"}
              phx-click="registry_use"
              phx-value-id={agent["id"]}
              class="btn btn-primary btn-xs"
            >
              Use
            </button>
            <button
              :if={agent["installed"]}
              type="button"
              id={"registry-remove-#{agent["id"]}"}
              phx-click="registry_remove"
              phx-value-id={agent["id"]}
              class="btn btn-ghost btn-xs"
            >
              Remove
            </button>
            <button
              :if={not agent["installed"]}
              type="button"
              id={"registry-install-#{agent["id"]}"}
              phx-click="registry_install"
              phx-value-id={agent["id"]}
              class="btn btn-primary btn-xs"
            >
              Install
            </button>
          </div>
        </div>
        <p class="desk-muted mt-3 flex flex-wrap items-center gap-3 text-xs">
          <span>ID: {agent["id"]}</span>
          <span>{agent["distribution"]}</span>
          <a
            :if={is_binary(agent["repository"])}
            href={agent["repository"]}
            target="_blank"
            rel="noreferrer"
            class="link link-hover"
          >
            GitHub
          </a>
        </p>
      </article>
    </section>
    """
  end

  attr :report, :map, required: true

  def analytics(assigns) do
    ~H"""
    <section id="agent-analytics" class="desk-analytics">
      <header class="desk-registry-header">
        <div>
          <h2 class="desk-title text-xl">Dashboard</h2>
          <p class="desk-muted mt-1 text-xs">
            SQLite is canonical. Runtime memory is this BEAM. XERJ is a searchable projection.
          </p>
        </div>
      </header>

      <div class="desk-analytics-grid">
        <article class="desk-registry-card">
          <h3 class="desk-kicker">Runtime memory</h3>
          <p class="mt-2 font-semibold tabular-nums">
            {Analytics.format_bytes(@report.runtime.total)}
          </p>
          <p class="desk-muted mt-1 text-xs">
            {@report.runtime.process_count} processes
          </p>
          <ul class="mt-3 space-y-1 text-sm">
            <li class="flex justify-between gap-3">
              <span>processes</span>
              <span class="tabular-nums">{Analytics.format_bytes(@report.runtime.processes)}</span>
            </li>
            <li class="flex justify-between gap-3">
              <span>ETS</span>
              <span class="tabular-nums">{Analytics.format_bytes(@report.runtime.ets)}</span>
            </li>
            <li class="flex justify-between gap-3">
              <span>binaries</span>
              <span class="tabular-nums">{Analytics.format_bytes(@report.runtime.binary)}</span>
            </li>
            <li class="flex justify-between gap-3">
              <span>atoms</span>
              <span class="tabular-nums">{Analytics.format_bytes(@report.runtime.atom)}</span>
            </li>
          </ul>
        </article>

        <article class="desk-registry-card">
          <h3 class="desk-kicker">SQLite</h3>
          <p class="mt-2 font-semibold tabular-nums">
            {Analytics.format_bytes(@report.sqlite.bytes)}
          </p>
          <p class="desk-muted mt-1 break-all text-xs">{@report.sqlite.path}</p>
          <ul class="mt-3 space-y-1 text-sm">
            <li :for={table <- @report.sqlite.tables} class="flex justify-between gap-3">
              <span>{table["name"]}</span>
              <span class="tabular-nums">{table["rows"]}</span>
            </li>
          </ul>
        </article>

        <article class="desk-registry-card">
          <h3 class="desk-kicker">XERJ / search</h3>
          <p class="mt-2 font-semibold">{@report.xerj.adapter} · {@report.xerj.status}</p>
          <p class="desk-muted mt-1 text-xs">Health {@report.xerj.health}</p>
          <p class="desk-muted mt-1 break-all text-xs">{@report.xerj.data_dir}</p>
        </article>

        <article class="desk-registry-card">
          <h3 class="desk-kicker">Memories</h3>
          <p class="mt-2 font-semibold tabular-nums">
            {@report.memory.total} notes · {Analytics.format_bytes(@report.memory.bytes)}
          </p>
          <p :if={@report.memory.namespaces == []} class="desk-empty mt-2">No remembered notes.</p>
          <ul class="mt-3 space-y-1 text-sm">
            <li :for={ns <- @report.memory.namespaces} class="flex justify-between gap-3">
              <span>{ns["kind"]}</span>
              <span class="tabular-nums">{ns["count"]}</span>
            </li>
          </ul>
        </article>

        <article class="desk-registry-card">
          <h3 class="desk-kicker">Usage</h3>
          <p class="mt-2 text-sm">
            {@report.exchange.sessions} sessions · {@report.exchange.pending_deliveries} pending deliveries
          </p>
          <p class="desk-muted mt-1 text-xs tabular-nums">
            {@report.exchange.usage["total_tokens"] || 0} tokens · {@report.exchange.usage[
              "cost_cents"
            ] || 0} cents
          </p>
          <ul class="mt-3 space-y-1 text-sm">
            <li :for={row <- @report.exchange.messages} class="flex justify-between gap-3">
              <span>message {row["name"]}</span>
              <span class="tabular-nums">{row["count"]}</span>
            </li>
            <li :for={row <- @report.exchange.artifacts} class="flex justify-between gap-3">
              <span>artifact {row["name"]}</span>
              <span class="tabular-nums">{row["count"]}</span>
            </li>
            <li :for={row <- @report.exchange.events} class="flex justify-between gap-3">
              <span>{row["name"]}</span>
              <span class="tabular-nums">{row["count"]}</span>
            </li>
          </ul>
        </article>
      </div>
    </section>
    """
  end

  defp filter_label("not_installed"), do: "Not Installed"
  defp filter_label("installed"), do: "Installed"
  defp filter_label(_), do: "All"

  attr :sessions, :list, required: true

  def grove(assigns) do
    sessions = assigns.sessions || []
    working = Enum.count(sessions, &(&1.status in ~w(working starting waiting)))
    blocked = Enum.count(sessions, &(&1.status in ~w(blocked interrupted)))
    total = length(sessions)

    assigns =
      assigns
      |> assign(:working, working)
      |> assign(:blocked, blocked)
      |> assign(:total, total)
      |> assign(:caption, grove_caption(working, total))

    ~H"""
    <section
      id="agent-grove"
      class="desk-grove"
      phx-hook="Grove"
      data-working={@working}
      data-blocked={@blocked}
      data-total={@total}
      aria-label={@caption}
    >
      <div class="flex items-baseline justify-between gap-2">
        <h3 class="desk-kicker">Grove</h3>
        <p id="grove-caption" class="desk-muted text-xs" aria-live="polite">{@caption}</p>
      </div>
      <div class="desk-grove-frame">
        <canvas class="desk-grove-canvas" aria-hidden="true"></canvas>
      </div>
    </section>
    """
  end

  defp grove_caption(0, 0), do: "Idle until a session starts"
  defp grove_caption(0, _total), do: "Grove at rest"
  defp grove_caption(1, _total), do: "An agent is growing the grove"
  defp grove_caption(n, _total), do: "#{n} agents are growing the grove"

  attr :projects, :list, required: true
  attr :current_project, :any, default: nil
  attr :live_project_ids, :list, default: []
  attr :confirm_close_project_id, :any, default: nil
  attr :failed_recent_id, :any, default: nil
  attr :confirm_forget_project_id, :any, default: nil

  def recent_projects(assigns) do
    ~H"""
    <div class="mt-3">
      <h2 class="desk-kicker">Recent projects</h2>
      <ul id="recent-projects" class="mt-2 space-y-2">
        <li :if={@projects == []} class="desk-empty">
          No projects opened yet.
        </li>
        <li :for={project <- @projects} id={"recent-#{project.id}"} class="desk-project-row">
          <button
            type="button"
            id={"open-recent-#{project.id}"}
            phx-click="open_recent"
            phx-value-id={project.id}
            class={[
              "desk-nav-item w-full text-left",
              @current_project && @current_project.id == project.id && "desk-nav-item-active"
            ]}
            aria-label={"Open #{project.name}"}
          >
            <span class="flex items-center justify-between gap-2 pr-5">
              <span class="block truncate font-semibold">{project.name}</span>
              <span
                :if={project.id in @live_project_ids}
                class="desk-status desk-status-completed"
              >
                <span class="desk-status-dot" aria-hidden="true"></span> live
              </span>
            </span>
            <span class="desk-muted mt-0.5 block truncate pr-5 text-xs" title={project.canonical_path}>
              {project.canonical_path}
            </span>
          </button>
          <div class="desk-project-close">
            <button
              :if={@confirm_close_project_id == project.id}
              type="button"
              id={"confirm-close-#{project.id}"}
              phx-click="close_project"
              phx-value-id={project.id}
              class="btn btn-xs btn-error"
            >
              Confirm
            </button>
            <button
              :if={@confirm_close_project_id == project.id}
              type="button"
              phx-click="cancel_close_project"
              class="desk-close-x"
              aria-label="Cancel close"
            >
              ×
            </button>
            <button
              :if={@confirm_close_project_id != project.id}
              type="button"
              id={"close-project-#{project.id}"}
              phx-click="confirm_close_project"
              phx-value-id={project.id}
              class="desk-close-x"
              aria-label={"Close #{project.name}"}
            >
              ×
            </button>
          </div>
          <div class="desk-recent-actions">
            <button
              type="button"
              id={"check-recent-#{project.id}"}
              phx-click="check_recent"
              phx-value-id={project.id}
              class="btn btn-ghost btn-xs"
            >
              Check again
            </button>
            <p :if={@failed_recent_id == project.id} class="desk-recent-missing">
              That folder is gone. It may have been moved or deleted.
            </p>
            <button
              :if={@failed_recent_id == project.id and @confirm_forget_project_id == project.id}
              type="button"
              id={"confirm-forget-#{project.id}"}
              phx-click="forget_recent"
              phx-value-id={project.id}
              class="btn btn-xs btn-error"
            >
              Confirm remove
            </button>
            <button
              :if={@failed_recent_id == project.id and @confirm_forget_project_id == project.id}
              type="button"
              phx-click="cancel_forget_recent"
              class="btn btn-ghost btn-xs"
            >
              Cancel
            </button>
            <button
              :if={@failed_recent_id == project.id and @confirm_forget_project_id != project.id}
              type="button"
              id={"forget-recent-#{project.id}"}
              phx-click="confirm_forget_recent"
              phx-value-id={project.id}
              class="btn btn-ghost btn-xs"
            >
              Remove from recents
            </button>
          </div>
        </li>
      </ul>
    </div>
    """
  end

  attr :id, :string, default: "first-run"
  attr :step, :integer, default: 1
  attr :current_project, :any, default: nil
  attr :provider_status, :map, default: %{}
  attr :sessions, :list, default: []
  attr :search_status, :map, default: %{}
  attr :delegation_depth, :integer, default: 3
  attr :xerj_enabled, :boolean, default: false

  def onboarding(assigns) do
    project? = match?(%{id: _}, assigns.current_project)
    git? = project? and is_binary(assigns.current_project.default_branch)
    ready = Enum.count(assigns.provider_status, fn {_key, status} -> status[:available] end)
    copy = onboard_copy(assigns.step, project?, git?, ready, assigns.xerj_enabled)

    assigns =
      assigns
      |> assign(:project?, project?)
      |> assign(:git?, git?)
      |> assign(:ready, ready)
      |> assign(:copy, copy)

    ~H"""
    <div id={@id} class="desk-onboard">
      <p class="desk-onboard-index">First run · step {@step} of 10</p>
      <div class="desk-onboard-step mt-2">
        <p class="font-semibold text-sm">{@copy.title}</p>
        <p class="mt-1">{@copy.body}</p>
        <ul :if={@step == 3} class="mt-2 space-y-1">
          <li :for={{key, status} <- @provider_status}>
            {provider_name(key)} · {if(status[:available],
              do: status[:version] || "ready",
              else: "missing"
            )}
          </li>
        </ul>
        <form
          :if={@step == 7}
          id="onboard-policy"
          phx-submit="set_delegation_policy"
          class="mt-2 space-y-2"
        >
          <label class="desk-muted text-xs">
            Max delegation depth
            <input
              type="number"
              min="1"
              max="8"
              name="depth"
              value={@delegation_depth}
              class="input input-bordered input-xs mt-1 w-full"
            />
          </label>
          <.button class="btn btn-xs">Save policy</.button>
        </form>
        <div class="mt-2 flex flex-wrap gap-1">
          <button
            :if={@step == 9 and not @xerj_enabled}
            type="button"
            id="enable-xerj"
            phx-click="enable_xerj"
            class="btn btn-xs"
          >
            Enable XERJ indexing
          </button>
          <button
            :if={@step < 10}
            type="button"
            id="onboard-next"
            phx-click="onboard_next"
            class="btn btn-xs btn-primary"
          >
            Continue
          </button>
          <button
            :if={@step == 10}
            type="button"
            id="onboard-done"
            phx-click={JS.focus(to: "#new-session") |> JS.push("onboard_complete")}
            class="btn btn-xs btn-primary"
          >
            Create first session
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp onboard_copy(1, _, _, _, _),
    do: %{
      title: "Select a Git repository",
      body:
        "Use Choose folder… for the native macOS picker, or reopen a recent project. Cuckoding never initializes a repo."
    }

  defp onboard_copy(2, true, true, _, _),
    do: %{
      title: "Git looks healthy",
      body: "Default branch detected. Coordination stays in local SQLite."
    }

  defp onboard_copy(2, true, false, _, _),
    do: %{title: "Checking Git", body: "Open a Git repository so Cuckoding can attach worktrees."}

  defp onboard_copy(2, _, _, _, _),
    do: %{
      title: "Git and project health",
      body: "Open a repository first so we can check the default branch."
    }

  defp onboard_copy(3, _, _, ready, _) when ready > 0,
    do: %{
      title: "Providers detected",
      body: "Auth stays with each CLI. Cuckoding never reads credentials from disk."
    }

  defp onboard_copy(3, _, _, _, _),
    do: %{
      title: "Detect Codex, Claude, Cursor, and OpenCode",
      body: "Install a provider CLI, then we mark it ready. Missing CLIs stay listed."
    }

  defp onboard_copy(4, _, _, _, _),
    do: %{
      title: "Authentication readiness",
      body:
        "Sign in with the vendor CLI if needed. Cuckoding only reports whether the binary is on PATH."
    }

  defp onboard_copy(5, _, _, _, _),
    do: %{
      title: "Roles and Agent Cards",
      body:
        "Save a role if you want. Session prompts stay on the session and are never published on cards."
    }

  defp onboard_copy(6, _, _, _, _),
    do: %{
      title: "Internal A2A",
      body:
        "Agent Cards, task delegation, acknowledgements, and resource leases live here. Ack means delivered, not done."
    }

  defp onboard_copy(7, _, _, _, _),
    do: %{
      title: "Delegation policy",
      body: "Bound depth and fan-out so agents cannot recurse without limit."
    }

  defp onboard_copy(8, _, _, _, _),
    do: %{
      title: "Isolated worktrees",
      body:
        "Each tab gets its own worktree and branch. App-owned storage stays off the primary tree."
    }

  defp onboard_copy(9, _, _, _, true),
    do: %{
      title: "XERJ is on",
      body: "Search is a projection. Missing XERJ never hides SQLite coordination rows."
    }

  defp onboard_copy(9, _, _, _, _),
    do: %{
      title: "Optional XERJ indexing",
      body:
        "Enable search if the XERJ binary is installed. Coordination still works when it is off."
    }

  defp onboard_copy(10, _, _, _, _),
    do: %{
      title: "Create the first agent tab",
      body: "Start Codex, Claude, Cursor, or OpenCode above. The hub registers a safe Agent Card."
    }

  defp onboard_copy(_, _, _, _, _),
    do: %{title: "Welcome", body: "Open a Git repository to begin."}

  defp provider_name("codex"), do: "Codex"
  defp provider_name("claude"), do: "Claude"
  defp provider_name("cursor"), do: "Cursor"
  defp provider_name("opencode"), do: "OpenCode"
  defp provider_name(key), do: key

  attr :item, :map, required: true
  attr :mode, :string, default: "cards"
  attr :dom_id, :string, required: true

  def activity_card(assigns) do
    payload = activity_payload(assigns.item)

    assigns =
      assigns
      |> assign(:payload, payload)
      |> assign(:path, payload["path"] || payload["file"] || payload["uri"])
      |> assign(:output, payload["output"] || payload["stdout"] || payload["result"])
      |> assign(:command, payload["command"] || payload["cmd"] || payload["name"])
      |> assign(:diff, payload["diff"])
      |> assign(:tool, payload["tool"] || payload["mcp_tool"] || payload["server"])

    ~H"""
    <article
      id={@dom_id}
      class={["desk-activity", "desk-activity-#{@item.type}", @mode == "raw" && "desk-activity-raw"]}
    >
      <p>{activity_heading(@item.type)}</p>
      <%= if @mode == "raw" do %>
        <pre class="desk-activity-pre">{inspect(@item.payload, pretty: true, limit: 24)}</pre>
      <% else %>
        <p :if={@path} class="desk-activity-path">{@path}</p>
        <p :if={@command} class="font-mono text-xs">{@command}</p>
        <p :if={@tool} class="desk-muted text-xs">MCP {@tool}</p>
        <p class="desk-activity-body whitespace-pre-wrap">{@item.text}</p>
        <pre :if={is_binary(@diff) and @diff != ""} class="desk-activity-pre">{String.slice(@diff, 0, 4000)}</pre>
        <details :if={is_binary(@output) and @output != ""} class="desk-activity-output">
          <summary>Output</summary>
          <pre class="desk-activity-pre">{String.slice(@output, 0, 8000)}</pre>
        </details>
      <% end %>
    </article>
    """
  end

  defp activity_payload(%{payload: payload}) when is_map(payload), do: payload
  defp activity_payload(_), do: %{}

  defp activity_heading("message_delta"), do: "Agent"
  defp activity_heading("message_completed"), do: "Agent"
  defp activity_heading("reasoning"), do: "Reasoning"
  defp activity_heading("turn_started"), do: "Turn"
  defp activity_heading("turn_completed"), do: "Turn complete"
  defp activity_heading("session_ready"), do: "Ready"
  defp activity_heading("file_change"), do: "File change"
  defp activity_heading("provider_error"), do: "Error"
  defp activity_heading("approval_requested"), do: "Approval"
  defp activity_heading("command_started"), do: "Command"
  defp activity_heading("command_completed"), do: "Command"
  defp activity_heading("tool_started"), do: "MCP tool"
  defp activity_heading("tool_completed"), do: "MCP tool"
  defp activity_heading("lease_acquired"), do: "Lease"
  defp activity_heading("lease_conflict"), do: "Lease conflict"
  defp activity_heading("lease_released"), do: "Lease released"
  defp activity_heading("session_exited"), do: "Exited"
  defp activity_heading("artifact_published"), do: "Artifact"
  defp activity_heading("delegation_updated"), do: "Delegation"
  defp activity_heading("agent_card"), do: "Agent Card"
  defp activity_heading("handoff"), do: "Handoff"
  defp activity_heading("stderr"), do: "Error"
  defp activity_heading("usage"), do: "Usage"
  defp activity_heading(type) when is_binary(type), do: String.replace(type, "_", " ")
  defp activity_heading(_), do: "Activity"
end
