defmodule BossWeb.ProjectLive do
  use BossWeb, :live_view
  alias Boss.{Deliveries, Projects, Repo, Runs, Tasks}
  alias Boss.Projects.{SpecImporter, SpecWatcher}
  alias Boss.Deliveries.Queue
  alias BossWeb.{DeliveryPanel, RunPanel, TaskBoard, TaskDependencies, TaskRevision}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project = find_project(id)

    if project && connected?(socket) do
      SpecWatcher.subscribe(project.id)
      Runs.subscribe(project.id)
      Tasks.subscribe(project.id)
    end

    {:ok,
     socket
     |> assign(
       project: project,
       project_route: id,
       page_title: if(project, do: "#{project.name} · BOSS", else: "Project not found · BOSS"),
       entries: if(project, do: Projects.list_spec_entries(project.id), else: []),
       auto_sync: Application.get_env(:boss, :spec_auto_sync, true),
       syncing: false,
       refreshing: false,
       refresh_pending: nil,
       drawer_open: false,
       selection: nil,
       details: nil,
       detail_loading: false,
       detail_pending: false,
       detail_error: nil,
       adoption_requests: %{},
       adoption_starting: nil,
       deliveries: [],
       queued_workflows: [],
       queue_actions: %{},
       queue_starting: nil,
       queue_error: nil,
       delivery_requests: %{},
       integration_requests: %{},
       delivery_starting: nil,
       delivery_stopping: nil,
       delivery_error: nil,
       manual_pending: %{},
       runs: [],
       run_commands: %{},
       run_command_id: nil,
       run_starting: nil,
       run_stopping: nil,
       run_error: nil,
       run_supported: :os.type() == {:unix, :darwin},
       check_requests: %{},
       review_requests: %{},
       status: nil,
       errors: []
     )
     |> show_result(if(project, do: SpecWatcher.status(project.id)))}
  end

  @impl true
  def handle_params(%{"id" => id} = params, uri, socket) do
    cond do
      id != socket.assigns.project_route ->
        target = URI.parse(uri)
        path = target.path <> if(target.query, do: "?#{target.query}", else: "")
        {:noreply, push_navigate(socket, to: path)}

      socket.assigns.project && Map.has_key?(params, "task_id") ->
        task_id = positive_id(params["task_id"])
        revision = if params["revision"], do: positive_id(params["revision"])

        selection =
          if task_id && (is_nil(params["revision"]) || revision),
            do: {task_id, revision},
            else: :invalid

        {:noreply, select_task(socket, selection)}

      true ->
        {:noreply,
         socket
         |> assign(
           drawer_open: false,
           selection: nil,
           details: nil,
           runs: [],
           deliveries: [],
           queued_workflows: [],
           queue_error: nil,
           delivery_error: nil,
           run_error: nil,
           detail_pending: false,
           detail_error: nil
         )}
    end
  end

  @impl true
  def handle_event("select_revision", %{"revision" => value}, socket) do
    with {task_id, _} <- socket.assigns.selection,
         revision when is_integer(revision) <- positive_id(value) do
      {:noreply,
       push_patch(socket,
         to: ~p"/projects/#{socket.assigns.project.id}/tasks/#{task_id}?revision=#{revision}"
       )}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("adopt_revision", %{"command-id" => id}, socket) do
    with {task, _} <- socket.assigns.selection,
         %{id: ^id} = request <- socket.assigns.adoption_requests[task],
         true <- adoption_available?(socket.assigns) do
      key = {:adopt_revision, task, id}

      {:noreply,
       socket
       |> put_adoption_request(task, %{request | locked: true, error: nil})
       |> assign(adoption_starting: key)
       |> start_async(key, fn ->
         delivery_call(fn -> Tasks.transition(task, request.command) end)
       end)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("adopt_revision", _, socket), do: {:noreply, socket}

  def handle_event("sync", _, %{assigns: %{syncing: true}} = socket), do: {:noreply, socket}
  def handle_event("sync", _, %{assigns: %{project: nil}} = socket), do: {:noreply, socket}

  def handle_event("sync", _, socket) do
    id = socket.assigns.project.id

    {:noreply,
     socket
     |> assign(syncing: true, status: "Syncing specs…")
     |> start_async(:sync, fn -> SpecImporter.sync(id) end)}
  end

  def handle_event("start_run", %{"command-id" => command}, socket) do
    if command == socket.assigns.run_command_id && run_start_available?(socket.assigns) &&
         !verification_uncertain?(socket.assigns) do
      {task_id, _} = socket.assigns.selection
      project_id = socket.assigns.project.id

      {:noreply,
       socket
       |> assign(
         run_starting: {task_id, command},
         manual_pending: Map.put(socket.assigns.manual_pending, task_id, command),
         run_error: nil
       )
       |> start_async(:start_run, fn ->
         {task_id, command, start_run(project_id, task_id, command)}
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("start_run", _, socket), do: {:noreply, socket}

  def handle_event(
        "edit_check",
        %{"parent_id" => parent, "command_id" => id, "command" => text},
        socket
      ) do
    case Map.get(socket.assigns.check_requests, parent) do
      %{id: ^id, locked: false} = request when is_binary(text) and byte_size(text) <= 4096 ->
        if check_available?(socket.assigns, parent) do
          {:noreply, put_check_request(socket, parent, %{request | text: text})}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("edit_check", _, socket), do: {:noreply, socket}

  def handle_event(
        "start_check",
        %{"parent_id" => parent, "command_id" => id, "command" => text},
        socket
      ) do
    request = Map.get(socket.assigns.check_requests, parent)

    if check_available?(socket.assigns, parent) && request && request.id == id &&
         is_binary(text) &&
         (!request.locked || request.text == text) do
      if byte_size(text) > 4096 do
        {:noreply, assign(socket, run_error: check_error({:error, :invalid_command}))}
      else
        {task_id, _} = socket.assigns.selection
        project = socket.assigns.project.id

        {:noreply,
         socket
         |> put_check_request(parent, %{request | text: text, locked: true})
         |> assign(run_starting: {task_id, id}, run_error: nil)
         |> start_async(:start_check, fn ->
           {task_id, parent, id, start_check(project, parent, id, text)}
         end)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("start_check", _, socket), do: {:noreply, socket}

  def handle_event("start_review", %{"parent-id" => parent, "command-id" => id}, socket) do
    request = Map.get(socket.assigns.review_requests, parent)

    if review_available?(socket.assigns, parent) && request && request.id == id do
      {task_id, _} = socket.assigns.selection
      project = socket.assigns.project.id

      {:noreply,
       socket
       |> put_review_request(parent, %{request | locked: true})
       |> assign(run_starting: {task_id, id}, run_error: nil)
       |> start_async(:start_review, fn ->
         {task_id, parent, id, start_review(project, parent, id)}
       end)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("start_review", _, socket), do: {:noreply, socket}

  def handle_event("stop_run", %{"run-id" => id}, socket) do
    if Enum.any?(socket.assigns.runs, &(&1.id == id && Runs.active?(&1))) do
      case Runs.stop(socket.assigns.project.id, id) do
        :ok -> {:noreply, assign(socket, run_stopping: id, run_error: nil)}
        _ -> {:noreply, refresh_details(socket)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("stop_run", _, socket), do: {:noreply, socket}

  def handle_event(
        "edit_delivery",
        %{"command_id" => id, "command" => text, "reviewer" => reviewer},
        socket
      ) do
    with {task, _} <- socket.assigns.selection,
         %{id: ^id, locked: false} = request <- socket.assigns.delivery_requests[task],
         true <- reviewer in ~w(codex claude),
         true <-
           is_binary(text) && byte_size(text) <= 4096 && delivery_form_available?(socket.assigns) do
      {:noreply,
       put_delivery_request(socket, :start, task, %{request | text: text, reviewer: reviewer})}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("edit_delivery", _, socket), do: {:noreply, socket}

  def handle_event(
        "start_delivery",
        %{"command_id" => id, "command" => text, "reviewer" => reviewer} = params,
        socket
      ) do
    action = if params["intent"] == "queue", do: :queue, else: :start

    with {task, _} <- socket.assigns.selection,
         %{id: ^id} = request <- socket.assigns.delivery_requests[task],
         true <- delivery_action_available?(socket.assigns, action),
         true <- reviewer in ~w(codex claude),
         true <- is_binary(text) && byte_size(text) <= 4096,
         true <-
           !request.locked ||
             (request.text == text && request.reviewer == reviewer &&
                Map.get(request, :action, :start) == action) do
      project = socket.assigns.project.id
      key = {:delivery_request, task, action, task, id}

      {:noreply,
       socket
       |> put_delivery_request(
         action,
         task,
         Map.merge(request, %{text: text, reviewer: reviewer, locked: true, action: action})
       )
       |> assign(delivery_starting: key, delivery_error: nil)
       |> start_async(key, fn ->
         delivery_call(fn ->
           if action == :queue,
             do: Queue.enqueue(project, task, id, text, reviewer),
             else: Deliveries.start(project, task, id, text, reviewer, Boss.Runs.Manager)
         end)
       end)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("start_delivery", _, socket), do: {:noreply, socket}

  def handle_event(action, %{"queue-id" => id}, socket)
      when action in ["cancel_queue", "resume_queue"] do
    kind = if action == "cancel_queue", do: :cancel, else: :resume

    with {task, _} <- socket.assigns.selection,
         request when not is_nil(request) <-
           Enum.find(socket.assigns.queued_workflows, &(&1.id == id)),
         true <- queue_action_available?(socket.assigns, request, kind) do
      project = socket.assigns.project.id
      key = {:queue_action, task, id, kind}

      {:noreply,
       socket
       |> assign(
         queue_actions: Map.put(socket.assigns.queue_actions, id, kind),
         queue_starting: key,
         queue_error: nil
       )
       |> start_async(key, fn ->
         delivery_call(fn ->
           if kind == :cancel, do: Queue.cancel(project, id), else: Queue.resume(project, id)
         end)
       end)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(action, _, socket) when action in ["cancel_queue", "resume_queue"],
    do: {:noreply, socket}

  def handle_event("integrate_delivery", %{"delivery-id" => delivery, "command-id" => id}, socket) do
    with {task, _} <- socket.assigns.selection,
         %{id: ^id} = request <- socket.assigns.integration_requests[delivery],
         true <- delivery_integrate_available?(socket.assigns),
         true <- !delivery_uncertain?(socket.assigns) || request.locked,
         true <-
           Enum.any?(
             socket.assigns.deliveries,
             &(&1.id == delivery && &1.status == "ready_to_merge")
           ) do
      project = socket.assigns.project.id
      key = {:delivery_request, task, :integrate, delivery, id}

      {:noreply,
       socket
       |> put_delivery_request(:integrate, delivery, %{request | locked: true})
       |> assign(delivery_starting: key, delivery_error: nil)
       |> start_async(key, fn ->
         delivery_call(fn -> Deliveries.integrate(project, delivery, id) end)
       end)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("integrate_delivery", _, socket), do: {:noreply, socket}

  def handle_event("stop_delivery", %{"delivery-id" => id}, socket) do
    if Enum.any?(socket.assigns.deliveries, &(&1.id == id && delivery_active?(&1))) do
      case Deliveries.stop(socket.assigns.project.id, id) do
        :ok -> {:noreply, assign(socket, delivery_stopping: id, delivery_error: nil)}
        _ -> {:noreply, refresh_details(socket)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("stop_delivery", _, socket), do: {:noreply, socket}

  @impl true
  def handle_async({:adopt_revision, task, id} = key, reply, socket) do
    result =
      case reply do
        {:ok, result} -> result
        _ -> :unknown
      end

    socket =
      if socket.assigns.adoption_starting == key,
        do: assign(socket, adoption_starting: nil),
        else: socket

    case socket.assigns.adoption_requests[task] do
      %{id: ^id, locked: true} = request ->
        request = %{
          request
          | locked: !TaskRevision.resolved?(result),
            error: TaskRevision.error(result)
        }

        {:noreply, socket |> put_adoption_request(task, request) |> refresh(:delivery_update)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_async({:queue_action, task, id, kind} = key, reply, socket) do
    result =
      case reply do
        {:ok, result} -> result
        _ -> :unknown
      end

    current = socket.assigns.queue_starting == key
    pending = socket.assigns.queue_actions[id] == kind
    socket = if current, do: assign(socket, queue_starting: nil), else: socket

    if pending do
      socket =
        if delivery_input_resolved?(result),
          do: assign(socket, queue_actions: Map.delete(socket.assigns.queue_actions, id)),
          else: socket

      case socket.assigns.selection do
        {^task, _} ->
          {:noreply, socket |> assign(queue_error: delivery_error(result)) |> refresh_details()}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_async({:delivery_request, task, kind, target, id} = key, reply, socket) do
    result =
      case reply do
        {:ok, result} -> result
        _ -> :unknown
      end

    request = delivery_request(socket.assigns, kind, target)
    confirmed = delivery_admitted?(socket.assigns, kind, id)
    current = socket.assigns.delivery_starting == key
    obsolete = is_nil(request) || request.id != id || (!request.locked && !current)

    socket = if current, do: assign(socket, delivery_starting: nil), else: socket

    socket =
      if !obsolete && (confirmed || delivery_input_resolved?(result)),
        do: put_delivery_request(socket, kind, target, %{request | locked: false}),
        else: socket

    case socket.assigns.selection do
      {^task, _} when not obsolete ->
        error = if confirmed, do: nil, else: delivery_error(result)
        {:noreply, socket |> assign(delivery_error: error) |> refresh_details()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_async(:start_run, {:ok, {task_id, command, result}}, socket) do
    socket =
      if socket.assigns.run_starting == {task_id, command},
        do: assign(socket, run_starting: nil),
        else: socket

    socket =
      if check_input_resolved?(result) && socket.assigns.manual_pending[task_id] == command,
        do: assign(socket, manual_pending: Map.delete(socket.assigns.manual_pending, task_id)),
        else: socket

    case socket.assigns.selection do
      {^task_id, _} ->
        socket = assign(socket, run_command_id: command, run_error: run_error(result))
        {:noreply, refresh_details(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_async(:start_run, _failure, socket) do
    error =
      case {socket.assigns.run_starting, socket.assigns.selection} do
        {{id, _}, {id, _}} -> run_error(:unknown)
        _ -> socket.assigns.run_error
      end

    {:noreply, socket |> assign(run_starting: nil, run_error: error) |> refresh_details()}
  end

  def handle_async(:start_check, {:ok, {task_id, parent, id, result}}, socket) do
    socket = assign(socket, run_starting: nil)
    request = Map.get(socket.assigns.check_requests, parent)
    confirmed = check_admitted?(socket.assigns, id) || is_nil(request) || request.id != id

    socket =
      if request && request.id == id && (confirmed || check_input_resolved?(result)),
        do: put_check_request(socket, parent, %{request | locked: false}),
        else: socket

    case socket.assigns.selection do
      {^task_id, _} ->
        error = if confirmed, do: nil, else: check_error(result)
        {:noreply, socket |> assign(run_error: error) |> refresh_details()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_async(:start_check, _failure, socket) do
    error =
      case {socket.assigns.run_starting, socket.assigns.selection} do
        {{id, command}, {id, _}} ->
          if check_admitted?(socket.assigns, command), do: nil, else: check_error(:unknown)

        _ ->
          socket.assigns.run_error
      end

    {:noreply, socket |> assign(run_starting: nil, run_error: error) |> refresh_details()}
  end

  def handle_async(:start_review, {:ok, {task_id, parent, id, result}}, socket) do
    socket =
      if socket.assigns.run_starting == {task_id, id},
        do: assign(socket, run_starting: nil),
        else: socket

    request = Map.get(socket.assigns.review_requests, parent)
    confirmed = review_admitted?(socket.assigns, id) || is_nil(request) || request.id != id

    socket =
      if request && request.id == id && (confirmed || check_input_resolved?(result)),
        do: put_review_request(socket, parent, %{request | locked: false}),
        else: socket

    case socket.assigns.selection do
      {^task_id, _} ->
        error = if confirmed, do: nil, else: review_error(result)
        {:noreply, socket |> assign(run_error: error) |> refresh_details()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_async(:start_review, _failure, socket) do
    error =
      case {socket.assigns.run_starting, socket.assigns.selection} do
        {{id, command}, {id, _}} ->
          if review_admitted?(socket.assigns, command), do: nil, else: review_error(:unknown)

        _ ->
          socket.assigns.run_error
      end

    {:noreply, socket |> assign(run_starting: nil, run_error: error) |> refresh_details()}
  end

  def handle_async(:sync, {:ok, result}, socket),
    do: {:noreply, socket |> assign(syncing: false) |> refresh(result)}

  def handle_async(:sync, _failure, socket) do
    {:noreply,
     socket
     |> assign(syncing: false, status: "Sync was interrupted. Refreshing saved entries…")
     |> refresh(:interrupted)}
  end

  def handle_async(:refresh, {:ok, {entries, result}}, socket) do
    result = if socket.assigns.refresh_pending == :interrupted, do: :interrupted, else: result

    {:noreply,
     socket
     |> assign(entries: entries)
     |> show_result(result)
     |> refresh_details()
     |> finish_refresh()}
  end

  def handle_async(:refresh, _failure, socket) do
    {:noreply,
     socket
     |> assign(
       status:
         "Saved entries could not be refreshed. Showing the last loaded entries. Try Sync again."
     )
     |> finish_refresh()}
  end

  def handle_async(
        :details,
        {:ok, {selection, result}},
        %{assigns: %{selection: selection, drawer_open: true}} = socket
      ) do
    socket =
      case result do
        {:ok, details} ->
          socket
          |> assign(
            details: details,
            detail_error: nil,
            runs: Map.get(details, :runs, []),
            deliveries: Map.get(details, :deliveries, []),
            queued_workflows: Map.get(details, :queued_workflows, [])
          )
          |> renew_run_command()
          |> renew_check_requests()
          |> renew_review_requests()
          |> renew_queue_actions()
          |> renew_delivery_requests()
          |> renew_manual_pending()
          |> renew_adoption_request()

        {:error, :not_found} ->
          assign(socket,
            details: nil,
            runs: [],
            deliveries: [],
            queued_workflows: [],
            detail_error: :not_found
          )

        _ ->
          assign(socket, detail_error: :storage_error)
      end

    {:noreply, finish_details(socket)}
  end

  def handle_async(:details, {:ok, _obsolete}, socket), do: {:noreply, finish_details(socket)}

  def handle_async(
        :details,
        _failure,
        %{assigns: %{drawer_open: true, selection: {_, _}}} = socket
      ),
      do: {:noreply, socket |> assign(detail_error: :storage_error) |> finish_details()}

  def handle_async(:details, _obsolete, socket), do: {:noreply, finish_details(socket)}

  @impl true
  def handle_info({:task_changed, id}, %{assigns: %{project: %{id: id}}} = socket),
    do: {:noreply, refresh(socket, :delivery_update)}

  def handle_info({:task_changed, _}, socket), do: {:noreply, socket}

  def handle_info({:run_changed, id}, %{assigns: %{project: %{id: id}}} = socket),
    do: {:noreply, refresh(socket, :delivery_update)}

  def handle_info({:run_changed, _}, socket), do: {:noreply, socket}

  def handle_info({:spec_sync, id, result}, %{assigns: %{project: %{id: id}}} = socket),
    do: {:noreply, refresh(socket, result)}

  def handle_info({:spec_sync, _, _}, socket), do: {:noreply, socket}

  defp select_task(%{assigns: %{selection: selection}} = socket, selection), do: socket

  defp select_task(socket, selection) do
    same_task =
      case {socket.assigns.selection, selection} do
        {{id, _}, {id, _}} -> true
        _ -> false
      end

    socket =
      socket
      |> assign(
        drawer_open: true,
        selection: selection,
        details: if(same_task, do: socket.assigns.details),
        runs: if(same_task, do: socket.assigns.runs, else: []),
        deliveries: if(same_task, do: socket.assigns.deliveries, else: []),
        queued_workflows: if(same_task, do: socket.assigns.queued_workflows, else: []),
        queue_error: if(same_task, do: socket.assigns.queue_error),
        delivery_error: if(same_task, do: socket.assigns.delivery_error),
        run_error: if(same_task, do: socket.assigns.run_error),
        detail_pending: false,
        detail_error: nil
      )

    if selection == :invalid,
      do: assign(socket, detail_error: :not_found),
      else: socket |> select_run_command() |> select_delivery_request() |> refresh_details()
  end

  defp refresh_details(
         %{assigns: %{drawer_open: true, selection: {_, _}, detail_loading: true}} = socket
       ),
       do: assign(socket, detail_pending: true)

  defp refresh_details(%{assigns: %{drawer_open: true, selection: {_, _}}} = socket),
    do: load_details(socket)

  defp refresh_details(socket), do: socket

  defp load_details(socket) do
    project_id = socket.assigns.project.id
    {task_id, revision} = selection = socket.assigns.selection

    socket
    |> assign(detail_loading: true, detail_pending: false)
    |> start_async(:details, fn ->
      {selection, read_details(project_id, task_id, revision)}
    end)
  end

  defp read_details(project_id, task_id, revision) do
    selector = Repo.get_dynamic_repo()
    repo = if is_atom(selector), do: Process.whereis(selector), else: selector

    if is_pid(repo) do
      Repo.put_dynamic_repo(repo)

      try do
        Repo.transaction(
          fn ->
            case Tasks.get_details(project_id, task_id, revision) do
              {:ok, details} ->
                details
                |> Map.put(:runs, Runs.list(project_id, task_id))
                |> Map.put(:deliveries, Deliveries.list(project_id, task_id))
                |> Map.put(:queued_workflows, Queue.list(project_id, task_id))

              {:error, reason} ->
                Repo.rollback(reason)
            end
          end,
          mode: :deferred
        )
      after
        Repo.put_dynamic_repo(selector)
      end
    else
      {:error, :storage_error}
    end
  end

  defp put_adoption_request(socket, task, request),
    do:
      assign(socket, adoption_requests: Map.put(socket.assigns.adoption_requests, task, request))

  defp renew_adoption_request(socket) do
    details = socket.assigns.details
    request = socket.assigns.adoption_requests[details.task.id]
    request = TaskRevision.renew(request, details, socket.assigns.project.id)
    put_adoption_request(socket, details.task.id, request)
  end

  defp adoption_pending?(assigns),
    do: Enum.any?(assigns.adoption_requests, fn {_, request} -> request.locked end)

  defp adoption_available?(assigns) do
    with {task, revision} <- assigns.selection,
         %{task: %{id: ^task}} = details <- assigns.details,
         request when not is_nil(request) <- assigns.adoption_requests[task] do
      selected = revision || details.pinned_revision.number

      !assigns.detail_loading && is_nil(assigns.detail_error) &&
        selected == details.selected_revision.number && is_nil(assigns.adoption_starting) &&
        (request.locked ||
           (details.adoption.available? && !adoption_pending?(assigns) &&
              is_nil(assigns.run_starting) && map_size(assigns.manual_pending) == 0 &&
              !verification_uncertain?(assigns) && !delivery_busy?(assigns) &&
              !delivery_uncertain?(assigns)))
    else
      _ -> false
    end
  end

  defp select_run_command(socket) do
    {task_id, _} = socket.assigns.selection
    command = Map.get(socket.assigns.run_commands, task_id) || Ecto.UUID.generate()

    assign(socket,
      run_command_id: command,
      run_commands: Map.put(socket.assigns.run_commands, task_id, command)
    )
  end

  defp renew_run_command(socket) do
    if is_nil(socket.assigns.run_starting) &&
         Enum.any?(
           socket.assigns.runs,
           &(&1.command_id == socket.assigns.run_command_id && !Runs.active?(&1))
         ) do
      {task_id, _} = socket.assigns.selection

      socket
      |> assign(run_commands: Map.delete(socket.assigns.run_commands, task_id))
      |> select_run_command()
    else
      socket
    end
  end

  defp select_delivery_request(socket) do
    {task, _} = socket.assigns.selection
    request = socket.assigns.delivery_requests[task] || new_delivery_request()
    put_delivery_request(socket, :start, task, request)
  end

  defp new_delivery_request(text \\ "", reviewer \\ "codex"),
    do: %{id: Ecto.UUID.generate(), text: text, reviewer: reviewer, locked: false, action: nil}

  defp delivery_request(assigns, kind, target) when kind in [:start, :queue],
    do: assigns.delivery_requests[target]

  defp delivery_request(assigns, :integrate, target), do: assigns.integration_requests[target]

  defp put_delivery_request(socket, kind, target, request) when kind in [:start, :queue],
    do:
      assign(socket,
        delivery_requests: Map.put(socket.assigns.delivery_requests, target, request)
      )

  defp put_delivery_request(socket, :integrate, target, request),
    do:
      assign(socket,
        integration_requests: Map.put(socket.assigns.integration_requests, target, request)
      )

  defp delivery_admitted?(assigns, :queue, command),
    do: Enum.any?(assigns.queued_workflows, &(&1.command_id == command))

  defp delivery_admitted?(assigns, kind, command) do
    Enum.any?(assigns.deliveries, fn delivery ->
      if kind == :start,
        do: delivery.command_id == command,
        else: delivery.integration_command_id == command
    end)
  end

  defp renew_delivery_requests(socket) do
    socket =
      Enum.reduce(socket.assigns.queued_workflows, socket, fn saved, socket ->
        case socket.assigns.delivery_requests[saved.task_id] do
          %{id: id} = request when id == saved.command_id ->
            put_delivery_request(
              socket,
              :queue,
              saved.task_id,
              new_delivery_request(request.text, request.reviewer)
            )

          _ ->
            socket
        end
      end)

    socket =
      Enum.reduce(socket.assigns.deliveries, socket, fn delivery, socket ->
        socket =
          if socket.assigns.delivery_stopping == delivery.id && !delivery_active?(delivery),
            do: assign(socket, delivery_stopping: nil),
            else: socket

        request = socket.assigns.delivery_requests[delivery.task_id]

        socket =
          if request && request.id == delivery.command_id do
            request =
              if delivery_active?(delivery),
                do: %{request | locked: false},
                else: new_delivery_request(request.text, request.reviewer)

            put_delivery_request(socket, :start, delivery.task_id, request)
          else
            socket
          end

        request = socket.assigns.integration_requests[delivery.id]

        cond do
          request && request.id == delivery.integration_command_id ->
            put_delivery_request(socket, :integrate, delivery.id, %{request | locked: false})

          is_nil(request) && delivery.status == "ready_to_merge" ->
            put_delivery_request(socket, :integrate, delivery.id, %{
              id: Ecto.UUID.generate(),
              locked: false
            })

          true ->
            socket
        end
      end)

    socket =
      case socket.assigns.delivery_starting do
        {:delivery_request, _, kind, _, command} ->
          if delivery_admitted?(socket.assigns, kind, command),
            do: assign(socket, delivery_starting: nil),
            else: socket

        _ ->
          socket
      end

    if !delivery_uncertain?(socket.assigns) &&
         socket.assigns.delivery_error == delivery_error(:unknown),
       do: assign(socket, delivery_error: nil),
       else: socket
  end

  defp renew_manual_pending(socket) do
    pending =
      Map.reject(socket.assigns.manual_pending, fn {_, command} ->
        Enum.any?(socket.assigns.runs, &(&1.command_id == command))
      end)

    assign(socket, manual_pending: pending)
  end

  defp delivery_active?(delivery),
    do: delivery.status in ~w(planning implementing testing reviewing integrating)

  defp delivery_busy?(assigns),
    do:
      !is_nil(Map.get(assigns, :delivery_starting)) || queue_pending?(assigns) ||
        Enum.any?(
          Map.get(assigns, :deliveries, []),
          &(delivery_active?(&1) || &1.cleanup == "unknown")
        )

  defp delivery_uncertain?(assigns),
    do:
      map_size(Map.get(assigns, :queue_actions, %{})) > 0 ||
        Enum.any?(Map.get(assigns, :delivery_requests, %{}), fn {_, request} -> request.locked end) ||
        Enum.any?(Map.get(assigns, :integration_requests, %{}), fn {_, request} ->
          request.locked
        end)

  defp delivery_integrate_available?(assigns) do
    assigns.run_supported && assigns.details != nil && assigns.detail_error == nil &&
      !assigns.detail_loading && is_nil(assigns.run_starting) && !delivery_busy?(assigns) &&
      map_size(assigns.manual_pending) == 0 && !verification_uncertain?(assigns) &&
      !adoption_pending?(assigns) &&
      !Enum.any?(assigns.runs, &(Runs.active?(&1) || &1.cleanup == "unknown"))
  end

  defp delivery_start_available?(assigns), do: delivery_action_available?(assigns, :start)

  defp delivery_form_available?(assigns),
    do: delivery_action_available?(assigns, :start) || delivery_action_available?(assigns, :queue)

  defp delivery_action_available?(assigns, action) do
    request = assigns.details && assigns.delivery_requests[assigns.details.task.id]

    delivery_integrate_available?(assigns) && request &&
      assigns.details.task.state in ~w(new failed interrupted cancelled blocked needs_input) &&
      (action == :queue || dependencies_ready?(assigns) || request.locked) &&
      (!request.locked || Map.get(request, :action, :start) == action) &&
      (!delivery_uncertain?(assigns) || request.locked)
  end

  defp queue_pending?(assigns),
    do: Enum.any?(Map.get(assigns, :queued_workflows, []), &(&1.status in ~w(queued paused)))

  defp queue_action_available?(assigns, request, kind) do
    saved = assigns.queue_actions[request.id]
    eligible = request.status in if kind == :cancel, do: ~w(queued paused), else: ~w(paused)

    queue_controls_available?(assigns) && is_nil(assigns.queue_starting) && eligible &&
      (kind == :cancel || assigns.run_supported) &&
      (saved == kind || !delivery_uncertain?(assigns))
  end

  defp queue_controls_available?(assigns) do
    assigns.details != nil && !assigns.detail_loading && is_nil(assigns.detail_error) &&
      is_nil(assigns.delivery_starting) && is_nil(assigns.run_starting) &&
      !adoption_pending?(assigns) && !verification_uncertain?(assigns) &&
      map_size(assigns.manual_pending) == 0
  end

  defp renew_queue_actions(socket) do
    actions =
      Enum.reduce(socket.assigns.queued_workflows, socket.assigns.queue_actions, fn request,
                                                                                    actions ->
        resolved =
          case actions[request.id] do
            :cancel -> request.status not in ~w(queued paused)
            :resume -> request.status != "paused"
            _ -> false
          end

        if resolved, do: Map.delete(actions, request.id), else: actions
      end)

    socket = assign(socket, queue_actions: actions)

    socket =
      case socket.assigns.queue_starting do
        {:queue_action, _, id, _} ->
          if Map.has_key?(actions, id), do: socket, else: assign(socket, queue_starting: nil)

        _ ->
          socket
      end

    if map_size(actions) == 0 && socket.assigns.queue_error == delivery_error(:unknown),
      do: assign(socket, queue_error: nil),
      else: socket
  end

  defp dependencies_ready?(%{details: %{dependencies: %{ready?: true}}}), do: true
  defp dependencies_ready?(_), do: false

  defp run_start_available?(assigns) do
    run_available?(assigns) &&
      (dependencies_ready?(assigns) ||
         assigns.manual_pending[assigns.details.task.id] == assigns.run_command_id)
  end

  defp delivery_call(fun) do
    fun.()
  rescue
    _ -> {:error, :storage_error}
  catch
    :exit, _ -> {:error, :storage_error}
  end

  defp delivery_input_resolved?({:error, {:dependencies_blocked, _}}), do: true

  defp delivery_input_resolved?({:error, reason}),
    do:
      reason in [
        :busy,
        :queue_full,
        :task_queued,
        :already_started,
        :request_finished,
        :invalid_check_command,
        :invalid_reviewer,
        :invalid_command,
        :not_found,
        :task_unavailable,
        :source_unavailable,
        :not_ready,
        :stale_state,
        :missing_evidence
      ]

  defp delivery_input_resolved?({:ok, _}), do: true
  defp delivery_input_resolved?(_), do: false

  defp delivery_error({:ok, _}), do: nil

  defp delivery_error({:error, :busy}),
    do: "Workflow capacity is occupied, an exclusive run is active, or cleanup needs attention."

  defp delivery_error({:error, :queue_full}),
    do: "The workflow queue is full. Try again after queued work finishes."

  defp delivery_error({:error, :task_queued}),
    do: "This task already has a queued workflow. Cancel it before changing the task."

  defp delivery_error({:error, :already_started}), do: nil

  defp delivery_error({:error, :request_finished}),
    do: "This queue request has finished. Refresh its saved state."

  defp delivery_error({:error, :invalid_check_command}),
    do: check_error({:error, :invalid_command})

  defp delivery_error({:error, :invalid_reviewer}),
    do: "Choose Codex or Claude as the workflow reviewer."

  defp delivery_error({:error, :invalid_command}), do: check_error({:error, :invalid_command})

  defp delivery_error({:error, {:dependencies_blocked, _}}), do: dependency_error()

  defp delivery_error({:error, reason})
       when reason in [
              :not_found,
              :task_unavailable,
              :source_unavailable,
              :not_ready,
              :stale_state,
              :missing_evidence
            ],
       do: "This task or workflow cannot accept that action. Refresh its saved state."

  defp delivery_error({:error, :idempotency_conflict}),
    do: "This saved request belongs to different input. Retry its original command."

  defp delivery_error(_),
    do:
      "The workflow request outcome could not be confirmed. Retry the same saved request before starting other work."

  defp run_available?(assigns) do
    assigns.run_supported && assigns.details != nil && assigns.detail_error == nil &&
      !assigns.detail_loading && is_nil(assigns.run_starting) &&
      !delivery_busy?(assigns) && !delivery_uncertain?(assigns) && !adoption_pending?(assigns) &&
      assigns.details.task.state in ~w(new ready failed interrupted cancelled blocked needs_input) &&
      !Enum.any?(assigns.runs, &(Runs.active?(&1) || &1.cleanup == "unknown"))
  end

  defp check_available?(assigns, parent) do
    request = Map.get(assigns.check_requests, parent)

    run_available?(assigns) &&
      !reviews_uncertain?(assigns) &&
      (!checks_uncertain?(assigns) || (request && request.locked)) &&
      Enum.any?(assigns.runs, &eligible_check_parent?(&1, parent))
  end

  defp eligible_check_parent?(run, id),
    do:
      run.id == id && run.adapter == "codex" && run.status == "finished" &&
        run.cleanup == "group_empty"

  defp put_check_request(socket, parent, request),
    do: assign(socket, check_requests: Map.put(socket.assigns.check_requests, parent, request))

  defp renew_check_requests(socket) do
    confirmed =
      Enum.any?(socket.assigns.check_requests, fn {_, request} ->
        request.locked && check_admitted?(socket.assigns, request.id)
      end)

    requests =
      Enum.reduce(socket.assigns.runs, socket.assigns.check_requests, fn run, requests ->
        if eligible_check_parent?(run, run.id) do
          request = Map.get(requests, run.id)
          receipt = request && Enum.find(socket.assigns.runs, &(&1.command_id == request.id))

          cond do
            is_nil(request) || (receipt && !Runs.active?(receipt)) ->
              Map.put(requests, run.id, %{
                id: Ecto.UUID.generate(),
                text: if(request, do: request.text, else: ""),
                locked: false
              })

            receipt ->
              Map.put(requests, run.id, %{request | locked: false})

            true ->
              requests
          end
        else
          requests
        end
      end)

    socket = assign(socket, check_requests: requests)

    if confirmed && socket.assigns.run_error == check_error(:unknown),
      do: assign(socket, run_error: nil),
      else: socket
  end

  defp check_admitted?(assigns, command),
    do: Enum.any?(assigns.runs, &(&1.adapter == "check" && &1.command_id == command))

  defp review_available?(assigns, parent) do
    request = Map.get(assigns.review_requests, parent)

    run_available?(assigns) && !checks_uncertain?(assigns) &&
      (!reviews_uncertain?(assigns) || (request && request.locked)) &&
      Enum.any?(assigns.runs, &eligible_review_parent?(&1, parent))
  end

  defp eligible_review_parent?(run, id),
    do:
      run.id == id && run.adapter == "check" && run.status == "finished" &&
        run.cleanup == "group_empty" && is_binary(run.candidate_commit)

  defp put_review_request(socket, parent, request),
    do: assign(socket, review_requests: Map.put(socket.assigns.review_requests, parent, request))

  defp renew_review_requests(socket) do
    requests = Map.get(socket.assigns, :review_requests, %{})

    confirmed =
      Enum.any?(requests, fn {_, request} ->
        request.locked && review_admitted?(socket.assigns, request.id)
      end)

    requests =
      Enum.reduce(socket.assigns.runs, requests, fn run, requests ->
        if eligible_review_parent?(run, run.id) do
          request = Map.get(requests, run.id)
          receipt = request && Enum.find(socket.assigns.runs, &(&1.command_id == request.id))

          cond do
            is_nil(request) || (receipt && !Runs.active?(receipt)) ->
              Map.put(requests, run.id, %{id: Ecto.UUID.generate(), locked: false})

            receipt ->
              Map.put(requests, run.id, %{request | locked: false})

            true ->
              requests
          end
        else
          requests
        end
      end)

    socket = assign(socket, review_requests: requests)

    if confirmed && socket.assigns.run_error == review_error(:unknown),
      do: assign(socket, run_error: nil),
      else: socket
  end

  defp review_admitted?(assigns, command),
    do: Enum.any?(assigns.runs, &(&1.adapter == "review" && &1.command_id == command))

  defp start_review(project, parent, id) do
    Runs.start_review(project, parent, id)
  rescue
    _ -> {:error, :storage_error}
  catch
    :exit, _ -> {:error, :storage_error}
  end

  defp start_check(project, parent, id, command) do
    Runs.start_check(project, parent, id, command)
  rescue
    _ -> {:error, :storage_error}
  catch
    :exit, _ -> {:error, :storage_error}
  end

  defp check_input_resolved?({:ok, _}), do: true
  defp check_input_resolved?({:error, {:dependencies_blocked, _}}), do: true

  defp check_input_resolved?({:error, reason}),
    do:
      reason in [
        :busy,
        :task_queued,
        :invalid_command,
        :not_found,
        :task_unavailable,
        :source_unavailable
      ]

  defp check_input_resolved?(_), do: false

  defp checks_uncertain?(assigns),
    do: Enum.any?(Map.get(assigns, :check_requests, %{}), fn {_, request} -> request.locked end)

  defp reviews_uncertain?(assigns),
    do: Enum.any?(Map.get(assigns, :review_requests, %{}), fn {_, request} -> request.locked end)

  defp verification_uncertain?(assigns),
    do: checks_uncertain?(assigns) || reviews_uncertain?(assigns)

  defp review_error({:ok, _}), do: nil
  defp review_error({:error, :busy}), do: run_error({:error, :busy})
  defp review_error({:error, :task_queued}), do: delivery_error({:error, :task_queued})

  defp review_error({:error, reason})
       when reason in [:not_found, :task_unavailable, :source_unavailable],
       do: "This saved check is no longer available for review. Refresh the task."

  defp review_error({:error, :idempotency_conflict}),
    do: "This request already belongs to another review. Retry the original request."

  defp review_error(_),
    do:
      "The review start outcome could not be confirmed. Retry the same saved request before starting another review."

  defp check_error({:ok, _}), do: nil
  defp check_error({:error, :busy}), do: run_error({:error, :busy})
  defp check_error({:error, :task_queued}), do: delivery_error({:error, :task_queued})

  defp check_error({:error, :invalid_command}),
    do: "Enter one command with arguments, up to 4096 bytes. Shell expansion is unavailable."

  defp check_error({:error, :idempotency_conflict}),
    do:
      "This request already belongs to another command. Keep the original command when retrying."

  defp check_error({:error, reason})
       when reason in [:not_found, :task_unavailable, :source_unavailable],
       do: "This saved Codex result is no longer available for checks. Refresh the task."

  defp check_error(_),
    do:
      "The checks start outcome could not be confirmed. Retry with the same saved command to check the original request."

  defp start_run(project_id, task_id, command) do
    Runs.start(project_id, task_id, command)
  rescue
    _ -> {:error, :storage_error}
  catch
    :exit, _ -> {:error, :storage_error}
  end

  defp run_error({:ok, _}), do: nil
  defp run_error({:error, :task_queued}), do: delivery_error({:error, :task_queued})

  defp run_error({:error, :busy}),
    do: "Another run is active or its cleanup needs attention. New runs are blocked."

  defp run_error({:error, :task_unavailable}),
    do: "This task cannot start a run in its current state."

  defp run_error({:error, :not_found}), do: "This task is no longer available in this project."

  defp run_error({:error, {:dependencies_blocked, _}}), do: dependency_error()

  defp run_error(_),
    do: "The start outcome could not be confirmed. Retry Start Codex to check the same request."

  defp dependency_error,
    do: "Dependencies are not ready. Review the Dependencies section before starting again."

  defp finish_details(socket) do
    pending = socket.assigns.detail_pending
    socket = assign(socket, detail_loading: false, detail_pending: false)
    if pending, do: refresh_details(socket), else: socket
  end

  defp refresh(%{assigns: %{refreshing: true}} = socket, result) do
    pending = if socket.assigns.refresh_pending == :interrupted, do: :interrupted, else: result
    assign(socket, refresh_pending: pending)
  end

  defp refresh(socket, fallback) do
    id = socket.assigns.project.id

    socket
    |> assign(refreshing: true)
    |> start_async(:refresh, fn ->
      entries = Projects.list_spec_entries(id)
      result = if fallback == :interrupted, do: fallback, else: SpecWatcher.status(id) || fallback
      {entries, result}
    end)
  end

  defp finish_refresh(socket) do
    pending = socket.assigns.refresh_pending
    socket = assign(socket, refreshing: false, refresh_pending: nil)
    if pending, do: refresh(socket, pending), else: socket
  end

  defp show_result(socket, {:ok, summary}) do
    assign(socket,
      errors: [],
      status:
        "Sync complete: #{summary.created} created, #{summary.revised} revised, " <>
          "#{summary.unchanged} unchanged, #{summary.missing} missing."
    )
  end

  defp show_result(socket, {:error, errors}), do: assign(socket, errors: errors, status: nil)

  defp show_result(socket, :interrupted),
    do:
      assign(socket,
        status: "Sync was interrupted. Saved entries have been refreshed. Try Sync again."
      )

  defp show_result(socket, :delivery_update), do: socket
  defp show_result(socket, nil), do: socket

  defp find_project(id) do
    if number = positive_id(id), do: Projects.get_project!(number)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp positive_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 and number <= 9_223_372_036_854_775_807 -> number
      _ -> nil
    end
  end

  defp positive_id(_), do: nil

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:adoption_available, adoption_available?(assigns))
      |> assign(:run_available, run_available?(assigns))
      |> assign(:run_start_available, run_start_available?(assigns))
      |> assign(:delivery_start_available, delivery_start_available?(assigns))
      |> assign(:delivery_queue_available, delivery_action_available?(assigns, :queue))
      |> assign(:queue_controls_available, queue_controls_available?(assigns))
      |> assign(:delivery_integrate_available, delivery_integrate_available?(assigns))
      |> assign(:delivery_uncertain, delivery_uncertain?(assigns))

    ~H"""
    <.link
      navigate={~p"/"}
      class="text-sm text-emerald-400 underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-emerald-400"
    >
      ← Projects
    </.link>
    <div :if={is_nil(@project)} class="mt-6">
      <h1 class="text-3xl font-semibold">Project not found</h1>
      <p class="mt-3 text-zinc-300">Choose a project from the project list.</p>
    </div>
    <div :if={@project}>
      <div class="mt-6 flex flex-col items-start gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div class="min-w-0">
          <p class="text-sm font-semibold tracking-widest text-emerald-400">BOSS · LOCAL</p>
          <h1 class="mt-2 break-words text-3xl font-semibold">{@project.name}</h1>
        </div>
        <button
          id="sync-specs"
          type="button"
          phx-click="sync"
          disabled={@syncing}
          aria-describedby="sync-help"
          class="shrink-0 rounded-md bg-emerald-400 px-5 py-3 font-semibold text-zinc-950 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400 disabled:opacity-50"
        >
          {if @syncing, do: "Syncing…", else: "Sync specs"}
        </button>
      </div>
      <p id="sync-help" class="mt-5 text-sm text-zinc-300">
        <%= if @auto_sync do %>
          Changes in this specs folder refresh automatically. Use Sync specs to check now.
        <% else %>
          Sync reads Markdown files from this project's specs folder. Run it again after editing files.
        <% end %>
      </p>
      <p class="mt-2 break-all font-mono text-sm text-zinc-400">{@project.specs_path}</p>
      <p id="sync-status" role="status" class="mt-4 min-h-5 text-sm text-zinc-300">{@status}</p>
      <div
        :if={@errors != []}
        id="sync-errors"
        role="alert"
        class="mt-4 rounded-md border border-red-900 px-4 py-3 text-sm text-red-300"
      >
        <p class="font-semibold">Sync could not finish. Review the details and try again.</p>
        <ul class="mt-2 space-y-2">
          <li :for={error <- @errors}>
            <span class="break-all font-mono">{error.path}</span>: {error.message}
          </li>
        </ul>
      </div>
      <section aria-labelledby="task-board-heading" aria-busy={@syncing} class="mt-6 min-w-0">
        <p
          :if={@entries == []}
          class="mt-4 rounded-md border border-dashed border-zinc-700 px-5 py-6 text-zinc-400"
        >
          No specs imported yet. Add .md files to the specs folder.
          <%= if @auto_sync do %>
            They will appear after the next automatic refresh.
          <% else %>
            Then choose Sync specs.
          <% end %>
        </p>
        <TaskBoard.board entries={@entries} project_id={@project.id} />
      </section>
      <TaskBoard.drawer
        :if={@drawer_open}
        project_id={@project.id}
        selection={@selection}
        details={@details}
        loading={@detail_loading}
        error={@detail_error}
      >
        <:source_actions>
          <TaskRevision.panel
            :if={@details}
            details={@details}
            request={@adoption_requests[@details.task.id]}
            available={@adoption_available}
            starting={
              @adoption_starting ==
                {:adopt_revision, @details.task.id, @adoption_requests[@details.task.id].id}
            }
          />
        </:source_actions>
        <:run_panel>
          <TaskDependencies.panel
            :if={@details}
            snapshot={@details.dependencies}
            project_id={@project.id}
            revision={@details.pinned_revision.number}
          />
          <DeliveryPanel.panel
            :if={@details}
            details={@details}
            deliveries={@deliveries}
            queued_workflows={@queued_workflows}
            queue_actions={@queue_actions}
            queue_starting={@queue_starting}
            queue_error={@queue_error}
            queue_available={@delivery_queue_available}
            queue_controls_available={@queue_controls_available}
            request={@delivery_requests[@details.task.id]}
            integration_requests={@integration_requests}
            start_available={@delivery_start_available}
            integrate_available={@delivery_integrate_available}
            uncertain={@delivery_uncertain}
            starting={@delivery_starting}
            stopping={@delivery_stopping}
            error={@delivery_error}
            supported={@run_supported}
          />
          <RunPanel.panel
            :if={@details}
            details={@details}
            runs={@runs}
            command_id={@run_command_id}
            starting={!is_nil(@run_starting)}
            stopping={@run_stopping}
            available={@run_available}
            start_available={@run_start_available}
            supported={@run_supported}
            error={@run_error}
            check_requests={Map.get(assigns, :check_requests, %{})}
            review_requests={Map.get(assigns, :review_requests, %{})}
          />
        </:run_panel>
      </TaskBoard.drawer>
    </div>
    """
  end
end
