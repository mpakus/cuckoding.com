defmodule BossWeb.AgentsLive do
  use BossWeb, :live_view

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
    {:ok,
     assign(socket,
       page_title: "Agents · BOSS",
       agents: @agents,
       results: %{},
       detecting: false,
       checked_at: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event("detect", _, %{assigns: %{detecting: true}} = socket), do: {:noreply, socket}

  def handle_event("detect", _, socket) do
    detector = Application.get_env(:boss, :agent_detector, Boss.Agents.Detector)

    {:noreply,
     socket
     |> assign(detecting: true, error: nil)
     |> start_async(:detect, fn -> detector.scan() end)}
  end

  @impl true
  def handle_async(:detect, {:ok, {:ok, results}}, socket) do
    {:noreply,
     assign(socket,
       results: Map.new(results, &{&1.id, &1}),
       detecting: false,
       checked_at: DateTime.utc_now() |> DateTime.truncate(:second),
       error: nil
     )}
  end

  def handle_async(:detect, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, detecting: false, error: scan_error(reason))}

  def handle_async(:detect, _failure, socket),
    do: {:noreply, assign(socket, detecting: false, error: scan_error(:cancelled))}

  @impl true
  def render(assigns) do
    ~H"""
    <header class="app-page-header flex flex-col items-start gap-5 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <p class="app-eyebrow">Local tools</p>
        <h1 class="app-page-title">Agents</h1>
        <p class="app-page-description">Your tools. Your accounts. One workspace.</p>
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
    <div class="border-y border-line py-5">
      <p id="agents-help" class="max-w-3xl text-sm leading-6 text-body">
        Detect checks the CLIs installed on this computer. It makes no model request and
        does not verify provider access or quota. Sign-in status is reported by each CLI;
        BOSS does not read credential files.
      </p>
      <p id="agents-status" role="status" class="mt-3 min-h-5 text-sm font-medium text-ink">
        <%= cond do %>
          <% @detecting -> %>
            Detecting agents…
          <% @checked_at && is_nil(@error) -> %>
            Detection complete.
          <% true -> %>
            Choose Detect agents to check installed CLIs.
        <% end %>
      </p>
      <p :if={@checked_at} class="mt-2 text-sm text-muted">
        Last completed scan:
        <time id="agents-checked-at" datetime={DateTime.to_iso8601(@checked_at)}>
          {Calendar.strftime(@checked_at, "%Y-%m-%d %H:%M:%S UTC")}
        </time>
      </p>
    </div>
    <div
      :if={@error}
      id="agents-error"
      role="alert"
      class="mt-4 rounded-sm border border-warning-line px-4 py-3 text-sm text-warning bg-warning-soft"
    >
      <p>Latest scan failed. {@error}</p>
      <p :if={@checked_at} class="mt-1">Showing the last completed scan.</p>
    </div>
    <div
      id="agents"
      aria-busy={@detecting}
      class="mt-6 grid min-w-0 gap-6 md:grid-cols-2"
    >
      <.agent :for={agent <- @agents} agent={agent} result={@results[agent.id]} />
    </div>
    """
  end

  attr :agent, :map, required: true
  attr :result, :any, required: true

  defp agent(assigns) do
    assigns = assign(assigns, capabilities: @capabilities)

    ~H"""
    <section
      id={"agent-#{@agent.id}"}
      aria-labelledby={"agent-title-#{@agent.id}"}
      class="app-panel flex min-w-0 flex-col"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h2 id={"agent-title-#{@agent.id}"} class="app-panel-heading">{@agent.name}</h2>
        <p class="app-badge">
          {if @result, do: probe_status(@result.probe_status), else: "Not checked"}
        </p>
      </div>
      <div :if={@result} class="mt-4 space-y-4 text-sm">
        <dl class="space-y-3">
          <div>
            <dt class="text-muted">Version</dt><dd class="mt-1 font-mono">
              {@result.version || "Not reported"}
            </dd>
          </div>
          <div>
            <dt class="text-muted">Executable</dt><dd class="mt-1 break-all font-mono">
              {@result.path || "Not found on PATH"}
            </dd>
          </div>
          <div>
            <dt class="text-muted">Local sign-in report</dt><dd class="mt-1">
              {auth_status(@result.auth_status)}
            </dd>
          </div>
        </dl>
        <div>
          <h3 class="font-semibold">Capabilities advertised by CLI help</h3>
          <dl class="mt-3 space-y-2 border-t border-line pt-3">
            <div
              :for={{key, label} <- @capabilities}
              data-capability={key}
              class="flex flex-wrap justify-between gap-2"
            >
              <dt class="text-muted">{label}</dt><dd>
                {capability_status(@result.capabilities[key])}
              </dd>
            </div>
          </dl>
        </div>
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
          To sign in, run
          <code class="break-all rounded bg-surface px-1 py-0.5 text-ink">{@agent.login}</code>
          in your terminal.
        </p>
      </div>
    </section>
    """
  end

  defp probe_status(:ok), do: "CLI metadata recognized"
  defp probe_status(:missing), do: "Not found on PATH"
  defp probe_status(:unsupported), do: "CLI metadata unsupported"
  defp probe_status(_), do: "Detection incomplete"

  defp auth_status(:configured), do: "CLI reports credentials configured"
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

  defp scan_error(:busy), do: "Another detection is running. Try Detect agents again shortly."
  defp scan_error(:cancelled), do: "Detection was interrupted. Try again."
  defp scan_error(_), do: "Agent detection is unavailable. Try again."
end
