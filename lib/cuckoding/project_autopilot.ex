defmodule Cuckoding.ProjectAutopilot do
  @moduledoc "Durable project admission; a supervised worker only refreshes this projection."

  import Ecto.Query

  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.GitService
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.Scheduler
  alias Cuckoding.GuidedRun
  alias Cuckoding.Projects
  alias Cuckoding.Projects.ProjectAutopilot, as: Projection
  alias Cuckoding.ProjectWorkflow
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Finding
  alias Cuckoding.Workflows.Task
  alias Cuckoding.Workflows.TaskDependency

  @default_runs 2
  @default_blockers 1

  def get(project_id), do: Repo.get(Projection, project_id)

  def settings(project_id) do
    get(project_id) ||
      %Projection{
        project_id: project_id,
        state: "paused",
        max_active_runs: @default_runs,
        critical_blocker_limit: @default_blockers
      }
  end

  def list_running do
    Repo.all(from(control in Projection, where: control.state == "running"))
  end

  def start(project_id, attrs, options \\ []) when is_binary(project_id) and is_map(attrs) do
    case get(project_id) do
      %Projection{state: "running"} = control -> {:ok, control}
      _other -> do_start(project_id, attrs, options)
    end
  end

  defp do_start(project_id, attrs, options) do
    with project when not is_nil(project) <- Projects.get_project(project_id),
         "active" <- project.status,
         :ok <- preflight(project),
         {:ok, control} <- change(project_id, "running", attrs, nil) do
      if Keyword.get(options, :wake, true), do: Cuckoding.ProjectAutopilot.Worker.wake()
      {:ok, control}
    else
      nil -> {:error, :project_not_found}
      "archived" -> {:error, :project_archived}
      error -> error
    end
  end

  def pause(project_id) do
    case get(project_id) do
      %Projection{state: "paused"} = control -> {:ok, control}
      _other -> change(project_id, "paused", %{}, nil)
    end
  end

  def attention(project_id, issue), do: transition_running(project_id, "attention", issue)
  def done(project_id), do: transition_running(project_id, "done", nil)

  def critical_blocker_count(project_id) do
    Repo.one(
      from(task in Task,
        join: board in Board,
        on: board.id == task.board_id,
        join: finding in Finding,
        on: finding.run_id == task.active_run_id,
        where:
          board.project_id == ^project_id and task.kind == "delivery" and
            task.state == "blocked" and finding.severity == "blocker" and
            finding.status == "open",
        select: count(task.id, :distinct)
      )
    ) || 0
  end

  def task_counts(project_id) do
    Repo.all(
      from(task in Task,
        join: board in Board,
        on: board.id == task.board_id,
        where: board.project_id == ^project_id and task.kind == "delivery",
        group_by: task.state,
        select: {task.state, count(task.id)}
      )
    )
    |> Map.new()
  end

  @doc "One bounded admission pass; callable with a fake starter/probe in tests."
  def dispatch_once(options \\ []) do
    controls = list_running()

    eligible =
      Enum.reject(controls, fn control ->
        cond do
          Projects.get_project(control.project_id).status != "active" ->
            attention(control.project_id, :project_archived)
            true

          critical_blocker_count(control.project_id) >= control.critical_blocker_limit ->
            attention(control.project_id, :critical_blockers)
            true

          true ->
            false
        end
      end)

    ids = Enum.map(eligible, & &1.project_id)
    start_queued(ids, options)

    running = Enum.filter(eligible, &(get(&1.project_id).state == "running"))

    if running != [] do
      limits = Map.new(running, &{&1.project_id, &1.max_active_runs})

      scheduler_options =
        options
        |> Keyword.take([:resource_probe, :global_limit])
        |> Keyword.merge(project_ids: Map.keys(limits), project_limits: limits)

      case Scheduler.plan(scheduler_options) do
        {:ok, plan} -> Enum.each(plan.candidates, &start_candidate(&1, options))
        {:error, _reason} -> Enum.each(running, &attention(&1.project_id, :capacity_unknown))
      end
    end

    Enum.each(ids, &settle/1)
    :ok
  end

  def issue_message("critical_blockers"),
    do:
      "Critical review blockers reached this project's limit. Review the blocked tasks before resuming."

  def issue_message("project_archived"),
    do: "This project was archived. Restore it before starting new tasks."

  def issue_message("agent_auth_required"),
    do: "A saved agent needs sign-in. Re-authorize it in Agents, then resume this project."

  def issue_message("capacity_unknown"),
    do: "Machine capacity could not be verified. Check system resources, then resume."

  def issue_message("preparation_failed"),
    do: "A task run could not be prepared. Inspect the Ready task and repository, then resume."

  def issue_message("run_start_failed"),
    do: "A queued run could not start. Inspect its run page, then resume."

  def issue_message("awaiting_completion"),
    do: "Review passed, but a task needs your local-completion or release decision."

  def issue_message("no_ready_tasks"),
    do: "No Ready tasks can start. Mark Draft tasks Ready or resolve blocked tasks, then resume."

  def issue_message("dependencies_blocked"),
    do:
      "Ready tasks are waiting on unfinished prerequisite tasks. Resolve those dependencies, then resume."

  def issue_message(_issue), do: nil

  defp preflight(project) do
    ready = ready_tasks(project.id)
    queued = queued_runs(project.id)

    cond do
      ready == [] and queued == [] and not active_delivery_runs?(project.id) ->
        {:error, :no_ready_tasks}

      Enum.any?(ready, &(ProjectWorkflow.validate_delivery_roles(&1.board_id) != :ok)) ->
        {:error, :roles_not_configured}

      ready == [] ->
        :ok

      true ->
        case GitService.capture_base(project) do
          {:ok, _sha} -> :ok
          error -> error
        end
    end
  end

  defp change(project_id, state, attrs, issue) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    EventStore.transaction(fn ->
      with true <- not is_nil(Projects.get_project(project_id)),
           current <- Repo.get(Projection, project_id) || %Projection{project_id: project_id},
           changeset <-
             Projection.changeset(
               current,
               Map.merge(attrs, %{"state" => state, "last_issue" => issue})
             ),
           {:ok, control} <- save(current, changeset),
           {:ok, _event} <-
             EventStore.append_in_transaction("project:" <> project_id, %{
               event_type: "project.autopilot_#{state}",
               public_summary: "Project automatic work is #{state}",
               payload: %{"project_id" => project_id, "state" => state, "issue" => issue}
             }) do
        control
      else
        false -> Repo.rollback(:project_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp save(%Projection{__meta__: %{state: :built}}, changeset), do: Repo.insert(changeset)
  defp save(_current, changeset), do: Repo.update(changeset)

  defp transition_running(project_id, state, issue) do
    case get(project_id) do
      %Projection{state: "running"} ->
        change(project_id, state, %{}, if(issue, do: Atom.to_string(issue), else: nil))

      _other ->
        {:ok, get(project_id)}
    end
  end

  defp start_queued([], _options), do: :ok

  defp start_queued(ids, options) do
    Enum.each(queued_runs(ids), fn run ->
      if match?(%Projection{state: "running"}, get(run.project_id)) and
           capacity_for_queued?(run.project_id, run.board_id) do
        start_run(run.id, run.project_id, options)
      end
    end)
  end

  defp capacity_for_queued?(project_id, board_id) do
    active =
      Repo.all(
        from(run in Run,
          join: task in Task,
          on: task.id == run.task_id,
          join: board in Board,
          on: board.id == task.board_id,
          where:
            run.state in ["running", "waiting"] and
              (run.state != "waiting" or run.wait_reason != "approval"),
          select: {board.id, board.project_id}
        )
      )

    board = Repo.get!(Board, board_id)
    requested_limit = get(project_id).max_active_runs
    policy = Projects.latest_config_version(project_id)
    policy_limit = get_in(policy.config_json, ["resources", "per_project", "max_active_runs"])

    project_limit =
      if is_integer(policy_limit) and policy_limit > 0,
        do: min(requested_limit, policy_limit),
        else: requested_limit

    global_limit =
      Application.get_env(:cuckoding, :scheduler, [])[:max_active_agent_sessions] || 4

    session_count =
      Repo.aggregate(
        from(session in AgentSession,
          where:
            session.state in [
              "created",
              "starting",
              "running",
              "waiting",
              "paused",
              "interrupted"
            ]
        ),
        :count,
        :id
      )

    max(length(active), session_count) < global_limit and
      Enum.count(active, fn {id, _project} -> id == board_id end) < board.concurrency_limit and
      Enum.count(active, fn {_board, id} -> id == project_id end) < project_limit
  end

  defp start_candidate(candidate, options) do
    if get(candidate.project.id).state == "running" do
      case ProjectWorkflow.prepare_task(candidate.task.id) do
        {:ok, %{run: run}} -> start_run(run.id, candidate.project.id, options)
        {:error, _reason} -> attention(candidate.project.id, :preparation_failed)
      end
    end
  end

  defp start_run(run_id, project_id, options) do
    starter = Keyword.get(options, :starter, &GuidedRun.start/1)

    case starter.(run_id) do
      {:ok, _result} ->
        :ok

      {:error, reason} when reason in [:provider_auth_required, :run_scoped_auth_required] ->
        attention(project_id, :agent_auth_required)
        {:error, reason}

      {:error, reason} ->
        attention(project_id, :run_start_failed)
        {:error, reason}
    end
  end

  defp settle(project_id) do
    if match?(%Projection{state: "running"}, get(project_id)) do
      case settlement(project_id) do
        :done -> done(project_id)
        :running -> :ok
        issue -> attention(project_id, issue)
      end
    end
  end

  defp settlement(project_id) do
    counts = task_counts(project_id)
    total = Enum.sum(Map.values(counts))

    cond do
      total > 0 and Map.get(counts, "done", 0) == total -> :done
      Map.get(counts, "ready", 0) > 0 -> ready_settlement(project_id)
      Map.get(counts, "running", 0) > 0 -> :running
      queued_runs(project_id) != [] -> :running
      Map.get(counts, "waiting", 0) > 0 -> :awaiting_completion
      true -> :no_ready_tasks
    end
  end

  defp ready_settlement(project_id) do
    if dependencies_blocked?(project_id), do: :dependencies_blocked, else: :running
  end

  defp dependencies_blocked?(project_id) do
    tasks = ready_tasks(project_id)

    tasks != [] and
      Enum.all?(tasks, fn task ->
        Repo.exists?(
          from(dependency in TaskDependency,
            join: prerequisite in Task,
            on: prerequisite.id == dependency.depends_on_task_id,
            where: dependency.task_id == ^task.id and prerequisite.state != "done"
          )
        )
      end) and
      not Repo.exists?(
        from(run in Run,
          join: task in Task,
          on: task.id == run.task_id,
          join: board in Board,
          on: board.id == task.board_id,
          where:
            board.project_id == ^project_id and run.state in ["running", "waiting"] and
              (run.state != "waiting" or run.wait_reason != "approval")
        )
      )
  end

  defp ready_tasks(project_id) do
    Repo.all(
      from(task in Task,
        join: board in Board,
        on: board.id == task.board_id,
        where:
          board.project_id == ^project_id and board.status == "active" and
            task.kind == "delivery" and task.state == "ready",
        select: task
      )
    )
  end

  defp queued_runs(project_id) when is_binary(project_id), do: queued_runs([project_id])

  defp queued_runs(project_ids) do
    Repo.all(
      from(run in Run,
        join: task in Task,
        on: task.id == run.task_id,
        join: board in Board,
        on: board.id == task.board_id,
        where:
          board.project_id in ^project_ids and board.status == "active" and
            task.kind == "delivery" and
            run.state == "queued",
        select: %{id: run.id, project_id: board.project_id, board_id: board.id}
      )
    )
  end

  defp active_delivery_runs?(project_id) do
    Repo.exists?(
      from(run in Run,
        join: task in Task,
        on: task.id == run.task_id,
        join: board in Board,
        on: board.id == task.board_id,
        where:
          board.project_id == ^project_id and task.kind == "delivery" and
            run.state in ["running", "waiting"]
      )
    )
  end
end

defmodule Cuckoding.ProjectAutopilot.Worker do
  @moduledoc false
  use GenServer
  require Logger

  @tick_ms 5_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)
  def wake, do: if(Process.whereis(__MODULE__), do: GenServer.cast(__MODULE__, :tick))

  @impl true
  def init(options) do
    if Keyword.get(options, :enabled, true), do: Process.send_after(self(), :tick, 0)
    {:ok, nil}
  end

  @impl true
  def handle_cast(:tick, state) do
    dispatch()
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    dispatch()
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, state}
  end

  defp dispatch do
    Cuckoding.ProjectAutopilot.dispatch_once()
  rescue
    _error -> Logger.error("project automatic dispatch failed; next tick will retry")
  end
end
