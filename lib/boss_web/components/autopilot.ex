defmodule BossWeb.Autopilot do
  use BossWeb, :live_component
  alias Boss.Deliveries.Autopilot, as: Engine
  alias Boss.Projects.Intake

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       project: nil,
       entries: [],
       eligible_task_ids: [],
       supported: false,
       open: false,
       batch: nil,
       intake: nil,
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
    changed = Map.get(assigns, :entries, socket.assigns.entries) != socket.assigns.entries
    socket = assign(socket, Map.take(assigns, [:id, :project, :entries, :supported]))

    socket =
      if first and documentation?(socket.assigns.project) do
        text =
          if File.regular?(Path.join(socket.assigns.project.root_path, "mix.exs")),
            do: "mix test",
            else: ""

        assign(socket, open: true, text: text)
      else
        socket
      end

    {:ok, if(first or changed, do: load(socket), else: socket)}
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
    tasks = choices(socket.assigns) |> Enum.map(& &1.task_id)

    planning? = plans_from_docs?(socket.assigns)

    if ready?(socket.assigns) and (planning? or length(tasks) in 1..256) do
      request = %{
        kind: if(planning?, do: :intake_start, else: :start),
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
      message =
        if planning?,
          do: "Wait for the current Autopilot action or inspect its saved status.",
          else: "Autopilot requires 1–256 eligible unfinished tasks for a new Start."

      {:noreply, assign(socket, error: message)}
    end
  end

  def handle_event(
        "stop_intake",
        _,
        %{assigns: %{intake: %{id: id, status: "planning"}, pending: nil, acting: false}} = socket
      ) do
    {:noreply, act(socket, %{kind: :intake_stop, id: Ecto.UUID.generate(), intake: id})}
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
        :intake_start ->
          Intake.start(project, request.id, request.text, request.reviewer)

        :intake_stop ->
          case Intake.stop(project, request.intake) do
            :ok -> {:ok, :stopping}
            result -> result
          end

        :start ->
          Engine.start(project, request.id, request.tasks, request.text, request.reviewer)

        :pause ->
          Engine.pause(project, request.batch, request.version)

        :resume ->
          Engine.resume(project, request.batch, request.version)

        :cancel ->
          Engine.cancel(project, request.batch, request.version)
      end
    end)
  end

  @impl true
  def handle_async({:load, generation}, result, %{assigns: %{generation: generation}} = socket) do
    socket =
      case result do
        {:ok, {{:ok, batch}, intake, selection}} ->
          socket = apply_load(socket, batch, intake)

          case selection do
            {:ok, ids} ->
              assign(socket, eligible_task_ids: ids)

            _ ->
              assign(socket,
                eligible_task_ids: [],
                loaded: false,
                error: "Could not load eligible tasks. Retry loading."
              )
          end

        {:ok, {:ok, batch}} ->
          apply_load(socket, batch, nil)

        {:ok, {{:ok, batch}, intake}} ->
          apply_load(socket, batch, intake)

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

  defp apply_load(socket, batch, intake) do
    reveal =
      batch && batch.status in ~w(running paused blocked) &&
        (is_nil(socket.assigns.batch) || socket.assigns.batch.id != batch.id)

    socket
    |> assign(batch: batch, intake: intake, loaded: true, open: socket.assigns.open || !!reveal)
    |> confirm_start(batch)
    |> confirm_intake(intake)
  end

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

  defp confirm_intake(
         %{assigns: %{pending: %{kind: :intake_stop, intake: id}}} = socket,
         %{id: id, status: status}
       )
       when status != "planning",
       do: assign(socket, pending: nil, error: nil, command: Ecto.UUID.generate())

  defp confirm_intake(socket, intake) do
    with %{kind: :intake_start, id: id, text: text, reviewer: reviewer} <- socket.assigns.pending,
         %{id: project} <- socket.assigns.project,
         {:ok, config, hash} <- Boss.Checks.Command.parse(text),
         %{
           command_id: ^id,
           project_id: ^project,
           check_config: ^config,
           config_hash: ^hash,
           reviewer: ^reviewer
         } <- intake do
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
    documentation? = documentation?(socket.assigns.project)

    socket
    |> assign(loading: true, generation: generation, load_again: false)
    |> start_async({:load, generation}, fn ->
      batch = Engine.current(project)
      intake = if documentation?, do: Intake.latest(project)
      {batch, intake, Engine.selection(project)}
    end)
  end

  defp value(params, key, default) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _ -> default
    end
  end

  defp choices(assigns) do
    eligible = MapSet.new(Map.get(assigns, :eligible_task_ids, []))

    Enum.filter(assigns.entries, fn entry ->
      !entry.missing and entry.state in ~w(new failed blocked needs_input) and
        MapSet.member?(eligible, entry.task_id)
    end)
  end

  defp documentation?(%{intake_mode: "documentation"}), do: true
  defp documentation?(_), do: false

  defp plans_from_docs?(assigns),
    do: documentation?(assigns.project) and !match?(%{status: "finished"}, assigns.intake)

  defp ready?(assigns),
    do:
      assigns.supported and assigns.loaded and !assigns.loading and !assigns.acting and
        is_nil(assigns.pending) and
        !match?(%{status: "planning"}, assigns.intake) and
        !match?(%{cleanup: "unknown"}, assigns.intake) and
        (is_nil(assigns.batch) or assigns.batch.status in ~w(blocked completed cancelled))

  defp error(:busy),
    do:
      "Another execution is active, another Autopilot is running or paused, or previous process cleanup is unconfirmed. Review the affected task or Autopilot; waiting or restarting does not clear unconfirmed cleanup."

  defp error(:task_queued), do: "A selected task is already queued. Review its saved request."
  defp error(:queue_full), do: "The workflow queue is full. Finish or cancel pending requests."

  defp error(:not_running), do: "Planning has already settled. Review its current status."

  defp error(:target_checked_out),
    do: "The integration target is checked out. Choose a free target before starting."

  defp error(:target_unavailable), do: "The integration target could not be verified."

  defp error(:invalid_command),
    do: "Choose a reviewer and enter a valid check command for the unfinished tasks."

  defp error(:stale_version),
    do: "Autopilot changed in another browser. Review its current status."

  defp error(:backlog_changed),
    do: "Eligible unfinished tasks changed before Start. Review the updated list and start again."

  defp error(:idempotency_conflict),
    do: "This request was already saved with different inputs. Reload Autopilot."

  defp error({:dependencies_blocked, _}),
    do: "A selected task has unresolved dependencies. Review its task details."

  defp error(_),
    do: "Autopilot could not apply this request. Review the current tasks and try again."

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        choices: choices(assigns),
        ready: ready?(assigns),
        documentation: documentation?(assigns.project),
        plans_from_docs: plans_from_docs?(assigns)
      )

    BossWeb.AutopilotPanel.panel(assigns)
  end
end
