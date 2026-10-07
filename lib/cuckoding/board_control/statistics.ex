defmodule Cuckoding.BoardControl.Statistics do
  @moduledoc "Complete batch accounting, independent of capped dashboard projections."
  import Ecto.Query
  alias Cuckoding.{BoardControl, Clock, Repo}

  alias Cuckoding.Execution.{
    AgentSession,
    Environment,
    ProcessRecord,
    Run,
    RunEvent,
    StageAttempt
  }

  alias Cuckoding.Telemetry.{ResourceSample, UsageRecord}

  def for_board(board_id) do
    case BoardControl.latest(board_id) do
      nil -> nil
      execution -> snapshot(execution)
    end
  end

  def summaries do
    Repo.all(from e in BoardControl.Execution, order_by: [desc: e.inserted_at, desc: e.id])
    |> Enum.uniq_by(& &1.board_id)
    |> Enum.map(&snapshot/1)
  end

  def snapshot(e) do
    # ponytail: scan the full batch for correct totals; use SQL rollups if measured refresh cost grows.
    items = BoardControl.items(e.id)

    runs =
      Repo.all(
        from r in Run,
          where: r.board_execution_id == ^e.id,
          order_by: [asc: r.inserted_at, asc: r.id]
      )

    run_ids = Enum.map(runs, & &1.id)

    attempts =
      Repo.all(
        from a in StageAttempt,
          where: a.run_id in ^run_ids,
          order_by: [asc: a.inserted_at, asc: a.id]
      )

    attempt_ids = Enum.map(attempts, & &1.id)

    sessions =
      Repo.all(
        from s in AgentSession,
          where: s.stage_attempt_id in ^attempt_ids,
          order_by: [asc: s.inserted_at, asc: s.id]
      )

    session_ids = Enum.map(sessions, & &1.id)
    usage = Repo.all(from u in UsageRecord, where: u.agent_session_id in ^session_ids)

    samples =
      Repo.all(
        from s in ResourceSample,
          where: s.agent_session_id in ^session_ids,
          order_by: s.sampled_at
      )

    environments = Repo.all(from env in Environment, where: env.run_id in ^run_ids)
    env_ids = Enum.map(environments, & &1.id)
    processes = Repo.all(from p in ProcessRecord, where: p.environment_id in ^env_ids)

    events =
      Repo.all(
        from event in RunEvent,
          where: event.run_id == ^("board:" <> e.board_id),
          order_by: event.sequence
      )
      |> Enum.filter(&(&1.payload["board_execution_id"] == e.id))

    until = e.finished_at || Clock.wall_now()

    sleep_ms =
      Repo.all(
        from p in Cuckoding.Power.PowerEvent,
          where:
            p.kind == "sleep_gap" and p.occurred_at >= ^e.inserted_at and p.occurred_at <= ^until
      )
      |> Enum.reduce(0, fn p, sum ->
        sum + min(p.gap_ms, max(DateTime.diff(p.occurred_at, e.inserted_at, :millisecond), 0))
      end)

    next =
      case BoardControl.next_item(e) do
        {:ok, item} -> item
        _ -> nil
      end

    %{
      execution: e,
      items: items,
      totals: Enum.frequencies_by(items, &if(&1.superseded, do: "superseded", else: &1.state)),
      plans: BoardControl.Plans.revisions(e.id),
      questions: BoardControl.Plans.questions(e.id),
      recovery_attempts: Enum.sum(Enum.map(items, & &1.retry_count)),
      criteria: criteria(e, items),
      included: length(items),
      next: next,
      runs: runs,
      attempts: attempts,
      sessions: sessions,
      environments: environments,
      wall_ms: max(DateTime.diff(until, e.inserted_at, :millisecond), 0),
      active_ms: if(attempts == [], do: nil, else: Enum.sum(Enum.map(attempts, & &1.active_ms))),
      pause_ms: pause_time(events, until),
      sleep_ms: sleep_ms,
      review_returns:
        review_returns(attempt_ids) +
          Enum.count(BoardControl.Plans.revisions(e.id), &(&1.state == "rejected")),
      tokens:
        Map.new(
          ~w(input_tokens output_tokens reasoning_tokens cache_read_tokens cache_write_tokens)a,
          &{&1, measure(usage, &1, session_ids)}
        ),
      costs:
        usage
        |> Enum.filter(&is_integer(&1.cost_micros))
        |> Enum.group_by(&{&1.currency, &1.cost_source})
        |> Enum.map(fn {{currency, source}, rows} ->
          %{currency: currency, source: source, measure: measure(rows, :cost_micros, session_ids)}
        end),
      resources: resources(samples, processes, session_ids),
      last_event: List.last(events)
    }
  end

  defp review_returns(attempt_ids) do
    Repo.all(
      from f in Cuckoding.Workflows.Finding,
        where: f.stage_attempt_id in ^attempt_ids and f.severity in ~w(error blocker),
        distinct: true,
        select: f.stage_attempt_id
    )
    |> length()
  end

  defp criteria(e, items) do
    criteria =
      if BoardControl.Plans.autonomous?(e), do: BoardControl.Plans.goal(e)["criteria"], else: []

    final = if BoardControl.Plans.prepared_goal?(e), do: BoardControl.GoalReview.latest(e.id)

    for criterion <- criteria do
      members =
        Enum.filter(
          items,
          &(not &1.superseded and criterion["id"] in (&1.criteria_json["ids"] || []))
        )

      passed =
        if BoardControl.Plans.prepared_goal?(e),
          do: final_passed?(final, e),
          else: members != [] and Enum.all?(members, &(&1.state == "done"))

      Map.put(criterion, "passed", passed)
    end
  end

  defp final_passed?(%{"passed" => true, "head_sha" => head}, %{head_sha: head, state: "done"}),
    do: true

  defp final_passed?(_, _), do: false

  defp measure(rows, field, session_ids) do
    known = Enum.filter(rows, &is_integer(Map.get(&1, field)))
    covered = known |> Enum.map(& &1.agent_session_id) |> Enum.uniq() |> length()

    %{
      value: if(known == [], do: nil, else: Enum.sum(Enum.map(known, &Map.fetch!(&1, field)))),
      covered: covered,
      total: length(session_ids),
      partial?: covered < length(session_ids)
    }
  end

  defp resources([], _processes, session_ids),
    do: %{available?: false, covered: 0, total: length(session_ids)}

  defp resources(samples, processes, session_ids) do
    grouped = Enum.group_by(samples, & &1.process_id)
    running = for p <- processes, p.state in ~w(running paused), do: p.id

    latest =
      grouped
      |> Map.values()
      |> Enum.map(&List.last/1)
      |> Enum.filter(&(&1.process_id in running))

    %{
      available?: true,
      covered: samples |> Enum.map(& &1.agent_session_id) |> Enum.uniq() |> length(),
      total: length(session_ids),
      sampled_at: List.last(samples).sampled_at,
      cpu_nanos:
        Enum.sum(for {_id, rows} <- grouped, do: List.last(rows).cpu_nanos - hd(rows).cpu_nanos),
      peak_memory_bytes: Enum.max(Enum.map(samples, & &1.memory_bytes)),
      current_memory_bytes:
        if(latest == [], do: nil, else: Enum.sum(Enum.map(latest, & &1.memory_bytes))),
      processes: length(running),
      ports: samples |> Enum.flat_map(& &1.open_ports_json) |> Enum.uniq() |> Enum.sort()
    }
  end

  defp pause_time(events, until) do
    events
    |> Enum.zip(Enum.drop(events, 1) ++ [%{occurred_at: until}])
    |> Enum.reduce(0, fn {event, next}, sum -> sum + pause_interval(event, next) end)
  end

  defp pause_interval(%{payload: %{"state" => "paused"}} = event, next),
    do: max(DateTime.diff(next.occurred_at, event.occurred_at, :millisecond), 0)

  defp pause_interval(_, _), do: 0
end
