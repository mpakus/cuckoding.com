defmodule BossWeb.ProjectLive do
  use BossWeb, :live_view
  alias Boss.{Projects, Repo, Runs, Tasks}
  alias Boss.Projects.{SpecImporter, SpecWatcher}
  alias BossWeb.{RunPanel, TaskBoard}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project = find_project(id)

    if project && connected?(socket) do
      SpecWatcher.subscribe(project.id)
      Runs.subscribe(project.id)
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
       runs: [],
       run_commands: %{},
       run_command_id: nil,
       run_starting: nil,
       run_stopping: nil,
       run_error: nil,
       run_supported: :os.type() == {:unix, :darwin},
       check_requests: %{},
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
         |> cancel_async(:details)
         |> assign(
           drawer_open: false,
           selection: nil,
           details: nil,
           runs: [],
           run_error: nil,
           detail_loading: false,
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
    if command == socket.assigns.run_command_id && run_available?(socket.assigns) &&
         !checks_uncertain?(socket.assigns) do
      {task_id, _} = socket.assigns.selection
      project_id = socket.assigns.project.id

      {:noreply,
       socket
       |> assign(run_starting: {task_id, command}, run_error: nil)
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

  @impl true
  def handle_async(:start_run, {:ok, {task_id, command, result}}, socket) do
    socket = assign(socket, run_starting: nil)

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
          |> assign(details: details, detail_error: nil, runs: Map.get(details, :runs, []))
          |> renew_run_command()
          |> renew_check_requests()

        {:error, :not_found} ->
          assign(socket, details: nil, runs: [], detail_error: :not_found)

        _ ->
          assign(socket, detail_error: :storage_error)
      end

    {:noreply, finish_details(socket)}
  end

  def handle_async(:details, {:ok, _obsolete}, socket), do: {:noreply, socket}

  def handle_async(
        :details,
        _failure,
        %{assigns: %{drawer_open: true, selection: {_, _}}} = socket
      ),
      do: {:noreply, socket |> assign(detail_error: :storage_error) |> finish_details()}

  def handle_async(:details, _obsolete, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:run_changed, id}, %{assigns: %{project: %{id: id}}} = socket),
    do: {:noreply, refresh_details(socket)}

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
      |> cancel_async(:details)
      |> assign(
        drawer_open: true,
        selection: selection,
        details: if(same_task, do: socket.assigns.details),
        runs: if(same_task, do: socket.assigns.runs, else: []),
        run_error: if(same_task, do: socket.assigns.run_error),
        detail_loading: false,
        detail_pending: false,
        detail_error: nil
      )

    if selection == :invalid,
      do: assign(socket, detail_error: :not_found),
      else: socket |> select_run_command() |> load_details()
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
              {:ok, details} -> Map.put(details, :runs, Runs.list(project_id, task_id))
              {:error, reason} -> Repo.rollback(reason)
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

  defp run_available?(assigns) do
    assigns.run_supported && assigns.details != nil && assigns.detail_error == nil &&
      !assigns.detail_loading && is_nil(assigns.run_starting) &&
      assigns.details.task.state in ~w(new ready failed interrupted cancelled blocked needs_input) &&
      !Enum.any?(assigns.runs, &(Runs.active?(&1) || &1.cleanup == "unknown"))
  end

  defp check_available?(assigns, parent) do
    request = Map.get(assigns.check_requests, parent)

    run_available?(assigns) &&
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

  defp start_check(project, parent, id, command) do
    Runs.start_check(project, parent, id, command)
  rescue
    _ -> {:error, :storage_error}
  catch
    :exit, _ -> {:error, :storage_error}
  end

  defp check_input_resolved?({:ok, _}), do: true

  defp check_input_resolved?({:error, reason}),
    do: reason in [:busy, :invalid_command, :not_found, :task_unavailable, :source_unavailable]

  defp check_input_resolved?(_), do: false

  defp checks_uncertain?(assigns),
    do: Enum.any?(Map.get(assigns, :check_requests, %{}), fn {_, request} -> request.locked end)

  defp check_error({:ok, _}), do: nil
  defp check_error({:error, :busy}), do: run_error({:error, :busy})

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

  defp run_error({:error, :busy}),
    do: "Another run is active or its cleanup needs attention. New runs are blocked."

  defp run_error({:error, :task_unavailable}),
    do: "This task cannot start a run in its current state."

  defp run_error({:error, :not_found}), do: "This task is no longer available in this project."

  defp run_error(_),
    do: "The start outcome could not be confirmed. Retry Start Codex to check the same request."

  defp finish_details(socket) do
    pending = socket.assigns.detail_pending
    socket = assign(socket, detail_loading: false, detail_pending: false)
    if pending, do: refresh_details(socket), else: socket
  end

  defp refresh(%{assigns: %{refreshing: true}} = socket, result),
    do: assign(socket, refresh_pending: result)

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
    assigns = assign(assigns, :run_available, run_available?(assigns))

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
        <:run_panel>
          <RunPanel.panel
            :if={@details}
            details={@details}
            runs={@runs}
            command_id={@run_command_id}
            starting={!is_nil(@run_starting)}
            stopping={@run_stopping}
            available={@run_available}
            supported={@run_supported}
            error={@run_error}
            check_requests={Map.get(assigns, :check_requests, %{})}
          />
        </:run_panel>
      </TaskBoard.drawer>
    </div>
    """
  end
end
