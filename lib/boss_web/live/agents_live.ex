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
    <.link
      navigate={~p"/"}
      class="text-sm text-emerald-400 underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400"
    >← Projects</.link>
    <div class="mt-6 flex flex-col items-start gap-4 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <p class="text-sm font-semibold tracking-widest text-emerald-400">BOSS · LOCAL</p>
        <h1 class="mt-2 text-3xl font-semibold">Agents</h1>
      </div>
      <button
        id="detect-agents"
        type="button"
        phx-click="detect"
        disabled={@detecting}
        aria-describedby="agents-help"
        class="shrink-0 rounded-md bg-emerald-400 px-5 py-3 font-semibold text-zinc-950 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400 disabled:opacity-50"
      >{if @detecting, do: "Detecting…", else: "Detect agents"}</button>
    </div>
    <p id="agents-help" class="mt-5 text-sm leading-6 text-zinc-300">
      Detect checks the CLIs installed on this computer. It makes no model request and
      does not verify provider access or quota. Sign-in status is reported by each CLI;
      BOSS does not read credential files.
    </p>
    <p id="agents-status" role="status" class="mt-4 min-h-5 text-sm text-zinc-300">
      <%= cond do %>
        <% @detecting -> %>
          Detecting agents…
        <% @checked_at && is_nil(@error) -> %>
          Detection complete.
        <% true -> %>
          Choose Detect agents to check installed CLIs.
      <% end %>
    </p>
    <p :if={@checked_at} class="mt-2 text-sm text-zinc-400">
      Last completed scan:
      <time id="agents-checked-at" datetime={DateTime.to_iso8601(@checked_at)}>
        {Calendar.strftime(@checked_at, "%Y-%m-%d %H:%M:%S UTC")}
      </time>
    </p>
    <div
      :if={@error}
      id="agents-error"
      role="alert"
      class="mt-4 rounded-md border border-amber-900 px-4 py-3 text-sm text-amber-200"
    >
      <p>Latest scan failed. {@error}</p>
      <p :if={@checked_at} class="mt-1">Showing the last completed scan.</p>
    </div>
    <div
      id="agents"
      aria-busy={@detecting}
      class="mt-6 divide-y divide-zinc-800 border-t border-zinc-800"
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
      class="min-w-0 py-6"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h2 id={"agent-title-#{@agent.id}"} class="text-xl font-semibold">{@agent.name}</h2>
        <p class="rounded bg-zinc-800 px-2 py-1 text-sm text-zinc-300">
          {if @result, do: probe_status(@result.probe_status), else: "Not checked"}
        </p>
      </div>
      <div :if={@result} class="mt-4 space-y-4 text-sm">
        <dl class="space-y-3">
          <div>
            <dt class="text-zinc-400">Version</dt><dd class="mt-1 font-mono">
              {@result.version || "Not reported"}
            </dd>
          </div>
          <div>
            <dt class="text-zinc-400">Executable</dt><dd class="mt-1 break-all font-mono">
              {@result.path || "Not found on PATH"}
            </dd>
          </div>
          <div>
            <dt class="text-zinc-400">Local sign-in report</dt><dd class="mt-1">
              {auth_status(@result.auth_status)}
            </dd>
          </div>
        </dl>
        <div>
          <h3 class="font-semibold">Capabilities advertised by CLI help</h3>
          <dl class="mt-3 grid gap-x-6 gap-y-2 sm:grid-cols-2">
            <div
              :for={{key, label} <- @capabilities}
              data-capability={key}
              class="flex flex-wrap justify-between gap-2"
            >
              <dt class="text-zinc-400">{label}</dt><dd>
                {capability_status(@result.capabilities[key])}
              </dd>
            </div>
          </dl>
        </div>
        <ul
          :if={@result.errors != []}
          aria-label={"#{@agent.name} detection issues"}
          class="space-y-1 text-amber-200"
        >
          <li :for={error <- @result.errors}>{probe_error(error)}</li>
        </ul>
      </div>
      <div class="mt-5 space-y-2 text-sm text-zinc-300">
        <.link
          href={@agent.docs}
          class="text-emerald-400 underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400"
        >
          Official {@agent.name} installation and setup
        </.link>
        <p>
          To sign in, run
          <code class="break-all rounded bg-zinc-900 px-1 py-0.5 text-zinc-100">{@agent.login}</code>
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
