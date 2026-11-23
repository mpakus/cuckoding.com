defmodule BossWeb.Autopilot do
  use BossWeb, :live_component
  alias Boss.Agents.Roles
  alias Boss.Deliveries.Autopilot, as: Engine
  alias Boss.Projects.{Documentation, Intake}

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
       intake_attempts: [],
       loaded: false,
       loading: false,
       load_again: false,
       generation: 0,
       text: "",
       reviewer: "codex",
       reviewer_edited: false,
       brief_selection: nil,
       reviewers: Roles.reviewer_choices(),
       spec_loop: true,
       command: Ecto.UUID.generate(),
       pending: nil,
       acting: false,
       active_blocker: nil,
       stopping_blocker: false,
       error: nil
     )}
  end

  @impl true
  def update(%{refresh: true}, socket), do: {:ok, load(socket)}
  def update(%{open: true}, socket), do: {:ok, assign(socket, open: true)}

  def update(assigns, socket) do
    first = is_nil(socket.assigns.project)

    converted =
      !documentation?(socket.assigns.project) and
        documentation?(Map.get(assigns, :project, socket.assigns.project))

    changed =
      Map.get(assigns, :entries, socket.assigns.entries) != socket.assigns.entries or
        Map.get(assigns, :project, socket.assigns.project) != socket.assigns.project

    socket = assign(socket, Map.take(assigns, [:id, :project, :entries, :supported]))

    socket =
      if (first or converted) and documentation?(socket.assigns.project) do
        assign(socket, open: true)
      else
        socket
      end

    {:ok, if(first or changed, do: load(socket), else: socket)}
  end

  @impl true
  def handle_event("toggle", _, socket),
    do: {:noreply, assign(socket, open: !socket.assigns.open)}

  def handle_event("edit", params, %{assigns: %{pending: nil}} = socket) do
    explicit_reviewer? =
      case Map.get(params, "reviewer") do
        r when is_binary(r) and r != "" -> true
        _ -> false
      end

    next_reviewer =
      if explicit_reviewer?,
        do: params["reviewer"],
        else: socket.assigns.reviewer

    spec_loop =
      case Map.get(params, "spec_loop") do
        "true" -> true
        "false" -> false
        _ -> socket.assigns.spec_loop
      end

    pin = Map.get(socket.assigns, :brief_selection)

    {:noreply,
     assign(socket,
       text: if(pin, do: pin.check_text, else: value(params, "command", socket.assigns.text)),
       reviewer: if(pin, do: pin.reviewer, else: next_reviewer),
       reviewer_edited: socket.assigns.reviewer_edited or explicit_reviewer?,
       spec_loop: spec_loop,
       error: nil
     )}
  end

  def handle_event("edit", _, socket), do: {:noreply, socket}
  def handle_event("reload", _, socket), do: {:noreply, load(socket)}

  def handle_event(
        "recover_interrupted",
        _,
        %{assigns: %{project: %{id: project_id}, pending: nil, acting: false}} = socket
      ) do
    _ = Boss.Deliveries.requeue_interrupted_tasks(project_id)
    {:noreply, load(socket)}
  end

  def handle_event("recover_interrupted", _, socket), do: {:noreply, socket}

  def handle_event(
        "stop_blocking_delivery",
        %{"delivery-id" => delivery_id},
        %{assigns: %{project: %{id: project_id}, pending: nil, acting: false}} = socket
      )
      when is_binary(delivery_id) do
    if Map.get(socket.assigns, :stopping_blocker, false) do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(stopping_blocker: true, error: nil)
       |> start_async({:stop_blocker, delivery_id}, fn ->
         Boss.Deliveries.stop_for_autopilot(project_id, delivery_id)
       end)}
    end
  end

  def handle_event("stop_blocking_delivery", _, socket), do: {:noreply, socket}

  def handle_event("plan_from_documentation", %{"command-id" => id}, socket) do
    if id == socket.assigns.command and conversion_ready?(socket.assigns) do
      {:noreply, act(socket, %{kind: :documentation_convert, id: id})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("retry", _, %{assigns: %{pending: request, acting: false}} = socket)
      when is_map(request),
      do: {:noreply, act(socket, request)}

  def handle_event(event, params, socket) when event in ["start", "replan"] do
    tasks = choices(socket.assigns) |> Enum.map(& &1.task_id)
    interrupted = interrupted_tasks(socket.assigns)

    replan_source = socket.assigns.intake && Map.get(socket.assigns.intake, :replan_source_id)
    previous = params["previous_intake_id"]
    replanning? = event == "replan" and is_binary(previous) and previous == replan_source
    planning? = plans_from_docs?(socket.assigns) or replanning?

    explicit_reviewer =
      case Map.get(params, "reviewer") do
        r when is_binary(r) and r != "" -> r
        _ -> nil
      end

    pin = Map.get(socket.assigns, :brief_selection)
    text = value(params, "command", if(pin, do: pin.check_text, else: ""))

    reviewer =
      cond do
        is_binary(explicit_reviewer) ->
          explicit_reviewer

        pin ->
          pin.reviewer

        socket.assigns.reviewer_edited ->
          socket.assigns.reviewer

        socket.assigns.project != nil ->
          Boss.Projects.RoleBindings.reviewer_agent(socket.assigns.project.id)

        true ->
          socket.assigns.reviewer
      end

    spec_loop =
      case Map.get(params, "spec_loop") do
        "false" -> false
        "true" -> true
        _ -> socket.assigns.spec_loop
      end

    cond do
      event == "replan" and !replanning? ->
        {:noreply, assign(socket, error: error(:replan_unavailable))}

      pin && (pin.check_text != text || pin.reviewer != reviewer) ->
        {:noreply, assign(socket, error: error(:brief_policy_mismatch))}

      not Boss.Agents.Metadata.review_runner?(reviewer) ->
        {:noreply, assign(socket, error: "Choose an agent from the Independent reviewer list.")}

      ready?(socket.assigns) and
          (planning? or length(tasks) in 1..256 or interrupted != []) ->
        request = %{
          kind: if(planning?, do: :intake_start, else: :start),
          previous_intake_id: if(replanning?, do: previous),
          id: socket.assigns.command,
          tasks: tasks,
          auto_recover_interrupted: interrupted != [],
          spec_loop: spec_loop,
          text: text,
          reviewer: reviewer
        }

        {:noreply,
         socket
         |> assign(
           text: request.text,
           reviewer: request.reviewer,
           reviewer_edited: socket.assigns.reviewer_edited or is_binary(explicit_reviewer),
           spec_loop: spec_loop
         )
         |> act(request)}

      true ->
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
        :documentation_convert ->
          Documentation.convert(project, request.id)

        :intake_start ->
          if previous = Map.get(request, :previous_intake_id) do
            Intake.replan(
              project,
              request.id,
              request.text,
              request.reviewer,
              request.spec_loop,
              previous
            )
          else
            Intake.start(project, request.id, request.text, request.reviewer, request.spec_loop)
          end

        :intake_stop ->
          case Intake.stop(project, request.intake) do
            :ok -> {:ok, :stopping}
            result -> result
          end

        :start ->
          tasks =
            if Map.get(request, :auto_recover_interrupted, false) and
                 (request.tasks == [] or
                    not Enum.any?(
                      request.tasks,
                      &(Boss.Tasks.Dependencies.check(project, &1) == :ok)
                    )) do
              _ = Boss.Deliveries.requeue_interrupted_tasks(project)

              case Engine.selection(project) do
                {:ok, ids} when ids != [] -> ids
                _ -> request.tasks
              end
            else
              request.tasks
            end

          pool_size = Boss.Projects.RoleBindings.implementer_pool_size(project)
          spec_loop? = Map.get(request, :spec_loop, true)

          if pool_size > 1 or spec_loop? do
            Engine.start_loop(project, request.id, tasks, request.text, request.reviewer,
              parallel: pool_size > 1,
              spec_loop: spec_loop?
            )
          else
            Engine.start(project, request.id, tasks, request.text, request.reviewer)
          end

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
        {:ok, {batch, intake, selection, conversion, attempts, reviewers, blocker}} ->
          saved_reviewer =
            case batch do
              {:ok, %{reviewer: r}} when is_binary(r) -> r
              _ -> nil
            end

          socket
          |> assign(intake_attempts: attempts, active_blocker: blocker)
          |> keep_reviewer(reviewers, saved_reviewer)
          |> confirm_conversion(conversion)
          |> apply_selection(batch, intake, selection)

        {:ok, {batch, intake, selection, conversion, attempts, reviewers}} ->
          saved_reviewer =
            case batch do
              {:ok, %{reviewer: r}} when is_binary(r) -> r
              _ -> nil
            end

          socket
          |> assign(intake_attempts: attempts)
          |> keep_reviewer(reviewers, saved_reviewer)
          |> confirm_conversion(conversion)
          |> apply_selection(batch, intake, selection)

        {:ok, {batch, intake, selection, conversion, attempts}} ->
          socket
          |> assign(intake_attempts: attempts)
          |> confirm_conversion(conversion)
          |> apply_selection(batch, intake, selection)

        {:ok, {batch, intake, selection, conversion}} ->
          socket
          |> confirm_conversion(conversion)
          |> apply_selection(batch, intake, selection)

        {:ok, {{:ok, batch}, intake, selection}} ->
          apply_selection(socket, {:ok, batch}, intake, selection)

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

  def handle_async({:stop_blocker, _delivery_id}, result, socket) do
    socket = assign(socket, stopping_blocker: false)

    case result do
      {:ok, {:ok, _}} ->
        {:noreply, socket |> assign(active_blocker: nil, error: nil) |> load()}

      _ ->
        {:noreply,
         socket
         |> assign(
           error: "Could not stop the active workflow. Inspect the task details and try again."
         )
         |> load()}
    end
  end

  def handle_async(_, _, socket), do: {:noreply, socket}

  defp apply_selection(socket, {:ok, batch}, intake, selection) do
    socket = apply_load(socket, batch, intake)

    case selection do
      {:ok, ids} ->
        pin =
          case intake do
            %{brief_task: %{id: id, state: state}} ->
              if id in ids or state == "interrupted",
                do: Map.take(intake, [:check_text, :reviewer])

            _ ->
              nil
          end

        socket = assign(socket, eligible_task_ids: ids, brief_selection: pin)

        if pin && is_nil(socket.assigns.pending),
          do: assign(socket, text: pin.check_text, reviewer: pin.reviewer),
          else: socket

      _ ->
        assign(socket,
          eligible_task_ids: [],
          loaded: false,
          error: "Could not load eligible tasks. Retry loading."
        )
    end
  end

  defp apply_selection(socket, _, _, _),
    do: assign(socket, loaded: false, error: "Could not load Autopilot. Retry loading.")

  defp confirm_conversion(socket, receipt) do
    with %{kind: :documentation_convert, id: id} <- socket.assigns.pending,
         %{id: project} <- socket.assigns.project,
         %{project_id: ^project, command_id: ^id} <- receipt do
      send(self(), {:project_documentation, project})
      assign(socket, pending: nil, error: nil, command: Ecto.UUID.generate())
    else
      _ -> socket
    end
  end

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
    with %{kind: :start, id: id, tasks: tasks, text: text, reviewer: reviewer} = pending <-
           socket.assigns.pending,
         %{id: project} when is_integer(project) and project > 0 <- socket.assigns.project,
         true <-
           is_binary(id) and is_list(tasks) and Boss.Agents.Metadata.review_runner?(reviewer),
         {:ok, config, hash} <- Boss.Checks.Command.parse_workflow(text),
         %{
           command_id: ^id,
           project_id: ^project,
           task_ids: saved_tasks,
           check_config: ^config,
           config_hash: ^hash,
           reviewer: ^reviewer
         } <- batch,
         true <-
           saved_tasks == tasks or
             (Map.get(pending, :auto_recover_interrupted, false) and is_list(saved_tasks)) do
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
    with %{
           kind: :intake_start,
           id: id,
           text: text,
           reviewer: reviewer,
           spec_loop: spec_loop,
           previous_intake_id: previous
         } <- socket.assigns.pending,
         %{id: project} <- socket.assigns.project,
         {:ok, config, hash} <- Boss.Checks.Command.parse_workflow(text),
         %{
           command_id: ^id,
           project_id: ^project,
           check_config: ^config,
           config_hash: ^hash,
           reviewer: ^reviewer,
           start_policy: %{
             "version" => 1,
             "spec_loop" => ^spec_loop,
             "previous_intake_id" => ^previous
           }
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
    pending = socket.assigns.pending

    socket
    |> assign(loading: true, generation: generation, load_again: false)
    |> start_async({:load, generation}, fn ->
      batch = Engine.current(project)
      intake = if documentation?, do: Intake.latest(project)
      attempts = if intake, do: Intake.attempts(intake.id), else: []

      conversion =
        case pending do
          %{kind: :documentation_convert, id: id} -> Documentation.get(project, id)
          _ -> nil
        end

      {batch, intake, Engine.selection(project), conversion, attempts,
       Roles.reviewer_choices(project), Boss.Deliveries.autopilot_blocker(project)}
    end)
  end

  defp keep_reviewer(socket, reviewers, saved_reviewer) do
    ids = Enum.map(reviewers, & &1.id)
    current = socket.assigns.reviewer

    project_rev =
      if socket.assigns.project do
        Boss.Projects.RoleBindings.reviewer_agent(socket.assigns.project.id)
      end

    chosen =
      cond do
        !socket.assigns.reviewer_edited and is_binary(project_rev) and
            Boss.Agents.Metadata.review_runner?(project_rev) ->
          project_rev

        !socket.assigns.reviewer_edited and is_binary(saved_reviewer) and saved_reviewer in ids ->
          saved_reviewer

        current in ids ->
          current

        "codex" in ids ->
          "codex"

        "claude" in ids ->
          "claude"

        ids != [] ->
          hd(ids)

        true ->
          "codex"
      end

    assign(socket, reviewers: reviewers, reviewer: chosen)
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
      !Map.get(entry, :reference_only, false) and !entry.missing and
        entry.state in ~w(new failed blocked needs_input) and
        MapSet.member?(eligible, entry.task_id)
    end)
  end

  defp documentation?(%{intake_mode: "documentation"}), do: true
  defp documentation?(_), do: false

  defp plans_from_docs?(assigns) do
    documentation?(assigns.project) and !match?(%{status: "finished"}, assigns.intake) and
      !Enum.any?(assigns.entries, &(!Map.get(&1, :reference_only, false)))
  end

  defp ready?(assigns),
    do:
      assigns.supported and assigns.loaded and !assigns.loading and !assigns.acting and
        is_nil(assigns.pending) and
        !match?(%{status: "planning"}, assigns.intake) and
        !match?(%{cleanup: "unknown"}, assigns.intake) and
        (is_nil(assigns.batch) or assigns.batch.status in ~w(blocked completed cancelled))

  defp conversion_ready?(assigns),
    do:
      !documentation?(assigns.project) and assigns.loaded and !assigns.loading and
        !assigns.acting and is_nil(assigns.pending) and
        (is_nil(assigns.batch) or assigns.batch.status in ~w(blocked completed cancelled))

  defp error(:already_documentation), do: "This project already plans from documentation."
  defp error(:too_many_sources), do: "This project has too many source documents to convert."

  defp error(:invalid_sources),
    do: "The saved sources could not be converted. Refresh the project."

  defp error(:busy),
    do:
      "Another execution is active, another Autopilot is running or paused, or previous process cleanup is unconfirmed. Review the affected task or Autopilot; waiting or restarting does not clear unconfirmed cleanup."

  defp error(:replan_unavailable),
    do: "Replanning requires a verified whole-brief delivery with every executable task Done."

  defp error(:brief_policy_mismatch),
    do: "Use the check command and reviewer saved with the original documentation Start."

  defp error(:brief_check_required),
    do:
      "Enter a trusted CLI check for the finished application before starting documentation planning."

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

  defp interrupted_tasks(assigns) do
    Enum.filter(assigns.entries, fn entry ->
      !Map.get(entry, :reference_only, false) and !entry.missing and
        entry.state == "interrupted"
    end)
  end

  @impl true
  def render(assigns) do
    pool_size =
      if assigns.project,
        do: Boss.Projects.RoleBindings.implementer_pool_size(assigns.project.id),
        else: 1

    reviewer_tag =
      if assigns.project && !Map.get(assigns, :brief_selection) do
        get_in(Boss.Projects.RoleBindings.for_project(assigns.project.id), [
          "reviewer",
          :active,
          :tag
        ])
      end

    loop_cfg = if assigns.batch, do: Engine.loop_info(assigns.batch.id)

    assigns =
      assign(assigns,
        choices: choices(assigns),
        interrupted_tasks: interrupted_tasks(assigns),
        implementer_pool_size: pool_size,
        reviewer_tag: reviewer_tag,
        loop_cfg: loop_cfg,
        active_blocker: Map.get(assigns, :active_blocker),
        stopping_blocker: Map.get(assigns, :stopping_blocker, false),
        conversion_ready: conversion_ready?(assigns),
        ready: ready?(assigns),
        documentation: documentation?(assigns.project),
        plans_from_docs:
          plans_from_docs?(assigns) ||
            !!(assigns.intake && Map.get(assigns.intake, :replan_source_id))
      )

    BossWeb.AutopilotPanel.panel(assigns)
  end
end
