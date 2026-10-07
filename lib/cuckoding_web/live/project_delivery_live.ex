defmodule CuckodingWeb.ProjectDeliveryLive do
  use CuckodingWeb, :live_view
  import CuckodingWeb.ModalComponents
  alias Cuckoding.{BoardControl, Identifier, ProjectDelivery, Projects}
  alias CuckodingWeb.BoardControlComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Projects.get_project(id) do
      nil ->
        raise Phoenix.Router.NoRouteError, conn: socket, router: CuckodingWeb.Router

      project ->
        if connected?(socket) do
          Cuckoding.ActivityStream.subscribe(:all)
          Process.send_after(self(), :tick, 5_000)
        end

        socket =
          assign(socket,
            page_title: project.name,
            project: project,
            brief: "",
            answers: %{},
            editing: false,
            busy: false,
            error: nil,
            notice: nil,
            preview: nil,
            preview_revision: nil,
            confirmation: nil,
            command_key: Identifier.generate()
          )
          |> refresh()

        brief =
          if socket.assigns.execution,
            do: BoardControl.Plans.goal(socket.assigns.execution)["goal"],
            else: project.description || ""

        {:ok, assign(socket, brief: brief)}
    end
  end

  @impl true
  def handle_info({:activity_event, _stream, _sequence}, socket), do: {:noreply, refresh(socket)}

  def handle_info(:tick, socket) do
    if connected?(socket), do: Process.send_after(self(), :tick, 5_000)
    {:noreply, refresh(socket)}
  end

  @impl true
  def handle_event("change", %{"goal" => %{"brief" => brief}}, socket),
    do: {:noreply, assign(socket, brief: brief)}

  def handle_event("change-board-answer", %{"question" => attrs}, socket),
    do:
      {:noreply,
       assign(socket, answers: Map.put(socket.assigns.answers, attrs["id"], attrs["answer"]))}

  def handle_event("answer-board-question", %{"question" => attrs}, socket) do
    e = socket.assigns.execution

    result =
      with {revision, ""} <- Integer.parse(attrs["revision"] || ""),
           do:
             BoardControl.answer_question(
               e.id,
               revision,
               attrs["id"],
               attrs["answer"],
               "answer:#{attrs["id"]}:#{revision}"
             )

    case result do
      {:ok, _} ->
        Cuckoding.ProjectAutopilot.Worker.wake()
        {:noreply, outcome(socket, result)}

      _ ->
        {:noreply,
         assign(socket, error: "The question changed. Refresh and save your answer again.")}
    end
  end

  def handle_event("edit", _params, socket), do: {:noreply, assign(socket, editing: true)}

  def handle_event("open-worktree", %{"destination" => destination}, socket) do
    env = socket.assigns.final_environment
    target = if destination == "editor", do: :editor, else: :finder

    result =
      if env,
        do: Cuckoding.Execution.WorktreeOpener.open(env, target),
        else: {:error, :missing_worktree}

    case result do
      :ok ->
        {:noreply, assign(socket, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: message(reason))}
    end
  end

  def handle_event("prepare", %{"goal" => %{"brief" => brief}}, socket) do
    project_id = socket.assigns.project.id
    e = socket.assigns.execution
    key = socket.assigns.command_key
    editing = socket.assigns.editing

    {:noreply,
     socket
     |> assign(busy: true, error: nil, brief: brief)
     |> start_async(:prepare, fn ->
       if editing and e,
         do: BoardControl.revise_brief(e.id, e.revision, brief, key),
         else: ProjectDelivery.prepare(project_id, brief, key)
     end)}
  end

  def handle_event("run", _params, %{assigns: %{preview: nil}} = socket), do: {:noreply, socket}

  def handle_event("run", _params, socket) do
    id = socket.assigns.execution.id
    digest = socket.assigns.preview.digest
    key = socket.assigns.command_key

    {:noreply,
     socket
     |> assign(busy: true, error: nil)
     |> start_async(:run, fn -> BoardControl.activate_goal(id, digest, key) end)}
  end

  def handle_event("control", %{"action" => "stop"}, socket),
    do: {:noreply, assign(socket, confirmation: socket.assigns.execution)}

  def handle_event("cancel-stop", _params, socket),
    do: {:noreply, assign(socket, confirmation: nil)}

  def handle_event("confirm-stop", _params, %{assigns: %{confirmation: e}} = socket)
      when not is_nil(e) do
    result =
      BoardControl.control(e.id, e.revision, "stop", Identifier.generate(), confirmed: true)

    {:noreply, socket |> assign(confirmation: nil) |> outcome(result)}
  end

  def handle_event("control", %{"action" => action}, socket)
      when action in ~w(pause resume retry) do
    e = socket.assigns.execution

    {:noreply,
     outcome(socket, BoardControl.control(e.id, e.revision, action, Identifier.generate()))}
  end

  @impl true
  def handle_async(name, {:ok, result}, socket) when name in [:prepare, :run] do
    {:noreply, socket |> assign(busy: false) |> outcome(result)}
  end

  def handle_async(name, {:exit, _reason}, socket) when name in [:prepare, :run],
    do:
      {:noreply,
       assign(socket,
         busy: false,
         error:
           "The operation was interrupted. Your saved work is retained; inspect its status before retrying."
       )
       |> refresh()}

  defp outcome(socket, {:ok, _}) do
    socket |> assign(error: nil, editing: false, command_key: Identifier.generate()) |> refresh()
  end

  defp outcome(socket, {:error, reason}),
    do: socket |> assign(error: message(reason), command_key: Identifier.generate()) |> refresh()

  defp refresh(socket) do
    board = ProjectDelivery.board(socket.assigns.project.id)
    stats = board && BoardControl.Statistics.for_board(board.id)
    e = stats && stats.execution
    final = e && BoardControl.GoalReview.latest(e.id)
    final_environment = final && Enum.find(stats.environments, &(&1.run_id == final["run_id"]))
    final_run = final && Enum.find(stats.runs, &(&1.id == final["run_id"]))

    socket =
      assign(socket,
        board: board,
        stats: stats,
        execution: e,
        final_review: final,
        final_environment: final_environment,
        final_run: final_run,
        assumptions: assumptions(e),
        recovery: pending_recovery(stats)
      )

    refresh_preview(socket, e)
  end

  defp pending_recovery(nil), do: nil

  defp pending_recovery(stats) do
    Enum.find_value(stats.attempts, fn attempt ->
      recovery = (attempt.checkpoint_json || %{})["recovery"]

      if recovery && recovery["state"] == "pending" &&
           attempt.run_id == stats.execution.current_run_id,
         do: recovery
    end)
  end

  defp refresh_preview(socket, %{phase: "ready_to_run"} = e) do
    if e.revision != socket.assigns.preview_revision do
      case BoardControl.delivery_preview(e.id) do
        {:ok, preview} ->
          assign(socket, preview: preview, preview_revision: e.revision)

        {:error, reason} ->
          assign(socket, preview: nil, preview_revision: e.revision, error: message(reason))
      end
    else
      socket
    end
  end

  defp refresh_preview(socket, _e), do: assign(socket, preview: nil, preview_revision: nil)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="projects">
      <section class="mx-auto max-w-3xl space-y-8" aria-labelledby="delivery-heading">
        <header class="flex flex-wrap items-end justify-between gap-4">
          <div class="space-y-2">
            <p class="eyebrow">Project</p>
            <h1 id="delivery-heading" class="text-3xl font-semibold tracking-tight text-slate-950">
              {@project.name}
            </h1>
            <p class="max-w-2xl text-sm leading-6 text-slate-600">
              Describe the outcome. The saved team plans it, reviews it, and implements it after Run. Publishing stays a separate action.
            </p>
          </div>
          <.link
            navigate={~p"/projects/#{@project.id}/edit"}
            class="inline-flex min-h-11 items-center text-sm font-medium text-slate-700 underline decoration-slate-300 underline-offset-4"
          >
            Advanced settings
          </.link>
        </header>
        <p
          :if={@error}
          id="delivery-error"
          role="alert"
          class="rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm leading-6 text-amber-950"
        >
          {@error}
        </p>
        <p :if={@busy} role="status" class="text-sm text-slate-600">
          Checking the saved team and project…
        </p>
        <form
          :if={!@execution || @editing || @execution.state in ~w(done finished_with_skips stopped)}
          id="project-goal-form"
          phx-change="change"
          phx-submit="prepare"
          class="space-y-4 rounded-xl border border-slate-200 bg-white p-6 shadow-sm"
        >
          <label class="grid gap-2 text-sm font-medium text-slate-900">
            What should we build or change? <textarea
              name="goal[brief]"
              rows="8"
              maxlength="20000"
              required
              class="w-full rounded-xl border border-slate-300 p-3 text-base font-normal leading-6 text-slate-950"
            >{@brief}</textarea>
          </label>
          <p class="text-sm leading-6 text-slate-600">
            Create plan inspects the repository and prepares reviewed tasks. Implementation starts when you press Run.
          </p>
          <button
            disabled={@busy}
            phx-disable-with="Preparing…"
            class="inline-flex min-h-11 items-center rounded-xl bg-slate-950 px-5 text-sm font-semibold text-white"
          >{if @editing, do: "Review revised plan", else: "Create plan"}</button>
        </form>
        <section
          :if={@execution}
          id="goal-progress"
          class="space-y-5 rounded-xl border border-slate-200 bg-white p-6 shadow-sm"
          aria-labelledby="goal-state"
        >
          <div class="space-y-2">
            <p class="eyebrow">Goal</p>
            <h2
              id="goal-state"
              role="status"
              aria-live="polite"
              class="text-2xl font-semibold tracking-tight text-slate-950"
            >
              {state_label(@execution)}
            </h2>
            <p class="whitespace-pre-wrap break-words text-sm leading-6 text-slate-700">
              {BoardControl.Plans.goal(@execution)["goal"]}
            </p>
          </div>
          <dl class="grid gap-3 text-sm sm:grid-cols-3">
            <div class="rounded-xl bg-slate-50 px-3 py-3">
              <dt class="text-slate-600">Elapsed</dt>
              <dd class="mt-1 font-semibold text-slate-950">{div(@stats.wall_ms, 1000)} seconds</dd>
            </div>
            <div class="rounded-xl bg-slate-50 px-3 py-3">
              <dt class="text-slate-600">Tasks</dt>
              <dd class="mt-1 font-semibold text-slate-950">
                {@stats.totals["done"] || 0}/{@stats.included} completed
              </dd>
            </div>
            <div :if={List.last(@stats.attempts)} class="rounded-xl bg-slate-50 px-3 py-3">
              <dt class="text-slate-600">Current role</dt>
              <dd class="mt-1 font-semibold text-slate-950">{role_label(@stats)}</dd>
            </div>
          </dl>
          <p :if={List.last(@stats.sessions)} class="text-sm text-slate-600">
            Runtime: {List.last(@stats.sessions).adapter_key} · Model: {List.last(@stats.sessions).actual_model ||
              List.last(@stats.sessions).requested_model || "Unavailable"}
          </p>
          <p
            :if={@execution.issue}
            role="alert"
            class="rounded-xl border border-amber-300 bg-amber-50 p-4 text-sm leading-6"
          >
            {BoardControlComponents.issue(@execution.issue)}
          </p>
          <BoardControlComponents.question
            :for={question <- @stats.questions}
            question={question}
            execution={@execution}
            answers={@answers}
          />
          <p :if={@recovery} id="goal-recovery" role="status" class="text-sm leading-6 text-slate-700">
            {recovery_label(@recovery["kind"])} · {@recovery["count"]}/{@recovery["limit"]} used.
            Next eligible: <time datetime={@recovery["next_eligible_at"]}>{@recovery["next_eligible_at"]}</time>.
            Work and evidence are retained. Recovery resumes automatically while this goal is running.
          </p>
          <div :if={@assumptions != []} class="space-y-2">
            <h3 class="text-sm font-semibold text-slate-950">Recorded assumptions</h3>
            <ul class="list-disc space-y-1 pl-5 text-sm leading-6 text-slate-700">
              <li :for={assumption <- @assumptions}>{assumption}</li>
            </ul>
          </div>
          <div :if={@preview && !@editing} class="space-y-4 border-t border-slate-200 pt-5">
            <p class="text-sm leading-6 text-slate-700">
              Run authorizes this reviewed plan, the saved team, in-scope corrections and automatic local completion. Publication remains a separate action.
            </p>
            <p class="text-sm leading-6 text-slate-600">
              Limits: {@preview.snapshot["execution_profile"]["tasks"]} tasks · {@preview.snapshot[
                "execution_profile"
              ]["wall_minutes"]} elapsed minutes · {@preview.snapshot["execution_profile"]["retries"]} failure retries per task.
            </p>
            <p class="text-sm leading-6 text-slate-600">
              {@preview.snapshot["execution_profile"]["continuations"]} continuations and {@preview.snapshot[
                "execution_profile"
              ]["provider_waits"]} provider waits per task, within the same total deadline.
            </p>
            <ul class="list-disc space-y-1 pl-5 text-sm leading-6">
              <li :for={criterion <- @preview.snapshot["goal"]["criteria"]}>{criterion["text"]}</li>
            </ul>
            <ul
              :if={@preview.snapshot["plan"]["assumptions"] != []}
              class="list-disc space-y-1 pl-5 text-sm leading-6"
            >
              <li :for={assumption <- @preview.snapshot["plan"]["assumptions"] || []}>
                Assumption: {assumption}
              </li>
            </ul>
            <div id="goal-commands" class="space-y-2 text-sm leading-6">
              <p>
                Run authorizes these commands on the host in the goal's worktrees. Setup may download dependencies. Commands use the app's restricted environment and no provider credentials.
              </p>
              <ul class="list-disc pl-5">
                <li :for={command <- @preview.snapshot["commands"]}>
                  {command["phase"]}:
                  <code class="break-all">{Enum.join(command["command"], " ")}</code>
                </li>
              </ul>
              <details id="goal-toolchain" phx-mounted={JS.ignore_attributes("open")}>
                <summary class="min-h-11 cursor-pointer py-3 font-medium">
                  Verified developer tools
                </summary>
                <p>
                  These tools passed version checks with an isolated HOME. Run keeps their recorded paths.
                </p>
                <ul class="list-disc pl-5">
                  <li :for={tool <- @preview.snapshot["toolchain"]["tools"]}>
                    {tool["name"]}: <code class="break-all">{tool["path"]}</code>
                  </li>
                </ul>
              </details>
            </div>
            <div class="flex flex-wrap gap-3">
              <button
                id="run-goal"
                phx-click="run"
                disabled={@busy}
                phx-disable-with="Starting…"
                class="inline-flex min-h-11 items-center rounded-xl bg-slate-950 px-6 text-sm font-semibold text-white"
              >Run</button>
              <button
                phx-click="edit"
                disabled={@busy}
                class="inline-flex min-h-11 items-center rounded-xl border border-slate-300 px-4 text-sm font-medium"
              >Edit brief</button>
            </div>
          </div>
          <div class="flex flex-wrap gap-3 border-t border-slate-200 pt-5">
            <button
              :if={@execution.state in ~w(running waiting) && @execution.phase != "ready_to_run"}
              phx-click="control"
              phx-value-action="pause"
              class="inline-flex min-h-11 items-center rounded-xl border border-slate-300 px-4 text-sm font-medium"
            >Pause</button>
            <button
              :if={@execution.state == "paused"}
              phx-click="control"
              phx-value-action="resume"
              class="inline-flex min-h-11 items-center rounded-xl border border-slate-300 px-4 text-sm font-medium"
            >Resume</button>
            <button
              :if={@execution.state not in ~w(done finished_with_skips stopped)}
              id="stop-goal"
              phx-click="control"
              phx-value-action="stop"
              class="inline-flex min-h-11 items-center rounded-xl border border-slate-300 px-4 text-sm font-medium"
            >{if @execution.phase == "ready_to_run", do: "Discard plan", else: "Stop"}</button>
            <.link
              navigate={~p"/boards/#{@board.id}"}
              class="inline-flex min-h-11 items-center text-sm font-medium underline decoration-slate-300 underline-offset-4"
            >Inspect tasks and evidence</.link>
          </div>
          <details id="goal-task-list" phx-mounted={JS.ignore_attributes("open")}>
            <summary class="min-h-11 cursor-pointer py-3 text-sm font-medium">Tasks</summary>
            <ol class="list-decimal space-y-3 pl-5 text-sm leading-6">
              <li :for={item <- @stats.items} :if={!item.superseded}>
                <strong>{item.snapshot_json["title"]}</strong>
                · {item.state}
                <p class="whitespace-pre-wrap text-slate-700">{item.snapshot_json["description"]}</p>
              </li>
            </ol>
          </details>
          <section
            :if={@final_review}
            id="goal-result"
            class="space-y-4 border-t border-slate-200 pt-5"
            aria-label="Goal verification"
          >
            <div class="space-y-2">
              <h3 class="text-lg font-semibold text-slate-950">Final goal verification</h3>
              <p class="text-sm leading-6 text-slate-700">{@final_review["summary"]}</p>
            </div>
            <p
              :if={@final_review["candidate_clean"] == false}
              class="text-sm leading-6 text-amber-950"
            >
              Verification changed files. The worktree is retained and the team must repair the result before this goal can complete.
            </p>
            <dl class="grid gap-3 text-sm">
              <div>
                <dt class="text-slate-600">Reviewed commit</dt>
                <dd><code class="break-all">{@final_review["head_sha"]}</code></dd>
              </div>
              <div :if={@final_run}>
                <dt class="text-slate-600">Local branch</dt>
                <dd>Local branch: <code class="break-all">{@final_run.branch}</code></dd>
              </div>
              <div :if={@final_environment}>
                <dt class="text-slate-600">Worktree</dt>
                <dd><code class="break-all">{@final_environment.worktree_path}</code></dd>
              </div>
            </dl>
            <ul class="list-disc space-y-1 pl-5 text-sm leading-6">
              <li :for={criterion <- @final_review["criteria"]}>
                {criterion["id"]}: {criterion["verdict"]} — {criterion["evidence"]}
              </li>
              <li :for={check <- @final_review["checks"]}>
                {check["name"]}: {if check["exit_status"] == 0 && !check["timed_out"],
                  do: "passed",
                  else: "failed"}
              </li>
            </ul>
            <div class="flex flex-wrap gap-3">
              <a
                :if={preview_url(@final_environment)}
                href={preview_url(@final_environment)}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex min-h-11 items-center rounded-xl bg-slate-950 px-4 text-sm font-semibold text-white"
              >Open preview</a>
              <button
                :if={@final_environment}
                id="goal-open-finder"
                type="button"
                phx-click="open-worktree"
                phx-value-destination="finder"
                class="inline-flex min-h-11 items-center rounded-xl border border-slate-300 px-4 text-sm font-medium"
              >Open in Finder</button>
              <button
                :if={@final_environment}
                type="button"
                phx-click="open-worktree"
                phx-value-destination="editor"
                class="inline-flex min-h-11 items-center rounded-xl border border-slate-300 px-4 text-sm font-medium"
              >Open in editor</button>
              <.link
                navigate={~p"/runs/#{@final_review["run_id"]}"}
                class="inline-flex min-h-11 items-center text-sm font-medium underline decoration-slate-300 underline-offset-4"
              >Open verification logs</.link>
            </div>
            <p class="text-sm leading-6 text-slate-600">
              This result stays on this Mac. A pull request or merge is a separate approval.
            </p>
          </section>
        </section>
        <.modal
          :if={@confirmation}
          id="stop-goal-modal"
          on_cancel="cancel-stop"
          title="Stop this goal?"
          return_focus="stop-goal"
        >
          <p>
            Stop owned work and keep all tasks, branches and evidence. A prepared plan will be released without starting delivery.
          </p>
          <button phx-click="confirm-stop" class="min-h-11 rounded border px-4">Stop and retain work</button>
        </.modal>
      </section>
    </Layouts.app>
    """
  end

  defp assumptions(nil), do: []

  defp assumptions(execution) do
    case BoardControl.Plans.accepted(execution) do
      %{plan_json: %{"assumptions" => list}} when is_list(list) -> list
      _other -> []
    end
  end

  defp preview_url(%{preview_url: url}) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "http", host: "127.0.0.1", port: port, userinfo: nil}
      when is_integer(port) and port in 1_024..65_535 ->
        url

      _other ->
        nil
    end
  end

  defp preview_url(_environment), do: nil

  defp state_label(%{phase: "ready_to_run", state: "waiting"}), do: "Ready to run"
  defp state_label(%{state: "attention"}), do: "Needs you"

  defp state_label(%{state: state}) when state in ~w(done stopped paused),
    do: String.capitalize(state)

  defp state_label(%{phase: phase}) when phase in ~w(planning plan_review),
    do: "Preparing your plan"

  defp state_label(%{phase: "final_review"}), do: "Verifying the whole goal"

  defp state_label(_), do: "Working"

  defp role_label(stats) do
    attempt = List.last(stats.attempts)
    run = Enum.find(stats.runs, &(&1.id == attempt.run_id))
    Cuckoding.AgentFloor.role_label(run, attempt.role_key)
  end

  defp recovery_label("provider_wait"), do: "Waiting for the provider"
  defp recovery_label("continuation"), do: "Continuing unfinished work"
  defp recovery_label(_), do: "Recovering a temporary failure"

  defp message(reason) when is_atom(reason), do: message(Atom.to_string(reason))

  defp message(reason)
       when reason in ~w(agent_authorization_required roles_not_configured agent_connection_required),
       do:
         "The saved team needs setup. Check Agents and this project's role assignments, then try again."

  defp message("invalid_goal_or_limits"),
    do: "Describe a goal within 20,000 bytes and the saved execution limits."

  defp message("project_goal_in_progress"),
    do: "This project already has an active goal. Inspect it or edit its prepared brief."

  defp message(reason)
       when reason in ~w(missing_worktree open_failed environment_not_found worktree_path_mismatch path_resolution_failed invalid_destination invalid_editor_application),
       do:
         "The recorded worktree could not be opened. Use the path above or open the verification logs."

  defp message(_),
    do:
      "The request could not proceed with the current project state. Inspect the saved work and project settings, then try again."
end
