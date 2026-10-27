defmodule BossWeb.TaskBoard do
  use BossWeb, :html

  @columns [
    {"backlog", "Backlog"},
    {"in-progress", "In Progress"},
    {"review", "Review"},
    {"needs-attention", "Needs Attention"},
    {"done", "Done"}
  ]

  attr :entries, :list, required: true
  attr :project_id, :integer, required: true

  def board(assigns) do
    groups = Enum.group_by(assigns.entries, &column(&1.state))

    assigns =
      assign(
        assigns,
        :columns,
        Enum.map(@columns, fn {id, title} -> {id, title, Map.get(groups, id, [])} end)
      )

    ~H"""
    <div id="task-board" class="mt-6 min-w-0">
      <h2 id="task-board-heading" tabindex="-1" class="text-xl font-semibold">Tasks</h2>
      <div
        class="mt-4 max-w-full overflow-x-auto overscroll-x-contain pb-3 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400"
        tabindex="0"
        role="region"
        aria-label="Task board"
      >
        <div id="spec-entries" class="grid min-w-[73rem] grid-cols-5 gap-3">
          <section
            :for={{id, title, entries} <- @columns}
            id={"column-#{id}"}
            aria-labelledby={"heading-#{id}"}
            class="min-w-0 rounded-lg border border-zinc-800 bg-zinc-900/40 p-3"
          >
            <h3
              id={"heading-#{id}"}
              class="flex items-center justify-between gap-2 text-sm font-semibold"
            >
              {title}<span class="text-xs font-normal tabular-nums text-zinc-400">{length(entries)}</span>
            </h3>
            <p :if={entries == []} class="mt-5 text-sm text-zinc-400">No tasks</p>
            <ul class="mt-3 space-y-3">
              <li :for={entry <- entries} id={"spec-#{entry.id}"} data-task-card={entry.task_id}>
                <.link
                  id={"task-#{entry.task_id}"}
                  patch={~p"/projects/#{@project_id}/tasks/#{entry.task_id}"}
                  class="block rounded-md border border-zinc-800 bg-zinc-950 p-3 hover:border-zinc-600 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400"
                >
                  <h4 class="break-words text-sm font-semibold">{entry.title}</h4>
                  <div class="mt-2 flex flex-wrap gap-2 text-xs">
                    <span class="rounded bg-zinc-800 px-2 py-1 text-zinc-300">{state_label(
                      entry.state
                    )}</span>
                    <span :if={entry.missing} class="rounded bg-amber-950 px-2 py-1 text-amber-300">File missing</span>
                  </div>
                  <p class="mt-3 break-all font-mono text-xs text-zinc-400">{entry.relative_path}</p>
                  <p class="mt-2 text-xs text-zinc-400">
                    Source revision {entry.latest_revision} · Task snapshot {entry.task_revision}
                  </p>
                  <p
                    :if={entry.latest_revision != entry.task_revision}
                    class="mt-2 text-xs text-amber-300"
                  >
                    Source changed; the task keeps its saved snapshot.
                  </p>
                </.link>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </div>
    """
  end

  attr :project_id, :integer, required: true
  attr :selection, :any, required: true
  attr :details, :any, default: nil
  attr :loading, :boolean, default: false
  attr :error, :any, default: nil
  slot :run_panel
  slot :source_actions

  def drawer(assigns) do
    requested =
      case assigns.selection do
        {_, revision} -> revision
        _ -> nil
      end

    desired = requested || (assigns.details && assigns.details.pinned_revision.number)
    source_ready = assigns.details && desired == assigns.details.selected_revision.number

    return_focus =
      case assigns.selection do
        {task_id, _} -> "task-#{task_id}"
        _ -> "task-board-heading"
      end

    assigns =
      assign(assigns,
        desired: desired,
        source_ready: source_ready,
        return_focus: return_focus
      )

    ~H"""
    <dialog
      id="task-drawer"
      phx-hook="TaskDrawer"
      phx-mounted={JS.ignore_attributes("open")}
      data-return-focus={@return_focus}
      data-revision={@desired}
      aria-labelledby="task-drawer-title"
      class="fixed inset-y-0 right-0 left-auto m-0 h-dvh max-h-none w-full max-w-2xl overflow-y-auto border-l border-zinc-800 bg-zinc-950 p-0 text-zinc-100 backdrop:bg-black/60"
    >
      <div class="sticky top-0 z-10 flex items-start justify-between gap-4 border-b border-zinc-800 bg-zinc-950 px-5 py-4">
        <h2 id="task-drawer-title" class="min-w-0 break-words text-xl font-semibold">
          {if @details, do: @details.task.title, else: "Task details"}
        </h2>
        <.link
          id="task-drawer-close"
          data-drawer-close
          patch={~p"/projects/#{@project_id}"}
          autofocus
          class="shrink-0 rounded px-2 py-1 text-sm text-zinc-300 hover:bg-zinc-800 focus-visible:outline-2 focus-visible:outline-emerald-400"
        >Close</.link>
      </div>
      <div class="space-y-6 px-5 py-5">
        <p :if={@loading && !@source_ready} role="status" class="text-sm text-zinc-400">
          Loading task details…
        </p>
        <p
          :if={@error}
          id="task-drawer-error"
          role="alert"
          class="rounded border border-red-900 px-3 py-2 text-sm text-red-300"
        >
          {if @error == :not_found,
            do: "Task or revision not found in this project.",
            else: "Task details could not be refreshed. Try opening this task again."}
        </p>
        <div :if={@details} class="space-y-6">
          <div class="flex flex-wrap gap-2 text-sm">
            <span class="rounded bg-zinc-800 px-2 py-1">{state_label(@details.task.state)}</span>
            <span :if={@details.spec.missing} class="rounded bg-amber-950 px-2 py-1 text-amber-300">File missing</span>
          </div>
          <p
            :if={@details.task.attention_reason}
            id="task-attention"
            class="break-words rounded border border-amber-900 px-3 py-2 text-sm text-amber-200"
          >
            {@details.task.attention_reason}
          </p>
          <dl class="grid gap-4 text-sm sm:grid-cols-2">
            <div>
              <dt class="text-zinc-400">Task snapshot</dt><dd id="task-snapshot" class="mt-1">
                Revision {@details.pinned_revision.number}
              </dd><dd class="mt-1 break-all font-mono text-xs text-zinc-400">
                {@details.pinned_revision.relative_path}
              </dd>
            </div>
            <div>
              <dt class="text-zinc-400">Latest source</dt><dd id="task-latest-revision" class="mt-1">
                Revision {@details.latest_revision.number}
              </dd><dd class="mt-1 break-all font-mono text-xs text-zinc-400">
                {@details.latest_revision.relative_path}
              </dd>
            </div>
          </dl>
          <p
            :if={@details.latest_revision.id != @details.pinned_revision.id}
            class="text-sm text-amber-300"
          >
            Source changed; the task keeps its saved snapshot.
          </p>
          {render_slot(@run_panel)}
          <section aria-labelledby="task-source-heading">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h3 id="task-source-heading" class="font-semibold">Source</h3>
              <form id="task-revision-form" phx-change="select_revision">
                <label for="task-revision" class="mr-2 text-sm text-zinc-400">Revision</label>
                <select
                  id="task-revision"
                  name="revision"
                  class="rounded border border-zinc-700 bg-zinc-900 px-2 py-1 text-sm focus-visible:outline-2 focus-visible:outline-emerald-400"
                >
                  <option
                    :for={revision <- @details.revisions}
                    value={revision.number}
                    selected={revision.number == @desired}
                  >
                    Revision {revision.number}{if revision.number == @details.pinned_revision.number,
                      do: " · task snapshot"}
                  </option>
                </select>
              </form>
            </div>
            {render_slot(@source_actions)}
            <pre
              :if={@source_ready}
              id="task-source"
              class="mt-3 whitespace-pre-wrap break-words rounded-md border border-zinc-800 bg-zinc-900/40 p-4 font-mono text-sm leading-6 text-zinc-200"
            >{@details.selected_revision.original_text}</pre>
          </section>
          <section aria-labelledby="task-events-heading">
            <h3 id="task-events-heading" class="font-semibold">Recent events</h3>
            <p class="mt-1 text-xs text-zinc-400">Latest 50 task transitions</p>
            <p :if={@details.events == []} class="mt-3 text-sm text-zinc-400">No task events yet.</p>
            <ol id="task-events" class="mt-3 divide-y divide-zinc-800">
              <li :for={event <- @details.events} class="py-3 text-sm">
                <p>
                  Version {event.version} · {state_label(event.from_state)} → {state_label(
                    event.to_state
                  )}
                </p>
                <p :if={event.action == "adopt_revision"} class="mt-1 text-zinc-300">
                  Source revision {BossWeb.TaskRevision.number(@details, event.spec_revision_id)} → {BossWeb.TaskRevision.number(
                    @details,
                    event.target_spec_revision_id
                  )} adopted.
                </p>
                <p :if={event.reason} class="mt-1 break-words text-zinc-300">{event.reason}</p>
                <time
                  datetime={DateTime.to_iso8601(event.inserted_at)}
                  class="mt-1 block text-xs text-zinc-400"
                >{Calendar.strftime(event.inserted_at, "%Y-%m-%d %H:%M UTC")}</time>
              </li>
            </ol>
          </section>
        </div>
      </div>
    </dialog>
    """
  end

  defp column(state) when state in ~w(new planning ready), do: "backlog"
  defp column(state) when state in ~w(implementing testing integrating), do: "in-progress"
  defp column(state) when state in ~w(reviewing approved), do: "review"
  defp column("done"), do: "done"
  defp column(_), do: "needs-attention"

  defp state_label(state) when is_binary(state),
    do: state |> String.replace("_", " ") |> String.capitalize()

  defp state_label(_), do: "Unknown"
end
