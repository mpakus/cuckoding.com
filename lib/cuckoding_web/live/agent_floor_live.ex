defmodule CuckodingWeb.AgentFloorLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.AgentFloorComponents

  alias Cuckoding.AgentFloor

  @groups ~w(role runtime project)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Cuckoding.ActivityStream.subscribe(:all)

    {:ok,
     assign(socket,
       page_title: "Agent Floor",
       group_by: "role",
       group_options: @groups,
       cards: [],
       lane_groups: [],
       refresh_pending: false,
       notice: ""
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    group_by = if params["group"] in @groups, do: params["group"], else: "role"
    {:noreply, socket |> assign(:group_by, group_by) |> load_cards()}
  end

  @impl true
  def handle_event("group", %{"group" => group_by}, socket) do
    {:noreply, push_patch(socket, to: ~p"/agents?group=#{group_by}")}
  end

  @impl true
  def handle_info(
        {:activity_event, _stream_id, _sequence},
        %{assigns: %{refresh_pending: false}} = socket
      ) do
    Process.send_after(self(), :refresh_floor, 250)
    {:noreply, assign(socket, refresh_pending: true)}
  end

  def handle_info({:activity_event, _stream_id, _sequence}, socket), do: {:noreply, socket}

  def handle_info(:refresh_floor, socket) do
    {:noreply,
     socket
     |> assign(refresh_pending: false, notice: "Agent Floor updated.")
     |> load_cards()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app>
      <section aria-labelledby="agent-floor-heading" class="space-y-8">
        <header class="space-y-2">
          <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">Live operations</p>
          <h1 id="agent-floor-heading" class="text-3xl font-semibold tracking-tight text-slate-950">
            Agent Floor
          </h1>
          <p class="max-w-3xl text-slate-700">
            Durable agent sessions, their handoffs, attention state, resource use, and safe inspection controls.
          </p>
        </header>

        <form
          id="agent-floor-group"
          phx-change="group"
          aria-label="Group Agent Floor"
          class="max-w-xs"
        >
          <label class="grid gap-1 font-medium text-slate-800">
            Group lanes
            <select
              name="group"
              class="min-h-10 rounded-md border border-slate-400 bg-white px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
            >
              <option :for={group <- @group_options} value={group} selected={@group_by == group}>
                {String.capitalize(group)}
              </option>
            </select>
          </label>
        </form>

        <p role="status" aria-live="polite" class="text-sm text-emerald-900">{@notice}</p>
        <p :if={@cards == []} class="rounded-md border border-slate-300 p-5 text-slate-700">
          No agent sessions have been recorded.
        </p>
        <.agent_floor :if={@cards != []} groups={@lane_groups} cards={@cards} group_by={@group_by} />
      </section>
    </Layouts.app>
    """
  end

  defp load_cards(socket) do
    cards = AgentFloor.list_sessions()

    assign(socket,
      cards: cards,
      lane_groups: AgentFloor.group_sessions(cards, socket.assigns.group_by)
    )
  end
end
