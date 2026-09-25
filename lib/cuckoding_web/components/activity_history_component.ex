defmodule CuckodingWeb.ActivityHistoryComponent do
  @moduledoc "Bounded, read-only LiveView history shared by run and task pages."
  use Phoenix.LiveComponent

  import CuckodingWeb.ActivityComponents
  alias Cuckoding.ActivityStream

  @impl true
  def update(assigns, socket) do
    previous_scope = socket.assigns[:scope]

    socket =
      if previous_scope,
        do: socket,
        else: stream_configure(socket, :events, dom_id: &"activity-#{&1.id}")

    socket = assign(socket, assigns)

    {:ok,
     if previous_scope != socket.assigns.scope do
       latest(socket)
     else
       refresh(socket)
     end}
  end

  @impl true
  def handle_event("older-activity", _params, socket) do
    if socket.assigns.has_older do
      page = page(socket, before: List.last(socket.assigns.window))
      window = Enum.take(socket.assigns.window ++ Enum.map(page.events, &cursor/1), -90)

      {:noreply,
       socket
       |> assign(window: window, has_older: page.more?, browsing: true)
       |> stream(:events, page.events, at: -1, limit: -90)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("newer-activity", %{"_overran" => true}, socket),
    do: {:noreply, socket |> latest() |> push_event("activity:latest", %{})}

  def handle_event("newer-activity", _params, %{assigns: %{window: []}} = socket),
    do: {:noreply, socket}

  def handle_event("newer-activity", _params, socket) do
    page = page(socket, after: hd(socket.assigns.window))
    window = Enum.map(page.events, &cursor/1) ++ socket.assigns.window

    {:noreply,
     socket
     |> assign(
       window: Enum.take(window, 90),
       has_older: socket.assigns.has_older or length(window) > 90
     )
     |> stream(:events, Enum.reverse(page.events), at: 0, limit: 90)}
  end

  def handle_event("latest-activity", _params, socket),
    do: {:noreply, socket |> latest() |> push_event("activity:latest", %{})}

  defp latest(socket) do
    page = page(socket)

    socket
    |> assign(window: Enum.map(page.events, &cursor/1), has_older: page.more?, browsing: false)
    |> observe_latest(page)
    |> stream(:events, page.events, reset: true, limit: 30)
  end

  defp refresh(socket) do
    page = page(socket)

    if socket.assigns.browsing do
      observe_latest(socket, page)
    else
      new_events = Enum.filter(page.events, &(cursor(&1) > socket.assigns.latest))

      socket
      |> assign(window: Enum.map(page.events, &cursor/1), has_older: page.more?)
      |> observe_latest(page)
      |> stream(:events, Enum.reverse(new_events), at: 0, limit: 30)
    end
  end

  defp observe_latest(socket, page) do
    assign(socket,
      latest: if(page.events == [], do: {0, 0}, else: cursor(hd(page.events))),
      status: ActivityStream.status(Enum.reverse(page.events), Cuckoding.Clock.wall_now(), 60_000)
    )
  end

  defp page(socket, options \\ [])
  defp page(%{assigns: %{scope: {:task, id}}}, options), do: ActivityStream.task_page(id, options)

  defp page(%{assigns: %{scope: {:run, id}}}, options) do
    ActivityStream.page(id, Enum.map(options, fn {key, {_run, sequence}} -> {key, sequence} end))
  end

  defp cursor(event), do: {Map.get(event, :run_sequence, 0), event.sequence}

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="min-w-0">
      <.activity_history
        events={@streams.events}
        window={@window}
        has_older={@has_older}
        has_newer={@window != [] && hd(@window) < @latest}
        browsing={@browsing}
        status={@status}
        run_state={@run_state}
        run={@run}
        target={@myself}
        heading={@heading}
        heading_id={@heading_id}
        events_id={@events_id}
      />
    </div>
    """
  end
end
