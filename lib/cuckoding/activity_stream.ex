defmodule Cuckoding.ActivityStream do
  @moduledoc "Durable, redacted public activity with reconnect-safe per-stream sequences."

  import Ecto.Query

  alias Cuckoding.Adapters.Types
  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.Commands
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Projects.Project
  alias Cuckoding.Repo
  alias Cuckoding.Security.Redactor
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Task

  @maximum_page 200

  @doc "Persists one normalized adapter event exactly once for an agent session."
  def record(%AgentSession{} = session, %Types.Event{} = event) do
    with :ok <- validate_event(event),
         %StageAttempt{} = attempt <- Repo.get(StageAttempt, session.stage_attempt_id),
         %Run{} = run <- Repo.get(Run, attempt.run_id) do
      provider_event_key = digest(event.event_id)

      Commands.execute_once(
        %{
          idempotency_key: "activity:#{session.id}:#{provider_event_key}",
          kind: "activity.record",
          target_type: "agent_session",
          target_id: session.id,
          payload: %{
            "provider_event_key" => provider_event_key,
            "provider_sequence" => event.sequence
          }
        },
        fn _command -> persist(run, session, attempt, event) end
      )
    else
      nil -> {:error, :activity_owner_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Subscribes first, then returns committed events after the acknowledged sequence."
  def connect(stream_id, after_sequence \\ 0) do
    with :ok <- subscribe(stream_id), do: {:ok, list(stream_id, after_sequence)}
  end

  def subscribe(stream_id) when is_binary(stream_id),
    do: Phoenix.PubSub.subscribe(Cuckoding.PubSub, "activity:#{stream_id}")

  def subscribe(:all), do: Phoenix.PubSub.subscribe(Cuckoding.PubSub, "activity")

  @doc "Returns a bounded, ordered catch-up page after a per-stream sequence."
  def list(stream_id, after_sequence, options \\ [])
      when is_binary(stream_id) and is_integer(after_sequence) and after_sequence >= 0 do
    limit = options |> Keyword.get(:limit, @maximum_page) |> min(@maximum_page) |> max(1)

    Repo.all(
      from(event in RunEvent,
        where: event.run_id == ^stream_id and event.sequence > ^after_sequence,
        order_by: [asc: event.sequence],
        limit: ^limit
      )
    )
    |> Enum.map(&public_event/1)
  end

  @doc "Returns the latest public events across streams for the dashboard component."
  def recent(limit \\ 20) when is_integer(limit) and limit > 0 do
    limit = min(limit, @maximum_page)

    Repo.all(
      from(event in RunEvent,
        order_by: [desc: event.occurred_at, desc: event.id],
        limit: ^limit
      )
    )
    |> Enum.reverse()
    |> Enum.map(&public_event/1)
  end

  @doc "Builds the complete nullable correlation chain for persistence and display."
  def correlation(stream_id, payload \\ %{}) when is_binary(stream_id) and is_map(payload) do
    ids = stream_ids(stream_id)
    stage_id = stage_attempt_id(payload)
    context(ids, stage_id)
  end

  @doc "Classifies freshness without inferring or changing workflow state."
  def status([], _now, _stale_after_ms), do: %{stale?: true, reconciling?: false}

  def status(events, now, stale_after_ms)
      when is_list(events) and is_struct(now, DateTime) and is_integer(stale_after_ms) do
    latest = List.last(events)
    age_ms = max(DateTime.diff(now, latest.occurred_at, :millisecond), 0)

    %{
      stale?: age_ms > stale_after_ms,
      reconciling?:
        String.starts_with?(latest.event_type, "run.reconciliation_") and
          is_integer(latest.sleep_gap_ms) and latest.sleep_gap_ms > 0
    }
  end

  defp persist(run, session, attempt, event) do
    provider_event_key = digest(event.event_id)

    attrs = %{
      event_type: event.type,
      public_summary: event.public_summary,
      payload:
        event.metadata
        |> Map.put("provider_event_key", provider_event_key)
        |> Map.put("provider_sequence", event.sequence)
        |> Map.put("trust", Atom.to_string(event.trust))
        |> Map.put("stage_attempt_id", attempt.id)
        |> Map.put("agent_session_id", session.id)
    }

    case EventStore.append_in_transaction(run.id, attrs) do
      {:ok, {stored, _projection}} ->
        {:ok,
         %{
           "outcome" => "recorded",
           "event_id" => stored.id,
           "event_sequence" => stored.sequence
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp public_event(event) do
    payload = Redactor.redact(event.payload)

    correlation =
      case Map.fetch(payload, "correlation") do
        {:ok, stored} -> stored
        :error -> correlation(event.run_id, payload)
      end

    %{
      id: event.id,
      stream_id: event.run_id,
      sequence: event.sequence,
      event_type: event.event_type,
      public_summary: Redactor.redact(event.public_summary),
      metadata: Map.drop(payload, ["correlation"]),
      correlation: correlation,
      occurred_at: event.occurred_at,
      sleep_gap_ms: positive_integer(payload["gap_ms"])
    }
  end

  defp stream_ids("board:" <> board_id), do: %{board_id: board_id}
  defp stream_ids("task:" <> task_id), do: %{task_id: task_id}
  defp stream_ids(run_id), do: %{run_id: run_id}

  defp context(%{run_id: run_id}, stage_id) do
    with %Run{} = run <- get(Run, run_id),
         %Task{} = task <- get(Task, run.task_id),
         %Board{} = board <- get(Board, task.board_id),
         %Project{} = project <- get(Project, board.project_id) do
      correlation(project, board, task, run, stage_id)
    else
      _missing -> empty_correlation(%{"run_id" => run_id})
    end
  end

  defp context(%{task_id: task_id}, stage_id) do
    with %Task{} = task <- get(Task, task_id),
         %Board{} = board <- get(Board, task.board_id),
         %Project{} = project <- get(Project, board.project_id) do
      correlation(project, board, task, nil, stage_id)
    else
      _missing -> empty_correlation(%{"task_id" => task_id})
    end
  end

  defp context(%{board_id: board_id}, stage_id) do
    with %Board{} = board <- get(Board, board_id),
         %Project{} = project <- get(Project, board.project_id) do
      correlation(project, board, nil, nil, stage_id)
    else
      _missing -> empty_correlation(%{"board_id" => board_id})
    end
  end

  defp correlation(project, board, task, run, stage_id) do
    attempt = if is_binary(stage_id), do: get(StageAttempt, stage_id)

    session =
      if attempt do
        Repo.one(
          from(session in AgentSession,
            where: session.stage_attempt_id == ^attempt.id,
            order_by: [desc: session.inserted_at, desc: session.id],
            limit: 1
          )
        )
      end

    empty_correlation(%{
      "project_id" => project.id,
      "board_id" => board.id,
      "task_id" => record_id(task),
      "run_id" => record_id(run),
      "stage_attempt_id" => record_id(attempt),
      "agent_session_id" => record_id(session),
      "role" => field(attempt, :role_key),
      "runtime" => field(session, :adapter_key),
      "model" => model(session)
    })
  end

  defp empty_correlation(values) do
    Map.merge(
      %{
        "project_id" => nil,
        "board_id" => nil,
        "task_id" => nil,
        "run_id" => nil,
        "stage_attempt_id" => nil,
        "agent_session_id" => nil,
        "role" => nil,
        "runtime" => nil,
        "model" => nil,
        "correlation_id" => Cuckoding.Correlation.current()
      },
      values
    )
  end

  defp stage_attempt_id(%{"stage_attempt_id" => id}) when is_binary(id), do: id

  defp stage_attempt_id(%{"entity" => "stage_attempt", "id" => id}) when is_binary(id),
    do: id

  defp stage_attempt_id(_payload), do: nil
  defp positive_integer(value) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value), do: nil
  defp digest(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp validate_event(%Types.Event{} = event) do
    valid = {
      nonempty_binary?(event.event_id),
      nonnegative_integer?(event.sequence),
      nonempty_binary?(event.type),
      nonempty_binary?(event.public_summary),
      is_map(event.metadata),
      event.trust in [:trusted, :untrusted]
    }

    if valid == {true, true, true, true, true, true},
      do: :ok,
      else: {:error, :invalid_activity_event}
  end

  defp validate_event(_event), do: {:error, :invalid_activity_event}
  defp nonempty_binary?(value), do: is_binary(value) and value != ""
  defp nonnegative_integer?(value), do: is_integer(value) and value >= 0

  defp record_id(nil), do: nil
  defp record_id(record), do: record.id
  defp field(nil, _key), do: nil
  defp field(record, key), do: Map.fetch!(record, key)
  defp model(nil), do: nil
  defp model(session), do: session.actual_model || session.requested_model

  defp get(schema, id) do
    case Ecto.UUID.cast(id) do
      {:ok, valid_id} -> Repo.get(schema, valid_id)
      :error -> nil
    end
  end
end
