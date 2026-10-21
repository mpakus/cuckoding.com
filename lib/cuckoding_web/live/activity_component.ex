defmodule CuckodingWeb.ActivityComponent do
  @moduledoc false
  use CuckodingWeb, :live_component
  alias Cuckoding.Dashboard

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(
       follow: true,
       before: nil,
       history: [],
       loaded: false,
       page: %{rows: [], more?: false}
     )
     |> CuckodingWeb.SessionAuth.guard_events()}
  end

  @impl true
  def update(assigns, socket) do
    changed = not socket.assigns.loaded or socket.assigns[:arena_id] != assigns.arena_id
    socket = socket |> assign(assigns) |> assign(:loaded, true)
    socket = if changed, do: assign(socket, follow: true, before: nil, history: []), else: socket
    {:ok, if(socket.assigns.follow or changed, do: reload(socket), else: socket)}
  end

  @impl true
  def handle_event("older", _, %{assigns: %{page: %{rows: [oldest | _], more?: true}}} = socket) do
    {:noreply,
     socket
     |> assign(
       follow: false,
       before: oldest.id,
       history: [socket.assigns.before | socket.assigns.history]
     )
     |> reload()}
  end

  def handle_event("newer", _, %{assigns: %{history: [cursor | history]}} = socket),
    do: {:noreply, socket |> assign(before: cursor, history: history, follow: false) |> reload()}

  def handle_event("latest", _, socket),
    do: {:noreply, socket |> assign(follow: true, before: nil, history: []) |> reload()}

  def handle_event("follow", _, socket) do
    if socket.assigns.follow,
      do: {:noreply, assign(socket, :follow, false)},
      else: handle_event("latest", %{}, socket)
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp reload(socket),
    do: assign(socket, :page, Dashboard.activity(socket.assigns.arena_id, socket.assigns.before))

  defp label(kind), do: kind |> String.replace([".", "_"], " ") |> String.capitalize()

  @impl true
  def render(assigns) do
    ~H"""
    <details
      id={@id}
      class="activity retained-activity"
      phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
    >
      <summary>Activity · {if @follow, do: "Live", else: "Reading saved activity"}</summary>
      <div class="team-actions" aria-label="Activity controls">
        <button
          type="button"
          class="button"
          phx-click="follow"
          phx-target={@myself}
          aria-pressed={to_string(@follow)}
        >
          {if @follow, do: "Pause updates", else: "Follow latest"}
        </button>
        <button
          type="button"
          class="button"
          phx-click="older"
          phx-target={@myself}
          disabled={!@page.more?}
        >Older</button>
        <button
          type="button"
          class="button"
          phx-click="newer"
          phx-target={@myself}
          disabled={@history == []}
        >Newer</button>
      </div>
      <p :if={@page.rows == []} class="fine-print">No saved activity yet.</p>
      <ol
        id={@id <> "-entries"}
        class="activity-entries"
        phx-hook="ActivityFollow"
        data-follow={to_string(@follow)}
        tabindex="0"
        aria-label="Saved activity"
      >
        <li :for={event <- @page.rows} id={@id <> "-event-#{event.id}"}>
          <time datetime={DateTime.to_iso8601(event.occurred_at)}>{Calendar.strftime(
            event.occurred_at,
            "%m-%d %H:%M:%S UTC"
          )}</time>
          {label(event.kind)}
        </li>
      </ol>
      <p class="fine-print">
        Up to 20 saved events per page. Open a task to inspect its retained evidence.
      </p>
    </details>
    """
  end
end
