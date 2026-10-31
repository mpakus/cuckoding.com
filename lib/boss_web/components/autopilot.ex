defmodule BossWeb.Autopilot do
  use BossWeb, :live_component
  alias Boss.Deliveries.Autopilot, as: Engine

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       project: nil,
       entries: [],
       supported: false,
       open: false,
       batch: nil,
       loaded: false,
       loading: false,
       load_again: false,
       generation: 0,
       text: "",
       reviewer: "codex",
       command: Ecto.UUID.generate(),
       pending: nil,
       acting: false,
       error: nil
     )}
  end

  @impl true
  def update(%{refresh: true}, socket), do: {:ok, load(socket)}
  def update(%{open: true}, socket), do: {:ok, assign(socket, open: true)}

  def update(assigns, socket) do
    first = is_nil(socket.assigns.project)
    socket = assign(socket, Map.take(assigns, [:id, :project, :entries, :supported]))
    {:ok, if(first, do: load(socket), else: socket)}
  end

  @impl true
  def handle_event("toggle", _, socket),
    do: {:noreply, assign(socket, open: !socket.assigns.open)}

  def handle_event("edit", params, %{assigns: %{pending: nil}} = socket) do
    {:noreply,
     assign(socket,
       text: value(params, "command", socket.assigns.text),
       reviewer: value(params, "reviewer", socket.assigns.reviewer),
       error: nil
     )}
  end

  def handle_event("edit", _, socket), do: {:noreply, socket}
  def handle_event("reload", _, socket), do: {:noreply, load(socket)}

  def handle_event("retry", _, %{assigns: %{pending: request, acting: false}} = socket)
      when is_map(request),
      do: {:noreply, act(socket, request)}

  def handle_event("start", params, socket) do
    tasks = Enum.filter(socket.assigns.entries, &eligible?/1) |> Enum.map(& &1.task_id)

    if ready?(socket.assigns) and length(tasks) in 1..256 do
      request = %{
        kind: :start,
        id: socket.assigns.command,
        tasks: tasks,
        text: value(params, "command", ""),
        reviewer: value(params, "reviewer", "codex")
      }

      {:noreply,
       socket
       |> assign(text: request.text, reviewer: request.reviewer)
       |> act(request)}
    else
      {:noreply, assign(socket, error: "Autopilot requires 1–256 tasks in the current Backlog.")}
    end
  end

  def handle_event(kind, _, %{assigns: %{batch: batch, pending: nil, acting: false}} = socket)
      when kind in ["pause", "resume", "cancel"] and is_map(batch) do
    allowed =
      case kind do
        "pause" -> batch.status == "running"
        "resume" -> batch.status == "paused"
        "cancel" -> batch.status in ["running", "paused"]
      end

    if allowed do
      request = %{
        kind: String.to_existing_atom(kind),
        id: Ecto.UUID.generate(),
        batch: batch.id,
        version: batch.version
      }

      {:noreply, act(socket, request)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp act(socket, request) do
    project = socket.assigns.project.id

    socket
    |> assign(
      pending: request,
      acting: true,
      error: nil,
      generation: socket.assigns.generation + 1,
      loading: false,
      load_again: false
    )
    |> start_async({:action, request.id}, fn ->
      case request.kind do
        :start -> Engine.start(project, request.id, request.tasks, request.text, request.reviewer)
        :pause -> Engine.pause(project, request.batch, request.version)
        :resume -> Engine.resume(project, request.batch, request.version)
        :cancel -> Engine.cancel(project, request.batch, request.version)
      end
    end)
  end

  @impl true
  def handle_async({:load, generation}, result, %{assigns: %{generation: generation}} = socket) do
    socket =
      case result do
        {:ok, {:ok, batch}} ->
          reveal =
            batch && batch.status in ~w(running paused blocked) &&
              (is_nil(socket.assigns.batch) || socket.assigns.batch.id != batch.id)

          socket
          |> assign(batch: batch, loaded: true, open: socket.assigns.open || !!reveal)
          |> confirm_start(batch)

        _ ->
          assign(socket, loaded: false, error: "Could not load Autopilot. Retry loading.")
      end

    again = socket.assigns.load_again
    socket = assign(socket, loading: false, load_again: false)
    {:noreply, if(again, do: load(socket), else: socket)}
  end

  def handle_async({:load, _}, _, socket), do: {:noreply, socket}

  def handle_async({:action, id}, result, %{assigns: %{pending: %{id: id}}} = socket) do
    socket = assign(socket, acting: false)

    case result do
      {:ok, {:ok, _}} ->
        {:noreply,
         socket
         |> assign(pending: nil, error: nil, command: Ecto.UUID.generate())
         |> load()}

      {:ok, {:error, reason}} when reason != :storage_error ->
        {:noreply, socket |> assign(pending: nil, error: error(reason)) |> load()}

      _ ->
        {:noreply,
         socket
         |> assign(
           error: "The request could not be confirmed. Retry the same saved Autopilot request."
         )
         |> load()}
    end
  end

  def handle_async(_, _, socket), do: {:noreply, socket}

  defp confirm_start(socket, batch) do
    with %{kind: :start, id: id, tasks: tasks, text: text, reviewer: reviewer} <-
           socket.assigns.pending,
         %{id: project} when is_integer(project) and project > 0 <- socket.assigns.project,
         true <- is_binary(id) and is_list(tasks) and reviewer in ~w(codex claude),
         {:ok, config, hash} <- Boss.Checks.Command.parse(text),
         %{
           command_id: ^id,
           project_id: ^project,
           task_ids: ^tasks,
           check_config: ^config,
           config_hash: ^hash,
           reviewer: ^reviewer
         } <- batch do
      assign(socket, pending: nil, error: nil, command: Ecto.UUID.generate())
    else
      _ -> socket
    end
  end

  defp load(%{assigns: %{project: nil}} = socket), do: socket
  defp load(%{assigns: %{acting: true}} = socket), do: assign(socket, load_again: true)
  defp load(%{assigns: %{loading: true}} = socket), do: assign(socket, load_again: true)

  defp load(socket) do
    project = socket.assigns.project.id
    generation = socket.assigns.generation + 1

    socket
    |> assign(loading: true, generation: generation, load_again: false)
    |> start_async({:load, generation}, fn -> Engine.current(project) end)
  end

  defp value(params, key, default) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _ -> default
    end
  end

  defp eligible?(entry),
    do: !entry.missing and entry.state == "new"

  defp ready?(assigns),
    do:
      assigns.supported and assigns.loaded and !assigns.acting and is_nil(assigns.pending) and
        (is_nil(assigns.batch) or assigns.batch.status in ~w(blocked completed cancelled))

  defp error(:busy),
    do:
      "Another execution is active, another Autopilot is running or paused, or previous process cleanup is unconfirmed. Review the affected task or Autopilot; waiting or restarting does not clear unconfirmed cleanup."

  defp error(:task_queued), do: "A selected task is already queued. Review its saved request."
  defp error(:queue_full), do: "The workflow queue is full. Finish or cancel pending requests."

  defp error(:invalid_command),
    do: "Choose a reviewer and enter a valid check command for the current Backlog."

  defp error(:stale_version),
    do: "Autopilot changed in another browser. Review its current status."

  defp error(:backlog_changed),
    do: "Backlog changed before Start. Review the updated list and start again."

  defp error(:idempotency_conflict),
    do: "This request was already saved with different inputs. Reload Autopilot."

  defp error({:dependencies_blocked, _}),
    do: "A selected task has unresolved dependencies. Review its task details."

  defp error(_),
    do: "Autopilot could not apply this request. Review the current tasks and try again."

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, choices: Enum.filter(assigns.entries, &eligible?/1), ready: ready?(assigns))

    BossWeb.AutopilotPanel.panel(assigns)
  end
end
