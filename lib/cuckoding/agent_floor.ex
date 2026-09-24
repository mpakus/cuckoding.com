defmodule Cuckoding.AgentFloor do
  @moduledoc "Read-only durable projections for the Agent Floor and inspectors."

  import Ecto.Query

  alias Cuckoding.ActivityStream
  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.ProcessRecord
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Projects.Project
  alias Cuckoding.Repo
  alias Cuckoding.Telemetry.OptimizationRecord
  alias Cuckoding.Telemetry.ResourceSample
  alias Cuckoding.Telemetry.UsageRecord
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Finding
  alias Cuckoding.Workflows.Task

  @maximum_cards 100
  @maximum_operations 50
  @maximum_detail_rows 200
  @activity_minutes 12

  def list_sessions(limit \\ @maximum_cards)
      when is_integer(limit) and limit in 1..@maximum_cards do
    rows =
      Repo.all(
        from(session in AgentSession,
          join: attempt in StageAttempt,
          on: attempt.id == session.stage_attempt_id,
          join: run in Run,
          on: run.id == attempt.run_id,
          join: task in Task,
          on: task.id == run.task_id,
          join: board in Board,
          on: board.id == task.board_id,
          join: project in Project,
          on: project.id == board.project_id,
          order_by: [desc: session.inserted_at, desc: session.id],
          limit: ^limit,
          select: %{
            session: session,
            attempt: attempt,
            run: run,
            task: task,
            board: board,
            project: project
          }
        )
      )

    session_ids = Enum.map(rows, & &1.session.id)
    run_ids = rows |> Enum.map(& &1.run.id) |> Enum.uniq()
    resources = latest_resources(session_ids)
    usage = latest_usage(session_ids)
    activity = latest_activity(session_ids)
    handoffs = handoffs(run_ids)

    Enum.map(rows, fn row ->
      Map.merge(row, %{
        resource: resources[row.session.id],
        usage: usage[row.session.id],
        activity: activity[row.session.id],
        handoff_from: handoffs[{row.run.id, row.attempt.id}],
        attention?: attention?(row)
      })
    end)
  end

  def group_sessions(cards, group_by) when group_by in ~w(role runtime project) do
    cards
    |> Enum.group_by(&group_key(&1, group_by))
    |> Enum.sort_by(&elem(&1, 0))
  end

  def group_sessions(cards, _group_by), do: group_sessions(cards, "role")

  @doc "Distinct currently selected agent sessions with a measured process sample per UTC minute."
  def sampled_activity(session_ids, now \\ Cuckoding.Clock.wall_now())
      when is_list(session_ids) and is_struct(now, DateTime) do
    minute = DateTime.from_unix!(div(DateTime.to_unix(now), 60) * 60)
    first = DateTime.add(minute, -(@activity_minutes - 1) * 60, :second)

    counts =
      if session_ids == [] do
        %{}
      else
        Repo.all(
          from(sample in ResourceSample,
            where:
              sample.agent_session_id in ^session_ids and sample.sampled_at >= ^first and
                sample.sampled_at <= ^now,
            group_by: fragment("strftime('%Y-%m-%dT%H:%M:00.000000Z', ?)", sample.sampled_at),
            select: {
              fragment("strftime('%Y-%m-%dT%H:%M:00.000000Z', ?)", sample.sampled_at),
              count(sample.agent_session_id, :distinct)
            }
          )
        )
        |> Map.new()
      end

    for offset <- (@activity_minutes - 1)..0//-1 do
      bucket = DateTime.add(minute, -offset * 60, :second)
      key = Calendar.strftime(bucket, "%Y-%m-%dT%H:%M:00.000000Z")
      %{minute: Calendar.strftime(bucket, "%H:%M"), count: counts[key]}
    end
  end

  def list_operations(limit \\ 12)
      when is_integer(limit) and limit in 1..@maximum_operations do
    rows =
      Repo.all(
        from(run in Run,
          join: task in Task,
          on: task.id == run.task_id,
          join: board in Board,
          on: board.id == task.board_id,
          join: project in Project,
          on: project.id == board.project_id,
          order_by: [desc: run.updated_at, desc: run.id],
          limit: ^limit,
          select: %{run: run, task: task, board: board, project: project}
        )
      )

    operation_details(rows)
  end

  def progress_for_tasks(tasks) do
    ids = tasks |> Enum.map(& &1.active_run_id) |> Enum.reject(&is_nil/1)

    Repo.all(from run in Run, where: run.id in ^ids, select: %{run: run})
    |> operation_details()
    |> Map.new(&{&1.run.task_id, &1})
  end

  def role_label(run, role_key) do
    role = Enum.find(run.workflow_snapshot_json["roles"] || [], &(&1["role_key"] == role_key))

    (role && get_in(role, ["settings", "role_name"])) ||
      role_key |> String.replace("_", " ") |> String.capitalize()
  end

  defp operation_details(rows) do
    run_ids = Enum.map(rows, & &1.run.id)
    attempts = latest_attempts(run_ids)
    sessions = latest_sessions(attempts)
    resources = latest_resources(Enum.map(sessions, fn {_id, session} -> session.id end))

    Enum.map(rows, fn row ->
      attempt = attempts[row.run.id]
      session = attempt && sessions[attempt.id]

      Map.merge(row, %{
        attempt: attempt,
        session: session,
        resource: session && resources[session.id],
        attention?: row.run.state in ~w(waiting blocked failed)
      })
    end)
  end

  def get_run(run_id) when is_binary(run_id) do
    case run_context(run_id) do
      nil -> nil
      context -> Map.merge(context, run_related(context.run))
    end
  end

  def get_session(session_id) when is_binary(session_id) do
    case session_context(session_id) do
      nil -> nil
      context -> Map.merge(context, session_related(context))
    end
  end

  defp run_context(run_id) do
    Repo.one(
      from(run in Run,
        join: task in Task,
        on: task.id == run.task_id,
        join: board in Board,
        on: board.id == task.board_id,
        join: project in Project,
        on: project.id == board.project_id,
        where: run.id == ^run_id,
        select: %{run: run, task: task, board: board, project: project}
      )
    )
  end

  defp latest_attempts([]), do: %{}

  defp latest_attempts(run_ids) do
    Repo.all(
      from(attempt in StageAttempt,
        where: attempt.run_id in ^run_ids,
        order_by: [desc: attempt.inserted_at, desc: attempt.id]
      )
    )
    |> Enum.reduce(%{}, &Map.put_new(&2, &1.run_id, &1))
  end

  defp latest_sessions(attempts) when map_size(attempts) == 0, do: %{}

  defp latest_sessions(attempts) do
    attempt_ids = Enum.map(attempts, fn {_run_id, attempt} -> attempt.id end)

    Repo.all(
      from(session in AgentSession,
        where: session.stage_attempt_id in ^attempt_ids,
        order_by: [desc: session.inserted_at, desc: session.id]
      )
    )
    |> Enum.reduce(%{}, &Map.put_new(&2, &1.stage_attempt_id, &1))
  end

  defp session_context(session_id) do
    Repo.one(
      from(session in AgentSession,
        join: attempt in StageAttempt,
        on: attempt.id == session.stage_attempt_id,
        join: run in Run,
        on: run.id == attempt.run_id,
        join: task in Task,
        on: task.id == run.task_id,
        join: board in Board,
        on: board.id == task.board_id,
        join: project in Project,
        on: project.id == board.project_id,
        where: session.id == ^session_id,
        select: %{
          session: session,
          attempt: attempt,
          run: run,
          task: task,
          board: board,
          project: project
        }
      )
    )
  end

  defp run_related(run) do
    attempts =
      Repo.all(
        from(attempt in StageAttempt,
          where: attempt.run_id == ^run.id,
          order_by: [asc: attempt.inserted_at, asc: attempt.id]
        )
      )

    attempt_ids = Enum.map(attempts, & &1.id)

    sessions =
      Repo.all(
        from(session in AgentSession,
          where: session.stage_attempt_id in ^attempt_ids,
          order_by: [asc: session.inserted_at, asc: session.id]
        )
      )

    session_ids = Enum.map(sessions, & &1.id)
    environment = latest_environment(run.id)

    %{
      attempts: attempts,
      sessions: sessions,
      environment: environment,
      activity: ActivityStream.list(run.id, 0, limit: @maximum_detail_rows),
      findings: findings(run.id),
      usage: usage_records(session_ids),
      resources: resource_samples(session_ids),
      optimizations: optimizations(run.id),
      artifacts: artifacts(environment),
      processes: processes(run.id)
    }
  end

  defp session_related(context) do
    resources = resource_samples([context.session.id])
    usage = usage_records([context.session.id])

    activity =
      context.run.id
      |> ActivityStream.list(0, limit: @maximum_detail_rows)
      |> Enum.filter(&(&1.correlation["agent_session_id"] == context.session.id))

    %{
      resources: resources,
      usage: usage,
      activity: activity,
      processes:
        Repo.all(
          from(process in ProcessRecord,
            where: process.agent_session_id == ^context.session.id,
            order_by: [desc: process.inserted_at, desc: process.id]
          )
        )
    }
  end

  defp latest_resources([]), do: %{}

  defp latest_resources(session_ids) do
    latest =
      from(sample in ResourceSample,
        where: sample.agent_session_id in ^session_ids,
        group_by: sample.agent_session_id,
        select: %{
          agent_session_id: sample.agent_session_id,
          sampled_at: max(sample.sampled_at)
        }
      )

    Repo.all(
      from(sample in ResourceSample,
        join: latest in subquery(latest),
        on:
          latest.agent_session_id == sample.agent_session_id and
            latest.sampled_at == sample.sampled_at,
        order_by: [desc: sample.id]
      )
    )
    |> Enum.reduce(%{}, &Map.put_new(&2, &1.agent_session_id, &1))
  end

  defp latest_usage([]), do: %{}

  defp latest_usage(session_ids) do
    latest =
      from(record in UsageRecord,
        where: record.agent_session_id in ^session_ids,
        group_by: record.agent_session_id,
        select: %{agent_session_id: record.agent_session_id, occurred_at: max(record.occurred_at)}
      )

    Repo.all(
      from(record in UsageRecord,
        join: latest in subquery(latest),
        on:
          latest.agent_session_id == record.agent_session_id and
            latest.occurred_at == record.occurred_at,
        order_by: [desc: record.id]
      )
    )
    |> Enum.reduce(%{}, &Map.put_new(&2, &1.agent_session_id, &1))
  end

  defp latest_activity(session_ids) do
    session_ids = MapSet.new(session_ids)

    ActivityStream.recent(@maximum_detail_rows)
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn event, latest ->
      session_id = event.correlation["agent_session_id"]

      if MapSet.member?(session_ids, session_id),
        do: Map.put_new(latest, session_id, event),
        else: latest
    end)
  end

  defp handoffs([]), do: %{}

  defp handoffs(run_ids) do
    Repo.all(
      from(attempt in StageAttempt,
        where: attempt.run_id in ^run_ids,
        order_by: [asc: attempt.run_id, asc: attempt.inserted_at, asc: attempt.id]
      )
    )
    |> Enum.group_by(& &1.run_id)
    |> Enum.flat_map(fn {run_id, attempts} ->
      previous_roles = [nil | Enum.map(attempts, & &1.role_key)]

      attempts
      |> Enum.zip(previous_roles)
      |> Enum.map(fn {attempt, previous} ->
        {{run_id, attempt.id}, previous}
      end)
    end)
    |> Map.new()
  end

  defp latest_environment(run_id) do
    Repo.one(
      from(environment in Environment,
        where: environment.run_id == ^run_id,
        order_by: [desc: environment.inserted_at, desc: environment.id],
        limit: 1
      )
    )
  end

  defp findings(run_id),
    do:
      Repo.all(
        from(finding in Finding,
          where: finding.run_id == ^run_id,
          order_by: [desc: finding.inserted_at, desc: finding.id]
        )
      )

  defp usage_records([]), do: []

  defp usage_records(session_ids),
    do:
      Repo.all(
        from(record in UsageRecord,
          where: record.agent_session_id in ^session_ids,
          order_by: [desc: record.occurred_at, desc: record.id],
          limit: @maximum_detail_rows
        )
      )

  defp resource_samples([]), do: []

  defp resource_samples(session_ids),
    do:
      Repo.all(
        from(sample in ResourceSample,
          where: sample.agent_session_id in ^session_ids,
          order_by: [desc: sample.sampled_at, desc: sample.id],
          limit: @maximum_detail_rows
        )
      )
      |> Enum.reverse()

  defp optimizations(run_id),
    do:
      Repo.all(
        from(record in OptimizationRecord,
          where: record.run_id == ^run_id,
          order_by: [desc: record.recorded_at, desc: record.id],
          limit: @maximum_detail_rows
        )
      )

  defp processes(run_id) do
    Repo.all(
      from(process in ProcessRecord,
        join: environment in Environment,
        on: environment.id == process.environment_id,
        where: environment.run_id == ^run_id,
        order_by: [desc: process.inserted_at, desc: process.id]
      )
    )
  end

  defp artifacts(nil), do: []

  defp artifacts(environment) do
    root = Path.expand(environment.run_dir)
    directory = Path.expand(Path.join(root, "artifacts"))

    if String.starts_with?(directory, root <> "/") do
      directory
      |> File.ls()
      |> case do
        {:ok, names} ->
          names |> Enum.sort() |> Enum.take(100) |> Enum.map(&artifact(directory, &1))

        {:error, _reason} ->
          []
      end
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp artifact(directory, name) do
    path = Path.join(directory, name)

    case File.lstat(path) do
      {:ok, %{type: :regular, size: size}} -> %{name: name, size: size}
      _other -> nil
    end
  end

  defp group_key(card, "role"), do: card.attempt.role_key
  defp group_key(card, "runtime"), do: card.session.adapter_key
  defp group_key(card, "project"), do: card.project.name

  defp attention?(row) do
    row.run.state in ~w(blocked failed) or
      (row.run.state in ~w(running waiting) and row.attempt.state in ~w(waiting failed))
  end
end
