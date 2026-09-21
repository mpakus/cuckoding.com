defmodule Cuckoding.Execution.Transitions do
  @moduledoc """
  Applies idempotent task/run transitions and timing updates with their durable events.
  """

  alias Cuckoding.Execution.Commands
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.StateMachine
  alias Cuckoding.Workflows.Task

  @standalone_task_transitions MapSet.new([
                                 {"draft", "ready"},
                                 {"draft", "cancelled"},
                                 {"draft", "archived"},
                                 {"ready", "draft"},
                                 {"ready", "cancelled"},
                                 {"ready", "archived"},
                                 {"done", "archived"},
                                 {"failed", "ready"},
                                 {"failed", "archived"},
                                 {"cancelled", "ready"},
                                 {"cancelled", "archived"},
                                 {"archived", "draft"}
                               ])
  @terminal_states ~w(done failed cancelled)
  @stage_transitions %{
    "pending" => ~w(running cancelled),
    "running" => ~w(waiting succeeded failed cancelled),
    "waiting" => ~w(running failed cancelled),
    "succeeded" => [],
    "failed" => [],
    "cancelled" => []
  }

  def transition_task(task_id, to, idempotency_key, attrs \\ %{}) do
    command = command_attrs(idempotency_key, "task.transition", "task", task_id, to, attrs)

    Commands.execute_once(command, fn _command ->
      case Repo.get(Task, task_id) do
        nil -> {:ok, rejected("task", task_id, nil, to, :not_found)}
        task -> transition_standalone_task(task, to, wait_reason(attrs))
      end
    end)
  end

  def allowed_task_transitions(%Task{active_run_id: nil, state: state}) do
    @standalone_task_transitions
    |> Enum.filter(&(elem(&1, 0) == state))
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort()
  end

  def allowed_task_transitions(%Task{}), do: []

  def transition_run(run_id, to, idempotency_key, attrs \\ %{}) do
    command = command_attrs(idempotency_key, "run.transition", "run", run_id, to, attrs)

    Commands.execute_once(command, fn _command ->
      with %Run{} = run <- Repo.get(Run, run_id),
           %Task{} = task <- Repo.get(Task, run.task_id) do
        transition_run_and_task(run, task, to, wait_reason(attrs))
      else
        nil -> {:ok, rejected("run", run_id, nil, to, :not_found)}
      end
    end)
  end

  @doc "Marks a queued run whose worktree preparation failed, leaving its task Ready."
  def fail_run_preparation(run_id, reason) when is_binary(run_id) do
    Commands.execute_once(
      %{
        idempotency_key: "prepare:#{run_id}:failed",
        kind: "run.preparation_failed",
        target_type: "run",
        target_id: run_id,
        payload: %{"code" => preparation_code(reason)}
      },
      fn _command ->
        case Repo.get(Run, run_id) do
          %Run{state: "queued"} = run -> fail_queued_run(run, reason)
          _other -> {:ok, rejected("run", run_id, nil, "failed", :invalid_transition)}
        end
      end
    )
  end

  defp fail_queued_run(run, reason) do
    case Repo.get(Task, run.task_id) do
      %Task{state: "ready", active_run_id: nil} ->
        persist_preparation_failure(run, reason)

      _other ->
        {:ok, rejected("run", run.id, run.state, "failed", :task_not_ready)}
    end
  end

  defp persist_preparation_failure(run, reason) do
    case EventStore.append_in_transaction(
           run.id,
           %{
             event_type: "run.preparation_failed",
             public_summary: "Run preparation failed; the task remains Ready",
             payload: %{"code" => preparation_code(reason)}
           },
           fn repo, _sequence ->
             repo.update(Run.transition_changeset(run, %{state: "failed"}))
           end
         ) do
      {:ok, {event, _run}} -> {:ok, %{"outcome" => "failed", "event_id" => event.id}}
      error -> error
    end
  end

  defp preparation_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp preparation_code(_reason), do: "preparation_failed"

  def transition_stage_attempt(stage_attempt_id, to, idempotency_key) do
    command =
      command_attrs(
        idempotency_key,
        "stage.transition",
        "stage_attempt",
        stage_attempt_id,
        to,
        %{}
      )

    Commands.execute_once(command, fn _command ->
      case Repo.get(StageAttempt, stage_attempt_id) do
        nil -> {:ok, rejected("stage_attempt", stage_attempt_id, nil, to, :not_found)}
        attempt -> transition_stage_attempt(attempt, to)
      end
    end)
  end

  def record_stage_time(stage_attempt_id, active_delta_ms, wall_delta_ms, idempotency_key) do
    payload = %{"active_delta_ms" => active_delta_ms, "wall_delta_ms" => wall_delta_ms}

    command = %{
      idempotency_key: idempotency_key,
      kind: "stage.record_time",
      target_type: "stage_attempt",
      target_id: stage_attempt_id,
      payload: payload
    }

    Commands.execute_once(command, fn _command ->
      case Repo.get(StageAttempt, stage_attempt_id) do
        nil -> {:ok, rejected("stage_attempt", stage_attempt_id, nil, nil, :not_found)}
        attempt -> record_time(attempt, active_delta_ms, wall_delta_ms)
      end
    end)
  end

  defp transition_standalone_task(task, to, reason) do
    with :ok <- StateMachine.validate(:task, task.state, to, reason),
         :ok <- standalone_transition?(task, to) do
      attrs = transition_attrs(to, reason, nil)

      append_transition("task:" <> task.id, "task", task, to, reason, fn repo, _sequence ->
        repo.update(Task.transition_changeset(task, attrs))
      end)
    else
      {:error, reason} -> {:ok, rejected("task", task.id, task.state, to, reason)}
    end
  end

  defp transition_stage_attempt(attempt, to) do
    if to in Map.fetch!(@stage_transitions, attempt.state) do
      now = Cuckoding.Clock.wall_now()

      attrs =
        %{state: to}
        |> maybe_put(:started_at, attempt.state == "pending", now)
        |> maybe_put(:finished_at, to in ~w(succeeded failed cancelled), now)

      append_transition(attempt.run_id, "stage_attempt", attempt, to, nil, fn repo, _sequence ->
        repo.update(StageAttempt.transition_changeset(attempt, attrs))
      end)
    else
      {:ok, rejected("stage_attempt", attempt.id, attempt.state, to, :invalid_transition)}
    end
  end

  defp transition_run_and_task(run, task, to, reason) do
    with :ok <- StateMachine.validate(:run, run.state, to, reason),
         :ok <- StateMachine.validate(:task, task.state, to, reason),
         :ok <- run_owns_task?(run, task) do
      append_transition(run.id, "run", run, to, reason, fn repo, _sequence ->
        update_run_and_task(repo, run, task, to, reason)
      end)
    else
      {:error, reason} -> {:ok, rejected("run", run.id, run.state, to, reason)}
    end
  end

  defp update_run_and_task(repo, run, task, to, reason) do
    with {:ok, updated_run} <-
           repo.update(Run.transition_changeset(run, transition_attrs(to, reason))),
         {:ok, updated_task} <-
           repo.update(
             Task.transition_changeset(
               task,
               transition_attrs(to, reason, active_run_id(run.id, to))
             )
           ) do
      {:ok, {updated_run, updated_task}}
    end
  end

  defp append_transition(stream_id, entity, record, to, reason, projection) do
    event_attrs = %{
      event_type: entity <> ".transitioned",
      public_summary: "#{String.capitalize(entity)} moved from #{record.state} to #{to}",
      payload: transition_payload(entity, record.id, record.state, to, reason)
    }

    case EventStore.append_in_transaction(stream_id, event_attrs, projection) do
      {:ok, {event, _projection}} ->
        {:ok, transitioned(entity, record.id, record.state, to, reason, event)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_time(attempt, active_delta_ms, wall_delta_ms)
       when is_integer(active_delta_ms) and is_integer(wall_delta_ms) and active_delta_ms >= 0 and
              wall_delta_ms >= active_delta_ms do
    attrs = %{
      active_ms: attempt.active_ms + active_delta_ms,
      wall_ms: attempt.wall_ms + wall_delta_ms
    }

    event_attrs = %{
      event_type: "stage.timing_recorded",
      public_summary: "Stage timing recorded",
      payload: %{
        "stage_attempt_id" => attempt.id,
        "active_delta_ms" => active_delta_ms,
        "wall_delta_ms" => wall_delta_ms
      }
    }

    projection = fn repo, _sequence ->
      repo.update(StageAttempt.timing_changeset(attempt, attrs))
    end

    case EventStore.append_in_transaction(attempt.run_id, event_attrs, projection) do
      {:ok, {event, _attempt}} ->
        {:ok,
         %{
           "outcome" => "recorded",
           "stage_attempt_id" => attempt.id,
           "active_ms" => attrs.active_ms,
           "wall_ms" => attrs.wall_ms,
           "event_id" => event.id,
           "event_sequence" => event.sequence
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_time(attempt, _active_delta_ms, _wall_delta_ms) do
    {:ok, rejected("stage_attempt", attempt.id, nil, nil, :invalid_duration)}
  end

  defp standalone_transition?(%Task{active_run_id: nil, state: from}, to) do
    if MapSet.member?(@standalone_task_transitions, {from, to}),
      do: :ok,
      else: {:error, :run_transition_required}
  end

  defp standalone_transition?(_task, _to), do: {:error, :active_run_controls_state}

  defp run_owns_task?(%Run{state: "queued"}, %Task{active_run_id: nil}), do: :ok

  defp run_owns_task?(%Run{id: run_id}, %Task{active_run_id: run_id}), do: :ok

  defp run_owns_task?(_run, _task), do: {:error, :run_does_not_own_task}

  defp active_run_id(_run_id, state) when state in @terminal_states, do: nil
  defp active_run_id(run_id, _state), do: run_id

  defp transition_attrs(to, reason, active_run_id \\ :unchanged) do
    attrs = %{state: to, wait_reason: if(to == "waiting", do: reason)}
    if active_run_id == :unchanged, do: attrs, else: Map.put(attrs, :active_run_id, active_run_id)
  end

  defp command_attrs(key, kind, target_type, target_id, to, attrs) do
    %{
      idempotency_key: key,
      kind: kind,
      target_type: target_type,
      target_id: target_id,
      payload: %{"to" => to, "wait_reason" => wait_reason(attrs)}
    }
  end

  defp wait_reason(attrs), do: attrs[:wait_reason] || attrs["wait_reason"]

  defp transition_payload(entity, id, from, to, reason) do
    %{"entity" => entity, "id" => id, "from" => from, "to" => to, "wait_reason" => reason}
  end

  defp transitioned(entity, id, from, to, reason, event) do
    transition_payload(entity, id, from, to, reason)
    |> Map.merge(%{
      "outcome" => "transitioned",
      "event_id" => event.id,
      "event_sequence" => event.sequence
    })
  end

  defp rejected(entity, id, from, to, reason) do
    %{
      "outcome" => "rejected",
      "reason" => Atom.to_string(reason),
      "entity" => entity,
      "id" => id,
      "from" => from,
      "to" => to
    }
  end

  defp maybe_put(map, key, true, value), do: Map.put(map, key, value)
  defp maybe_put(map, _key, false, _value), do: map
end
