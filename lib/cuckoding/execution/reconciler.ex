defmodule Cuckoding.Execution.Reconciler do
  @moduledoc """
  Reconciles durable run ownership before scheduling without mutating host resources.
  """

  import Ecto.Query

  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.CommandRecovery
  alias Cuckoding.Execution.Commands
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.Leases
  alias Cuckoding.Execution.ProcessRecord
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Execution.UnavailableRecoveryInspector
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Task

  @active_run_states ~w(queued running waiting paused hibernated blocked)
  @active_attempt_states ~w(pending running waiting)

  def run(options \\ []) do
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())
    gap_ms = Keyword.get(options, :gap_ms, 0)
    inspector = Keyword.get(options, :inspector, configured_inspector())
    inspector_options = Keyword.get(options, :inspector_options, [])
    cycle_id = Keyword.get(options, :cycle_id, cycle_id(now, gap_ms))
    run_ids = Keyword.get(options, :run_ids)

    with {:ok, extended_leases} <- extend_sleep_gap(gap_ms, now),
         {:ok, expired_leases} <- Leases.expire(now),
         {recovered_commands, nil} <- CommandRecovery.recover(now) do
      decisions =
        run_ids
        |> active_runs_query()
        |> Repo.all()
        |> Enum.map(&reconcile_run(&1, inspector, inspector_options, cycle_id, gap_ms, now))

      finish_reconciliation(
        decisions,
        extended_leases,
        expired_leases,
        recovered_commands,
        now
      )
    end
  end

  defp finish_reconciliation(
         decisions,
         extended_leases,
         expired_leases,
         recovered_commands,
         now
       ) do
    case Enum.find_value(decisions, &decision_failure/1) do
      nil ->
        command_results = CommandRecovery.dispatch(now: now)

        {:ok,
         %{
           extended_leases: length(extended_leases),
           expired_leases: expired_leases,
           recovered_commands: recovered_commands,
           dispatched_commands: length(command_results),
           decisions: decisions
         }}

      reason ->
        {:error, {:run_reconciliation_failed, reason}}
    end
  end

  defp decision_failure({:error, reason}), do: reason

  defp decision_failure({:ok, %{result: %{"outcome" => "rejected", "reason" => reason}}}),
    do: reason

  defp decision_failure(_result), do: nil

  defp active_runs_query(nil) do
    from(run in Run, where: run.state in ^@active_run_states, order_by: run.id)
  end

  defp active_runs_query(run_ids) do
    from(run in Run,
      where: run.state in ^@active_run_states and run.id in ^run_ids,
      order_by: run.id
    )
  end

  defp reconcile_run(run, inspector, options, cycle_id, gap_ms, now) do
    inspection = inspect_run(run, inspector, options)
    decision = classify(run, inspection)
    key = reconciliation_key(run, inspection, decision, cycle_id)

    attrs = %{
      idempotency_key: key,
      kind: "run.reconcile",
      target_type: "run",
      target_id: run.id,
      payload: %{
        "cycle_id" => cycle_id,
        "decision" => Atom.to_string(decision.outcome),
        "reasons" => Enum.map(decision.reasons, &Atom.to_string/1)
      }
    }

    Commands.execute_once(attrs, fn _command ->
      persist_decision(run, inspection, decision, cycle_id, gap_ms, now)
    end)
  end

  defp inspect_run(run, inspector, options) do
    environment =
      Repo.one(
        from(environment in Environment,
          where: environment.run_id == ^run.id and environment.state not in ["stopped", "failed"]
        )
      )

    case environment do
      nil ->
        %{environment: nil, worktree: :not_allocated, port: :not_allocated, processes: []}

      environment ->
        processes =
          Repo.all(
            from(process in ProcessRecord,
              where: process.environment_id == ^environment.id and process.state == "running",
              order_by: process.id
            )
          )
          |> Enum.map(&inspect_process(&1, inspector, options))

        %{
          environment: environment,
          worktree: normalize_worktree(inspector.worktree_status(environment, options)),
          port: inspect_port(environment.port, processes, inspector, options),
          processes: processes
        }
    end
  end

  defp inspect_process(process, inspector, options) do
    status =
      case inspector.process_identity(process.pid, options) do
        {:ok, identity} when identity == process.start_identity -> :matching
        {:ok, _identity} -> :identity_mismatch
        :gone -> :gone
        {:error, _reason} -> :unverified
      end

    %{record: process, status: status}
  end

  defp inspect_port(nil, _processes, _inspector, _options), do: :not_allocated

  defp inspect_port(port, processes, inspector, options) do
    case inspector.port_owner(port, options) do
      :free ->
        :free

      {:ok, pid, identity} ->
        if owned_port?(processes, pid, identity),
          do: :owned,
          else: :conflict

      {:error, _reason} ->
        :unverified
    end
  end

  defp normalize_worktree(status) when status in [:present, :missing], do: status
  defp normalize_worktree({:drift, _reason}), do: :drift
  defp normalize_worktree({:error, _reason}), do: :unverified

  defp owned_port?(processes, pid, identity) do
    Enum.any?(processes, fn inspected ->
      inspected.record.pid == pid and inspected.record.start_identity == identity and
        inspected.status == :matching
    end)
  end

  defp classify(%Run{state: "queued"}, %{environment: nil}),
    do: decision(:continue, [:not_started])

  defp classify(%Run{state: state, wait_reason: "reconciliation"}, %{environment: nil})
       when state in ["waiting", "blocked"],
       do: decision(:continue, [:awaiting_recovery])

  defp classify(_run, %{environment: nil}), do: decision(:recover, [:environment_missing], true)

  defp classify(run, inspection) do
    statuses = Enum.map(inspection.processes, & &1.status)

    [
      unsafe_worktree(inspection.worktree),
      unsafe_process(statuses),
      unsafe_port(inspection.port),
      missing_worktree(inspection, statuses),
      missing_process(inspection, statuses),
      missing_port_service(inspection),
      missing_process_record(run, statuses),
      decision(:continue, [:resources_verified])
    ]
    |> Enum.find(& &1)
  end

  defp unsafe_worktree(status) when status in [:drift, :unverified],
    do: decision(:block, [worktree_reason(status)])

  defp unsafe_worktree(_status), do: nil

  defp unsafe_process(statuses) do
    cond do
      :identity_mismatch in statuses -> decision(:block, [:process_identity_mismatch])
      :unverified in statuses -> decision(:block, [:process_identity_unverified])
      true -> nil
    end
  end

  defp unsafe_port(status) when status in [:conflict, :unverified],
    do: decision(:block, [port_reason(status)])

  defp unsafe_port(_status), do: nil

  defp missing_worktree(%{worktree: :missing} = inspection, statuses) do
    if :matching in statuses,
      do: decision(:block, [:worktree_missing_with_live_process]),
      else: decision(:recover, [:worktree_missing], true, gone_ids(inspection))
  end

  defp missing_worktree(_inspection, _statuses), do: nil

  defp missing_process(inspection, statuses) do
    if :gone in statuses,
      do: decision(:recover, [:process_missing], :matching not in statuses, gone_ids(inspection)),
      else: nil
  end

  defp missing_port_service(%{port: :free, environment: %{state: "running"}}),
    do: decision(:recover, [:port_service_missing])

  defp missing_port_service(_inspection), do: nil

  defp missing_process_record(%Run{state: state}, []) when state in ["running", "paused"],
    do: decision(:recover, [:process_record_missing])

  defp missing_process_record(_run, _statuses), do: nil

  defp persist_decision(expected_run, inspection, decision, cycle_id, gap_ms, now) do
    run = Repo.get!(Run, expected_run.id)

    if run.state == expected_run.state do
      append_decision(run, inspection, decision, cycle_id, gap_ms, now)
    else
      {:ok,
       %{
         "outcome" => "rejected",
         "reason" => "state_changed",
         "run_id" => run.id,
         "expected_state" => expected_run.state,
         "actual_state" => run.state
       }}
    end
  end

  defp append_decision(run, inspection, decision, cycle_id, gap_ms, now) do
    event_attrs = %{
      event_type: event_type(decision.outcome, gap_ms),
      public_summary: public_summary(decision.outcome, gap_ms),
      payload: %{
        "decision" => Atom.to_string(decision.outcome),
        "reasons" => Enum.map(decision.reasons, &Atom.to_string/1),
        "cycle_id" => cycle_id,
        "gap_ms" => gap_ms
      }
    }

    projection = fn repo, _sequence ->
      apply_decision(repo, run, inspection, decision, now)
    end

    case EventStore.append_in_transaction(run.id, event_attrs, projection) do
      {:ok, {event, _projection}} ->
        {:ok,
         %{
           "outcome" => Atom.to_string(decision.outcome),
           "run_id" => run.id,
           "reasons" => Enum.map(decision.reasons, &Atom.to_string/1),
           "event_id" => event.id,
           "event_sequence" => event.sequence
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_decision(_repo, _run, _inspection, %{outcome: :continue}, _now),
    do: {:ok, :continued}

  defp apply_decision(repo, run, inspection, decision, now) do
    state = if decision.outcome == :block, do: "blocked", else: "waiting"
    wait_reason = if state == "waiting", do: "reconciliation"
    task = repo.get!(Task, run.task_id)

    with {:ok, _run} <-
           repo.update(Run.transition_changeset(run, %{state: state, wait_reason: wait_reason})),
         {:ok, _task} <-
           repo.update(
             Task.transition_changeset(task, %{
               state: state,
               wait_reason: wait_reason,
               active_run_id: run.id
             })
           ) do
      recover_records(repo, run, inspection, decision, now)
      {:ok, state}
    end
  end

  defp recover_records(_repo, _run, _inspection, %{outcome: :block}, _now), do: :ok

  defp recover_records(repo, run, inspection, decision, now) do
    if decision.fail_environment? and inspection.environment do
      inspection.environment
      |> Ecto.Changeset.change(state: "failed")
      |> repo.update!()
    end

    if decision.lost_process_ids != [] do
      repo.update_all(
        from(process in ProcessRecord, where: process.id in ^decision.lost_process_ids),
        set: [state: "lost", ended_at: now, updated_at: now]
      )
    end

    repo.update_all(
      from(attempt in StageAttempt,
        where: attempt.run_id == ^run.id and attempt.state in ^@active_attempt_states
      ),
      set: [state: "waiting", updated_at: now]
    )

    repo.update_all(
      from(session in AgentSession,
        join: attempt in StageAttempt,
        on: attempt.id == session.stage_attempt_id,
        where: attempt.run_id == ^run.id and session.state not in ["finished", "failed"]
      ),
      set: [state: "interrupted", updated_at: now]
    )
  end

  defp decision(outcome, reasons, fail_environment? \\ false, lost_process_ids \\ []) do
    %{
      outcome: outcome,
      reasons: reasons,
      fail_environment?: fail_environment?,
      lost_process_ids: lost_process_ids
    }
  end

  defp gone_ids(inspection) do
    for %{record: process, status: :gone} <- inspection.processes, do: process.id
  end

  defp worktree_reason(:drift), do: :worktree_drift
  defp worktree_reason(:unverified), do: :worktree_unverified
  defp port_reason(:conflict), do: :port_ownership_conflict
  defp port_reason(:unverified), do: :port_ownership_unverified

  defp event_type(_outcome, gap_ms) when gap_ms > 0, do: "run.resumed_after_sleep"
  defp event_type(outcome, _gap_ms), do: "run.reconciliation_#{outcome}"

  defp public_summary(outcome, gap_ms) when gap_ms > 0,
    do: "Run reconciled after a #{gap_ms} ms sleep gap: #{outcome}"

  defp public_summary(outcome, _gap_ms), do: "Run startup reconciliation: #{outcome}"

  defp reconciliation_key(run, inspection, decision, cycle_id) do
    fingerprint =
      {run.id, run.state, inspection_fingerprint(inspection), decision.outcome, decision.reasons,
       cycle_id}
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "reconcile:" <> fingerprint
  end

  defp inspection_fingerprint(inspection) do
    process_states = Enum.map(inspection.processes, &{&1.record.id, &1.status})
    {environment_id(inspection.environment), inspection.worktree, inspection.port, process_states}
  end

  defp environment_id(nil), do: nil
  defp environment_id(environment), do: environment.id

  defp extend_sleep_gap(gap_ms, now) when gap_ms > 0,
    do: Leases.extend_for_sleep_gap(gap_ms, now: now)

  defp extend_sleep_gap(_gap_ms, _now), do: {:ok, []}

  defp cycle_id(now, gap_ms) when gap_ms > 0 do
    started_at = DateTime.add(now, -gap_ms, :millisecond)
    "sleep:" <> DateTime.to_iso8601(started_at)
  end

  defp cycle_id(_now, _gap_ms), do: "startup"

  defp configured_inspector do
    Application.get_env(:cuckoding, :recovery_inspector, UnavailableRecoveryInspector)
  end
end
