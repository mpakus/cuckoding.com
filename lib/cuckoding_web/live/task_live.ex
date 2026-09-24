defmodule CuckodingWeb.TaskLive do
  use CuckodingWeb, :live_view

  import Ecto.Query
  import CuckodingWeb.PolicyComponents

  alias Cuckoding.Execution
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.ProjectWorkflow
  alias Cuckoding.Repo
  alias Cuckoding.Security.Redactor
  alias Cuckoding.Workflows
  alias CuckodingWeb.PublicError

  @message_page 100
  @maximum_visible_messages 5_000

  @impl true
  def mount(%{"board_id" => board_id, "id" => task_id}, _session, socket) do
    with %{id: ^board_id} = board <- Workflows.get_board(board_id),
         %{board_id: ^board_id} = task <- Workflows.get_task(task_id) do
      if connected?(socket), do: Phoenix.PubSub.subscribe(Cuckoding.PubSub, "activity")
      runs = Execution.list_runs(task.id)
      {messages, more_messages?} = task_messages(task.id, @message_page)

      {:ok,
       assign(socket,
         page_title: task.title,
         board: board,
         task: task,
         unsaved_changes: false,
         runs: runs,
         messages: messages,
         more_messages?: more_messages?,
         message_limit: @message_page,
         maximum_visible_messages: @maximum_visible_messages,
         specification: latest_specification(task.id),
         activity_refresh_pending: false,
         notice: nil,
         error: nil
       )}
    else
      _missing -> raise Phoenix.Router.NoRouteError, conn: socket, router: CuckodingWeb.Router
    end
  end

  @impl true
  def handle_info({:activity_event, run_id, _sequence}, socket) do
    if !socket.assigns.activity_refresh_pending and
         Enum.any?(socket.assigns.runs, &(&1.id == run_id)) do
      Process.send_after(self(), :refresh_task_activity, 250)
      {:noreply, assign(socket, activity_refresh_pending: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:refresh_task_activity, socket) do
    {:noreply,
     socket
     |> reload(nil)
     |> assign(activity_refresh_pending: false)}
  end

  @impl true
  def handle_event("edit", _params, socket),
    do: {:noreply, assign(socket, unsaved_changes: true)}

  def handle_event("show-older-messages", _params, socket) do
    limit = min(socket.assigns.message_limit + @message_page, @maximum_visible_messages)
    {messages, more?} = task_messages(socket.assigns.task.id, limit)

    {:noreply,
     assign(socket,
       message_limit: limit,
       messages: messages,
       more_messages?: more? and limit < @maximum_visible_messages
     )}
  end

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

      {:error, _reason} ->
        {:noreply,
         assign(
           socket,
           error: "Task could not be saved. Reload its current details and try again.",
           notice: nil
         )}
    end
  end

  def handle_event("mark-ready", _params, socket) do
    key =
      "ui:task:#{socket.assigns.task.id}:ready:#{DateTime.to_unix(socket.assigns.task.updated_at, :microsecond)}"

    case Workflows.transition_task(socket.assigns.task.id, "ready", key) do
      {:ok, %{result: %{"outcome" => "transitioned"}}} ->
        {:noreply,
         reload(socket, "Task is Ready. Choose Prepare run, then start it on the run page.")}

      {:ok, %{result: %{"reason" => _reason}}} ->
        {:noreply,
         assign(
           socket,
           error:
             "Task could not be marked Ready. Reload its current state and review any unmet requirements.",
           notice: nil
         )}

      {:error, _reason} ->
        {:noreply,
         assign(
           socket,
           error:
             "Task could not be marked Ready. Reload its current state and review any unmet requirements.",
           notice: nil
         )}
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

  def handle_event("retry-task", _params, socket) do
    case ProjectWorkflow.retry_task(socket.assigns.task.id) do
      {:ok, %{run: run}} ->
        {:noreply,
         socket
         |> put_flash(:info, "A new run is ready. Check agent sign-in, then start it.")
         |> push_navigate(to: ~p"/runs/#{run.id}")}

      {:error, {:retry_preparation_failed, reason}} ->
        {:noreply,
         socket
         |> reload(nil)
         |> assign(
           error:
             "The task is Ready, but a new run could not be prepared: #{prepare_error(reason)} Fix the issue, then choose Prepare run."
         )}

      {:error, :previous_process_running} ->
        {:noreply,
         assign(socket,
           error:
             "The previous run still has a recorded running process. Stop or reconcile it before retrying; its worktree and evidence are unchanged.",
           notice: nil
         )}

      {:error, _reason} ->
        {:noreply,
         socket
         |> reload(nil)
         |> assign(error: "This task can no longer be retried. Review its latest run and state.")}
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
          <button
            :if={retryable?(@task, @runs)}
            id="retry-task"
            type="button"
            phx-click="retry-task"
            phx-disable-with="Preparing retry…"
            class="min-h-11 rounded-md bg-slate-950 px-5 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
          >Retry with a new run</button>
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

        <section
          aria-labelledby="task-specification-heading"
          class="space-y-3 rounded-xl border border-slate-200 bg-white p-5"
        >
          <h2 id="task-specification-heading" class="text-xl font-semibold text-slate-950">
            Latest specification message
          </h2>
          <p :if={!@specification} class="text-sm text-slate-700">
            No agent specification has been recorded yet. It will appear here after Specifications finishes.
          </p>
          <div :if={@specification} class="space-y-3">
            <p class="text-sm text-slate-600">
              From run {@specification.run_sequence} · Untrusted agent output
            </p>
            <pre
              id="task-specification"
              class="whitespace-pre-wrap break-words font-sans text-sm leading-6 text-slate-900"
            >{@specification.text}</pre>
            <.link
              navigate={~p"/runs/#{@specification.run_id}"}
              class="underline underline-offset-4"
            >
              Open run evidence and logs
            </.link>
          </div>
        </section>

        <section aria-labelledby="task-messages-heading" class="space-y-3">
          <h2 id="task-messages-heading" class="text-xl font-semibold text-slate-950">
            Task timeline and agent messages
          </h2>
          <p :if={@messages == []} class="text-sm text-slate-700">
            No run activity yet. Stage progress and public agent messages will appear here after work starts.
          </p>
          <ol :if={@messages != []} id="task-messages" class="space-y-3">
            <li :for={message <- @messages} class="rounded-lg border border-slate-200 bg-white p-4">
              <p class="text-sm font-medium text-slate-700">
                {role_label(message.role)} · Run {message.run_sequence}
              </p>
              <p class="mt-2 whitespace-pre-wrap break-words text-sm leading-6 text-slate-900">
                {message.text}
              </p>
            </li>
          </ol>
          <button
            :if={@more_messages?}
            type="button"
            phx-click="show-older-messages"
            class="min-h-10 rounded-md border border-slate-400 px-4 font-medium text-slate-950"
          >Show older messages</button>
          <p :if={@message_limit >= @maximum_visible_messages} class="text-sm text-slate-700">
            Showing the latest 5,000 entries. Open a run above for its complete redacted process log.
          </p>
        </section>

        <section aria-labelledby="run-history-heading" class="space-y-3">
          <h2 id="run-history-heading" class="text-xl font-semibold text-slate-950">Run history</h2>
          <p :if={@runs == []} class="text-sm text-slate-700">
            No runs prepared yet. Save the task, mark it Ready, then choose Prepare run.
          </p>
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
       when state in ["done", "archived"],
       do:
         "Review the run history below for results and errors. Return to the board for available task actions."

  defp next_step(%{state: state}, _runs) when state in ["blocked", "failed", "cancelled"],
    do:
      "Review the stopped or failed run. Retry prepares a fresh branch and worktree from the current base; the previous run, worktree, and evidence remain available. You start the new run after checking its agents."

  defp next_step(_task, _runs),
    do: "Open the current run for live progress, required approvals, and available controls."

  defp queued_run?(runs), do: Enum.any?(runs, &(&1.state == "queued"))

  defp retryable?(%{kind: "delivery", state: state}, [latest | _])
       when state in ["blocked", "failed", "cancelled"],
       do: latest.state in ["blocked", "failed", "cancelled"]

  defp retryable?(_task, _runs), do: false
  defp state_label(state), do: state |> String.replace("_", " ") |> String.capitalize()

  defp reload(socket, notice) do
    task = Workflows.get_task(socket.assigns.task.id)
    {messages, more?} = task_messages(task.id, socket.assigns.message_limit)

    assign(socket,
      task: task,
      page_title: task.title,
      runs: Execution.list_runs(task.id),
      messages: messages,
      more_messages?: more? and socket.assigns.message_limit < @maximum_visible_messages,
      specification: latest_specification(task.id),
      notice: notice,
      error: nil
    )
  end

  defp task_messages(task_id, limit) do
    rows =
      Repo.all(
        from(event in RunEvent,
          join: run in Run,
          on: run.id == event.run_id,
          where:
            run.task_id == ^task_id and
              event.event_type in [
                "activity.summary",
                "agent.messages_unavailable",
                "artifact.created",
                "process.started",
                "process.exited",
                "run.preparation_failed",
                "run.transitioned",
                "stage_attempt.transitioned",
                "workflow.failed"
              ],
          order_by: [desc: event.occurred_at, desc: event.sequence],
          limit: ^(limit + 1),
          select: {event, run.sequence}
        )
      )

    messages =
      rows
      |> Enum.take(limit)
      |> Enum.reverse()
      |> Enum.map(fn {event, sequence} ->
        %{
          text: Redactor.redact(event.public_summary),
          role: get_in(event.payload, ["correlation", "role"]),
          run_sequence: sequence
        }
      end)

    {messages, length(rows) > limit}
  end

  defp latest_specification(task_id) do
    Repo.one(
      from(event in RunEvent,
        join: run in Run,
        on: run.id == event.run_id,
        where:
          run.task_id == ^task_id and event.event_type == "activity.summary" and
            fragment("json_extract(?, '$.correlation.role')", event.payload) == "spec_writer",
        order_by: [desc: event.occurred_at, desc: event.sequence],
        limit: 1,
        select: {event, run.sequence}
      )
    )
    |> case do
      {event, sequence} ->
        %{
          text: Redactor.redact(event.public_summary),
          run_id: event.run_id,
          run_sequence: sequence
        }

      nil ->
        nil
    end
  end

  defp role_label(nil), do: "Run"
  defp role_label(role), do: role |> String.replace("_", " ") |> String.capitalize()

  defp prepare_error(:runtime_setup_only),
    do:
      "A board role uses a setup-only runtime. Assign Codex, Claude Code, or Cursor Agent, then create a new board snapshot."

  defp prepare_error(:roles_not_configured),
    do: "This board does not have all required role assignments."

  defp prepare_error(:dirty_repository),
    do: "Commit or stash changes in the project repository before preparing a run."

  defp prepare_error(:run_already_prepared), do: "A queued run is already prepared for this task."
  defp prepare_error(:task_not_ready), do: "Only a Ready task can prepare a run."

  defp prepare_error(_reason),
    do:
      "Run preparation failed. Review the task, repository, and board role settings, then try again."

  defp changeset_error(changeset), do: PublicError.changeset("Task could not be saved", changeset)
end
