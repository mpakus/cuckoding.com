defmodule CuckodingWeb.TaskLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.PolicyComponents

  alias Cuckoding.Execution
  alias Cuckoding.ProjectWorkflow
  alias Cuckoding.Workflows

  @impl true
  def mount(%{"board_id" => board_id, "id" => task_id}, _session, socket) do
    with %{id: ^board_id} = board <- Workflows.get_board(board_id),
         %{board_id: ^board_id} = task <- Workflows.get_task(task_id) do
      {:ok,
       assign(socket,
         page_title: task.title,
         board: board,
         task: task,
         unsaved_changes: false,
         runs: Execution.list_runs(task.id),
         notice: nil,
         error: nil
       )}
    else
      _missing -> raise Phoenix.Router.NoRouteError, conn: socket, router: CuckodingWeb.Router
    end
  end

  @impl true
  def handle_event("edit", _params, socket),
    do: {:noreply, assign(socket, unsaved_changes: true)}

  def handle_event(action, _params, %{assigns: %{unsaved_changes: true}} = socket)
      when action in ["mark-ready", "prepare-run"] do
    {:noreply,
     assign(socket,
       error: "Save your task changes before marking it Ready or preparing a run.",
       notice: nil
     )}
  end

  def handle_event("save", %{"task" => attrs}, socket) do
    case Workflows.update_task(socket.assigns.task.id, attrs) do
      {:ok, task} ->
        {:noreply,
         assign(socket,
           task: task,
           unsaved_changes: false,
           page_title: task.title,
           notice: "Task details saved.",
           error: nil
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, error: changeset_error(changeset), notice: nil)}

      {:error, :task_not_editable} ->
        {:noreply,
         assign(socket, error: "Task details can be edited only in Draft or Ready.", notice: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: "Save failed: #{inspect(reason)}", notice: nil)}
    end
  end

  def handle_event("mark-ready", _params, socket) do
    key =
      "ui:task:#{socket.assigns.task.id}:ready:#{DateTime.to_unix(socket.assigns.task.updated_at, :microsecond)}"

    case Workflows.transition_task(socket.assigns.task.id, "ready", key) do
      {:ok, %{result: %{"outcome" => "transitioned"}}} ->
        {:noreply,
         reload(socket, "Task is Ready. Choose Prepare run, then start it on the run page.")}

      {:ok, %{result: %{"reason" => reason}}} ->
        {:noreply,
         assign(socket, error: "Task could not be marked Ready: #{label(reason)}.", notice: nil)}

      {:error, reason} ->
        {:noreply,
         assign(socket, error: "Task could not be marked Ready: #{label(reason)}.", notice: nil)}
    end
  end

  def handle_event("prepare-run", _params, socket) do
    case ProjectWorkflow.prepare_task(socket.assigns.task.id) do
      {:ok, %{run: run}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Run prepared in an isolated worktree.")
         |> push_navigate(to: ~p"/runs/#{run.id}")}

      {:error, reason} ->
        {:noreply, socket |> reload(nil) |> assign(error: prepare_error(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="projects">
      <article aria-labelledby="task-heading" class="max-w-3xl space-y-8">
        <.link
          navigate={~p"/boards/#{@board.id}"}
          class="inline-flex min-h-10 items-center rounded underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          Back to {@board.name}
        </.link>

        <header class="space-y-2">
          <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">
            {state_label(@task.state)} task
          </p>
          <h1 id="task-heading" class="text-3xl font-semibold tracking-tight text-slate-950">
            {@task.title}
          </h1>
          <p class="text-slate-700">
            Priority {@task.priority} · Higher numbers are considered first
          </p>
        </header>

        <p id="task-status" role="status" aria-live="polite" class="text-sm text-emerald-900">
          {@notice || ""}
        </p>
        <p :if={@error} id="task-error" role="alert" class="text-sm font-medium text-red-800">
          {@error}
        </p>

        <section
          aria-labelledby="task-run-heading"
          class="space-y-4 rounded-xl border border-slate-200 bg-white p-5"
        >
          <div>
            <h2 id="task-run-heading" class="text-xl font-semibold text-slate-950">Next step</h2>
            <p class="mt-1 text-sm leading-6 text-slate-700">
              {next_step(@task, @runs)}
            </p>
          </div>
          <button
            :if={@task.state == "draft"}
            id="mark-task-ready"
            type="button"
            phx-click="mark-ready"
            phx-disable-with="Marking Ready…"
            class="min-h-11 rounded-md border border-slate-400 bg-white px-5 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Mark Ready
          </button>
          <button
            :if={@task.state == "ready" and !queued_run?(@runs)}
            id="prepare-task-run"
            type="button"
            phx-click="prepare-run"
            phx-disable-with="Preparing run…"
            class="min-h-11 rounded-md bg-slate-950 px-5 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Prepare run
          </button>
          <p :if={@task.state == "ready" and queued_run?(@runs)} class="text-sm text-slate-700">
            A run is prepared and waiting for authentication.
          </p>
          <.link
            :for={run <- Enum.filter(@runs, &(&1.state == "queued"))}
            navigate={~p"/runs/#{run.id}"}
            class="inline-flex min-h-11 items-center rounded-md bg-slate-950 px-5 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Open prepared run and start
          </.link>
          <.link
            :if={@task.active_run_id && !queued_run?(@runs)}
            navigate={~p"/runs/#{@task.active_run_id}"}
            class="inline-flex min-h-11 items-center rounded-md bg-slate-950 px-4 text-sm font-medium text-white"
          >Open current run</.link>
        </section>

        <.host_runner_notice />

        <form
          :if={editable?(@task)}
          id="task-edit"
          phx-change="edit"
          phx-submit="save"
          class="space-y-5"
        >
          <p :if={@unsaved_changes} role="status" class="text-sm text-slate-700">
            Unsaved changes. Save this task before leaving or starting work.
          </p>
          <label class="grid gap-1 font-medium text-slate-800">
            Title
            <input
              type="text"
              name="task[title]"
              value={@task.title}
              required
              maxlength="200"
              aria-invalid={if(@error, do: "true", else: "false")}
              aria-describedby={if(@error, do: "task-error")}
              class="min-h-10 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
            />
          </label>

          <label class="grid gap-1 font-medium text-slate-800">
            Description <textarea
              name="task[description]"
              rows="6"
              maxlength="10000"
              class="rounded-md border border-slate-400 px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2"
            >{@task.description}</textarea>
          </label>

          <label class="grid max-w-40 gap-1 font-medium text-slate-800">
            Priority
            <input
              type="number"
              name="task[priority]"
              value={@task.priority}
              min="-100"
              max="100"
              required
              class="min-h-10 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
            />
          </label>

          <button
            type="submit"
            phx-disable-with="Saving task…"
            class="min-h-10 rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Save task
          </button>
        </form>

        <p :if={!editable?(@task)} class="rounded-md border border-slate-300 p-4 text-slate-700">
          Task details can be edited only in Draft or Ready.
        </p>
        <section :if={!editable?(@task)} aria-labelledby="task-description-heading" class="space-y-3">
          <h2 id="task-description-heading" class="text-xl font-semibold">Task details</h2>
          <p class="whitespace-pre-wrap text-slate-700">
            {@task.description || "No details were added to this task."}
          </p>
        </section>

        <section aria-labelledby="run-history-heading" class="space-y-3">
          <h2 id="run-history-heading" class="text-xl font-semibold text-slate-950">Run history</h2>
          <p :if={@runs == []} class="text-sm text-slate-700">No runs prepared yet.</p>
          <ul
            :if={@runs != []}
            class="divide-y divide-slate-200 rounded-lg border border-slate-300 bg-white"
          >
            <li
              :for={run <- @runs}
              class="flex flex-wrap items-center justify-between gap-3 px-4 py-3"
            >
              <div>
                <p class="font-medium text-slate-950">Run {run.sequence}</p>
                <p class="text-sm text-slate-600">
                  {state_label(run.state)} · <code>{run.branch}</code>
                </p>
              </div>
              <.link
                navigate={~p"/runs/#{run.id}"}
                class="inline-flex min-h-10 items-center rounded-md border border-slate-400 px-4 text-sm font-medium focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                Open run
              </.link>
            </li>
          </ul>
        </section>
      </article>
    </Layouts.app>
    """
  end

  defp editable?(task), do: task.state in ["draft", "ready"]

  defp next_step(%{state: "draft"}, _runs),
    do:
      "Write the outcome and acceptance details below, save the task, then mark it Ready. Nothing starts yet."

  defp next_step(%{state: "ready"}, runs) do
    if queued_run?(runs),
      do: "Your run is prepared. Open it to check agent authentication and start the workflow.",
      else:
        "Ready does not start automatically. Prepare run creates a separate Git worktree; you check authentication and start on the next page."
  end

  defp next_step(%{state: state}, _runs)
       when state in ["done", "archived", "cancelled", "failed"],
       do:
         "Review the run history below for results and errors. Return to the board for available task actions."

  defp next_step(_task, _runs),
    do: "Open the current run for live progress, required approvals, and available controls."

  defp queued_run?(runs), do: Enum.any?(runs, &(&1.state == "queued"))
  defp state_label(state), do: state |> String.replace("_", " ") |> String.capitalize()

  defp reload(socket, notice) do
    task = Workflows.get_task(socket.assigns.task.id)

    assign(socket,
      task: task,
      page_title: task.title,
      runs: Execution.list_runs(task.id),
      notice: notice,
      error: nil
    )
  end

  defp prepare_error(:runtime_setup_only),
    do:
      "A board role uses a setup-only runtime. Assign Codex, Claude Code, or Cursor Agent, then create a new board snapshot."

  defp prepare_error(:roles_not_configured),
    do: "This board does not have all required role assignments."

  defp prepare_error(:dirty_repository),
    do: "Commit or stash changes in the project repository before preparing a run."

  defp prepare_error(:run_already_prepared), do: "A queued run is already prepared for this task."
  defp prepare_error(:task_not_ready), do: "Only a Ready task can prepare a run."
  defp prepare_error(reason), do: "Run preparation failed: #{label(reason)}."

  defp label(reason) when is_atom(reason), do: reason |> Atom.to_string() |> label()
  defp label(reason), do: reason |> to_string() |> String.replace("_", " ")

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _options}} -> "#{field} #{message}" end)
    |> then(&"Task could not be saved: #{&1}.")
  end
end
