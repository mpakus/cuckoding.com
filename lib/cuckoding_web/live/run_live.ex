defmodule CuckodingWeb.RunLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.ActivityComponents
  import CuckodingWeb.AgentFloorComponents
  import CuckodingWeb.UsageComponents

  alias Cuckoding.AgentFloor

  @refresh_ms 5_000

  @impl true
  def mount(%{"id" => run_id}, _session, socket) do
    case AgentFloor.get_run(run_id) do
      nil ->
        raise Phoenix.Router.NoRouteError, conn: socket, router: CuckodingWeb.Router

      detail ->
        if connected?(socket) do
          Cuckoding.ActivityStream.subscribe(run_id)
          Process.send_after(self(), :refresh_run, @refresh_ms)
        end

        {:ok,
         assign(socket,
           page_title: "Run #{detail.run.sequence}",
           detail: detail,
           refresh_pending: false,
           notice: ""
         )}
    end
  end

  @impl true
  def handle_info({:activity_event, stream_id, _sequence}, socket) do
    if stream_id == socket.assigns.detail.run.id and not socket.assigns.refresh_pending do
      Process.send_after(self(), :refresh_run_activity, 250)
      {:noreply, assign(socket, refresh_pending: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:refresh_run, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh_run, @refresh_ms)
    {:noreply, refresh(socket, "Run data updated.")}
  end

  def handle_info(:refresh_run_activity, socket) do
    {:noreply, refresh(socket, "Run activity updated.")}
  end

  defp refresh(socket, notice) do
    detail = AgentFloor.get_run(socket.assigns.detail.run.id)
    assign(socket, detail: detail, refresh_pending: false, notice: notice)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app>
      <article aria-labelledby="run-heading" class="space-y-8">
        <.link
          navigate={~p"/boards/#{@detail.board.id}/tasks/#{@detail.task.id}"}
          class="inline-flex min-h-10 items-center rounded underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          Back to {@detail.task.title}
        </.link>

        <header class="space-y-2">
          <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">
            {state_label(@detail.run.state)} run
          </p>
          <h1 id="run-heading" class="text-3xl font-semibold tracking-tight text-slate-950">
            Run {@detail.run.sequence}: {@detail.task.title}
          </h1>
          <p class="text-slate-700">{@detail.project.name} · <code>{@detail.run.branch}</code></p>
        </header>

        <p role="status" aria-live="polite" class="text-sm text-emerald-900">{@notice}</p>

        <nav aria-label="Run controls" class="flex flex-wrap gap-3">
          <.link
            :for={session <- @detail.sessions}
            navigate={~p"/agents/#{session.id}"}
            class="inline-flex min-h-10 items-center rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Inspect {session.adapter_key} agent
          </.link>
          <span :if={@detail.sessions == []} class="text-sm text-slate-700">No agent control is available until a session is recorded.</span>
        </nav>

        <.run_timeline attempts={@detail.attempts} />

        <section aria-labelledby="preview-heading" class="space-y-3">
          <h2 id="preview-heading" class="text-xl font-semibold text-slate-950">Preview</h2>
          <a
            :if={@detail.environment && @detail.environment.preview_url}
            href={@detail.environment.preview_url}
            target="_blank"
            rel="noreferrer"
            class="inline-flex min-h-10 items-center rounded underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2"
          >Open loopback preview</a>
          <p
            :if={!@detail.environment || !@detail.environment.preview_url}
            class="text-sm text-slate-700"
          >
            No preview is active.
          </p>
        </section>

        <section aria-labelledby="artifacts-heading" class="space-y-3">
          <h2 id="artifacts-heading" class="text-xl font-semibold text-slate-950">Artifacts</h2>
          <p :if={@detail.artifacts == []} class="text-sm text-slate-700">
            No durable artifacts recorded.
          </p>
          <ul class="divide-y divide-slate-200 rounded-lg border border-slate-300 bg-white">
            <li :for={artifact <- @detail.artifacts} class="flex justify-between gap-4 px-4 py-3">
              <span>{artifact.name}</span><span class="text-slate-600">{artifact.size} bytes</span>
            </li>
          </ul>
        </section>

        <section aria-labelledby="findings-heading" class="space-y-3">
          <h2 id="findings-heading" class="text-xl font-semibold text-slate-950">Findings</h2>
          <p :if={@detail.findings == []} class="text-sm text-slate-700">No findings recorded.</p>
          <ul class="space-y-2">
            <li
              :for={finding <- @detail.findings}
              class="rounded-md border border-slate-300 bg-white p-4"
            >
              <span class="font-semibold">{String.capitalize(finding.severity)}:</span> {finding.summary}
              <span class="text-slate-600">({finding.status})</span>
            </li>
          </ul>
        </section>

        <.usage_summary records={@detail.usage} />
        <.resource_history samples={@detail.resources} />

        <section
          aria-labelledby="knowledge-heading"
          class="rounded-lg border border-dashed border-slate-400 p-5"
        >
          <h2 id="knowledge-heading" class="text-xl font-semibold text-slate-950">Knowledge</h2>
          <p class="mt-2 text-sm text-slate-700">
            Project knowledge usage will appear here after Phase 7 publication and citation records are available.
          </p>
        </section>

        <section aria-labelledby="plugins-heading" class="space-y-3">
          <h2 id="plugins-heading" class="text-xl font-semibold text-slate-950">Plugins</h2>
          <p :if={plugin_keys(@detail.run.plugin_snapshot_json) == []} class="text-sm text-slate-700">
            No plugins were captured in this run snapshot.
          </p>
          <ul class="list-disc pl-5">
            <li :for={key <- plugin_keys(@detail.run.plugin_snapshot_json)}>{key}</li>
          </ul>
          <ul :if={@detail.optimizations != []} class="space-y-2">
            <li :for={record <- @detail.optimizations}>
              {record.plugin_key}: {Cuckoding.Telemetry.Accounting.optimization_label(record)} {record.kind}
            </li>
          </ul>
        </section>

        <.activity_stream events={@detail.activity} status={activity_status(@detail.activity)} />
      </article>
    </Layouts.app>
    """
  end

  defp activity_status(events),
    do: Cuckoding.ActivityStream.status(events, Cuckoding.Clock.wall_now(), 60_000)

  defp plugin_keys(snapshot) when is_map(snapshot), do: snapshot |> Map.keys() |> Enum.sort()
  defp plugin_keys(snapshot) when is_list(snapshot), do: Enum.map(snapshot, &to_string/1)
  defp plugin_keys(_snapshot), do: []
  defp state_label(state), do: state |> String.replace("_", " ") |> String.capitalize()
end
