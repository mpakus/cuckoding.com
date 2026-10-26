defmodule BossWeb.ProjectLive do
  use BossWeb, :live_view
  alias Boss.{Projects, Tasks}
  alias Boss.Projects.{SpecImporter, SpecWatcher}
  alias BossWeb.TaskBoard

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project = find_project(id)
    if project && connected?(socket), do: SpecWatcher.subscribe(project.id)

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

  @impl true
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
        {:ok, details} -> assign(socket, details: details, detail_error: nil)
        {:error, :not_found} -> assign(socket, details: nil, detail_error: :not_found)
        _ -> assign(socket, detail_error: :storage_error)
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
        detail_loading: false,
        detail_pending: false,
        detail_error: nil
      )

    if selection == :invalid,
      do: assign(socket, detail_error: :not_found),
      else: load_details(socket)
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
      {selection, Tasks.get_details(project_id, task_id, revision)}
    end)
  end

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
      />
    </div>
    """
  end
end
