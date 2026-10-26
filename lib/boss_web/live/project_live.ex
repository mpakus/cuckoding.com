defmodule BossWeb.ProjectLive do
  use BossWeb, :live_view
  alias Boss.Projects
  alias Boss.Projects.SpecImporter

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project = find_project(id)

    {:ok,
     assign(socket,
       project: project,
       page_title: if(project, do: "#{project.name} · BOSS", else: "Project not found · BOSS"),
       entries: if(project, do: Projects.list_spec_entries(project.id), else: []),
       syncing: false,
       status: nil,
       errors: []
     )}
  end

  @impl true
  def handle_event("sync", _, %{assigns: %{syncing: true}} = socket), do: {:noreply, socket}
  def handle_event("sync", _, %{assigns: %{project: nil}} = socket), do: {:noreply, socket}

  def handle_event("sync", _, socket) do
    id = socket.assigns.project.id

    {:noreply,
     socket
     |> assign(syncing: true, status: "Syncing specs…")
     |> start_async(:sync, fn ->
       result = SpecImporter.sync(id)
       {result, Projects.list_spec_entries(id)}
     end)}
  end

  @impl true
  def handle_async(:sync, {:ok, {{:ok, summary}, entries}}, socket) do
    {:noreply,
     assign(socket,
       syncing: false,
       entries: entries,
       errors: [],
       status:
         "Sync complete: #{summary.created} created, #{summary.revised} revised, " <>
           "#{summary.unchanged} unchanged, #{summary.missing} missing."
     )}
  end

  def handle_async(:sync, {:ok, {{:error, errors}, entries}}, socket),
    do: {:noreply, assign(socket, syncing: false, entries: entries, errors: errors, status: nil)}

  def handle_async(:sync, _failure, socket) do
    id = socket.assigns.project.id

    {:noreply,
     socket
     |> assign(status: "Sync was interrupted. Refreshing saved entries…")
     |> start_async(:reload, fn -> Projects.list_spec_entries(id) end)}
  end

  def handle_async(:reload, {:ok, entries}, socket) do
    {:noreply,
     assign(socket,
       syncing: false,
       entries: entries,
       status: "Sync was interrupted. Saved entries have been refreshed. Try Sync again."
     )}
  end

  def handle_async(:reload, _failure, socket) do
    {:noreply,
     assign(socket,
       syncing: false,
       status:
         "Saved entries could not be refreshed. Showing the last loaded entries. Try Sync again."
     )}
  end

  defp find_project(id) do
    case Integer.parse(id) do
      {number, ""} when number > 0 and number <= 9_223_372_036_854_775_807 ->
        Projects.get_project!(number)

      _ ->
        nil
    end
  rescue
    Ecto.NoResultsError -> nil
  end

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
        Sync reads Markdown files from this project's specs folder. Run it again after editing files.
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
      <section aria-labelledby="specs-heading" aria-busy={@syncing} class="mt-6">
        <h2 id="specs-heading" class="text-xl font-semibold">Specs</h2>
        <p
          :if={@entries == []}
          class="mt-4 rounded-md border border-dashed border-zinc-700 px-5 py-6 text-zinc-400"
        >
          No specs imported yet. Add .md files to the specs folder, then choose Sync specs.
        </p>
        <ul id="spec-entries" class="mt-3 divide-y divide-zinc-800">
          <li :for={entry <- @entries} id={"spec-#{entry.id}"} class="py-5">
            <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
              <h3 class="min-w-0 break-words font-semibold">{entry.title}</h3>
              <span class="rounded bg-zinc-800 px-2 py-1 text-xs text-zinc-300">
                {String.capitalize(entry.state)}
              </span>
              <span
                :if={entry.missing}
                class="rounded bg-amber-950 px-2 py-1 text-xs text-amber-300"
              >
                File missing
              </span>
            </div>
            <p class="mt-2 break-all font-mono text-sm text-zinc-400">{entry.relative_path}</p>
            <p class="mt-2 text-sm text-zinc-400">
              Source revision {entry.latest_revision} · Task snapshot {entry.task_revision}
            </p>
            <p
              :if={entry.latest_revision != entry.task_revision}
              class="mt-2 text-sm text-amber-300"
            >
              Source changed; the task keeps its saved snapshot.
            </p>
          </li>
        </ul>
      </section>
    </div>
    """
  end
end
