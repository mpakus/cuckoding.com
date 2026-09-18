defmodule CuckodingWeb.TaskLive do
  use CuckodingWeb, :live_view

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
      </article>
    </Layouts.app>
    """
  end

  defp editable?(task), do: task.state in ["draft", "ready"]
  defp state_label(state), do: state |> String.replace("_", " ") |> String.capitalize()

  defp changeset_error(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _options}} -> "#{field} #{message}" end)
    |> then(&"Task could not be saved: #{&1}.")
  end
end
