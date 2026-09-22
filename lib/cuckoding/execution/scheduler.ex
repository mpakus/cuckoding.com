defmodule Cuckoding.Execution.Scheduler.ResourceProbe do
  @moduledoc "Replaceable read-only host-capacity probe used by the scheduler."

  alias Cuckoding.Projects.Project

  @callback memory_available_bytes() :: {:ok, non_neg_integer()} | {:error, term()}
  @callback available_ports(Project.t()) :: {:ok, non_neg_integer()} | {:error, term()}
end

defmodule Cuckoding.Execution.Scheduler.HostResourceProbe do
  @moduledoc false
  @behaviour Cuckoding.Execution.Scheduler.ResourceProbe

  alias Cuckoding.Execution.Leases
  alias Cuckoding.Execution.PortAllocator

  @memory_kinds ["Pages free", "Pages inactive", "Pages speculative", "Pages purgeable"]

  @impl true
  def memory_available_bytes do
    with {output, 0} <- System.cmd("/usr/bin/vm_stat", [], stderr_to_stdout: true),
         [header | lines] <- String.split(output, "\n", trim: true),
         [page_size] <- Regex.run(~r/page size of (\d+) bytes/, header, capture: :all_but_first),
         {page_size, ""} <- Integer.parse(page_size) do
      {:ok, memory_pages(lines) * page_size}
    else
      _other -> {:error, :memory_probe_unavailable}
    end
  end

  @impl true
  def available_ports(project) do
    count =
      Enum.count(project.port_range_start..project.port_range_end, fn port ->
        resource_id = "tcp:127.0.0.1:#{port}"
        is_nil(Leases.active_for("port", resource_id)) and PortAllocator.available?(port)
      end)

    {:ok, count}
  end

  defp page_count(value) do
    case value |> String.trim() |> String.trim_trailing(".") |> Integer.parse() do
      {count, ""} -> count
      _other -> 0
    end
  end

  defp memory_pages(lines) do
    Enum.reduce(lines, 0, fn line, total ->
      case String.split(line, ":", parts: 2) do
        [kind, value] when kind in @memory_kinds -> total + page_count(value)
        _other -> total
      end
    end)
  end
end

defmodule Cuckoding.Execution.Scheduler.Dispatcher do
  @moduledoc "Starts one scheduler-admitted task through a host-owned runtime boundary."

  @callback start(map()) :: {:ok, term()} | {:error, term()}
end

defmodule Cuckoding.Execution.Scheduler.Notifier do
  @moduledoc "Delivers an idempotently keyed unattended-mode notification."

  @callback notify(map()) :: :ok | {:error, term()}
end

defmodule Cuckoding.Execution.Scheduler do
  @moduledoc "Plans fair, resource-aware task admission across independent boards."

  import Ecto.Query

  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.Scheduler.HostResourceProbe
  alias Cuckoding.Projects.Project
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Approval
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Task
  alias Cuckoding.Workflows.TaskDependency

  @admitted_run_states ~w(queued running waiting)
  @active_session_states ~w(created starting running waiting paused interrupted)

  def plan(options \\ []) do
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())
    probe = Keyword.get(options, :resource_probe, HostResourceProbe)
    global_limit = Keyword.get(options, :global_limit, configured_global_limit())

    with true <- is_integer(global_limit) and global_limit > 0,
         {:ok, memory_bytes} <- probe_memory(probe),
         candidates <- ready_candidates(Keyword.get(options, :project_ids)),
         policies <- latest_policies(candidates),
         {:ok, ports} <- probe_ports(probe, candidates),
         active_runs <- active_runs(),
         ordered <- fair_order(candidates, policies, options) do
      {selected, deferred} =
        admit(ordered, active_runs, ports, memory_bytes, global_limit)

      {:ok,
       %{
         candidates: selected,
         deferred: dependency_deferrals(candidates) ++ deferred,
         notifications: unattended_notifications(now),
         global_limit: global_limit,
         global_used: max(active_session_count(), length(active_runs))
       }}
    else
      false -> {:error, :invalid_global_session_limit}
      {:error, reason} -> {:error, {:resource_probe_failed, reason}}
    end
  end

  def dispatch(options \\ []) do
    with {:ok, dispatcher} <- Keyword.fetch(options, :dispatcher),
         {:ok, plan} <- plan(options) do
      dispatches = Enum.map(plan.candidates, &{public_candidate(&1), start(dispatcher, &1)})

      notifications =
        Enum.map(plan.notifications, fn notification ->
          {notification, notify(Keyword.get(options, :notifier), notification)}
        end)

      {:ok, Map.merge(plan, %{dispatches: dispatches, notification_results: notifications})}
    else
      :error -> {:error, :dispatcher_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ready_candidates(project_ids) do
    query =
      from(task in Task,
        join: board in Board,
        on: board.id == task.board_id,
        join: project in Project,
        on: project.id == board.project_id,
        where:
          task.kind == "delivery" and task.state == "ready" and
            is_nil(task.active_run_id) and board.status == "active",
        select: %{task: task, board: board, project: project}
      )

    query =
      if is_list(project_ids),
        do: where(query, [task, board, project], project.id in ^project_ids),
        else: query

    candidates = Repo.all(query)

    blocked = blocking_task_ids(Enum.map(candidates, & &1.task.id))
    Enum.map(candidates, &Map.put(&1, :dependency_blocked?, MapSet.member?(blocked, &1.task.id)))
  end

  defp blocking_task_ids([]), do: MapSet.new()

  defp blocking_task_ids(task_ids) do
    Repo.all(
      from(dependency in TaskDependency,
        join: prerequisite in Task,
        on: prerequisite.id == dependency.depends_on_task_id,
        where: dependency.task_id in ^task_ids and prerequisite.state != "done",
        select: dependency.task_id
      )
    )
    |> MapSet.new()
  end

  defp dependency_deferrals(candidates) do
    for candidate <- candidates,
        candidate.dependency_blocked?,
        do: deferred(candidate, :dependency)
  end

  defp active_runs do
    Repo.all(
      from(run in Run,
        join: task in Task,
        on: task.id == run.task_id,
        join: board in Board,
        on: board.id == task.board_id,
        where:
          run.state in ^@admitted_run_states and
            (run.state != "waiting" or run.wait_reason != "approval"),
        select: %{run: run, board_id: board.id, project_id: board.project_id}
      )
    )
  end

  defp active_session_count do
    Repo.aggregate(
      from(session in AgentSession, where: session.state in ^@active_session_states),
      :count,
      :id
    )
  end

  defp latest_policies(candidates) do
    project_ids = candidates |> Enum.map(& &1.project.id) |> Enum.uniq()

    Repo.all(
      from(policy in ProjectConfigVersion,
        where: policy.project_id in ^project_ids and not is_nil(policy.trusted_at),
        order_by: [desc: policy.revision]
      )
    )
    |> Enum.reduce(%{}, &Map.put_new(&2, &1.project_id, &1))
  end

  defp probe_ports(probe, candidates) do
    candidates
    |> Enum.map(& &1.project)
    |> Enum.uniq_by(& &1.id)
    |> Enum.reduce_while({:ok, %{}}, fn project, {:ok, ports} ->
      case available_ports(probe, project) do
        {:ok, count} when is_integer(count) and count >= 0 ->
          {:cont, {:ok, Map.put(ports, project.id, count)}}

        {:error, reason} ->
          {:halt, {:error, reason}}

        _invalid ->
          {:halt, {:error, :invalid_port_probe_result}}
      end
    end)
  end

  defp fair_order(candidates, policies, options) do
    last_scheduled = last_scheduled_by_board()

    candidates
    |> Enum.reject(& &1.dependency_blocked?)
    |> Enum.map(&decorate(&1, policies, options))
    |> Enum.group_by(& &1.board.id)
    |> then(fn queues ->
      board_ids =
        queues
        |> Map.keys()
        |> Enum.sort_by(fn board_id -> board_order_key(board_id, queues, last_scheduled) end)

      round_robin(board_ids, queues, [])
    end)
  end

  defp decorate(candidate, policies, options) do
    policy = policies[candidate.project.id]
    default_memory_mb = Keyword.get(options, :default_memory_mb, 1_024)

    default_project_limit =
      Keyword.get(options, :default_project_limit, configured_global_limit())

    project_limits = Keyword.get(options, :project_limits, %{})

    policy_limit = project_limit(policy, default_project_limit)

    candidate
    |> Map.put(:policy, policy)
    |> Map.put(:memory_bytes, memory_mb(policy, default_memory_mb) * 1_048_576)
    |> Map.put(
      :project_limit,
      min(Map.get(project_limits, candidate.project.id, policy_limit), policy_limit)
    )
  end

  defp last_scheduled_by_board do
    Repo.all(
      from(run in Run,
        join: task in Task,
        on: task.id == run.task_id,
        group_by: task.board_id,
        select: {task.board_id, max(run.inserted_at)}
      )
    )
    |> Map.new()
  end

  defp board_order_key(board_id, queues, last_scheduled) do
    [first | _rest] = Enum.sort_by(queues[board_id], &task_order_key/1)
    last = Map.get(last_scheduled, board_id)
    last_micros = if last, do: DateTime.to_unix(last, :microsecond), else: -1

    {last_micros, -first.task.priority, DateTime.to_unix(first.task.inserted_at, :microsecond),
     board_id}
  end

  defp round_robin(board_ids, queues, result) do
    {picked, remaining} =
      Enum.map_reduce(board_ids, queues, fn board_id, current ->
        case Map.get(current, board_id, []) |> Enum.sort_by(&task_order_key/1) do
          [candidate | rest] -> {candidate, Map.put(current, board_id, rest)}
          [] -> {nil, current}
        end
      end)

    picked = Enum.reject(picked, &is_nil/1)

    if picked == [],
      do: Enum.reverse(result),
      else: round_robin(board_ids, remaining, Enum.reverse(picked) ++ result)
  end

  defp task_order_key(candidate) do
    {-candidate.task.priority, DateTime.to_unix(candidate.task.inserted_at, :microsecond),
     candidate.task.id}
  end

  defp admit(candidates, active_runs, ports, memory, global_limit) do
    initial = %{
      selected: [],
      deferred: [],
      board_counts: Enum.frequencies_by(active_runs, & &1.board_id),
      project_counts: Enum.frequencies_by(active_runs, & &1.project_id),
      global_used: max(active_session_count(), length(active_runs)),
      memory: memory,
      ports: ports
    }

    state = Enum.reduce(candidates, initial, &admit_candidate(&1, &2, global_limit))
    {Enum.reverse(state.selected), Enum.reverse(state.deferred)}
  end

  defp admit_candidate(candidate, state, global_limit) do
    board_used = Map.get(state.board_counts, candidate.board.id, 0)
    project_used = Map.get(state.project_counts, candidate.project.id, 0)
    ports = Map.get(state.ports, candidate.project.id, 0)

    reason =
      cond do
        state.global_used >= global_limit -> :global_session_limit
        board_used >= candidate.board.concurrency_limit -> :board_concurrency_limit
        project_used >= candidate.project_limit -> :project_concurrency_limit
        ports < 1 -> :no_port_headroom
        state.memory < candidate.memory_bytes -> :memory_headroom
        true -> nil
      end

    if reason do
      %{state | deferred: [deferred(candidate, reason) | state.deferred]}
    else
      %{
        state
        | selected: [candidate | state.selected],
          global_used: state.global_used + 1,
          memory: state.memory - candidate.memory_bytes,
          ports: Map.update!(state.ports, candidate.project.id, &(&1 - 1)),
          board_counts: Map.update(state.board_counts, candidate.board.id, 1, &(&1 + 1)),
          project_counts: Map.update(state.project_counts, candidate.project.id, 1, &(&1 + 1))
      }
    end
  end

  defp unattended_notifications(now) do
    Repo.all(
      from(approval in Approval,
        join: run in Run,
        on: run.id == approval.run_id,
        join: task in Task,
        on: task.id == run.task_id,
        join: board in Board,
        on: board.id == task.board_id,
        where:
          approval.decision == "pending" and run.state == "waiting" and
            board.status == "active" and board.unattended_until > ^now,
        order_by: [asc: approval.inserted_at, asc: approval.id],
        select: %{approval: approval, task: task, board: board}
      )
    )
    |> Enum.map(fn item ->
      %{
        idempotency_key: "unattended:approval:#{item.approval.id}",
        kind: :approval_waiting,
        approval_id: item.approval.id,
        board_id: item.board.id,
        task_id: item.task.id,
        message: "#{item.task.title} is waiting for approval"
      }
    end)
  end

  defp deferred(candidate, reason), do: public_candidate(candidate) |> Map.put(:reason, reason)

  defp public_candidate(candidate) do
    %{
      task_id: candidate.task.id,
      board_id: candidate.board.id,
      project_id: candidate.project.id,
      priority: candidate.task.priority
    }
  end

  defp memory_mb(nil, default), do: default

  defp memory_mb(policy, default) do
    case get_in(policy.config_json, ["resources", "per_run", "memory_mb_ceiling"]) do
      value when is_integer(value) and value > 0 -> value
      _other -> default
    end
  end

  defp project_limit(nil, default), do: default

  defp project_limit(policy, default) do
    case get_in(policy.config_json, ["resources", "per_project", "max_active_runs"]) do
      value when is_integer(value) and value > 0 -> value
      _other -> default
    end
  end

  defp configured_global_limit do
    :cuckoding
    |> Application.get_env(:scheduler, [])
    |> Keyword.get(:max_active_agent_sessions, 4)
  end

  defp probe_memory(%{memory_available_bytes: callback}), do: callback.()
  defp probe_memory(module), do: module.memory_available_bytes()
  defp available_ports(%{available_ports: callback}, project), do: callback.(project)
  defp available_ports(module, project), do: module.available_ports(project)
  defp start(%{start: callback}, candidate), do: callback.(candidate)
  defp start(module, candidate), do: module.start(candidate)
  defp notify(nil, _notification), do: :not_configured
  defp notify(%{notify: callback}, notification), do: callback.(notification)
  defp notify(module, notification), do: module.notify(notification)
end

defmodule Cuckoding.Execution.BoardControl.RunController do
  @moduledoc "Safely pauses or hibernates one run with its live ownership handles."

  alias Cuckoding.Execution.Run

  @callback pause(Run.t()) :: {:ok, term()} | {:error, term()}
  @callback hibernate(Run.t()) :: {:ok, term()} | {:error, term()}
end

defmodule Cuckoding.Execution.BoardControl do
  @moduledoc "Stops new board admission before delegating safe per-run pause or hibernate work."

  import Ecto.Query

  alias Cuckoding.Execution.Run
  alias Cuckoding.Repo
  alias Cuckoding.Workflows
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Task

  @controllable_states ~w(running waiting paused)

  def control(board_id, action, options \\ [])

  def control(board_id, action, options) when action in [:pause, :hibernate] do
    with %Board{} <- Workflows.get_board(board_id),
         {:ok, board} <- Workflows.set_board_status(board_id, "paused") do
      results =
        Enum.map(
          active_runs(board_id),
          &{&1.id, control_run(options[:run_controller], action, &1)}
        )

      failures = Enum.reject(results, fn {_id, result} -> match?({:ok, _value}, result) end)

      if failures == [],
        do: {:ok, %{board: board, action: action, runs: results}},
        else: {:error, %{board: board, action: action, failures: failures}}
    else
      nil -> {:error, :board_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def control(_board_id, _action, _options), do: {:error, :invalid_board_action}

  def resume(board_id), do: Workflows.set_board_status(board_id, "active")

  defp active_runs(board_id) do
    Repo.all(
      from(run in Run,
        join: task in Task,
        on: task.id == run.task_id,
        where: task.board_id == ^board_id and run.state in ^@controllable_states,
        order_by: run.id
      )
    )
  end

  defp control_run(nil, _action, _run), do: {:error, :run_controller_required}
  defp control_run(%{pause: callback}, :pause, run), do: callback.(run)
  defp control_run(%{hibernate: callback}, :hibernate, run), do: callback.(run)
  defp control_run(module, action, run), do: apply(module, action, [run])
end
