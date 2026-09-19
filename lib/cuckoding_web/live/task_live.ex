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
         runs: Execution.list_runs(task.id),
         notice: nil,
         error: nil
       )}
    else
      _missing -> raise Phoenix.Router.NoRouteError, conn: socket, router: CuckodingWeb.Router
    end
  end

  @impl true
  def handle_event("save", %{"task" => attrs}, socket) do
    case Workflows.update_task(socket.assigns.task.id, attrs) do
      {:ok, task} ->
        {:noreply,
         assign(socket,
           task: task,
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
        {:noreply, reload(socket, "Task is ready to run.")}

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
    <Layouts.app>
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
          <p class="text-slate-700">Priority {@task.priority} · Knowledge: 0 linked</p>
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
            <h2 id="task-run-heading" class="text-xl font-semibold text-slate-950">Run this task</h2>
            <p class="mt-1 text-sm leading-6 text-slate-700">
              Draft tasks can be edited. Ready tasks can prepare a branch and worktree; agent
              authentication and execution begin only from the run page.
            </p>
          </div>
          <button
            :if={@task.state == "draft"}
            id="mark-task-ready"
            type="button"
            phx-click="mark-ready"
            class="min-h-11 rounded-md border border-slate-400 bg-white px-5 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Mark Ready
          </button>
          <button
            :if={@task.state == "ready" and !queued_run?(@runs)}
            id="prepare-task-run"
            type="button"
            phx-click="prepare-run"
            class="min-h-11 rounded-md bg-slate-950 px-5 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Prepare run
          </button>
          <p :if={@task.state == "ready" and queued_run?(@runs)} class="text-sm text-slate-700">
            A run is prepared and waiting for authentication.
          </p>
        </section>

        <.host_runner_notice />

        <form :if={editable?(@task)} id="task-edit" phx-submit="save" class="space-y-5">
          <label class="grid gap-1 font-medium text-slate-800">
            Title
            <input
              type="text"
              name="task[title]"
              value={@task.title}
              aria-invalid={if(@error, do: "true", else: "false")}
              aria-describedby={if(@error, do: "task-error")}
              class="min-h-10 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
            />
          </label>

          <label class="grid gap-1 font-medium text-slate-800">
            Description <textarea
              name="task[description]"
              rows="6"
              class="rounded-md border border-slate-400 px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2"
            >{@task.description}</textarea>
          </label>

          <label class="grid max-w-40 gap-1 font-medium text-slate-800">
            Priority
            <input
              type="number"
              name="task[priority]"
              value={@task.priority}
              class="min-h-10 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
            />
          </label>

          <button
            type="submit"
            class="min-h-10 rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Save task
          </button>
        </form>

        <p :if={!editable?(@task)} class="rounded-md border border-slate-300 p-4 text-slate-700">
          Task details can be edited only in Draft or Ready.
        </p>

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
