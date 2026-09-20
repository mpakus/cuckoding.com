defmodule CuckodingWeb.BoardLive do
  use CuckodingWeb, :live_view

  alias Cuckoding.Projects
  alias Cuckoding.ProjectWorkflow
  alias Cuckoding.Workflows

  @states ~w(draft ready running waiting paused hibernated blocked done failed cancelled archived)

  @impl true
  def mount(%{"id" => board_id}, _session, socket) do
    case Workflows.get_board(board_id) do
      nil ->
        raise Phoenix.Router.NoRouteError, conn: socket, router: CuckodingWeb.Router

      board ->
        project = Projects.get_project(board.project_id)
        if connected?(socket), do: Cuckoding.ActivityStream.subscribe(:all)

        {:ok,
         assign(socket,
           page_title: board.name,
           board: board,
           project: project,
           states: @states,
           show_all_states: false,
           refresh_pending: false,
           filters: %{"q" => "", "state" => "all"},
           task_form: %{"title" => "", "description" => "", "priority" => "0"},
           intake_form: %{"prompt" => "", "role_key" => "spec_writer"},
           agent_roles: Workflows.list_agent_roles(board.id),
           tasks: [],
           intake_error: nil,
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
  def handle_info({:activity_event, _stream_id, _sequence}, socket) do
    unless socket.assigns.refresh_pending, do: Process.send_after(self(), :refresh_board, 250)
    {:noreply, assign(socket, refresh_pending: true)}
  end

  def handle_info(:refresh_board, socket) do
    {:noreply, socket |> assign(refresh_pending: false) |> load_tasks()}
  end

  @impl true
  def handle_event("toggle-states", _params, socket),
    do: {:noreply, assign(socket, show_all_states: !socket.assigns.show_all_states)}

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

  def handle_event("create-task", %{"task" => attrs}, socket) do
    case ProjectWorkflow.create_task(socket.assigns.board.id, attrs) do
      {:ok, task} ->
        {:noreply,
         socket
         |> assign(
           task_form: %{"title" => "", "description" => "", "priority" => "0"},
           notice: "Created #{task.title} in Draft.",
           error: nil
         )
         |> load_tasks()}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           task_form: Map.merge(socket.assigns.task_form, attrs),
           notice: nil,
           error: task_error(reason)
         )}
    end
  end

  def handle_event("create-task-intake", %{"intake" => attrs}, socket) do
    case ProjectWorkflow.create_task_intake(socket.assigns.board.id, attrs) do
      {:ok, %{run: run}} ->
        {:noreply,
         socket
         |> assign(:intake_error, nil)
         |> put_flash(
           :info,
           "Planning run created. Verify agent authentication, then start project analysis."
         )
         |> push_navigate(to: ~p"/runs/#{run.id}")}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           intake_form: Map.merge(socket.assigns.intake_form, attrs),
           intake_error: intake_error(reason)
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="projects">
      <section aria-labelledby="board-heading" class="space-y-8">
        <header class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div class="space-y-2">
            <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">
              {@project.name} · Board
            </p>
            <h1 id="board-heading" class="text-3xl font-semibold tracking-tight text-slate-950">
              {@board.name}
            </h1>
            <p :if={@board.description} class="max-w-3xl text-slate-700">{@board.description}</p>
          </div>
          <nav aria-label="Board links" class="flex flex-wrap gap-2">
            <.link
              navigate={~p"/projects/#{@project.id}/edit"}
              class="inline-flex min-h-10 items-center rounded-md border border-slate-400 bg-white px-4 text-sm font-medium focus-visible:outline-2 focus-visible:outline-offset-2"
            >
              Project settings
            </.link>
            <.link
              navigate={~p"/agents"}
              class="inline-flex min-h-10 items-center rounded-md border border-slate-400 bg-white px-4 text-sm font-medium focus-visible:outline-2 focus-visible:outline-offset-2"
            >
              Monitor agents
            </.link>
          </nav>
        </header>

        <details
          id="new-task-panel"
          open={@error != nil}
          aria-labelledby="new-task-heading"
          class="rounded-xl border border-slate-200 bg-white p-5"
        >
          <summary id="new-task-heading" class="min-h-6 font-semibold text-slate-950">
            Add a task
          </summary>
          <p class="mt-1 text-sm text-slate-700">
            New tasks start in Draft so you can refine them before marking them Ready.
          </p>
          <form id="create-task-form" phx-submit="create-task" class="mt-4 grid gap-4 sm:grid-cols-4">
            <label class="grid gap-2 text-sm font-medium text-slate-800 sm:col-span-3">
              Title
              <input
                name="task[title]"
                value={@task_form["title"]}
                required
                maxlength="200"
                placeholder="Describe a concrete outcome"
                class="min-h-11 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
              />
            </label>
            <label class="grid gap-2 text-sm font-medium text-slate-800">
              Priority
              <input
                type="number"
                name="task[priority]"
                value={@task_form["priority"]}
                min="-100"
                max="100"
                required
                class="min-h-11 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
              />
            </label>
            <label class="grid gap-2 text-sm font-medium text-slate-800 sm:col-span-4">
              Details <textarea
                name="task[description]"
                rows="4"
                maxlength="10000"
                class="rounded-md border border-slate-400 px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2"
              >{@task_form["description"]}</textarea>
            </label>
            <div class="sm:col-span-4">
              <button
                phx-disable-with="Creating task…"
                class="min-h-11 rounded-md bg-slate-950 px-5 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                Create draft task
              </button>
            </div>
          </form>
        </details>

        <details
          id="agent-task-intake"
          open={@intake_error != nil}
          aria-labelledby="agent-task-intake-heading"
          class="rounded-xl border border-slate-200 bg-white p-5"
        >
          <summary id="agent-task-intake-heading" class="min-h-6 font-semibold text-slate-950">
            Ask an agent to plan tasks
          </summary>
          <p class="mt-1 max-w-3xl text-sm text-slate-700">
            The selected role reads the project in an isolated, network-denied planning run. You review every proposal before it becomes a Draft task.
          </p>
          <form id="task-intake-form" phx-submit="create-task-intake" class="mt-4 grid gap-4">
            <label class="grid gap-2 text-sm font-medium text-slate-800">
              Agent role
              <select
                name="intake[role_key]"
                required
                class="min-h-11 rounded-md border border-slate-400 bg-white px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                <option
                  :for={role <- @agent_roles}
                  value={role.role_key}
                  selected={@intake_form["role_key"] == role.role_key}
                >
                  {role_label(role)}
                </option>
              </select>
            </label>
            <label class="grid gap-2 text-sm font-medium text-slate-800">
              Planning prompt <textarea
                name="intake[prompt]"
                rows="5"
                required
                maxlength="10000"
                placeholder="Analyze docs/, including PLAN.md and tasks.md, then propose implementation tasks with source evidence."
                class="rounded-md border border-slate-400 px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2"
              >{@intake_form["prompt"]}</textarea>
            </label>
            <div>
              <button
                type="submit"
                disabled={@agent_roles == []}
                aria-describedby={
                  if(@intake_error,
                    do: "task-intake-submit-status task-intake-error",
                    else: "task-intake-submit-status"
                  )
                }
                phx-disable-with="Creating planning run…"
                class="min-h-11 rounded-md bg-slate-950 px-5 font-medium text-white disabled:cursor-not-allowed disabled:opacity-50 phx-submit-loading:cursor-wait focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                Create planning run
              </button>
              <span
                id="task-intake-submit-status"
                role="status"
                aria-live="polite"
                aria-atomic="true"
                class="ml-3 hidden text-sm text-slate-700 phx-submit-loading:inline"
              >
                Creating the planning run and isolated worktree…
              </span>
            </div>
            <p :if={@agent_roles == []} class="text-sm font-medium text-amber-900">
              This board has no assigned agent roles. Save roles in Project settings, then create a new board to use them.
            </p>
            <p
              :if={@intake_error}
              id="task-intake-error"
              role="alert"
              class="text-sm font-medium text-red-800"
            >
              {@intake_error}
            </p>
          </form>
        </details>

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

        <div class="flex flex-wrap items-center justify-between gap-3 text-sm text-slate-700">
          <p>Cards update live. Ready means you can start a task—not that an agent has started.</p>
          <button
            :if={@filters["state"] == "all"}
            id="toggle-board-states"
            type="button"
            phx-click="toggle-states"
            aria-pressed={to_string(@show_all_states)}
            class="min-h-11 rounded-md border border-slate-400 bg-white px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            {if @show_all_states, do: "Hide unused states", else: "Show all states"}
          </button>
          <.link
            :if={@filters["q"] != "" or @filters["state"] != "all"}
            patch={~p"/boards/#{@board.id}"}
            class="inline-flex min-h-11 items-center rounded px-3 underline"
          >Clear filters</.link>
        </div>

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
            :for={state <- visible_states(@tasks, @filters, @show_all_states)}
            id={"column-#{state}"}
            data-drop-state={state}
            aria-labelledby={"column-#{state}-heading"}
            class="min-w-0 rounded-lg border border-slate-300 bg-slate-50 p-4"
          >
            <h2 id={"column-#{state}-heading"} class="font-semibold text-slate-950">
              {state_label(state)}
              <span class="font-normal text-slate-600">({count_tasks(@tasks, state)})</span>
            </h2>
            <p :if={state == "ready"} class="mt-2 text-sm text-slate-700">
              Ready tasks do not start automatically. Set up a run, then verify authentication and start it.
            </p>
            <p :if={count_tasks(@tasks, state) == 0} class="mt-3 text-sm text-slate-600">
              No {String.downcase(state_label(state))} tasks.
            </p>
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
                  <p :if={task.wait_reason} class="text-sm font-medium text-amber-900">
                    Waiting: {task.wait_reason}
                  </p>
                </div>

                <.link
                  :if={task.state == "ready"}
                  id={"start-task-#{task.id}"}
                  navigate={~p"/boards/#{@board.id}/tasks/#{task.id}"}
                  class="inline-flex min-h-11 items-center rounded-md bg-slate-950 px-4 text-sm font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  Set up and start
                </.link>

                <.link
                  :if={task.active_run_id}
                  navigate={~p"/runs/#{task.active_run_id}"}
                  class="inline-flex min-h-11 items-center rounded px-3 text-sm font-medium underline"
                >View run</.link>

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
                      required
                      class="min-h-10 flex-1 rounded-md border border-slate-400 bg-white px-2 focus-visible:outline-2 focus-visible:outline-offset-2"
                    >
                      <option value="" selected disabled>Choose a state</option>
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
          {if @filters["q"] != "" or @filters["state"] != "all",
            do: "No tasks match these filters. Clear filters to see the board.",
            else:
              "No tasks yet. Open Add a task to write one, or Ask an agent to plan tasks from your project files."}
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
  defp visible_states(_tasks, %{"state" => state}, _all?) when state != "all", do: [state]
  defp visible_states(_tasks, _filters, true), do: @states

  defp visible_states(tasks, _filters, false) do
    occupied = MapSet.new(tasks, & &1.state)

    Enum.filter(
      @states,
      &(&1 in ~w(draft ready running waiting done) or MapSet.member?(occupied, &1))
    )
  end

  defp tasks_in(tasks, state), do: Enum.filter(tasks, &(&1.state == state))
  defp count_tasks(tasks, state), do: Enum.count(tasks, &(&1.state == state))
  defp state_label(state), do: state |> String.replace("_", " ") |> String.capitalize()
  defp role_label(role), do: role.settings_json["role_name"] || state_label(role.role_key)
  defp reason_label(reason) when is_atom(reason), do: reason |> Atom.to_string() |> reason_label()
  defp reason_label(reason), do: reason |> to_string() |> String.replace("_", " ")

  defp task_error(:task_title_required), do: "Enter a task title of 200 characters or fewer."

  defp task_error(:invalid_task_description),
    do: "Task details must be 10,000 characters or fewer."

  defp task_error(:invalid_number), do: "Priority must be between -100 and 100."

  defp task_error(%Ecto.Changeset{} = changeset),
    do: "Task could not be created: #{inspect(changeset.errors)}"

  defp task_error(reason), do: "Task could not be created: #{inspect(reason)}"

  defp intake_error(:intake_prompt_required),
    do: "Enter a planning prompt of 10,000 characters or fewer."

  defp intake_error(:intake_role_required), do: "Choose an assigned agent role."
  defp intake_error(:policy_not_trusted), do: "Review and trust the project policy first."

  defp intake_error(:dirty_repository),
    do:
      "Your project has uncommitted changes. Commit or stash the files you want to keep, then create the planning run again. Nothing has been discarded."

  defp intake_error(:runtime_setup_only),
    do:
      "This role uses a runtime that cannot run tasks yet. Save a Codex, Claude Code, or Cursor Agent assignment in Project settings, then create a new board to use it."

  defp intake_error({:intake_transition_rejected, reason}),
    do: "The planning task could not become Ready: #{reason_label(reason)}."

  defp intake_error(reason),
    do: "The planning run could not be created: #{reason_label(reason)}."
end
