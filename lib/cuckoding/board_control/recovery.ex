defmodule Cuckoding.BoardControl.Recovery do
  @moduledoc "Bounded recovery of known-ended stages, using durable attempts and the board dispatcher."
  import Ecto.Query
  alias Cuckoding.{BoardControl, Clock, Execution, Repo}
  alias Cuckoding.BoardControl.{Budget, Item, Plans}

  alias Cuckoding.Execution.{
    AgentSession,
    EventStore,
    GitService,
    ProcessRecord,
    Run,
    RunEvent,
    StageAttempt
  }

  def enabled?(%{board_execution_id: nil}), do: false
  def enabled?(run), do: Plans.prepared_goal?(BoardControl.get(run.board_execution_id))

  def schedule(skeleton, attempt, reason, cycle) do
    kind = Cuckoding.OrchestrationFailure.recovery_class(reason)

    if enabled?(skeleton.run) and kind in ~w(transient provider_wait continuation) do
      with :ok <- ended(skeleton),
           {:ok, _} <- GitService.inspect(skeleton.environment) do
        persist_schedule(skeleton, attempt, kind, reason, cycle)
      end
    else
      {:error, reason}
    end
  end

  defp persist_schedule(skeleton, attempt, kind, reason, cycle) do
    EventStore.transaction(fn ->
      run = Repo.get!(Run, skeleton.run.id)
      e = BoardControl.get(run.board_execution_id)
      require_running_budget!(run, e)

      scope =
        if BoardControl.controller?(run), do: "controller:#{e.phase}", else: "task:#{run.task_id}"

      count = consumed(e, scope, kind) + 1
      limit = recovery_limit(e, kind)
      if count > limit, do: Repo.rollback(:goal_recovery_limit)
      delay = backoff(kind, count, reason)

      data = %{
        "state" => "pending",
        "kind" => kind,
        "scope" => scope,
        "count" => count,
        "limit" => limit,
        "cycle" => cycle,
        "source_attempt_id" => attempt.id,
        "source_run_id" => run.id,
        "board_execution_id" => e.id,
        "code" => Cuckoding.OrchestrationFailure.recovery_code(reason),
        "next_eligible_at" =>
          Clock.wall_now() |> DateTime.add(delay, :millisecond) |> DateTime.to_iso8601()
      }

      record_failure_count(run, e, kind, count)

      checkpoint = Map.put(attempt.checkpoint_json || %{}, "recovery", data)
      {:ok, _} = Execution.checkpoint_stage_attempt(attempt, checkpoint)

      Repo.update_all(from(s in AgentSession, where: s.stage_attempt_id == ^attempt.id),
        set: [state: "failed"]
      )

      transition!(run.id, "waiting", "goal_recovery", "waiting:#{attempt.id}")

      {:ok, _} =
        EventStore.append_in_transaction("board:" <> e.board_id, %{
          event_type: "goal.recovery_scheduled",
          public_summary: "Automatic #{kind} recovery scheduled",
          payload: data
        })

      data
    end)
    |> case do
      {:ok, data} -> {:recovering, data}
      error -> error
    end
  end

  defp require_running_budget!(run, e) do
    unless run.state == "running", do: Repo.rollback(:run_interrupted)

    case Budget.check(e) do
      :ok -> :ok
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp record_failure_count(run, e, "transient", count) do
    unless BoardControl.controller?(run) do
      item = Repo.get_by!(Item, board_execution_id: e.id, task_id: run.task_id)
      item |> Ecto.Changeset.change(retry_count: count) |> Repo.update!()
    end
  end

  defp record_failure_count(_run, _e, _kind, _count), do: :ok

  def events(e) do
    Repo.all(
      from event in RunEvent,
        where:
          event.run_id == ^("board:" <> e.board_id) and
            event.event_type == "goal.recovery_scheduled",
        order_by: event.sequence,
        select: event.payload
    )
    |> Enum.filter(&(&1["board_execution_id"] == e.id))
  end

  defp consumed(e, "task:" <> task_id, "transient"),
    do: Repo.get_by!(Item, board_execution_id: e.id, task_id: task_id).retry_count

  defp consumed(e, scope, kind),
    do: Enum.count(events(e), &(&1["scope"] == scope and &1["kind"] == kind))

  defp recovery_limit(e, "transient"), do: e.snapshot_json["execution_profile"]["retries"]

  defp recovery_limit(e, "continuation"),
    do: e.snapshot_json["execution_profile"]["continuations"]

  defp recovery_limit(e, "provider_wait"),
    do: e.snapshot_json["execution_profile"]["provider_waits"] || 6

  defp backoff("continuation", _count, _reason), do: 0

  defp backoff(kind, count, _reason),
    do:
      min(
        if(kind == "provider_wait", do: 10_000, else: 1_000) * Integer.pow(2, count - 1),
        300_000
      )

  def pending(run) do
    Repo.all(
      from a in StageAttempt,
        where: a.run_id == ^run.id,
        order_by: [desc: a.attempt, desc: a.inserted_at]
    )
    |> Enum.find(fn a -> get_in(a.checkpoint_json || %{}, ["recovery", "state"]) == "pending" end)
  end

  def ready?(run, now \\ Clock.wall_now()) do
    case pending(run) do
      nil ->
        false

      attempt ->
        {:ok, time, 0} =
          DateTime.from_iso8601(attempt.checkpoint_json["recovery"]["next_eligible_at"])

        DateTime.compare(now, time) != :lt
    end
  end

  @doc "Claim a due checkpoint inside shared launch admission; stale wakeups cannot launch twice."
  def claim(run) do
    current = Repo.get!(Run, run.id)

    with "waiting" <- current.state,
         "goal_recovery" <- current.wait_reason,
         true <- enabled?(current),
         true <- ready?(current),
         :ok <- BoardControl.launch_authorized(current) do
      attempt = pending(current)
      checkpoint = put_in(attempt.checkpoint_json, ["recovery", "state"], "claimed")
      {:ok, _} = Execution.checkpoint_stage_attempt(attempt, checkpoint)
      transition!(run.id, "running", nil, "resume:#{attempt.id}")

      {:ok, _} =
        EventStore.append_in_transaction(run.id, %{
          event_type: "goal.recovery_resumed",
          public_summary: "Automatic recovery resumed from saved stage evidence",
          payload: checkpoint["recovery"]
        })

      {:ok, current}
    else
      _ -> {:error, :recovery_not_ready_or_owned}
    end
  end

  def preflight(skeleton) do
    with :ok <- ended(skeleton), {:ok, _} <- GitService.inspect(skeleton.environment), do: :ok
  end

  def record_failed_time(attempt, started) do
    elapsed = max(System.monotonic_time(:millisecond) - started, 0)

    process_ids =
      Repo.all(
        from p in ProcessRecord,
          join: s in AgentSession,
          on: s.id == p.agent_session_id,
          where: s.stage_attempt_id == ^attempt.id,
          select: p.id
      )

    paused =
      Repo.all(
        from e in RunEvent,
          where: e.run_id == ^attempt.run_id and e.event_type == "process.exited",
          select: e.payload
      )
      |> Enum.filter(&(&1["process_id"] in process_ids))
      |> Enum.reduce(0, &(Map.get(&1, "paused_ms", 0) + &2))

    # The successful path uses this same command key; late budget failures cannot double count.
    Execution.record_stage_time(
      attempt.id,
      max(elapsed - paused, 0),
      elapsed,
      "walking:#{attempt.id}:timing"
    )
  end

  defp transition!(id, state, reason, key) do
    case Execution.transition_run(id, state, "goal-recovery:#{key}", wait_reason: reason) do
      {:ok, %{result: %{"outcome" => "transitioned"}}} -> :ok
      _ -> Repo.rollback(:recovery_transition_rejected)
    end
  end

  def ended(skeleton) do
    active =
      Repo.exists?(
        from p in ProcessRecord,
          where: p.environment_id == ^skeleton.environment.id and is_nil(p.ended_at)
      )

    unsafe =
      Repo.exists?(
        from event in RunEvent,
          where: event.run_id == ^skeleton.run.id and event.event_type == "process.cleanup_failed"
      )

    if active or unsafe, do: {:error, :recovery_process_unverified}, else: :ok
  end

  def recovered_attempts(attempts),
    do: Enum.count(attempts, &is_map(get_in(&1.checkpoint_json || %{}, ["recovery"])))

  @doc "Store public stage output for deterministic continuation in this same run/worktree."
  def checkpoint(stage, run, cycle) do
    if enabled?(run) do
      data = %{
        "version" => 1,
        "cycle" => cycle,
        "output" => stage.output,
        "tools" => stage.request.grant["tools"]
      }

      case Execution.checkpoint_stage_attempt(
             stage.attempt,
             Map.put(stage.attempt.checkpoint_json || %{}, "completed_stage", data)
           ) do
        {:ok, _} -> {:ok, stage}
        error -> error
      end
    else
      {:ok, stage}
    end
  end

  def replay(skeleton, stage, cycle) do
    attempts =
      Repo.all(
        from a in StageAttempt,
          where:
            a.run_id == ^skeleton.run.id and a.stage_key == ^stage and a.state == "succeeded",
          order_by: [desc: a.attempt]
      )

    case Enum.find(
           attempts,
           &(get_in(&1.checkpoint_json || %{}, ["completed_stage", "cycle"]) == cycle)
         ) do
      nil ->
        :new

      attempt ->
        saved = attempt.checkpoint_json["completed_stage"]

        with {:ok, output} <- replay_output(saved["output"], skeleton.environment) do
          {:ok,
           %{
             attempt: attempt,
             output: output,
             environment: skeleton.environment,
             request: %{stage_key: stage, grant: %{"tools" => saved["tools"]}},
             replayed?: true
           }}
        end
    end
  end

  defp replay_output(%{"artifact" => artifact, "text" => text}, env) do
    path = Path.expand(Path.join("artifacts", artifact["path"]), env.run_dir)

    with true <- String.starts_with?(path, Path.join(env.run_dir, "artifacts") <> "/"),
         {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, content} <- File.read(path),
         true <- Base.encode16(:crypto.hash(:sha256, content), case: :lower) == artifact["sha256"] do
      {:ok, %{artifact: artifact, text: text}}
    else
      _ -> {:error, :recovery_artifact_changed}
    end
  end

  defp replay_output(output, _env), do: {:ok, output}
end
