defmodule CuckodingWeb.BattleComponent do
  @moduledoc false
  use Phoenix.LiveComponent
  use CuckodingWeb, :verified_routes
  alias Cuckoding.Battles

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(key: Ecto.UUID.generate(), error: nil, confirm_stop: nil)
     |> CuckodingWeb.SessionAuth.guard_events()}
  end

  @impl true
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl true
  def handle_event("recover", _, socket) do
    {:noreply,
     assign(socket,
       key: Ecto.UUID.generate(),
       confirm_stop: nil,
       error: "The connection changed. Review the current scope and press Start again."
     )}
  end

  def handle_event("scope-change", _, socket), do: {:noreply, socket}

  def handle_event(action, params, socket) when action in ~w(pause resume retry) do
    a = socket.assigns

    result =
      if a.battle && params["battle_id"] == a.battle.id && params["key"] == a.key &&
           params["revision"] == to_string(a.battle.control_revision) do
        case action do
          "pause" -> Battles.pause(a.battle.id, a.battle.control_revision)
          "resume" -> Battles.resume(a.battle.id, a.battle.control_revision)
          "retry" -> Battles.retry(a.battle.id, a.battle.control_revision)
        end
      else
        {:error, :stale_control}
      end

    send(self(), :updated)

    {:noreply,
     assign(socket, key: Ecto.UUID.generate(), error: result_error(result), confirm_stop: nil)}
  end

  def handle_event("start", params, socket) do
    a = socket.assigns

    result =
      if a.preview && params["key"] == a.key &&
           params["fingerprint"] == a.preview.fingerprint do
        Battles.start(a.key, a.board.arena_id, a.board.id, a.preview.fingerprint, true)
      else
        {:error, :stale_form}
      end

    send(self(), :updated)

    {:noreply,
     assign(socket, key: Ecto.UUID.generate(), error: result_error(result), confirm_stop: nil)}
  end

  def handle_event("ask-stop", _, socket) do
    battle = socket.assigns.battle

    {:noreply,
     assign(socket,
       confirm_stop:
         if(battle && battle.state in ~w(running pausing paused needs_attention), do: battle.id)
     )}
  end

  def handle_event("keep-running", _, socket),
    do: {:noreply, assign(socket, :confirm_stop, nil)}

  def handle_event("stop", %{"battle_id" => id}, socket) do
    a = socket.assigns

    result =
      if a.battle && a.battle.id == id && a.confirm_stop == id,
        do: Battles.stop(id),
        else: {:error, :stale_stop}

    send(self(), :updated)
    {:noreply, assign(socket, confirm_stop: nil, error: result_error(result))}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp result_error({:ok, _}), do: nil
  defp result_error({:error, reason}), do: message(reason)

  defp message(nil), do: message("unavailable")
  defp message({:not_ready, reasons}), do: Enum.map_join(reasons, " ", &message/1)
  defp message(reason) when is_atom(reason), do: message(Atom.to_string(reason))

  defp message(reason)
       when reason in ~w(stale_form stale_start stale_snapshot stale_fingerprint) do
    "The Start scope changed. Review the current tasks, team, checks and limits, then press Start again."
  end

  defp message("stale_stop"), do: "Review the current battle before confirming Stop."

  defp message("stale_control"),
    do: "The battle control changed. Review its current state and use the current button."

  defp message("resume_binding_changed"),
    do:
      "An assigned connection or model changed or expired. This battle keeps its original bindings. Stop and start a new battle with current connections."

  defp message("retry_unavailable"),
    do:
      "Retry requires a settled provider failure, verified cleanup and remaining time, turns and retries. Blocked reviews and uncertain effects need inspection."

  defp message("no_tasks"), do: "Create tasks or add a saved task before starting."

  defp message("task_limit"),
    do: "This board exceeds the battle's task limit. Use a smaller board."

  defp message("prompt_scope_too_large"),
    do:
      "The task and check scope is too large for one bounded review. Shorten descriptions, criteria or check arguments, or use a smaller board."

  defp message("incomplete_task"),
    do: "Save a description and acceptance criteria for every task."

  defp message("invalid_dependencies"), do: "Repair missing or circular task prerequisites."

  defp message("unsupported_columns"),
    do: "This workflow is not supported by the sequential Arena loop."

  defp message("checks_required"),
    do: "This older battle requires its original command checks. Inspect its frozen scope."

  defp message("check_timeout_limit"),
    do:
      "Keep each declared check within 300 seconds and their combined timeouts within 600 seconds."

  defp message("check_executable_unavailable"),
    do:
      "A declared check cannot run with this grant. Use a native command from /usr/bin or /bin that needs no subprocesses; Mix/npm toolchains are not supported yet. Update checks in Advanced, then stop this attempt and start a new battle."

  defp message(reason)
       when reason in ~w(check_runtime_version_required task_runtime_version_required),
       do:
         "Every assigned Codex connection needs version 0.162.0-alpha.17.2 for task execution. Recheck the connection in Agents."

  defp message("check_runtime_required"),
    do:
      "Extra command checks currently require a Codex Implementor. Cursor can implement and review task criteria, but cannot run these commands yet."

  defp message("agent_unassigned"),
    do: "Assign an agent and model to all four roles in Team, then adopt that team in Advanced."

  defp message("unsupported_provider"),
    do: "This agent does not support Arena execution yet. Codex and Cursor are supported."

  defp message("model_unavailable"),
    do: "A saved model is unavailable. Refresh its agent and explicitly update the assigned team."

  defp message("catalog_stale"), do: "Refresh the assigned agent's model catalog in Agents."
  defp message("connection_required"), do: "Refresh the assigned connection in Agents."
  defp message("version_required"), do: "Check the assigned agent's version in Agents."

  defp message("battle_active"),
    do: "This Arena already has an active battle. Inspect it before starting another."

  defp message("setup_busy"), do: "Finish or cancel the current setup operation first."

  defp message("git_required"),
    do: "Open Advanced → Repository setup to inspect Git and confirm any required initialization."

  defp message(reason) when reason in ~w(restart_uncertain restart_requires_inspection),
    do:
      "The app restarted with an unfinished attempt. Its effects are retained and will not replay."

  defp message("cleanup_required"),
    do:
      "Worker cleanup is uncertain. Inspect the retained attempt before any new execution; Stop cannot claim cleanup is complete."

  defp message("final_review_changes_requested"),
    do:
      "The final Secutor review requested changes. This battle needs attention; the local result and review evidence are retained, and completion has not been granted."

  defp message(reason),
    do:
      "Attention required: #{String.replace(to_string(reason), "_", " ")}. Inspect the retained evidence before continuing."

  defp label(value), do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp role_name("summa_rudis"), do: "Summa Rudis"
  defp role_name(nil), do: "Host"
  defp role_name(role), do: label(role)

  defp active_attempt(attempts),
    do: Enum.find(attempts, &(&1.state in ~w(pending running stopping)))

  defp binding(battle, attempt) do
    role = if attempt, do: attempt.role
    Enum.find(battle.snapshot["team"] || [], &(&1["id"] == role))
  end

  defp elapsed(started, now), do: max(0, DateTime.diff(now, started))

  defp summary(attempt),
    do: attempt.result["summary"] || get_in(attempt.result, ["provider", "report", "summary"])

  defp branch(battle) do
    case get_in(battle.context, ["native_battle", "reference"]) do
      "refs/heads/" <> name -> name
      reference -> reference
    end
  end

  defp battle_elapsed(battle, now) do
    ending =
      if battle.state in ~w(running pausing paused stopping), do: now, else: battle.updated_at

    elapsed(battle.inserted_at, ending)
  end

  defp inspection(assigns) do
    ~H"""
    <details id="battle-inspect" phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}>
      <summary>Inspect battle · {length(@attempts)} stage attempts</summary>
      <p class="fine-print">
        Battle {@battle.id} · started {Calendar.strftime(@battle.inserted_at, "%Y-%m-%d %H:%M UTC")}
      </p>
      <p :if={branch(@battle)} class="arena-path">Local branch: <code>{branch(@battle)}</code></p>
      <p :if={@battle.context["head"]} class="arena-path">
        Reviewed head: <code>{@battle.context["head"]}</code>
      </p>
      <p class="fine-print">
        Public summaries and retained attempt receipts. Original criteria remain part of the frozen scope.
      </p>
      <details id="battle-frozen-tasks" phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}>
        <summary>Authorized tasks · {length(@battle_tasks)}</summary>
        <article :for={task <- @battle_tasks} class="team-role">
          <h4>{task.snapshot["title"]}</h4>
          <p class="fine-print">
            Revision {task.snapshot["revision"]} · {label(task.state)} · review round {task.review_round}
          </p>
          <p class="draft-copy">{task.snapshot["description"]}</p>
          <p class="draft-copy">{task.snapshot["criteria"]}</p>
          <p class="fine-print">Criteria SHA-256: <code>{task.snapshot["criteria_sha256"]}</code></p>
        </article>
      </details>
      <article :for={attempt <- @attempts} id={"battle-attempt-#{attempt.id}"} class="team-role">
        <h4>{label(attempt.stage)} · {label(attempt.state)}</h4>
        <p class="fine-print">
          {role_name(attempt.role)} · {Calendar.strftime(attempt.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
        </p>
        <p :if={summary(attempt)} class="draft-copy">{summary(attempt)}</p>
        <p class="fine-print">Attempt receipt: <code>{attempt.id}</code></p>
        <p :if={attempt.task_id} class="fine-print">Task: <code>{attempt.task_id}</code></p>
        <p :if={attempt.result["status"]} class="fine-print">
          Result: {label(attempt.result["status"])}
        </p>
        <ul :if={get_in(attempt.result, ["provider", "changes"]) not in [nil, []]}>
          <li :for={change <- attempt.result["provider"]["changes"]}>
            Retained edit: <code>{change["path"]}</code> · SHA-256 <code>{change["sha256"]}</code>
          </li>
        </ul>
        <p :if={attempt.result["candidate_sha"]} class="fine-print">
          Candidate: <code>{attempt.result["candidate_sha"]}</code>
        </p>
        <p :if={get_in(attempt.result, ["provider", "observed_model"])} class="fine-print">
          Requested model: {get_in(attempt.result, ["provider", "requested_model"])} · runtime model: {get_in(
            attempt.result,
            ["provider", "observed_model"]
          )}
        </p>
        <ul :if={is_list(attempt.result["checks"])}>
          <li :for={check <- attempt.result["checks"]}>
            Check {check["id"]} · {label(check["status"])} · exit {check["exit_code"]}
          </li>
        </ul>
      </article>
    </details>
    """
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :attempt, active_attempt(assigns.attempts))

    assigns =
      assign(assigns, :binding, if(assigns.battle, do: binding(assigns.battle, assigns.attempt)))

    assigns =
      assign(
        assigns,
        :current_task,
        if(assigns.battle,
          do: Enum.find(assigns.battle_tasks, &(&1.task_id == assigns.battle.current_task_id))
        )
      )

    assigns =
      assign(
        assigns,
        :retry_available,
        assigns.battle && Battles.retry_available?(assigns.battle, assigns.now)
      )

    ~H"""
    <div id={@id} class="arena-battle">
      <div :if={@battle} id="battle-activity">
        <h3>Battle · {label(@battle.state)}</h3>
        <p id="battle-progress" role="status">
          {Enum.count(@battle_tasks, &(&1.state == "completed"))} / {length(@battle_tasks)} authorized tasks completed · {label(
            @battle.stage
          )}
        </p>
        <p :if={@current_task} class="fine-print">Current task: {@current_task.snapshot["title"]}</p>
        <p class="fine-print">
          {role_name(if(@attempt, do: @attempt.role))} · {if @binding,
            do: "#{@binding["kind"]} · requested model #{@binding["model"]}",
            else: "local host"} · {battle_elapsed(@battle, @now)}s elapsed · {@battle.turns_used} role stages used
        </p>
        <p :if={@battle.state == "stopping"} role="status">
          Stopping · waiting for owned worker cleanup. Changes and receipts are retained.
        </p>
        <p :if={@battle.state == "pausing"} id="battle-pause-status" role="status">
          Pausing · the current stage is finishing within its existing limit. No next stage will start.
          Use Stop to cancel it now.
        </p>
        <p :if={@battle.state == "paused"} id="battle-pause-status" role="status">
          Paused · no stage is running. Saved results and verified worker cleanup are retained. Resume continues from the saved stage.
        </p>
        <p :if={@battle.state in ~w(running pausing paused)} id="battle-pause-help" class="fine-print">
          Pause finishes the current stage before stopping new work. Time spent paused still counts toward
          the original deadline: {Calendar.strftime(@battle.deadline_at, "%Y-%m-%d %H:%M:%S UTC")}.
        </p>
        <p :if={@battle.state == "stopped"}>
          Stopped after worker cleanup. Unfinished tasks and evidence are retained.
        </p>
        <p :if={@battle.state == "needs_attention"} role="alert" class="notice">
          {message(@battle.reason)}
        </p>
        <p :if={@battle.state == "completed"} id="battle-result">
          Reviewed local result: <code>{branch(@battle)}</code>. Your original branch has not been merged. Push, merge and release remain separate actions.
        </p>
        <div :if={@retry_available && is_nil(@confirm_stop)}>
          <p id="battle-retry-help" class="fine-print">
            Retry uses the same agent, model and remaining limits and may use provider allowance.
            Up to two retries per task; final stages share two more. Failed edits stay retained.
            A failed Implementor starts in a fresh worktree through Summa Rudis and Speculator.
          </p>
          <button
            id="battle-retry"
            class="button"
            type="button"
            phx-click="retry"
            phx-value-battle_id={@battle.id}
            phx-value-revision={@battle.control_revision}
            phx-value-key={@key}
            phx-target={@myself}
            aria-describedby="battle-retry-help"
          >Retry failed stage</button>
        </div>
        <button
          :if={@battle.state in ~w(running paused) && is_nil(@confirm_stop)}
          id={if @battle.state == "paused", do: "battle-resume", else: "battle-pause"}
          class="button"
          type="button"
          phx-click={if @battle.state == "paused", do: "resume", else: "pause"}
          phx-value-battle_id={@battle.id}
          phx-value-revision={@battle.control_revision}
          phx-value-key={@key}
          phx-target={@myself}
          aria-describedby="battle-pause-help"
        >{if @battle.state == "paused", do: "Resume", else: "Pause"}</button>
        <button
          :if={@battle.state in ~w(running pausing paused needs_attention) && is_nil(@confirm_stop)}
          id="battle-stop"
          class="button"
          type="button"
          phx-click="ask-stop"
          phx-target={@myself}
        >Stop</button>
        <div
          :if={
            @confirm_stop == @battle.id && @battle.state in ~w(running pausing paused needs_attention)
          }
          id="battle-stop-confirmation"
          role="group"
          aria-labelledby="battle-stop-question"
          class="notice"
        >
          <p id="battle-stop-question">
            Stop this battle? No new work will start. Owned workers must finish cleanup before the battle is stopped; changes and evidence stay available.
          </p>
          <button
            id="battle-keep-running"
            class="button"
            type="button"
            phx-click="keep-running"
            phx-target={@myself}
            phx-mounted={Phoenix.LiveView.JS.focus()}
          >Keep current state</button>
          <button
            id="battle-confirm-stop"
            class="button"
            type="button"
            phx-click="stop"
            phx-value-battle_id={@battle.id}
            phx-target={@myself}
          >Confirm Stop</button>
        </div>
        <.inspection battle={@battle} battle_tasks={@battle_tasks} attempts={@attempts} />
      </div>
      <div :if={is_nil(@battle) && @preview && @preview.tasks == []} class="team-actions">
        <button
          id="arena-start"
          class="button"
          type="button"
          disabled
          aria-describedby="battle-blockers"
        >Start</button>
        <p id="battle-blockers" class="fine-print">
          Create tasks or add a saved task before starting.
        </p>
      </div>
      <div
        :if={
          @preview && @preview.tasks != [] &&
            (is_nil(@battle) || @battle.state in ~w(stopped completed))
        }
        id="battle-start-scope"
      >
        <p :if={@battle} class="notice">
          Start creates a new battle from the current committed source. Prior battle edits remain on its result branch.
        </p>
        <p id="arena-start-help" class="fine-print">
          Start runs the saved tasks with your assigned agents. Secutor reviews each task's acceptance criteria and checks on an app-owned local branch.
          The original checkout is preserved. No push, user-branch merge or release is included.
          Settled provider failures allow up to two explicit retries per task and two shared by final stages, within these same limits.
        </p>
        <div>
          <p class="fine-print">
            {length(@preview.tasks)} tasks · one worker at a time · up to {@preview.limits["tasks"]} tasks, {@preview.limits[
              "review_rounds"
            ]} review rounds per task, {@preview.limits["turns"]} role stages and {@preview.limits[
              "wall_seconds"
            ]}s total ({div(@preview.limits["wall_seconds"], 3600)} hours).
          </p>
          <p id="battle-check-scope" class="fine-print">
            Verification belongs in each task. Secutor inspects the result and evidence before completion;
            missing required test evidence pauses the battle for attention.
          </p>
          <p :if={@preview.checks != []} id="battle-command-scope" class="fine-print">
            Start also authorizes the {length(@preview.checks)} extra commands saved in Advanced.
            Declared checks run as single-process commands only; subprocess spawning is unavailable.
            Mix/npm pipelines are not yet supported. Final checks and independent final Secutor review
            must pass before completion; a failed final review needs attention.
          </p>
          <p id="battle-start-team" class="fine-print">
            {Enum.map_join(@preview.team, " · ", fn role ->
              "#{role["name"]}: #{role["kind"] || "agent needed"} / #{role["model"] || "model needed"}"
            end)}
          </p>
          <details
            id="battle-start-details"
            phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
          >
            <summary>Tasks, team and checks</summary>
            <ul>
              <li :for={task <- @preview.tasks}>{task["title"]} · revision {task["revision"]}</li>
            </ul>
            <ul>
              <li :for={role <- @preview.team}>
                {role["name"]} · {role["kind"]} · {role["model"] || "Model needed"}
              </li>
            </ul>
            <p :if={@preview.checks == []}>
              Checks come from the tasks. No extra command checks are configured; no command tests will run.
            </p>
            <article :for={check <- @preview.checks} class="team-role">
              <h4>{check["name"]}</h4>
              <pre class="draft-copy">{Jason.encode!([check["executable"] | check["arguments"]])}</pre>
              <p class="fine-print">
                Directory: {check["directory"]} · timeout {check["timeout_seconds"]}s
              </p>
            </article>
          </details>
          <ul :if={@preview.blockers != []} id="battle-blockers" class="notice">
            <li :for={reason <- @preview.blockers}>{message(reason)}</li>
          </ul>
          <div :if={@preview.blockers != []} class="team-actions">
            <p :for={role <- Enum.filter(@preview.team, &(&1["status"] != "ready"))}>
              {role["name"]}: {message(role["status"])}
              <.link
                :if={role["agent_id"]}
                navigate={~p"/agents/#{role["agent_id"]}"}
                class="text-link"
              >
                Open {role["agent_name"] || role["kind"]} ↗
              </.link>
            </p>
            <a
              href="#arena-advanced"
              phx-click={Phoenix.LiveView.JS.set_attribute({"open", ""}, to: "#arena-advanced")}
              class="text-link"
            >This board's team · Advanced ↓</a>
            <.link
              :if={
                Enum.any?(~w(check_timeout_limit check_runtime_required), &(&1 in @preview.blockers))
              }
              navigate={~p"/arenas/#{@board.arena_id}/checks"}
              class="text-link"
            >Extra command checks ↗</.link>
          </div>
          <.form
            for={%{}}
            id="battle-start-form"
            phx-change="scope-change"
            phx-auto-recover="recover"
            phx-submit="start"
            phx-target={@myself}
          >
            <input type="hidden" name="key" value={@key} />
            <input type="hidden" name="fingerprint" value={@preview.fingerprint} />
            <button
              id="arena-start"
              class="button primary"
              type="submit"
              aria-describedby={
                if @preview.blockers == [], do: "arena-start-help", else: "battle-blockers"
              }
              phx-disable-with="Starting…"
            >{if @preview.blockers == [], do: "Start", else: "Check Start readiness"}</button>
          </.form>
        </div>
      </div>
      <p :if={@error} id="battle-error" role="alert" class="notice">{@error}</p>
    </div>
    """
  end
end
