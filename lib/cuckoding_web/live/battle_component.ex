defmodule CuckodingWeb.BattleComponent do
  @moduledoc false
  use CuckodingWeb, :live_component
  alias Cuckoding.Battles
  alias Cuckoding.Battles.{Backoff, Slots, Stages, TaskBlocks, Waves}

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(key: Ecto.UUID.generate(), error: nil, confirm_stop: nil, confirm_skip: nil)
     |> CuckodingWeb.SessionAuth.guard_events()}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if socket.assigns.confirm_skip != skip_key(socket.assigns.battle),
        do: assign(socket, :confirm_skip, nil),
        else: socket

    {:ok, socket}
  end

  @impl true
  def handle_event("recover", _, socket) do
    {:noreply,
     assign(socket,
       key: Ecto.UUID.generate(),
       confirm_stop: nil,
       confirm_skip: nil,
       error: "The connection changed. Review the current scope and press Start again."
     )}
  end

  def handle_event("scope-change", _, socket), do: {:noreply, socket}

  def handle_event(action, params, socket)
      when action in ~w(pause resume retry skip cancel-backoff) do
    a = socket.assigns

    result =
      if a.battle && params["battle_id"] == a.battle.id && params["key"] == a.key &&
           params["revision"] == to_string(a.battle.control_revision) do
        control(action, a, params)
      else
        {:error, :stale_control}
      end

    send(self(), :updated)

    {:noreply,
     assign(socket,
       key: Ecto.UUID.generate(),
       error: result_error(result),
       confirm_stop: nil,
       confirm_skip: nil
     )}
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
       confirm_skip: nil,
       confirm_stop:
         if(battle && battle.state in ~w(running pausing paused needs_attention), do: battle.id)
     )}
  end

  def handle_event("ask-skip", _, socket) do
    battle = socket.assigns.battle

    {:noreply,
     assign(socket,
       confirm_stop: nil,
       confirm_skip: if(battle && Battles.skip_preview(battle) != [], do: skip_key(battle))
     )}
  end

  def handle_event("keep-task", _, socket),
    do: {:noreply, assign(socket, :confirm_skip, nil)}

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

  defp control(action, a, params) do
    case action do
      "pause" ->
        Battles.pause(a.battle.id, a.battle.control_revision)

      "resume" ->
        Battles.resume(a.battle.id, a.battle.control_revision)

      "retry" ->
        Battles.retry(a.battle.id, a.battle.control_revision)

      "cancel-backoff" ->
        Battles.cancel_backoff(a.battle.id, a.battle.control_revision)

      "skip" ->
        Battles.skip(
          a.battle.id,
          a.battle.control_revision,
          params["task_id"],
          a.confirm_skip == skip_key(a.battle)
        )
    end
  end

  defp skip_key(nil), do: nil
  defp skip_key(battle), do: {battle.id, battle.control_revision, battle.current_task_id}

  defp general_blockers(preview) do
    statuses = Enum.map(preview.team, & &1["status"])
    Enum.reject(preview.blockers, &(&1 in statuses))
  end

  defp role_blockers(preview) do
    preview.team
    |> Enum.reject(&(&1["status"] == "ready"))
    |> Enum.group_by(&{&1["agent_id"], &1["status"], custom_role?(&1)})
    |> Enum.map(fn {_, [role | _] = roles} -> {role, Enum.map(roles, & &1["name"])} end)
  end

  defp team_problem?(role),
    do: role["status"] in ~w(agent_unassigned model_unassigned model_unavailable)

  defp custom_role?(role), do: role["id"] not in ~w(speculator implementor secutor summa_rudis)

  defp role_message(role) do
    if custom_role?(role) and team_problem?(role),
      do: "Choose this custom role's agent and model in this board's Team, then Save team here.",
      else: message(role["status"])
  end

  defp repair_path(board, role) do
    path =
      if custom_role?(role),
        do: ~p"/arenas/#{board.arena_id}/tabulae/#{board.id}/team",
        else: ~p"/team?#{[arena: board.arena_id, tabula: board.id]}"

    path <> "#role-#{role["id"]}"
  end

  defp model_label(role),
    do: if(role["model"] in [nil, ""], do: "Model needed", else: role["model"])

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

  defp message("usage_limit"),
    do:
      "The provider reported a usage or session budget limit. Stop this run and wait for availability before starting again. Your work is retained."

  defp message("rate_limited"),
    do:
      "The provider returned a limit response (HTTP 429). Wait before using Retry; the response does not distinguish temporary throttling from exhausted usage. Your work is retained."

  defp message("provider_overloaded"),
    do:
      "The provider is overloaded. Your work is retained; Retry is available only after verified cleanup and within the original limits."

  defp message("skip_unavailable"),
    do:
      "Skip requires a clean paused task or a settled task failure, verified cleanup and remaining limits. Active workers, uncertain effects and final reviews cannot be skipped."

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
    do: "This workflow is not supported by the current Arena loop."

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
         "Every assigned Codex connection needs a verified task version (#{Enum.join(Cuckoding.Codex.task_versions(), " or ")}). Recheck the connection in Agents."

  defp message("check_runtime_required"),
    do:
      "Extra command checks currently require a Codex Implementor. Cursor can implement and review task criteria, but cannot run these commands yet."

  defp message("agent_unassigned"),
    do: "Choose an agent and model in Team, then use those assignments in Board team."

  defp message("model_unassigned"),
    do:
      "The agent is assigned, but no model is selected. Choose its model in Team, then use the saved team here."

  defp message("unsupported_provider"),
    do: "This agent does not support Arena execution yet. Codex and Cursor are supported."

  defp message("model_unavailable"),
    do: "A saved model is unavailable. Refresh its agent and explicitly update the assigned team."

  defp message("catalog_stale"),
    do:
      "The assigned agent's last model lookup failed. Open that agent in Agents and reconnect or refresh its models."

  defp message("connection_required"),
    do:
      "An assigned agent is not connected. Open that agent in Agents and sign in; another connected agent is not substituted automatically."

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

  defp message("late_result_rejected"),
    do:
      "The stage finished after its time limit. Its result was not accepted and no further work will run. Inspect the retained evidence, then Stop to close this battle once worker cleanup is verified."

  defp message("timing_gap"),
    do:
      "A timing gap or clock change interrupted this battle. No further work will run. Inspect the retained evidence and Stop once worker cleanup is verified; a new Start is required for unfinished work."

  defp message("final_review_changes_requested"),
    do:
      "The final Secutor review requested changes. This battle needs attention; the local result and review evidence are retained, and completion has not been granted."

  defp message(reason),
    do:
      "Attention required: #{String.replace(to_string(reason), "_", " ")}. Inspect the retained evidence before continuing."

  defp label(value), do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp stage_label(battle, stage),
    do:
      Enum.find_value(Stages.custom(battle.snapshot), &if(&1["key"] == stage, do: &1["name"])) ||
        label(stage)

  defp stage_grants(snapshot) do
    Enum.map_join(Stages.custom(snapshot), " → ", fn step ->
      access =
        if Stages.access(snapshot, step["key"]) == "write", do: "read and edit", else: "read only"

      position = if step["position"] == "after", do: "after", else: "before"
      "#{step["name"]} (#{access}, #{position} Implementor)"
    end)
  end

  defp role_name("summa_rudis"), do: "Summa Rudis"
  defp role_name(nil), do: "Host"
  defp role_name(role), do: label(role)

  defp active_attempt(attempts),
    do: Enum.find(attempts, &(&1.state in ~w(pending running stopping)))

  defp binding(_battle, attempt), do: if(attempt, do: attempt.request["role"])

  defp frozen_bindings(%{"team" => roles} = snapshot) when is_list(roles),
    do: Slots.bindings(snapshot)

  defp frozen_bindings(_), do: []

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
      <p :if={Stages.custom(@battle.snapshot) != []} id="battle-frozen-grants" class="fine-print">
        {stage_grants(@battle.snapshot)}
      </p>
      <p :if={@battle.snapshot["workflow_definition"]} id="battle-frozen-workflow" class="fine-print">
        Columns at Start: {Enum.map_join(
          @battle.snapshot["workflow_definition"]["columns"],
          " → ",
          & &1["name"]
        )}
      </p>
      <p :if={@battle.context["timing_gap"]} id="battle-timing-observation" class="notice">
        Timing observation: {label(@battle.context["timing_gap"]["kind"])} ·
        UTC elapsed {@battle.context["timing_gap"]["wall_elapsed_ms"]} ms ·
        monotonic elapsed {@battle.context["timing_gap"]["monotonic_elapsed_ms"]} ms.
        This does not prove sleep or worker cleanup. The original deadline is unchanged.
      </p>
      <p
        :if={@battle.context["candidate_recovery_pending"]}
        id="battle-candidate-inspecting"
        class="notice"
      >
        Checking retained candidate/worktree checkpoints. No capture, edit or agent turn will be repeated.
      </p>
      <article
        :for={{id, observation} <- @battle.context["candidate_reconciliations"] || %{}}
        id={"battle-candidate-reconciliation-#{id}"}
        class="team-role"
      >
        <h4>
          Retained checkpoint · {if observation["receipt"]["cleanup_verified"] == true,
            do: "Verified",
            else: "Needs inspection"}
        </h4>
        <p class="fine-print">
          Observed {observation["observed_at"]} · interrupted attempt: <code>{id}</code>.
          The original attempt and all edit evidence are retained.
        </p>
        <p>
          Every member must verify before one Paused checkpoint can Resume. Expired or
          timing-fenced observations permit confirmed Stop only; missing proof cannot advance work.
        </p>
      </article>
      <p
        :if={@battle.context["preparation_recovery_pending"]}
        id="battle-preparation-inspecting"
        class="notice"
      >
        Checking retained worktree preparation. No checkout or agent turn will be repeated.
      </p>
      <article
        :for={{id, observation} <- @battle.context["preparation_reconciliations"] || %{}}
        id={"battle-preparation-reconciliation-#{id}"}
        class="team-role"
      >
        <h4>
          Worktree preparation · {if observation["receipt"]["status"] == "prepared",
            do: "Verified",
            else: "Needs inspection"}
        </h4>
        <p class="fine-print">
          Observed {observation["observed_at"]} · interrupted attempt: <code>{id}</code>.
          No checkout or agent turn was repeated.
        </p>
        <p :if={observation["receipt"]["status"] == "prepared"}>
          Retained worktree and cleanup verified. Only an in-budget, unfenced checkpoint can Resume
          from Paused. Expired or timing-fenced observations permit confirmed Stop only.
        </p>
        <p :if={observation["receipt"]["status"] != "prepared"}>
          Preparation evidence could not be verified. Cleanup remains uncertain; keep the retained files for inspection.
        </p>
      </article>
      <p
        :if={@battle.context["integration_recovery_pending"]}
        id="battle-recovery-inspecting"
        class="notice"
      >
        Checking retained integration evidence. No Git change will be repeated.
      </p>
      <article
        :for={{id, receipt} <- @battle.context["integration_reconciliations"] || %{}}
        id={"battle-reconciliation-#{id}"}
        class="team-role"
      >
        <h4>
          Recovery inspection · {if receipt["status"] == "integrated",
            do: "Verified",
            else: "Needs inspection"}
        </h4>
        <p class="fine-print">
          Original interrupted attempt: <code>{id}</code>. No Git change was repeated.
        </p>
        <p :if={receipt["status"] == "integrated"}>
          Retained integration and cleanup verified. Candidate: <code>{receipt["head"]}</code>.
          This observation does not authorize Resume or extend the original time limits.
        </p>
        <p :if={receipt["status"] != "integrated"}>
          Evidence could not be verified: {label(receipt["reason"])}. Cleanup remains uncertain.
        </p>
      </article>
      <p
        :if={@battle.context["mixed_closure_pending"]}
        id="battle-mixed-closure-pending"
        class="notice"
      >
        Checking the retained native receipt beside the interrupted agent turn. No work will be repeated or accepted.
      </p>
      <article
        :for={{id, observation} <- @battle.context["mixed_closures"] || %{}}
        id={"battle-mixed-closure-#{id}"}
        class="team-role"
      >
        <h4>
          Native closure · {if observation["receipt"]["cleanup_verified"] == true,
            do: "Verified",
            else: "Needs inspection"}
        </h4>
        <p class="fine-print">
          Observed {observation["observed_at"]} · interrupted attempt: <code>{id}</code>.
          Its work has not been accepted. Every claim must verify closure before Stop;
          Resume, Retry and Skip remain unavailable.
        </p>
      </article>
      <p
        :if={@battle.context["provider_closure_pending"]}
        id="battle-provider-closure-pending"
        class="notice"
      >
        Checking retained provider closure. No agent turn will be repeated or accepted.
      </p>
      <article
        :for={{id, receipt} <- @battle.context["provider_closures"] || %{}}
        id={"battle-provider-closure-#{id}"}
        class="team-role"
      >
        <h4>
          Provider closure · {if receipt["cleanup_verified"] == true,
            do: "Verified",
            else: "Needs inspection"}
        </h4>
        <p class="fine-print">
          Interrupted attempt: <code>{id}</code>. Its work has not been accepted.
        </p>
        <p :if={receipt["cleanup_verified"] == true}>
          Retained native evidence verifies this provider's closure. Every claim must verify closure before Stop;
          Resume, Retry and Skip remain unavailable.
        </p>
        <p :if={receipt["cleanup_verified"] != true}>
          Closure could not be verified. Keep the retained files for inspection; no turn was replayed.
        </p>
      </article>
      <p id="battle-frozen-workers" class="fine-print">
        {if Waves.enabled?(@battle.snapshot),
          do:
            "Up to two independent tasks per wave; shared connections take turns. Review and integration are serialized.",
          else: "This saved battle uses sequential task execution."}
      </p>
      <dl id="battle-frozen-team" class="team-history">
        <div :for={role <- frozen_bindings(@battle.snapshot)}>
          <dt>{role["name"]}</dt>
          <dd>{role["agent_name"]} · {role["model"]}</dd>
        </div>
      </dl>
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
        <h4>{stage_label(@battle, attempt.stage)} · {label(attempt.state)}</h4>
        <p class="fine-print">
          {role_name(attempt.role)} · {Calendar.strftime(attempt.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
        </p>
        <p :if={summary(attempt)} class="draft-copy">{summary(attempt)}</p>
        <p class="fine-print">Attempt receipt: <code>{attempt.id}</code></p>
        <p :if={attempt.task_id} class="fine-print">Task: <code>{attempt.task_id}</code></p>
        <p
          :if={
            get_in(@battle.context, ["timing_gap", "attempt_id"]) == attempt.id or
              (Waves.enabled?(@battle.snapshot) and
                 attempt.id in (get_in(@battle.context, ["timing_gap", "attempt_ids"]) || []))
          }
          class="notice"
        >
          Interrupted after a timing gap · retained evidence, not accepted work.
          <span :if={attempt.result["cleanup_verified"] == true}>Worker cleanup verified.</span>
          <span :if={attempt.result["cleanup_verified"] != true}>Worker cleanup is still unverified.</span>
        </p>
        <p :if={attempt.state == "expired"} class="notice">
          Time limit reached · this receipt is retained as evidence, not accepted work.
          <span :if={attempt.result["cleanup_verified"] == true}>Worker cleanup verified.</span>
          <span :if={attempt.result["cleanup_verified"] != true}>
            Worker cleanup is uncertain; Stop cannot release this Arena yet.
          </span>
        </p>
        <p :if={attempt.result["status"] && attempt.state != "expired"} class="fine-print">
          Result: {label(attempt.result["status"])}
        </p>
        <p :if={attempt.result["status"] && attempt.state == "expired"} class="fine-print">
          Reported result (not accepted): {label(attempt.result["status"])}
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
    waiting = Backoff.pending?(assigns.battle)

    attempt =
      active_attempt(assigns.attempts) ||
        if(waiting,
          do:
            Enum.find(
              assigns.attempts,
              &(&1.id == assigns.battle.context["provider_backoff"]["attempt_id"])
            )
        )

    assigns = assign(assigns, attempt: attempt, waiting: waiting)

    assigns =
      assign(
        assigns,
        :task_blocks,
        if(assigns.battle,
          do:
            Enum.filter(assigns.battle_tasks, &TaskBlocks.local_task?(assigns.battle, &1.task_id)),
          else: []
        )
      )

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

    assigns =
      assign(
        assigns,
        :skip_tasks,
        if(assigns.battle, do: Battles.skip_preview(assigns.battle, assigns.now), else: [])
      )

    ~H"""
    <div id={@id} class="arena-battle">
      <div :if={@battle} id="battle-activity">
        <h3>Battle · {if @waiting, do: "Waiting to retry", else: label(@battle.state)}</h3>
        <p id="battle-progress" role="status">
          {Enum.count(@battle_tasks, &(&1.state == "completed"))} / {length(@battle_tasks)} authorized tasks completed · {stage_label(
            @battle,
            @battle.stage
          )}
        </p>
        <p
          :if={Waves.enabled?(@battle.snapshot) and @battle.context["wave"]}
          id="battle-wave-status"
          class="fine-print"
        >
          Implementation wave {@battle.context["wave"]} · {Enum.count(
            @attempts,
            &(&1.state == "running")
          )} stages claimed.
          Shared connections take turns; inspect receipts for current state and cleanup.
        </p>
        <p :if={(@battle.context["omitted_tasks"] || []) != []} id="battle-omissions" role="status">
          {Enum.count(@battle_tasks, &(&1.state == "skipped"))} skipped · {Enum.count(
            @battle_tasks,
            &(&1.state == "deferred")
          )} deferred · these tasks remain unfinished.
        </p>
        <p :if={@current_task} class="fine-print">Current task: {@current_task.snapshot["title"]}</p>
        <details
          :if={@task_blocks != []}
          id="battle-task-blocks"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>
            {length(@task_blocks)} {if length(@task_blocks) == 1, do: "task needs", else: "tasks need"} attention
          </summary>
          <p :if={@battle.state == "running"} role="status">
            Independent tasks continue. Blocked tasks and their dependents stay unfinished.
          </p>
          <p :if={@battle.state != "running"}>
            Blocked tasks stay unfinished. Review the task evidence before choosing Skip or Stop.
          </p>
          <ul>
            <li :for={task <- @task_blocks}>
              {task.snapshot["title"]} · {message(
                @battle.context["task_blocks"][task.task_id]["reason"]
              )}
            </li>
          </ul>
        </details>
        <p class="fine-print">
          {role_name(if(@attempt, do: @attempt.role))} · {if @binding,
            do: "#{@binding["kind"]} · requested model #{@binding["model"]}",
            else: "local host"} · {battle_elapsed(@battle, @now)}s elapsed · {@battle.turns_used} role stages used
        </p>
        <p :if={@battle.state == "stopping"} role="status">
          Stopping · waiting for owned worker cleanup. Changes and receipts are retained.
        </p>
        <p
          :if={@battle.state == "pausing" && @battle.reason == "timing_gap"}
          id="battle-timing-cancelling"
          role="status"
        >
          Timing gap detected · cancelling active stages and waiting for owned worker cleanup.
          Its result will be retained without advancing work.
        </p>
        <p
          :if={@battle.state == "pausing" && @battle.reason != "timing_gap"}
          id="battle-pause-status"
          role="status"
        >
          Pausing · current stages are finishing within their existing limits. No next stage will start.
          Use Stop to cancel it now.
        </p>
        <p
          :if={@battle.state == "paused" && @battle.reason not in ~w(restart_checkpoint timing_gap)}
          id="battle-pause-status"
          role="status"
        >
          Paused · no stage is running. Saved results and verified worker cleanup are retained. Resume continues from the saved stage.
        </p>
        <p
          :if={@battle.state == "paused" && @battle.reason == "timing_gap"}
          id="battle-timing-paused"
          role="status"
        >
          Paused after a timing gap · no stage is running. Resume continues the saved work
          with the original deadline and remaining limits.
        </p>
        <p
          :if={@battle.state == "paused" && @battle.reason == "restart_checkpoint"}
          id="battle-recovery-status"
          role="status"
        >
          Paused after restart · saved checkpoint and verified cleanup retained.
          Resume continues from the saved stage with the same agents, work and remaining limits.
          No work has been replayed.
        </p>
        <p :if={@battle.state in ~w(running pausing paused)} id="battle-pause-help" class="fine-print">
          Pause finishes current stages before stopping new work. Time spent paused still counts toward
          the original deadline: {Calendar.strftime(@battle.deadline_at, "%Y-%m-%d %H:%M:%S UTC")}.
        </p>
        <p :if={@battle.state == "stopped"}>
          Stopped after worker cleanup. Unfinished tasks and evidence are retained.
        </p>
        <div :if={@waiting} id="battle-backoff" role="status" class="notice">
          <p>
            {if @battle.reason == "provider_overloaded",
              do: "Provider overloaded",
              else: "Connection interrupted"} · retrying in {Backoff.remaining(@battle, @now)}s with the same
            agent and model. This may use provider allowance. Failed edits stay retained;
            the original deadline and two-retry limit still apply.
          </p>
          <button
            type="button"
            class="button"
            id="battle-cancel-backoff"
            phx-click="cancel-backoff"
            phx-target={@myself}
            phx-value-battle_id={@battle.id}
            phx-value-revision={@battle.control_revision}
            phx-value-key={@key}
          >Cancel automatic retry</button>
        </div>
        <p :if={@battle.state == "needs_attention" && !@waiting} role="alert" class="notice">
          <strong :if={TaskBlocks.enabled?(@battle.snapshot)}>
            {if @task_blocks != [] and TaskBlocks.local_task?(@battle, @battle.current_task_id),
              do: "Task needs attention · ",
              else: "Arena needs attention · "}
          </strong>
          {message(@battle.reason)}
        </p>
        <p :if={@battle.state == "completed"} id="battle-result">
          Reviewed local result: <code>{branch(@battle)}</code>. Your original branch has not been merged. Push, merge and release remain separate actions.
        </p>
        <p :if={@battle.state == "partial"} id="battle-partial-result">
          Partial result · retained tasks passed final review. Skipped and deferred tasks remain unfinished.
          Local branch: <code>{branch(@battle)}</code>. Your original branch has not been merged.
        </p>
        <div :if={@retry_available && is_nil(@confirm_stop) && is_nil(@confirm_skip)}>
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
          :if={@battle.state in ~w(running paused) && is_nil(@confirm_stop) && is_nil(@confirm_skip)}
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
          :if={@skip_tasks != [] && is_nil(@confirm_skip) && is_nil(@confirm_stop)}
          id="battle-skip"
          class="button"
          type="button"
          phx-click="ask-skip"
          phx-target={@myself}
        >Skip task</button>
        <div
          :if={@confirm_skip && @confirm_skip == skip_key(@battle) && @skip_tasks != []}
          id="battle-skip-confirmation"
          role="group"
          aria-labelledby="battle-skip-question"
          class="notice"
        >
          <p id="battle-skip-question">Skip “{@current_task.snapshot["title"]}”?</p>
          <p>
            Its edits and evidence stay retained; it will not be completed or integrated.
            Any final result will be partial. If no tasks remain and none completed, the battle stops.
          </p>
          <p :if={@battle.state == "paused"}>
            The battle stays paused. Resume will continue independent tasks with the same limits.
          </p>
          <p :if={@battle.state != "paused"}>
            Independent tasks will continue with the same agents and limits and may use provider allowance.
          </p>
          <div :if={length(@skip_tasks) > 1}>
            <p>These dependent tasks will also be deferred:</p>
            <ul>
              <li :for={task <- tl(@skip_tasks)}>{task.snapshot["title"]}</li>
            </ul>
          </div>
          <button
            id="battle-keep-task"
            class="button"
            type="button"
            phx-click="keep-task"
            phx-target={@myself}
            phx-mounted={Phoenix.LiveView.JS.focus()}
          >Keep task</button>
          <button
            id="battle-confirm-skip"
            class="button"
            type="button"
            phx-click="skip"
            phx-value-battle_id={@battle.id}
            phx-value-task_id={@battle.current_task_id}
            phx-value-revision={@battle.control_revision}
            phx-value-key={@key}
            phx-target={@myself}
          >Confirm Skip</button>
        </div>
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
            (is_nil(@battle) || @battle.state in ~w(stopped completed partial))
        }
        id="battle-start-scope"
      >
        <p :if={@battle} class="notice">
          Start creates a new battle from the current committed source. Prior battle edits remain on its result branch.
        </p>
        <div class="start-summary">
          <div>
            <p class="start-title">{length(@preview.tasks)} tasks. One Start.</p>
            <p id="arena-start-help" class="fine-print">
              Runs independent tasks in waves of up to two, with separate workspaces and independent Secutor review.
              Preserves the original checkout; no push, merge to your branch or release.
            </p>
            <p class="fine-print">
              Up to {@preview.limits["tasks"]} tasks · {@preview.limits["review_rounds"]} review rounds per task · {div(
                @preview.limits["wall_seconds"],
                3600
              )} hours {if @preview.checks != [], do: " · #{length(@preview.checks)} extra commands"}
            </p>
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
              disabled={@preview.blockers != []}
              aria-describedby={
                if @preview.blockers == [], do: "arena-start-help", else: "battle-blockers"
              }
              phx-disable-with="Starting…"
            >Start</button>
          </.form>
        </div>
        <div>
          <p :if={@preview.checks != []} id="battle-command-scope" class="fine-print">
            Start also authorizes the {length(@preview.checks)} extra commands saved in Advanced.
            Declared checks run as single-process commands only; subprocess spawning is unavailable.
            Mix/npm pipelines are not yet supported. Final checks and independent final Secutor review
            must pass before completion; a failed final review needs attention.
          </p>
          <details
            id="battle-start-details"
            phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
          >
            <summary>Inspect tasks, team & limits</summary>
            <p :if={@preview.planning_roles != []} id="battle-planning-roles" class="fine-print">
              Planning only: {Enum.map_join(@preview.planning_roles, ", ", & &1["name"])}.
              Start runs the required responsibilities and configured stages below.
            </p>
            <p
              :if={Stages.custom(@preview.snapshot) != []}
              id="battle-stage-grants"
              class="fine-print"
            >
              {stage_grants(@preview.snapshot)}
            </p>
            <p id="battle-start-team" class="fine-print">
              {Enum.map_join(@preview.team, " · ", fn role ->
                "#{role["name"]}: #{role["agent_name"] || "agent needed"} / #{model_label(role)}"
              end)}
            </p>
            <p class="fine-print">
              Up to {@preview.limits["turns"]} role stages within {@preview.limits["wall_seconds"]}s.
              Known transient connection failures retry automatically after 5/20 seconds, within two retries
              per task and two shared by final stages. You can cancel the wait; other eligible failures offer Retry.
              Skip retains unfinished work and defers its dependents; independent work can produce a reviewed partial result.
            </p>
            <p id="battle-capacity-scope" class="fine-print">
              Two stage workers are shared across Arenas. Up to two independent tasks form a wave;
              each assigned connection takes one provider turn at a time. Checks, review and integration
              run in order after implementation; dependent tasks wait for reviewed results.
            </p>
            <p id="battle-check-scope" class="fine-print">
              Verification belongs in each task. Secutor inspects the result and evidence before completion;
              missing required test evidence pauses the battle for attention.
            </p>
            <ul>
              <li :for={task <- @preview.tasks}>{task["title"]} · revision {task["revision"]}</li>
            </ul>
            <ul>
              <li :for={role <- @preview.team}>
                {role["name"]} · {role["agent_name"] || "Agent needed"} · {model_label(role)}
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
          <div :if={@preview.blockers != []} id="battle-blockers" class="notice start-blockers">
            <p><strong>Before Start</strong></p>
            <p :for={reason <- general_blockers(@preview)}>{message(reason)}</p>
            <p :for={{role, names} <- role_blockers(@preview)}>
              <strong>{Enum.join(names, ", ")}</strong>
              · {role_message(role)}
              <.link
                :if={team_problem?(role)}
                navigate={repair_path(@board, role)}
                class="text-link"
              >
                {if role["status"] == "model_unassigned", do: "Choose model", else: "Edit roles"} ↗
              </.link>
              <.link
                :if={not team_problem?(role) and role["agent_id"] not in [nil, ""]}
                navigate={~p"/agents/#{role["agent_id"]}"}
                class="text-link"
              >
                Open {role["agent_name"] || role["kind"]} ↗
              </.link>
            </p>
            <a
              href="#board-team"
              phx-click={Phoenix.LiveView.JS.dispatch("cc:open", to: "#board-team")}
              class="text-link"
            >Review board team</a>
            <.link
              :if={
                Enum.any?(~w(check_timeout_limit check_runtime_required), &(&1 in @preview.blockers))
              }
              navigate={~p"/arenas/#{@board.arena_id}/checks"}
              class="text-link"
            >Extra command checks ↗</.link>
          </div>
        </div>
      </div>
      <p :if={@error} id="battle-error" role="alert" class="notice">{@error}</p>
    </div>
    """
  end
end
