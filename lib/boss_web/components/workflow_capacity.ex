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
  def update(%{settings: settings} = assigns, socket) do
    socket = assign(socket, Map.take(assigns, [:id]))

    {:ok,
     if(socket.assigns.settings == settings, do: socket, else: receive_settings(socket, settings))}
  end

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

  def handle_event(
        "save",
        %{"capacity" => value},
        %{assigns: %{settings: %{version: version}}} = socket
      )
      when value in ~w(1 2 3),
      do: {:noreply, save(socket, %{version: version, capacity: String.to_integer(value)})}

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
      class="relative shrink-0"
    >
      <details open={@error != nil || @pending != nil} class="group">
        <summary class="app-button-secondary gap-1.5 px-2.5 py-1.5 text-xs">
          <span id="workflow-capacity-heading" class="font-medium text-muted group-open:text-ink">
            Capacity
          </span>
          <span class="rounded bg-sage px-1.5 py-0.5 font-mono text-[11px] font-semibold text-forest">
            {if @settings, do: "#{@settings.max_parallel_tasks}×", else: "…"}
          </span>
        </summary>

        <div class="mt-1.5 w-64 rounded-lg border border-control-line bg-surface p-3 shadow-2xl sm:absolute sm:right-0 sm:z-20">
          <p id="workflow-capacity-help" class="text-[11px] leading-4 text-muted">
            Maximum active workflows across all projects. Manual runs and integration run exclusively.
          </p>
          <form
            :if={@settings}
            id="workflow-capacity-form"
            phx-target={@myself}
            phx-change="edit"
            phx-submit="save"
            class="mt-2.5 flex items-end gap-2"
          >
            <div class="flex-1">
              <label for="workflow-capacity-value" class="block text-[11px] font-medium text-muted">
                Workers
              </label>
              <select
                id="workflow-capacity-value"
                name="capacity"
                aria-describedby="workflow-capacity-help"
                disabled={@pending != nil}
                class="app-field mt-1 w-full px-2.5 py-1 text-xs"
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
              class="app-button-secondary px-3 py-1.5 text-xs"
            >{cond do
              @saving -> "Saving…"
              @pending -> "Retry capacity save"
              true -> "Save"
            end}</button>
          </form>
          <p
            :if={@settings}
            id="workflow-capacity-current"
            role="status"
            class="mt-2 font-mono text-[11px] text-muted"
          >
            Current limit: {@settings.max_parallel_tasks}
          </p>
          <p :if={!@settings && !@error} role="status" class="mt-2 text-xs text-muted">
            Loading capacity…
          </p>
          <p :if={@error} id="workflow-capacity-error" role="alert" class="mt-2 text-xs text-warning">
            {@error}
          </p>
          <button
            :if={@error && !@pending}
            type="button"
            phx-target={@myself}
            phx-click="reload"
            class="app-button-secondary mt-2 w-full py-1 text-xs"
          >Reload capacity</button>
        </div>
      </details>
    </section>
    """
  end
end
