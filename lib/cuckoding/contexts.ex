defmodule Cuckoding.Projects do
  @moduledoc "Owns project registration, configuration revisions, and repository identity."

  alias Cuckoding.Identifier
  alias Cuckoding.Projects.Project
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Repo

  def register(attrs), do: insert(Project, attrs)
  def add_config_version(attrs), do: insert(ProjectConfigVersion, attrs)

  defp insert(schema, attrs) do
    schema.create_changeset(struct(schema), Map.put_new(attrs, :id, Identifier.generate()))
    |> Repo.insert()
  end
end

defmodule Cuckoding.Workflows do
  @moduledoc "Owns workflow definitions, boards, tasks, approvals, and domain transitions."

  alias Cuckoding.Identifier
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Approval
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Finding
  alias Cuckoding.Workflows.RoleAssignment
  alias Cuckoding.Workflows.Task
  alias Cuckoding.Workflows.TaskDependency
  alias Cuckoding.Workflows.WorkflowVersion

  def publish_workflow(attrs), do: insert(WorkflowVersion, attrs)

  def create_board(attrs) do
    workflow = Repo.get(WorkflowVersion, attrs[:workflow_version_id])

    if workflow && (is_nil(workflow.project_id) || workflow.project_id == attrs[:project_id]),
      do: insert(Board, attrs),
      else: {:error, :workflow_project_mismatch}
  end

  def assign_role(attrs), do: insert(RoleAssignment, attrs)
  def create_task(attrs), do: insert(Task, attrs)
  def request_approval(attrs), do: insert(Approval, attrs)
  def record_finding(attrs), do: insert(Finding, attrs)

  def add_dependency(task_id, depends_on_task_id, kind \\ "blocks") do
    Repo.transaction(fn ->
      task = Repo.get!(Task, task_id)
      dependency = Repo.get!(Task, depends_on_task_id)

      cond do
        task.board_id != dependency.board_id -> Repo.rollback(:different_boards)
        dependency_reaches?(depends_on_task_id, task_id) -> Repo.rollback(:dependency_cycle)
        true -> insert_dependency(task_id, depends_on_task_id, kind)
      end
    end)
  end

  defp dependency_reaches?(from_id, target_id) do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        WITH RECURSIVE reachable(id) AS (
          SELECT depends_on_task_id FROM task_dependencies WHERE task_id = ?
          UNION
          SELECT dependency.depends_on_task_id
          FROM task_dependencies AS dependency
          JOIN reachable ON dependency.task_id = reachable.id
        )
        SELECT 1 FROM reachable WHERE id = ? LIMIT 1
        """,
        [from_id, target_id]
      )

    rows != [] or from_id == target_id
  end

  defp insert_dependency(task_id, depends_on_task_id, kind) do
    attrs = %{
      id: Identifier.generate(),
      task_id: task_id,
      depends_on_task_id: depends_on_task_id,
      kind: kind
    }

    case Repo.insert(TaskDependency.create_changeset(%TaskDependency{}, attrs)) do
      {:ok, dependency} -> dependency
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp insert(schema, attrs) do
    schema.create_changeset(struct(schema), Map.put_new(attrs, :id, Identifier.generate()))
    |> Repo.insert()
  end
end

defmodule Cuckoding.Execution do
  @moduledoc "Owns durable commands, runs, attempts, leases, and host execution coordination."

  import Ecto.Query

  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.ProcessRecord
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Identifier
  alias Cuckoding.Projects.Project
  alias Cuckoding.Repo

  def create_run(attrs), do: insert(Run, attrs)
  def create_stage_attempt(attrs), do: insert(StageAttempt, attrs)

  def create_environment(attrs) do
    with :ok <- validate_environment_port(attrs[:run_id], attrs[:port]) do
      insert(Environment, attrs)
    end
  end

  def create_agent_session(attrs), do: insert(AgentSession, attrs)
  def record_process(attrs), do: insert(ProcessRecord, attrs)

  defp insert(schema, attrs) do
    schema.create_changeset(struct(schema), Map.put_new(attrs, :id, Identifier.generate()))
    |> Repo.insert()
  end

  defp validate_environment_port(_run_id, nil), do: :ok

  defp validate_environment_port(run_id, port) do
    query =
      from(project in Project,
        join: board in Cuckoding.Workflows.Board,
        on: board.project_id == project.id,
        join: task in Cuckoding.Workflows.Task,
        on: task.board_id == board.id,
        join: run in Run,
        on: run.task_id == task.id,
        where: run.id == ^run_id,
        select: {project.port_range_start, project.port_range_end}
      )

    case Repo.one(query) do
      {first, last} when port >= first and port <= last -> :ok
      {_first, _last} -> {:error, :port_out_of_range}
      nil -> {:error, :run_not_found}
    end
  end
end

defmodule Cuckoding.Adapters do
  @moduledoc "Defines replaceable agent-runtime adapter contracts and normalized results."

  alias Cuckoding.Adapters.ProviderAccount
  alias Cuckoding.Identifier
  alias Cuckoding.Repo

  def observe_provider(attrs) do
    ProviderAccount.create_changeset(
      %ProviderAccount{},
      Map.put_new(attrs, :id, Identifier.generate())
    )
    |> Repo.insert()
  end
end

defmodule Cuckoding.Plugins do
  @moduledoc "Owns plugin discovery, manifests, activation, capabilities, and health."
end

defmodule Cuckoding.Knowledge do
  @moduledoc "Owns project knowledge, provenance, review, publication, and retrieval records."
end

defmodule Cuckoding.Power do
  @moduledoc "Owns power assertions, sleep-gap detection, and wake reconciliation."
end

defmodule Cuckoding.Telemetry do
  @moduledoc "Owns normalized activity, measurements, estimates, and diagnostics."
end

defmodule Cuckoding.Shell do
  @moduledoc "Defines the authenticated boundary between the native shell and control plane."
end
