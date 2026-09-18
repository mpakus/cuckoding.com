defmodule CuckodingWeb.BoardLive do
  use CuckodingWeb, :live_view

  alias Cuckoding.Workflows

  @states ~w(draft ready running waiting paused hibernated blocked done failed cancelled archived)

  @impl true
  def mount(%{"id" => board_id}, _session, socket) do
    case Workflows.get_board(board_id) do
      nil ->
        raise Phoenix.Router.NoRouteError, conn: socket, router: CuckodingWeb.Router

      board ->
        {:ok,
         assign(socket,
           page_title: board.name,
           board: board,
           states: @states,
           filters: %{"q" => "", "state" => "all"},
           tasks: [],
           notice: nil,
           error: nil
         )}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      "q" => params |> Map.get("q", "") |> String.trim(),
      "state" => normalize_state(Map.get(params, "state", "all"))
    }

    {:noreply, socket |> assign(:filters, filters) |> load_tasks()}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    query = %{
      q: filters |> Map.get("q", "") |> String.trim(),
      state: normalize_state(Map.get(filters, "state", "all"))
    }

    {:noreply, push_patch(socket, to: ~p"/boards/#{socket.assigns.board.id}?#{query}")}
  end

  def handle_event("transition-task", params, socket) do
    task_id = params["id"] || params["_id"]
    target = params["to"]

    case Workflows.get_task(task_id) do
      %{board_id: board_id} = task when board_id == socket.assigns.board.id ->
        transition(socket, task, target)

      _task ->
        {:noreply, assign(socket, error: "Task is not on this board.", notice: nil)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app>
      <section aria-labelledby="board-heading" class="space-y-8">
        <header class="space-y-2">
          <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">Board</p>
          <h1 id="board-heading" class="text-3xl font-semibold tracking-tight text-slate-950">
            {@board.name}
          </h1>
          <p :if={@board.description} class="max-w-3xl text-slate-700">{@board.description}</p>
        </header>

        <form
          id="task-filters"
          phx-change="filter"
          aria-label="Filter tasks"
          class="grid gap-4 sm:grid-cols-2"
        >
          <label class="grid gap-1 text-sm font-medium text-slate-800">
            Search tasks
            <input
              type="search"
              name="filters[q]"
              value={@filters["q"]}
              phx-debounce="200"
              class="min-h-10 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
            />
          </label>
          <label class="grid gap-1 text-sm font-medium text-slate-800">
            State
            <select
              name="filters[state]"
              class="min-h-10 rounded-md border border-slate-400 bg-white px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
            >
              <option value="all" selected={@filters["state"] == "all"}>All states</option>
              <option :for={state <- @states} value={state} selected={@filters["state"] == state}>
                {state_label(state)}
              </option>
            </select>
          </label>
        </form>

        <p id="board-status" role="status" aria-live="polite" class="text-sm text-emerald-900">
          {@notice || ""}
        </p>
        <p :if={@error} id="board-error" role="alert" class="text-sm font-medium text-red-800">
          {@error}
        </p>

        <div
          id="board-kanban"
          phx-hook="TaskBoard"
          class="grid gap-4 md:grid-cols-2 xl:grid-cols-3"
          aria-label="Task board"
        >
          <section
            :for={state <- @states}
            id={"column-#{state}"}
            data-drop-state={state}
            aria-labelledby={"column-#{state}-heading"}
            class="min-w-0 rounded-lg border border-slate-300 bg-slate-50 p-4"
          >
            <h2 id={"column-#{state}-heading"} class="font-semibold text-slate-950">
              {state_label(state)}
              <span class="font-normal text-slate-600">({count_tasks(@tasks, state)})</span>
            </h2>
            <div data-task-list class="mt-3 space-y-3">
              <article
                :for={task <- tasks_in(@tasks, state)}
                id={"task-#{task.id}"}
                data-task-id={task.id}
                data-allowed-targets={Enum.join(Workflows.allowed_task_transitions(task), ",")}
                draggable={
                  if(Workflows.allowed_task_transitions(task) != [], do: "true", else: "false")
                }
                aria-label={"#{task.title}, #{state_label(task.state)}"}
                class="space-y-3 rounded-md border border-slate-300 bg-white p-4 shadow-sm"
              >
                <div>
                  <h3 class="font-medium text-slate-950">
                    <.link
                      navigate={~p"/boards/#{@board.id}/tasks/#{task.id}"}
                      class="rounded underline decoration-slate-400 underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2"
                    >
                      {task.title}
                    </.link>
                  </h3>
                  <p class="mt-1 text-sm text-slate-700">Priority {task.priority}</p>
                  <p class="text-sm text-slate-700">Knowledge: 0 linked</p>
                  <p :if={task.wait_reason} class="text-sm font-medium text-amber-900">
                    Waiting: {task.wait_reason}
                  </p>
                </div>

                <form
                  :if={Workflows.allowed_task_transitions(task) != []}
                  id={"task-#{task.id}-transition"}
                  phx-submit="transition-task"
                  class="grid gap-2"
                >
                  <input type="hidden" name="_id" value={task.id} />
                  <label for={"task-#{task.id}-target"} class="text-sm font-medium text-slate-800">
                    Move task
                  </label>
                  <div class="flex flex-wrap gap-2">
                    <select
                      id={"task-#{task.id}-target"}
                      name="to"
                      class="min-h-10 flex-1 rounded-md border border-slate-400 bg-white px-2 focus-visible:outline-2 focus-visible:outline-offset-2"
                    >
                      <option :for={target <- Workflows.allowed_task_transitions(task)} value={target}>
                        {state_label(target)}
                      </option>
                    </select>
                    <button
                      type="submit"
                      class="min-h-10 rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
                    >
                      Move
                    </button>
                  </div>
                </form>
              </article>
            </div>
          </section>
        </div>

        <p :if={@tasks == []} class="rounded-md border border-slate-300 p-5 text-slate-700">
          No tasks match these filters.
        </p>
      </section>
    </Layouts.app>
    """
  end

  defp transition(socket, task, target) do
    key =
      "ui:task:#{task.id}:#{task.state}:#{target}:#{DateTime.to_unix(task.updated_at, :microsecond)}"

    case Workflows.transition_task(task.id, target, key) do
      {:ok, %{result: %{"outcome" => "transitioned"}}} ->
        {:noreply,
         socket
         |> assign(notice: "Moved #{task.title} to #{state_label(target)}.", error: nil)
         |> load_tasks()}

      {:ok, %{result: %{"outcome" => "rejected", "reason" => reason}}} ->
        {:noreply,
         socket
         |> assign(
           error: "Move rejected: #{reason_label(reason)}.",
           notice: nil
         )
         |> load_tasks()}

      {:error, reason} ->
        {:noreply, assign(socket, error: "Move failed: #{reason_label(reason)}.", notice: nil)}
    end
  end

  defp load_tasks(socket) do
    tasks = Workflows.list_tasks(socket.assigns.board.id)
    q = String.downcase(socket.assigns.filters["q"])
    state = socket.assigns.filters["state"]

    filtered =
      Enum.filter(tasks, fn task ->
        (q == "" or String.contains?(String.downcase(task.title), q)) and
          (state == "all" or task.state == state)
      end)

    assign(socket, :tasks, filtered)
  end

  defp normalize_state(state) when state in ["all" | @states], do: state
  defp normalize_state(_state), do: "all"
  defp tasks_in(tasks, state), do: Enum.filter(tasks, &(&1.state == state))
  defp count_tasks(tasks, state), do: Enum.count(tasks, &(&1.state == state))
  defp state_label(state), do: state |> String.replace("_", " ") |> String.capitalize()
  defp reason_label(reason) when is_atom(reason), do: reason |> Atom.to_string() |> reason_label()
  defp reason_label(reason), do: reason |> to_string() |> String.replace("_", " ")
end
