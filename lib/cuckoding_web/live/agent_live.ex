defmodule CuckodingWeb.AgentLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.ActivityComponents
  import CuckodingWeb.AgentFloorComponents
  import CuckodingWeb.PolicyComponents
  import CuckodingWeb.UsageComponents

  alias Cuckoding.AgentFloor

  @refresh_ms 5_000

  @impl true
  def mount(%{"id" => session_id}, _session, socket) do
    case AgentFloor.get_session(session_id) do
      nil ->
        raise Phoenix.Router.NoRouteError, conn: socket, router: CuckodingWeb.Router

      detail ->
        if connected?(socket) do
          Cuckoding.ActivityStream.subscribe(detail.run.id)
          Process.send_after(self(), :refresh_agent, @refresh_ms)
        end

        {:ok,
         assign(socket,
           page_title: "Agent inspector",
           detail: detail,
           notice: "",
           refresh_pending: false
         )}
    end
  end

  @impl true
  def handle_info({:activity_event, stream_id, _sequence}, socket) do
    if stream_id == socket.assigns.detail.run.id and not socket.assigns.refresh_pending do
      Process.send_after(self(), :refresh_agent_activity, 250)
      {:noreply, assign(socket, refresh_pending: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:refresh_agent, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh_agent, @refresh_ms)
    {:noreply, refresh(socket, "Agent data updated.")}
  end

  def handle_info(:refresh_agent_activity, socket),
    do: {:noreply, refresh(socket, "Agent activity updated.")}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="agents">
      <article aria-labelledby="agent-heading" class="space-y-8">
        <.link
          navigate={~p"/runs/#{@detail.run.id}"}
          class="inline-flex min-h-10 items-center rounded underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2"
        >Back to run {@detail.run.sequence}</.link>

        <header class="space-y-2">
          <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">
            {state_label(@detail.attempt.state)} agent
          </p>
          <h1 id="agent-heading" class="text-3xl font-semibold tracking-tight text-slate-950">
            {AgentFloor.role_label(@detail.run, @detail.attempt.role_key)} session
          </h1>
          <p class="text-slate-700">
            {@detail.project.name} · {@detail.session.adapter_key}/{model(@detail.session)}
          </p>
          <.link
            navigate={~p"/projects/#{@detail.project.id}/edit#agents-heading"}
            class="inline-flex min-h-11 items-center rounded px-3 underline"
          >Manage project agents</.link>
        </header>

        <p role="status" aria-live="polite" class="text-sm text-emerald-900">{@notice}</p>

        <.host_runner_notice />

        <section aria-labelledby="identity-heading" class="space-y-3">
          <h2 id="identity-heading" class="text-xl font-semibold text-slate-950">Session</h2>
          <dl class="grid gap-3 rounded-lg border border-slate-300 bg-white p-4 sm:grid-cols-2">
            <div>
              <dt class="text-sm text-slate-600">Session state</dt><dd>
                {state_label(@detail.session.state)}
              </dd>
            </div>
            <div>
              <dt class="text-sm text-slate-600">Stage state</dt><dd>
                {state_label(@detail.attempt.state)}
              </dd>
            </div>
            <div>
              <dt class="text-sm text-slate-600">Active time</dt><dd>
                {@detail.attempt.active_ms} ms
              </dd>
            </div>
            <div>
              <dt class="text-sm text-slate-600">Wall time</dt><dd>{@detail.attempt.wall_ms} ms</dd>
            </div>
            <div>
              <dt class="text-sm text-slate-600">Enforced grants</dt><dd>
                {grant_keys(@detail.session, "enforced")}
              </dd>
            </div>
            <div>
              <dt class="text-sm text-slate-600">Unenforced grants</dt><dd>
                {grant_keys(@detail.session, "unenforced")}
              </dd>
            </div>
          </dl>
        </section>

        <section aria-labelledby="processes-heading" class="space-y-3">
          <h2 id="processes-heading" class="text-xl font-semibold text-slate-950">Owned processes</h2>
          <p :if={@detail.processes == []} class="text-sm text-slate-700">No process records.</p>
          <div
            :if={@detail.processes != []}
            tabindex="0"
            role="region"
            aria-label="Owned processes table"
            class="overflow-x-auto focus-visible:outline-2"
          >
            <table class="min-w-full divide-y divide-slate-200 rounded-lg border border-slate-300 bg-white text-left text-sm">
              <caption class="sr-only">Processes attributed to this agent session</caption>
              <thead>
                <tr>
                  <th class="px-3 py-2">PID</th><th class="px-3 py-2">Group</th><th class="px-3 py-2">
                    Role
                  </th><th class="px-3 py-2">State</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={process <- @detail.processes}>
                  <td class="px-3 py-2">{process.pid}</td><td class="px-3 py-2">{process.pgid}</td><td class="px-3 py-2">
                    {process.role}
                  </td><td class="px-3 py-2">{state_label(process.state)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <.usage_summary records={@detail.usage} />
        <.resource_history samples={@detail.resources} />
        <.activity_stream events={@detail.activity} status={activity_status(@detail.activity)} />
      </article>
    </Layouts.app>
    """
  end

  defp refresh(socket, notice) do
    assign(socket,
      detail: AgentFloor.get_session(socket.assigns.detail.session.id),
      notice: notice,
      refresh_pending: false
    )
  end

  defp activity_status(events),
    do: Cuckoding.ActivityStream.status(events, Cuckoding.Clock.wall_now(), 60_000)

  defp model(session), do: session.actual_model || session.requested_model || "Unknown model"
  defp state_label(state), do: state |> String.replace("_", " ") |> String.capitalize()

  defp grant_keys(session, kind) do
    session.effective_grant_json
    |> Map.get(kind, %{})
    |> Map.keys()
    |> Enum.sort()
    |> case do
      [] -> "None recorded"
      keys -> Enum.join(keys, ", ")
    end
  end
end
