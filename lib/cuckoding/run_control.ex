defmodule Cuckoding.RunControl do
  @moduledoc "Durable user controls and serialization of owned workflow launches."

  import Ecto.Query

  alias Cuckoding.Execution
  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.LocalProcessRunner
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Identifier
  alias Cuckoding.Repo
  alias Cuckoding.WalkingSkeleton

  @active_states ~w(queued running waiting paused hibernated blocked)

  def application_state do
    latest("application", "application.execution_control") ||
      %{"mode" => "active", "paused_runs" => []}
  end

  def admission_open?, do: application_state()["mode"] == "active"

  def error_message(:application_paused),
    do:
      "Workspace execution is paused or stopped. Resume it on the dashboard before starting or resuming this run."

  def error_message(reason)
      when reason in [:resume_worker_unavailable, :resume_checkpoint_unavailable],
      do:
        "This run has no live workflow to resume. Its history and worktree are retained. Inspect it before stopping and preparing a new run."

  def error_message(_reason),
    do:
      "Run control could not finish safely. Recorded state is preserved, but process suspension or cleanup is unconfirmed. Inspect the run and retry the control."

  def admit(run_id, callback) do
    case locked(run_id, fn -> admitted_transaction(callback) end) do
      {:ok, result} -> result
      error -> error
    end
  end

  defp admitted_transaction(callback) do
    EventStore.transaction(fn ->
      unless admission_open?(), do: Repo.rollback(:application_paused)

      case callback.() do
        {:error, reason} -> Repo.rollback(reason)
        result -> result
      end
    end)
  end

  def track(run_id, kind, callback) do
    with {:ok, _owner} <- Registry.register(Cuckoding.RunRegistry, {:orchestration, run_id}, nil) do
      try do
        Cuckoding.OrchestrationFailure.guard(run_id, kind, callback)
      after
        Registry.unregister(Cuckoding.RunRegistry, {:orchestration, run_id})
      end
    end
  end

  def await_running(run_id) do
    case Repo.get(Run, run_id) do
      %Run{state: "running"} ->
        :ok

      %Run{state: "paused"} ->
        Process.sleep(100)
        await_running(run_id)

      _run ->
        {:error, :run_interrupted}
    end
  end

  def launch(run_id, callback) do
    with :ok <- await_running(run_id),
         result <- locked(run_id, fn -> launch_active(run_id, callback) end) do
      case result do
        {:error, :launch_paused} -> launch(run_id, callback)
        result -> result
      end
    end
  end

  defp launch_active(id, callback) do
    if Repo.get!(Run, id).state == "running", do: callback.(), else: {:error, :launch_paused}
  end

  def control(run_id, action) when action in ["pause", "resume", "stop"] do
    locked(run_id, fn ->
      with {:ok, skeleton} <- WalkingSkeleton.load(run_id),
           {:ok, _request} <-
             EventStore.append(run_id, %{
               event_type: "run.control_requested",
               public_summary: "User requested #{action} for this run",
               payload: %{"action" => action}
             }),
           do: apply_control(skeleton, action)
    end)
  end

  def control_all(action) when action in ["pause", "resume", "stop"] do
    locked("application", fn -> control_batch(action) end)
  end

  defp control_batch(action) do
    with {:ok, {mode, ids}} <- record_application_control(action) do
      results = Enum.map(ids, &{&1, control(&1, action)})
      failures = Enum.reject(results, fn {_id, result} -> match?({:ok, _run}, result) end)
      if mode == "active", do: Cuckoding.ProjectAutopilot.Worker.wake()
      {:ok, %{mode: mode, failures: failures}}
    end
  end

  defp record_application_control(action) do
    EventStore.transaction(fn ->
      state = application_state()
      {mode, ids} = targets(action, state)
      paused = if action == "pause", do: Enum.uniq((state["paused_runs"] || []) ++ ids), else: []

      append!(
        "application",
        "application.execution_control",
        "User requested #{action} for all Cuckoding workflows",
        %{"mode" => mode, "paused_runs" => paused}
      )

      {mode, ids}
    end)
  end

  defp targets("pause", _state), do: {"paused", run_ids(~w(running waiting))}

  defp targets("stop", _state) do
    owned =
      Repo.all(
        from e in Cuckoding.Execution.Environment,
          join: p in Cuckoding.Execution.ProcessRecord,
          on: p.environment_id == e.id,
          where: p.state == "running",
          select: e.run_id
      )

    {"stopped", Enum.uniq(run_ids(@active_states) ++ owned)}
  end

  defp targets("resume", state) do
    ids = state["paused_runs"] || []

    {"active",
     Repo.all(from run in Run, where: run.id in ^ids and run.state == "paused", select: run.id)}
  end

  defp run_ids(states),
    do: Repo.all(from run in Run, where: run.state in ^states, order_by: run.id, select: run.id)

  defp apply_control(%{run: %{state: state}} = skeleton, "pause")
       when state in ["running", "waiting", "paused"] do
    with :ok <- persist_pause(skeleton),
         {:ok, _environment} <- LocalProcessRunner.pause(skeleton.environment) do
      {:ok, Repo.get!(Run, skeleton.run.id)}
    end
  end

  defp apply_control(%{run: %{state: "paused"}} = skeleton, "resume") do
    previous = latest(skeleton.run.id, "run.control_paused")

    with true <- admission_open?(),
         :ok <- resumable(skeleton.run.id, previous),
         {:ok, _environment} <- LocalProcessRunner.resume(skeleton.environment),
         {:ok, run} <- persist_resume(skeleton.run.id, previous) do
      {:ok, run}
    else
      false -> {:error, :application_paused}
      error -> error
    end
  end

  defp apply_control(skeleton, "stop") do
    with :ok <- persist_stop(skeleton.run),
         :ok <- LocalProcessRunner.destroy(skeleton.environment),
         {:ok, _environment} <-
           Execution.update_environment_preview(skeleton.environment, %{
             state: "stopped",
             preview_url: nil
           }) do
      {:ok, Repo.get!(Run, skeleton.run.id)}
    end
  end

  defp apply_control(_skeleton, _action), do: {:error, :control_not_available}

  defp persist_pause(%{run: %{state: "paused"}}), do: :ok

  defp persist_pause(skeleton) do
    transaction(fn ->
      checkpoint(skeleton.run.id)

      append!(skeleton.run.id, "run.control_paused", "Run paused by the user", %{
        "previous_state" => skeleton.run.state,
        "wait_reason" => skeleton.run.wait_reason
      })

      transition!(skeleton.run.id, "paused")
      update_sessions(skeleton.run.id, ~w(created starting running waiting), "paused")
      :ok
    end)
  end

  defp resumable(_id, %{"previous_state" => "waiting"}), do: :ok

  defp resumable(id, %{"previous_state" => "running"}) do
    if Registry.lookup(Cuckoding.RunRegistry, {:orchestration, id}) != [],
      do: :ok,
      else: {:error, :resume_worker_unavailable}
  end

  defp resumable(_id, _previous), do: {:error, :resume_checkpoint_unavailable}

  defp persist_resume(id, previous) do
    EventStore.transaction(fn ->
      transition!(id, "running")

      if previous["previous_state"] == "waiting",
        do: transition!(id, "waiting", previous["wait_reason"])

      update_sessions(id, ["paused"], "running")
      append!(id, "run.control_resumed", "Run resumed by the user", %{})
      Repo.get!(Run, id)
    end)
  end

  defp persist_stop(%{state: state}) when state in ~w(done failed cancelled), do: :ok

  defp persist_stop(run) do
    transaction(fn ->
      transition!(run.id, "cancelled")

      Enum.each(active_attempts(run.id), fn attempt ->
        {:ok, _command} =
          Execution.transition_stage_attempt(
            attempt.id,
            "cancelled",
            "stop:#{attempt.id}:#{Identifier.generate()}"
          )
      end)

      update_sessions(
        run.id,
        ~w(created starting running waiting paused interrupted),
        "cancelled"
      )

      Repo.update_all(
        from(a in Cuckoding.Workflows.Approval,
          where: a.run_id == ^run.id and a.decision == "pending"
        ),
        set: [
          decision: "rejected",
          actor: "local_user",
          reason: "Run stopped by the user",
          decided_at: Cuckoding.Clock.wall_now()
        ]
      )

      append!(
        run.id,
        "run.control_stopped",
        "Run stopped by the user; branch, worktree and evidence retained",
        %{}
      )

      :ok
    end)
  end

  defp checkpoint(id) do
    Enum.each(active_attempts(id), fn attempt ->
      {:ok, _result} =
        Execution.checkpoint_stage_attempt(
          attempt,
          Map.merge(attempt.checkpoint_json || %{}, %{
            "stage_attempt_id" => attempt.id,
            "reason" => "user_pause"
          })
        )
    end)
  end

  defp active_attempts(id),
    do:
      Repo.all(
        from a in StageAttempt, where: a.run_id == ^id and a.state in ~w(pending running waiting)
      )

  defp update_sessions(id, from_states, state) do
    Repo.update_all(
      from(s in AgentSession,
        join: a in StageAttempt,
        on: a.id == s.stage_attempt_id,
        where: a.run_id == ^id and s.state in ^from_states
      ),
      set: [state: state, updated_at: Cuckoding.Clock.wall_now()]
    )
  end

  defp transition!(id, state, reason \\ nil) do
    case Execution.transition_run(id, state, "control:#{id}:#{Identifier.generate()}",
           wait_reason: reason
         ) do
      {:ok, %{result: %{"outcome" => "transitioned"}}} -> :ok
      _error -> Repo.rollback(:control_transition_rejected)
    end
  end

  defp append!(id, type, summary, payload) do
    case EventStore.append_in_transaction(id, %{
           event_type: type,
           public_summary: summary,
           payload: payload
         }) do
      {:ok, _event} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp transaction(callback) do
    case EventStore.transaction(callback) do
      {:ok, :ok} -> :ok
      error -> error
    end
  end

  defp latest(id, type) do
    Repo.one(
      from event in RunEvent,
        where: event.run_id == ^id and event.event_type == ^type,
        order_by: [desc: event.sequence],
        limit: 1,
        select: event.payload
    )
  end

  # ponytail: one desktop BEAM VM; use distributed leases if hosts are added.
  # This mutex only orders live launches and
  # signals; durable run state and events still govern recovery after a crash.
  defp locked(id, callback), do: :global.trans({{__MODULE__, id}, self()}, callback, [node()])
end
