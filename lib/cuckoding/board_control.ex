defmodule Cuckoding.BoardControl do
  @moduledoc "Durable sequential board batches; agent decisions are proposals, never commands."
  import Ecto.Query
  alias Cuckoding.BoardControl.{Execution, Item}
  alias Cuckoding.{Clock, Identifier, Projects, ProjectWorkflow, Repo, RunControl, Workflows}
  alias Cuckoding.Execution.{Commands, Environment, EventStore, GitService, Run}
  alias Cuckoding.Workflows.{Task, TaskDependency}

  @terminal ~w(done finished_with_skips stopped)
  @active_runs ~w(queued running waiting paused hibernated blocked)

  def get(id), do: Repo.get(Execution, id)

  def current(board_id),
    do:
      Repo.one(from e in Execution, where: e.board_id == ^board_id and e.state not in ^@terminal)

  def latest(board_id),
    do:
      Repo.one(
        from e in Execution,
          where: e.board_id == ^board_id,
          order_by: [desc: e.inserted_at, desc: e.id],
          limit: 1
      )

  def items(id), do: Repo.all(from i in Item, where: i.board_execution_id == ^id, order_by: i.id)

  def pending_requests(id),
    do:
      for(
        item <- items(id),
        item.state == "pending",
        do: task_snapshot(Workflows.get_task(item.task_id))
      )

  def owned_board_ids,
    do: Repo.all(from e in Execution, where: e.state not in ^@terminal, select: e.board_id)

  def controller?(%Run{board_execution_id: nil}), do: false

  def controller?(run),
    do: get_in(run.workflow_snapshot_json, ["definition", "entry"]) == "board_control"

  def preflight(board_id, excluded \\ []) do
    with board when not is_nil(board) <- Workflows.get_board(board_id),
         project <- Projects.get_project(board.project_id),
         :ok <- require_active(board, project),
         nil <- current(board_id),
         :ok <- no_conflicting_runs(board_id),
         :ok <- ProjectWorkflow.validate_delivery_roles(board_id),
         {:ok, base} <- GitService.capture_base(project),
         policy when not is_nil(policy) <- Projects.latest_config_version(project.id),
         true <- not is_nil(policy.trusted_at),
         tasks <- Workflows.list_tasks(board_id),
         :ok <- validate_exclusions(tasks, excluded),
         candidates <- Enum.filter(tasks, &(&1.state in ~w(draft ready))),
         true <- candidates != [],
         {:ok, snapshot} <-
           Cuckoding.Execution.snapshot_run(%{
             task_id: hd(candidates).id,
             policy_snapshot_id: policy.id
           }),
         :ok <- current_flow(snapshot.workflow_snapshot_json),
         :ok <- authorize_roles(snapshot.workflow_snapshot_json),
         :ok <- dependencies_available(candidates, project, base) do
      requests = Enum.map(candidates, &task_snapshot/1) |> ordered()

      data = %{
        "version" => 1,
        "tasks" => requests,
        "excluded" => Enum.sort(excluded),
        "base_sha" => base,
        "policy_id" => policy.id,
        "workflow" => snapshot.workflow_snapshot_json,
        "plugins" => snapshot.plugin_snapshot_json,
        "completion_mode" => "local",
        "maximum_decisions" => length(requests) * 4 + 10
      }

      {:ok,
       %{
         board: board,
         project: project,
         snapshot: data,
         digest: digest(data),
         tasks: requests,
         queue: preview_order(requests, [])
       }}
    else
      %Execution{} -> {:error, :board_owned}
      nil -> {:error, :board_not_found}
      false -> {:error, :empty_batch}
      error -> error
    end
  end

  def start(board_id, expected_digest, excluded, key, consent)

  def start(board_id, expected_digest, excluded, key, true) do
    preview_result = preflight(board_id, excluded)

    command(board_id, key, "start", fn ->
      start_snapshot(board_id, expected_digest, preview_result)
    end)
  end

  def start(_board_id, _expected_digest, _excluded, _key, _consent),
    do: {:error, :local_completion_consent_required}

  defp start_snapshot(board_id, expected_digest, preview_result) do
    with {:ok, preview} <- preview_result,
         true <- preview.digest == expected_digest,
         true <- RunControl.admission_open?(),
         nil <- current(board_id),
         :ok <- no_conflicting_runs(board_id),
         true <-
           Enum.map(
             Workflows.list_tasks(board_id) |> Enum.filter(&(&1.state in ~w(draft ready))),
             &task_snapshot/1
           )
           |> ordered() == preview.tasks,
         {:ok, task} <-
           Workflows.create_task(%{
             board_id: board_id,
             title: "Board controller",
             description: "Coordinate the reviewed board batch.",
             priority: 0,
             position: 0,
             kind: "board_intake",
             intake_role_key: "spec_writer"
           }) do
      e =
        Repo.insert!(%Execution{
          id: Identifier.generate(),
          board_id: board_id,
          controller_task_id: task.id,
          base_sha: preview.snapshot["base_sha"],
          head_sha: preview.snapshot["base_sha"],
          snapshot_json: preview.snapshot
        })

      Enum.each(preview.tasks, fn request ->
        Repo.insert!(%Item{
          id: Identifier.generate(),
          board_execution_id: e.id,
          task_id: request["id"],
          snapshot_json: request
        })
      end)

      event(e, "started", "Board batch started with automatic local completion")
      {:ok, e}
    else
      false -> {:error, :stale_preflight_or_workspace_paused}
      %Execution{} -> {:error, :board_owned}
      error -> error
    end
  end

  def preparation(task, requested_id) do
    case current(task.board_id) do
      nil ->
        if is_nil(requested_id), do: :ok, else: {:error, :board_owned}

      e ->
        if e.id == requested_id and e.state == "running" and is_nil(e.current_run_id) and
             task.id == target_task(e), do: :ok, else: {:error, :board_owned}
    end
  end

  def run_snapshot(attrs) do
    task = Workflows.get_task(attrs.task_id)

    with :ok <- preparation(task, attrs[:board_execution_id]),
         do: batch_snapshot(attrs, task, attrs[:board_execution_id])
  end

  defp batch_snapshot(attrs, _task, nil), do: {:ok, attrs}

  defp batch_snapshot(attrs, task, id) do
    e = get(id)

    if attrs.base_sha == e.head_sha and attrs.policy_snapshot_id == e.snapshot_json["policy_id"] do
      workflow = e.snapshot_json["workflow"]

      workflow =
        if task.id == e.controller_task_id, do: controller_workflow(workflow), else: workflow

      {:ok,
       %{
         attrs
         | workflow_snapshot_json: workflow,
           plugin_snapshot_json: e.snapshot_json["plugins"]
       }}
    else
      {:error, :invalid_batch_base}
    end
  end

  def attach_run(%Run{board_execution_id: nil}), do: :ok

  def attach_run(run) do
    e = get(run.board_execution_id)
    update(e, %{current_run_id: run.id}, "run_reserved", "Board run reserved")
    :ok
  end

  def original_base(%Run{board_execution_id: nil} = run), do: run.base_sha
  def original_base(run), do: get(run.board_execution_id).base_sha

  def completion_policy(%Run{board_execution_id: nil}, _mode, _options), do: :ok

  def completion_policy(run, mode, options) do
    if mode == "local" and options[:completion_actor] == "board:#{run.board_execution_id}",
      do: :ok,
      else: {:error, :board_owned}
  end

  def review_gate(%Run{board_execution_id: nil}, _environment, _attempt_id), do: :ok

  def review_gate(run, environment, attempt_id) do
    policy = Repo.get!(Cuckoding.Projects.ProjectConfigVersion, run.policy_snapshot_id)
    paths = get_in(policy.config_json, ["repository", "protected_paths"]) || []

    with {:ok, changed} <- Cuckoding.Execution.ProtectedPaths.scan(environment, paths) do
      protected_approval(run, environment, attempt_id, changed)
    end
  end

  defp protected_approval(_run, _environment, _attempt, []), do: :ok

  defp protected_approval(run, environment, attempt_id, _changed) do
    case Cuckoding.Execution.ProtectedPaths.gate_qa(run, attempt_id, environment) do
      {:ok, _} -> :ok
      _ -> {:error, :protected_path_approval_required}
    end
  end

  def admission(run, options \\ []) do
    task = Workflows.get_task(run.task_id)

    case current(task.board_id) do
      nil ->
        if is_nil(run.board_execution_id), do: :ok, else: {:error, :board_not_running}

      e ->
        if e.id == run.board_execution_id and e.current_run_id == run.id and
             e.state in ~w(running waiting) and is_nil(e.pending_action) and
             controller?(run) == Keyword.get(options, :board_controller, false),
           do: :ok,
           else: {:error, :board_owned}
    end
  end

  def resume_admission(%Run{board_execution_id: nil}), do: :ok

  def resume_admission(run) do
    e = get(run.board_execution_id)

    if e && e.current_run_id == run.id &&
         (e.state in ~w(running waiting) or
            (e.state == "controlling" and e.pending_action == "resume")),
       do: validate_pending(e),
       else: {:error, :board_owned}
  end

  def validate_launch(%Run{board_execution_id: nil}), do: :ok
  def validate_launch(run), do: validate_pending(get(run.board_execution_id))

  def next_item(e) do
    members = items(e.id)
    done = members |> Enum.filter(&(&1.state == "done")) |> Enum.map(& &1.task_id)
    ids = Enum.map(members, & &1.task_id)
    pending = Enum.filter(members, &(&1.state == "pending"))

    eligible =
      Enum.filter(pending, fn item ->
        Enum.all?(item.snapshot_json["dependencies"], &(&1 in done or &1 not in ids))
      end)

    case Enum.sort_by(eligible, &order_key(&1.snapshot_json)) do
      [item | _] ->
        {:ok, item}

      [] when pending == [] ->
        if Enum.all?(members, &(&1.state in ~w(done skipped deferred))),
          do: {:ok, nil},
          else: {:error, :unfinished_batch_item}

      [] ->
        {:error, :dependencies_blocked}
    end
  end

  def decision_input(e) do
    with {:ok, next} <- next_item(e) do
      {:ok,
       %{
         "execution_id" => e.id,
         "revision" => e.revision,
         "head_sha" => e.head_sha,
         "next_task_id" => next && next.task_id,
         "queue" =>
           Enum.map(
             items(e.id),
             &Map.merge(&1.snapshot_json, %{"outcome" => &1.state, "reason" => &1.reason})
           ),
         "maximum_decisions" => e.snapshot_json["maximum_decisions"],
         "previous_outcomes" => previous_outcomes(e)
       }}
    end
  end

  defp previous_outcomes(e) do
    Repo.all(
      from r in Run,
        where:
          r.board_execution_id == ^e.id and r.state in ["done", "failed", "cancelled", "blocked"],
        order_by: [asc: r.inserted_at, asc: r.id]
    )
    |> Enum.map(fn run ->
      %{
        "run_id" => run.id,
        "task_id" => run.task_id,
        "state" => run.state,
        "branch" => run.branch,
        "base_sha" => run.base_sha,
        "evidence" =>
          Repo.all(
            from event in Cuckoding.Execution.RunEvent,
              where: event.run_id == ^run.id,
              order_by: [desc: event.sequence],
              limit: 5,
              select: %{type: event.event_type, summary: event.public_summary}
          )
      }
    end)
  end

  def dispatch_once(options \\ []) do
    if RunControl.admission_open?() do
      Repo.all(from e in Execution, where: e.state in ~w(running waiting controlling))
      |> Enum.each(&dispatch_execution(&1, options))
    end

    :ok
  end

  defp dispatch_execution(e, options),
    do: locked(e.board_id, fn -> dispatch_leased(get(e.id), options) end)

  defp dispatch_leased(e, options) do
    case Cuckoding.Execution.Leases.acquire("board_dispatch", e.board_id, e.id, 60_000) do
      {:ok, lease, token} ->
        try do
          dispatch_safely(e, options)
        after
          Cuckoding.Execution.Leases.release(lease.id, token)
        end

      {:error, _} ->
        :ok
    end
  end

  defp dispatch_safely(e, options) do
    case advance(e, options) do
      {:error, reason} -> attention(e.id, reason)
      _ -> :ok
    end
  rescue
    _ -> attention(e.id, :dispatch_failed)
  end

  defp advance(%Execution{state: state}, _options)
       when state not in ~w(running waiting controlling), do: :ok

  defp advance(%Execution{state: "controlling"} = e, _options), do: finish_control(e)

  defp advance(%Execution{current_run_id: id} = e, options) when is_binary(id) do
    run = Repo.get!(Run, id)

    case run.state do
      "queued" ->
        launch(e, run, options)

      "done" ->
        settle_run(e, run)

      state when state in ~w(blocked failed cancelled) ->
        {:error, :task_blocked}

      "paused" ->
        {:error, :task_paused}

      state when state in ~w(running waiting) ->
        worker_available(run)

      _ ->
        {:error, :reconciliation_required}
    end
  end

  defp advance(e, options) do
    with :ok <- validate_pending(e),
         :ok <- ensure_decision_budget(e),
         :ok <- next_decision_valid(e),
         :ok <- capacity(e, options),
         {:ok, e} <- ready_capacity(e),
         {:ok, e} <- ready_target(e),
         {:ok, prepared} <- ProjectWorkflow.prepare_task(target_task(e), board_execution_id: e.id) do
      launch(get(e.id), prepared.run, options)
    else
      {:wait, reason} -> wait_for_capacity(e, reason)
      error -> error
    end
  end

  defp worker_available(%Run{state: "waiting", wait_reason: "approval"}), do: :ok

  defp worker_available(run) do
    if Registry.lookup(Cuckoding.RunRegistry, {:orchestration, run.id}) == [],
      do: {:error, :worker_unavailable},
      else: :ok
  end

  defp ready_target(%Execution{phase: "decision"} = e) do
    task = Workflows.get_task(e.controller_task_id)

    case task.state do
      state when state in ~w(done cancelled failed) ->
        # One hidden planning task per decision preserves terminal task/run history.
        transaction(fn ->
          {:ok, fresh} =
            Workflows.create_task(%{
              board_id: e.board_id,
              title: "Board controller",
              description: "Coordinate the reviewed board batch.",
              priority: 0,
              position: 0,
              kind: "board_intake",
              intake_role_key: "spec_writer"
            })

          update(
            e,
            %{controller_task_id: fresh.id},
            "controller_prepared",
            "Next controller decision prepared"
          )
        end)
        |> then(fn {:ok, updated} -> ready_target(updated) end)

      "draft" ->
        transition_ready(task, e)

      "ready" ->
        {:ok, e}

      _ ->
        {:error, :controller_not_ready}
    end
  end

  defp ready_target(e) do
    task = Workflows.get_task(e.current_task_id)
    if task.state == "draft", do: transition_ready(task, e), else: {:ok, e}
  end

  defp next_decision_valid(%Execution{phase: "delivery"}), do: :ok

  defp next_decision_valid(e) do
    case next_item(e) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp transition_ready(task, e) do
    case Workflows.transition_task(
           task.id,
           "ready",
           "board:#{e.id}:ready:#{task.id}:#{e.revision}"
         ) do
      {:ok, %{result: %{"outcome" => "transitioned"}}} -> {:ok, e}
      _ -> {:error, :task_not_ready}
    end
  end

  defp launch(e, run, options) do
    {:ok, e} = ready_capacity(e)

    result =
      if controller?(run),
        do: Cuckoding.BoardControl.Decision.start(run.id, options),
        else:
          Cuckoding.GuidedRun.start(
            run.id,
            Keyword.merge(options, completion_mode: "local", completion_actor: "board:#{e.id}")
          )

    case result do
      {:error, {:capacity, reason}} -> wait_for_capacity(e, reason)
      other -> other
    end
  end

  defp settle_run(e, run) do
    if controller?(run) do
      {:error, :controller_result_missing}
    else
      settle_delivery(e, run)
    end
  end

  defp settle_delivery(e, run) do
    with {:ok, skeleton} <- Cuckoding.WalkingSkeleton.load(run.id),
         {:ok, evidence} <- Cuckoding.WalkingSkeleton.validated_evidence(skeleton.environment),
         {:ok, %{clean?: true, head_sha: head}} <- GitService.inspect(skeleton.environment),
         true <- evidence["head_sha"] == head,
         true <-
           evidence["run_id"] == run.id and evidence["branch"] == run.branch and
             evidence["base_sha"] == run.base_sha,
         true <- run.base_sha == e.head_sha,
         :ok <- GitService.ancestor(skeleton.project, e.head_sha, head) do
      transaction(fn ->
        current = get(e.id)
        item = Repo.get_by!(Item, board_execution_id: e.id, task_id: run.task_id)
        change_item(item, %{state: "done", completed_sha: head, reason: nil})

        update(
          current,
          %{
            head_sha: head,
            current_run_id: nil,
            current_task_id: nil,
            phase: "decision",
            state: "running",
            issue: nil
          },
          "task_completed",
          "Reviewed task completed; next decision ready"
        )
      end)
    else
      _ -> {:error, :reviewed_revision_invalid}
    end
  end

  def accept_decision(run_id, input, output) do
    run = Repo.get!(Run, run_id)
    e = get(run.board_execution_id)

    locked(e.board_id, fn ->
      validated_decision(e.id, run, input, output)
    end)
  end

  defp validated_decision(id, run, input, output) do
    with :ok <- validate_pending(get(id)),
         do: transaction(fn -> commit_decision(id, run, input, output) end)
  end

  defp commit_decision(id, run, input, output) do
    current = get(id)

    with true <- current.state == "running" and current.current_run_id == run.id,
         true <- decision_revision?(current, input["revision"]),
         :ok <- validate_snapshot(current),
         {:ok, next} <- next_item(current),
         :ok <- Cuckoding.BoardControl.Decision.validate(output, input, next) do
      finish_controller_run(run)
      apply_decision(current, output, next)
    else
      false -> Repo.rollback(:stale_controller_decision)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp decision_revision?(%{revision: revision}, revision), do: true

  defp decision_revision?(e, revision) when is_integer(revision) and revision < e.revision do
    events =
      Repo.all(
        from event in Cuckoding.Execution.RunEvent,
          where: event.run_id == ^("board:" <> e.board_id)
      )
      |> Enum.filter(
        &(&1.payload["board_execution_id"] == e.id and &1.payload["revision"] > revision)
      )

    events != [] and Enum.all?(events, &pause_or_resume_event?/1)
  end

  defp decision_revision?(_, _), do: false

  defp pause_or_resume_event?(%{event_type: type})
       when type in ~w(board.execution_paused board.execution_resumed), do: true

  defp pause_or_resume_event?(%{
         event_type: "board.execution_control_requested",
         payload: payload
       }),
       do: payload["action"] in ~w(pause resume)

  defp pause_or_resume_event?(_), do: false

  defp apply_decision(e, %{"action" => "start_task"} = output, next) do
    change_item(next, %{state: "active", reason: nil})

    update(
      e,
      %{phase: "delivery", current_task_id: next.task_id, current_run_id: nil},
      "decision",
      output["summary"]
    )
  end

  defp apply_decision(e, %{"action" => "block"} = output, next) do
    if next, do: change_item(next, %{state: "blocked", reason: "controller_blocker"})

    update(
      e,
      %{
        state: "attention",
        issue: "controller_blocker",
        current_task_id: output["task_id"],
        current_run_id: nil
      },
      "decision",
      output["summary"]
    )
  end

  defp apply_decision(e, output, nil) do
    outcome =
      if Enum.all?(items(e.id), &(&1.state == "done")), do: "done", else: "finished_with_skips"

    update(
      e,
      %{state: outcome, finished_at: Clock.wall_now(), current_run_id: nil},
      "finished",
      output["summary"]
    )
  end

  defp finish_controller_run(run) do
    case Cuckoding.Execution.transition_run(run.id, "done", "board:#{run.id}:decision-complete") do
      {:ok, %{result: %{"outcome" => "transitioned"}}} -> :ok
      _ -> Repo.rollback(:controller_transition_failed)
    end
  end

  def attention(id, reason) do
    transaction(fn -> mark_attention(get(id), reason) end)
  end

  defp mark_attention(%Execution{state: state} = e, _reason) when state in @terminal, do: e

  defp mark_attention(e, reason) do
    mark_current_blocked(e, reason)

    update(
      e,
      %{state: "attention", issue: safe_issue(reason)},
      "attention",
      "Board batch needs attention"
    )
  end

  defp mark_current_blocked(%{current_task_id: nil}, _reason), do: :ok

  defp mark_current_blocked(e, reason) do
    case Repo.get_by(Item, board_execution_id: e.id, task_id: e.current_task_id) do
      %Item{state: "active"} = item ->
        change_item(item, %{state: "blocked", reason: safe_issue(reason)})

      _ ->
        :ok
    end
  end

  def control(id, revision, action, key, options \\ [])
      when action in ~w(pause resume stop skip retry refresh) do
    case get(id) do
      nil -> {:error, :execution_not_found}
      e -> request_control(e, revision, action, key, options)
    end
  end

  defp request_control(e, revision, action, key, options) do
    refreshed = if action == "refresh", do: refresh_preview(e), else: {:ok, nil}

    result =
      command(e.board_id, key, action, fn ->
        with {:ok, snapshot} <- refreshed,
             do:
               control_intent(
                 get(e.id),
                 revision,
                 action,
                 Keyword.put(options, :snapshot, snapshot)
               )
      end)

    with {:ok, requested} <- result do
      locked(e.board_id, fn -> complete_requested_control(requested) end)
    end
  end

  defp complete_requested_control(%{pending_action: nil} = e), do: {:ok, get(e.id)}
  defp complete_requested_control(e), do: finish_control(get(e.id))

  defp control_intent(current, revision, action, options) do
    with :ok <- valid_control(current, revision, action, options) do
      if action == "refresh",
        do: refresh_pending(current, options[:snapshot], options[:expected_snapshot]),
        else: record_control(current, action)
    end
  end

  defp valid_control(current, revision, action, options) do
    cond do
      current.revision != revision ->
        {:error, :stale_execution}

      current.state in @terminal ->
        {:error, :execution_finished}

      current.pending_action not in [nil, action] ->
        {:error, :control_pending}

      action in ~w(resume retry refresh) and current.state not in ~w(paused attention) ->
        {:error, :control_not_available}

      true ->
        confirm_control(current, action, options)
    end
  end

  defp confirm_control(current, action, options) do
    cond do
      action in ~w(stop skip refresh) and options[:confirmed] != true ->
        {:error, :confirmation_required}

      action == "skip" and is_nil(skip_target(current)) ->
        {:error, :no_current_task}

      true ->
        :ok
    end
  end

  defp record_control(current, action) do
    task_id = if action == "skip", do: skip_target(current), else: current.current_task_id

    {:ok,
     update(
       current,
       %{
         state: "controlling",
         current_task_id: task_id,
         pending_action: action,
         control_json: %{"previous_state" => current.state}
       },
       "control_requested",
       "Board #{action} requested"
     )}
  end

  defp skip_target(%{current_task_id: id}) when is_binary(id), do: id

  defp skip_target(e) do
    case next_item(e) do
      {:ok, %Item{task_id: id}} -> id
      _ -> nil
    end
  end

  defp finish_control(e) do
    case validate_resume(e, e.pending_action) do
      :ok ->
        finish_process_control(e)

      {:error, reason} ->
        transaction(fn ->
          current = mark_attention(get(e.id), reason)

          update(
            current,
            %{pending_action: nil},
            "control_rejected",
            "Resume validation failed; execution remains closed"
          )
        end)

        {:error, reason}
    end
  end

  defp finish_process_control(e) do
    action = e.pending_action
    run = e.current_run_id && Repo.get(Run, e.current_run_id)
    result = control_run(run, action)

    case result do
      :ok ->
        transaction(fn -> apply_control(get(e.id), action) end)

      {:error, reason} ->
        # Keep the intent and ownership until verified cleanup can be retried.
        attention(e.id, reason)
        {:error, :control_unconfirmed}
    end
  end

  defp validate_resume(e, "resume"), do: validate_pending(e)
  defp validate_resume(_e, _action), do: :ok

  defp control_run(nil, _action), do: :ok

  defp control_run(%Run{state: state}, "pause") when state not in ~w(running waiting paused),
    do: :ok

  defp control_run(%Run{state: state}, "resume") when state in ~w(queued done), do: :ok

  defp control_run(%Run{state: state}, "resume") when state != "paused",
    do: {:error, :retry_required}

  defp control_run(run, action) do
    operation = if action in ~w(stop skip retry), do: "stop", else: action

    case RunControl.control(run.id, operation) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_control(e, "pause"),
    do: update(e, %{state: "paused", pending_action: nil, issue: nil}, "paused", "Board paused")

  defp apply_control(e, "stop") do
    mark_current_blocked(e, :batch_stopped)

    update(
      e,
      %{state: "stopped", pending_action: nil, finished_at: Clock.wall_now()},
      "stopped",
      "Board stopped; work retained"
    )
  end

  defp apply_control(e, "resume") do
    case validate_snapshot(e) do
      :ok ->
        if e.current_task_id do
          item = Repo.get_by!(Item, board_execution_id: e.id, task_id: e.current_task_id)

          change_item(item, %{
            state: if(e.phase == "decision", do: "pending", else: "active"),
            reason: nil
          })
        end

        update(
          e,
          %{
            state: "running",
            pending_action: nil,
            issue: nil,
            current_task_id: if(e.phase == "decision", do: nil, else: e.current_task_id)
          },
          "resumed",
          "Board resumed"
        )

      {:error, reason} ->
        update(
          e,
          %{state: "attention", pending_action: nil, issue: safe_issue(reason)},
          "attention",
          "Board resume needs attention"
        )
    end
  end

  defp apply_control(e, "skip") do
    item = Repo.get_by!(Item, board_execution_id: e.id, task_id: e.current_task_id)
    change_item(item, %{state: "skipped", reason: "user_skipped"})
    defer_descendants(e.id, [item.task_id])

    update(
      e,
      %{
        state: "running",
        pending_action: nil,
        issue: nil,
        current_run_id: nil,
        current_task_id: nil,
        phase: "decision"
      },
      "skipped",
      "Task skipped for this batch; dependent tasks deferred"
    )
  end

  defp apply_control(e, "retry") do
    task_id = e.current_task_id || e.controller_task_id
    task = Workflows.get_task(task_id)

    if task.state in ~w(cancelled failed) do
      case Workflows.transition_task(task_id, "ready", "board:#{e.id}:retry:#{e.revision}") do
        {:ok, %{result: %{"outcome" => "transitioned"}}} -> :ok
        _ -> Repo.rollback(:retry_transition_failed)
      end
    end

    if e.current_task_id do
      item = Repo.get_by!(Item, board_execution_id: e.id, task_id: task_id)

      change_item(item, %{
        state: if(e.phase == "decision", do: "pending", else: "active"),
        reason: nil
      })
    end

    update(
      e,
      %{
        state: "running",
        pending_action: nil,
        issue: nil,
        current_run_id: nil,
        current_task_id: if(e.phase == "decision", do: nil, else: e.current_task_id)
      },
      "retried",
      "New board attempt authorized"
    )
  end

  defp refresh_preview(e) do
    current_tasks =
      for item <- items(e.id), item.state == "pending", do: Workflows.get_task(item.task_id)

    board = Workflows.get_board(e.board_id)
    project = Projects.get_project(board.project_id)

    with :ok <- dependencies_available(current_tasks, project, e.head_sha),
         do: {:ok, Enum.map(current_tasks, &task_snapshot/1)}
  end

  defp refresh_pending(e, snapshot, expected) do
    pending = Enum.filter(items(e.id), &(&1.state == "pending"))
    current = Enum.map(pending, &task_snapshot(Workflows.get_task(&1.task_id)))
    unless current == snapshot and snapshot == expected, do: Repo.rollback(:stale_task_snapshot)

    Enum.zip(pending, snapshot)
    |> Enum.each(fn {item, request} ->
      change_item(item, %{snapshot_json: request})
    end)

    {:ok, update(e, %{}, "snapshot_refreshed", "Pending task snapshots refreshed by user")}
  end

  defp defer_descendants(id, excluded) do
    descendants =
      Enum.filter(items(id), fn item ->
        item.state == "pending" and
          Enum.any?(item.snapshot_json["dependencies"], &(&1 in excluded))
      end)

    Enum.each(descendants, &change_item(&1, %{state: "deferred", reason: "skipped_prerequisite"}))
    if descendants != [], do: defer_descendants(id, Enum.map(descendants, & &1.task_id))
  end

  defp capacity(e, options), do: Cuckoding.Execution.Scheduler.check_board(e.board_id, options)

  defp ready_capacity(%Execution{state: "waiting"} = e),
    do:
      transaction(fn ->
        update(e, %{state: "running", issue: nil}, "capacity_available", "Capacity available")
      end)

  defp ready_capacity(e), do: {:ok, e}

  defp wait_for_capacity(e, reason) do
    transaction(fn ->
      current = get(e.id)

      if current.state != "waiting" or current.issue != to_string(reason),
        do:
          update(
            current,
            %{state: "waiting", issue: to_string(reason)},
            "waiting",
            "Board waiting for capacity"
          ),
        else: current
    end)
  end

  defp validate_pending(e) do
    board = Workflows.get_board(e.board_id)
    project = Projects.get_project(board.project_id)

    with :ok <- require_active(board, project),
         true <- policy_current?(project.id, e),
         :ok <- authorize_roles(e.snapshot_json["workflow"]),
         {:ok, base} <- GitService.capture_base(project),
         true <- base == e.base_sha do
      validate_snapshot(e)
    else
      false -> {:error, :base_or_policy_changed}
      error -> error
    end
  end

  defp policy_current?(project_id, e) do
    case Projects.latest_config_version(project_id) do
      %{id: id, trusted_at: trusted} -> id == e.snapshot_json["policy_id"] and not is_nil(trusted)
      _ -> false
    end
  end

  defp validate_snapshot(e) do
    if Enum.all?(items(e.id), &snapshot_current?(&1, e)),
      do: :ok,
      else: {:error, :stale_task_snapshot}
  end

  defp snapshot_current?(%{state: state}, _e) when state not in ~w(pending active blocked),
    do: true

  defp snapshot_current?(item, e) do
    task = Workflows.get_task(item.task_id)

    task_snapshot(task) == item.snapshot_json and
      (item.task_id == e.current_task_id or task.state in ~w(draft ready))
  end

  defp ensure_decision_budget(e) do
    count =
      Repo.one(
        from r in Run,
          join: t in Task,
          on: t.id == r.task_id,
          where: r.board_execution_id == ^e.id and t.kind == "board_intake",
          select: count(r.id)
      )

    if e.phase != "decision" or count < e.snapshot_json["maximum_decisions"],
      do: :ok,
      else: {:error, :controller_budget_exhausted}
  end

  defp task_snapshot(task) do
    %{
      "id" => task.id,
      "title" => task.title,
      "description" => task.description,
      "priority" => task.priority,
      "created_at" => DateTime.to_iso8601(task.inserted_at),
      "dependencies" =>
        Repo.all(
          from d in TaskDependency,
            where: d.task_id == ^task.id,
            order_by: d.depends_on_task_id,
            select: d.depends_on_task_id
        )
    }
  end

  defp ordered(tasks), do: Enum.sort_by(tasks, &order_key/1)

  defp preview_order([], result), do: Enum.reverse(result)

  defp preview_order(pending, result) do
    ids = Enum.map(pending, & &1["id"])
    next = Enum.find(pending, fn task -> Enum.all?(task["dependencies"], &(&1 not in ids)) end)

    if next,
      do: preview_order(List.delete(pending, next), [next | result]),
      else: Enum.reverse(result) ++ pending
  end

  defp authorize_roles(workflow) do
    roles = Cuckoding.Workflows.Definition.agent_role_keys(workflow["definition"])

    workflow["roles"]
    |> Enum.filter(&(&1["role_key"] in roles and &1["adapter_key"] != "fake"))
    |> Enum.map(&get_in(&1, ["settings", "provider_account_id"]))
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn id, :ok ->
      with true <- is_binary(id),
           account when not is_nil(account) <- Cuckoding.Adapters.get_provider_account(id),
           {:ok, _} <- Cuckoding.AgentRuntime.check_account(account) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, :agent_authorization_required}}
      end
    end)
  end

  defp order_key(t), do: {-t["priority"], t["created_at"], t["id"]}
  defp target_task(%Execution{phase: "decision"} = e), do: e.controller_task_id
  defp target_task(e), do: e.current_task_id

  defp digest(data),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary(data, [:deterministic]))
      |> Base.encode16(case: :lower)

  defp require_active(%{status: "active"}, %{status: "active"}), do: :ok
  defp require_active(_, _), do: {:error, :board_not_active}

  defp no_conflicting_runs(board_id) do
    if Repo.exists?(
         from r in Run,
           join: t in Task,
           on: t.id == r.task_id,
           where: t.board_id == ^board_id and t.kind == "delivery" and r.state in ^@active_runs
       ), do: {:error, :conflicting_run}, else: :ok
  end

  defp validate_exclusions(tasks, excluded) when is_list(excluded) do
    blocked = for task <- tasks, task.state in ~w(blocked failed), do: task.id

    if Enum.sort(excluded) == Enum.sort(blocked),
      do: :ok,
      else: {:error, :unfinished_tasks_require_exclusion}
  end

  defp validate_exclusions(_, _), do: {:error, :invalid_exclusions}

  defp current_flow(snapshot) do
    qa = Enum.find(snapshot["definition"]["stages"], &(&1["key"] == "qa"))

    if qa && qa["transitions"]["fix_code"] == "specification" &&
         qa["transitions"]["fix_intent"] == "specification",
       do: :ok,
       else: {:error, :workflow_update_required}
  end

  defp controller_workflow(snapshot) do
    spec = Enum.find(snapshot["definition"]["stages"], &(&1["key"] == "specification"))

    stage =
      Map.merge(spec, %{
        "key" => "board_control",
        "name" => "Board controller",
        "transitions" => %{"pass" => "$done"}
      })

    Map.put(snapshot, "definition", %{"entry" => "board_control", "stages" => [stage]})
  end

  defp dependencies_available(tasks, project, base) do
    ids = Enum.map(tasks, & &1.id)

    prerequisites =
      Repo.all(
        from d in TaskDependency,
          where: d.task_id in ^ids and d.depends_on_task_id not in ^ids,
          select: d.depends_on_task_id
      )

    Enum.reduce_while(prerequisites, :ok, fn id, :ok ->
      result =
        with %Task{state: "done"} <- Workflows.get_task(id),
             %Run{} = run <-
               Repo.one(
                 from r in Run,
                   where: r.task_id == ^id and r.state == "done",
                   order_by: [desc: r.sequence],
                   limit: 1
               ),
             %Environment{} = env <- Repo.get_by(Environment, run_id: run.id),
             {:ok, evidence} <- Cuckoding.WalkingSkeleton.validated_evidence(env),
             true <-
               evidence["head_sha"] == env.head_sha and evidence["run_id"] == run.id and
                 evidence["branch"] == run.branch and evidence["base_sha"] == run.base_sha,
             do: GitService.ancestor(project, env.head_sha, base)

      if result == :ok, do: {:cont, :ok}, else: {:halt, {:error, :dependency_code_unavailable}}
    end)
  end

  defp change_item(item, attrs), do: item |> Ecto.Changeset.change(attrs) |> Repo.update!()
  defp transaction(callback), do: EventStore.transaction(callback)

  defp locked(board_id, callback),
    do: :global.trans({{__MODULE__, board_id}, self()}, callback, [node()])

  defp safe_issue(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_issue(_), do: "operation_failed"

  defp update(e, attrs, type, summary) do
    changed =
      e |> Ecto.Changeset.change(Map.put(attrs, :revision, e.revision + 1)) |> Repo.update!()

    event(changed, type, summary)
    changed
  end

  defp event(e, type, summary) do
    {:ok, _} =
      EventStore.append_in_transaction("board:" <> e.board_id, %{
        event_type: "board.execution_#{type}",
        public_summary: summary,
        payload: %{
          "board_id" => e.board_id,
          "board_execution_id" => e.id,
          "revision" => e.revision,
          "state" => e.state,
          "action" => e.pending_action,
          "task_id" => e.current_task_id,
          "issue" => e.issue
        }
      })
  end

  defp command(target, key, action, callback) do
    locked(target, fn ->
      result =
        Commands.execute_once(
          %{
            idempotency_key: key,
            kind: "board.#{action}",
            target_type: "board",
            target_id: target
          },
          fn _ -> command_result(callback.()) end
        )

      case result do
        {:ok, %{result: %{"outcome" => "accepted", "execution_id" => id}}} -> {:ok, get(id)}
        {:ok, %{result: %{"reason" => reason}}} -> {:error, reason}
        other -> other
      end
    end)
  end

  defp command_result({:ok, e}), do: {:ok, %{"outcome" => "accepted", "execution_id" => e.id}}

  defp command_result({:error, reason}),
    do: {:ok, %{"outcome" => "rejected", "reason" => safe_issue(reason)}}
end
