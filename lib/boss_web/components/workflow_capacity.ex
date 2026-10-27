defmodule BossWeb.WorkflowCapacity do
  use BossWeb, :live_component
  alias Boss.Deliveries.Scheduling

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(settings: nil, value: nil, pending: nil, saving: false, error: nil)
     |> start_async(:load, &Scheduling.get/0)}
  end

  @impl true
  def update(%{settings: settings} = assigns, socket),
    do: {:ok, socket |> assign(Map.take(assigns, [:id])) |> receive_settings(settings)}

  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl true
  def handle_event("edit", %{"capacity" => value}, %{assigns: %{pending: nil}} = socket) do
    {:noreply, assign(socket, value: value, error: nil)}
  end

  def handle_event("edit", _, socket), do: {:noreply, socket}

  def handle_event("save", _, %{assigns: %{saving: true}} = socket), do: {:noreply, socket}

  def handle_event("save", _, %{assigns: %{pending: request}} = socket)
      when is_map(request),
      do: {:noreply, save(socket, request)}

  def handle_event("save", %{"capacity" => value}, socket) when is_binary(value) do
    case {socket.assigns.settings, Integer.parse(value)} do
      {%{version: version}, {capacity, ""}} when capacity in 1..3 ->
        {:noreply, save(socket, %{version: version, capacity: capacity})}

      _ ->
        {:noreply, assign(socket, error: "Choose 1, 2 or 3 workers.")}
    end
  end

  def handle_event("save", _, socket),
    do: {:noreply, assign(socket, error: "Choose 1, 2 or 3 workers.")}

  def handle_event("reload", _, socket),
    do: {:noreply, socket |> assign(error: nil) |> start_async(:load, &Scheduling.get/0)}

  defp save(socket, request) do
    socket
    |> assign(pending: request, saving: true, error: nil, value: to_string(request.capacity))
    |> start_async(:save, fn -> Scheduling.set(request.version, request.capacity) end)
  end

  @impl true
  def handle_async(:load, {:ok, {:ok, settings}}, socket),
    do: {:noreply, receive_settings(socket, settings)}

  def handle_async(:load, _, socket),
    do: {:noreply, assign(socket, error: "Could not load workflow capacity. Retry loading.")}

  def handle_async(:save, {:ok, {:ok, settings}}, socket) do
    {:noreply,
     socket
     |> assign(pending: nil, saving: false, error: nil)
     |> receive_settings(settings)}
  end

  def handle_async(:save, {:ok, {:error, reason}}, socket)
      when reason in [:stale_settings, :workers_active, :invalid_capacity] do
    error =
      case reason do
        :stale_settings -> "Capacity changed elsewhere. Review the current value and save again."
        :workers_active -> "Wait for active workflows to finish before lowering this limit."
        :invalid_capacity -> "Choose 1, 2 or 3 workers."
      end

    {:noreply,
     socket
     |> assign(pending: nil, saving: false, error: error)
     |> start_async(:load, &Scheduling.get/0)}
  end

  def handle_async(:save, _, socket) do
    {:noreply,
     assign(socket,
       saving: false,
       error: "The save could not be confirmed. Retry the same capacity request."
     )}
  end

  defp receive_settings(socket, settings) do
    current = socket.assigns.settings

    latest =
      if is_nil(current) or settings.version >= current.version, do: settings, else: current

    socket = assign(socket, settings: latest)

    if socket.assigns.pending,
      do: socket,
      else: assign(socket, value: to_string(latest.max_parallel_tasks))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id={@id}
      aria-labelledby="workflow-capacity-heading"
      class="mt-5 border-t border-zinc-800 pt-4"
    >
      <h2 id="workflow-capacity-heading" class="text-sm font-semibold">Workflow capacity</h2>
      <p id="workflow-capacity-help" class="mt-1 text-xs text-zinc-400">
        Maximum active workflows across all projects. Waiting for a predicted file overlap also uses a slot.
        Manual runs and integration run exclusively.
      </p>
      <form
        :if={@settings}
        id="workflow-capacity-form"
        phx-target={@myself}
        phx-change="edit"
        phx-submit="save"
        class="mt-3 flex flex-wrap items-end gap-3"
      >
        <div>
          <label for="workflow-capacity-value" class="block text-sm">Workers</label>
          <select
            id="workflow-capacity-value"
            name="capacity"
            aria-describedby="workflow-capacity-help"
            disabled={@pending != nil}
            class="mt-1 rounded border border-zinc-600 bg-zinc-900 px-3 py-2 text-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400 disabled:opacity-50"
          >
            <option :for={count <- 1..3} value={count} selected={@value == to_string(count)}>
              {count}
            </option>
          </select>
        </div>
        <button
          id="save-workflow-capacity"
          type="submit"
          disabled={@saving}
          class="rounded border border-zinc-600 px-3 py-2 text-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400 disabled:opacity-50"
        >{cond do
          @saving -> "Saving…"
          @pending -> "Retry capacity save"
          true -> "Save capacity"
        end}</button>
        <p id="workflow-capacity-current" role="status" class="py-2 text-xs text-zinc-400">
          Current limit: {@settings.max_parallel_tasks}
        </p>
      </form>
      <p :if={!@settings && !@error} role="status" class="mt-2 text-sm text-zinc-400">
        Loading capacity…
      </p>
      <p :if={@error} id="workflow-capacity-error" role="alert" class="mt-2 text-sm text-amber-300">
        {@error}
      </p>
      <button
        :if={!@settings && @error}
        type="button"
        phx-target={@myself}
        phx-click="reload"
        class="mt-2 rounded border border-zinc-600 px-3 py-2 text-sm"
      >Retry loading</button>
    </section>
    """
  end
end
