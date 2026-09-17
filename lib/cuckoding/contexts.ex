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

  import Ecto.Query

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

  def transition_task(task_id, to, idempotency_key, attrs \\ %{}),
    do: Cuckoding.Execution.Transitions.transition_task(task_id, to, idempotency_key, attrs)

  def request_approval(attrs), do: insert(Approval, attrs)

  def decide_approval(approval_id, decision, actor, reason) do
    case Repo.get(Approval, approval_id) do
      %Approval{decision: "pending"} = approval ->
        decide_pending_approval(approval, decision, actor, reason)

      %Approval{} ->
        {:error, :approval_already_decided}

      nil ->
        {:error, :approval_not_found}
    end
  end

  defp decide_pending_approval(approval, decision, actor, reason) do
    decided_at = Cuckoding.Clock.wall_now()

    changeset =
      Approval.decision_changeset(approval, %{
        decision: decision,
        actor: actor,
        reason: reason,
        decided_at: decided_at
      })

    with {:ok, validated} <- Ecto.Changeset.apply_action(changeset, :update) do
      attrs = %{
        event_type: "approval.decided",
        public_summary: "Human decided a policy approval",
        payload: %{
          "approval_id" => approval.id,
          "kind" => approval.kind,
          "decision" => validated.decision,
          "actor" => validated.actor
        }
      }

      projection = approval_projection(approval, validated, decided_at)

      case Cuckoding.Execution.EventStore.append(approval.run_id, attrs, projection) do
        {:ok, {_event, decided}} -> {:ok, decided}
        {:error, {:projection_failed, error}} -> {:error, error}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp approval_projection(approval, validated, decided_at) do
    fn repo, _sequence ->
      query =
        from(candidate in Approval,
          where: candidate.id == ^approval.id and candidate.decision == "pending"
        )

      updates = [
        decision: validated.decision,
        actor: validated.actor,
        reason: validated.reason,
        decided_at: validated.decided_at,
        updated_at: decided_at
      ]

      case repo.update_all(query, set: updates) do
        {1, _rows} -> {:ok, repo.get!(Approval, approval.id)}
        {0, _rows} -> {:error, :approval_already_decided}
      end
    end
  end

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
  alias Cuckoding.Execution.Transitions
  alias Cuckoding.Identifier
  alias Cuckoding.Projects.Project
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.RoleAssignment
  alias Cuckoding.Workflows.Task
  alias Cuckoding.Workflows.WorkflowVersion

  def create_run(attrs) do
    Repo.transaction(fn ->
      with {:ok, attrs} <- snapshot_run(attrs),
           {:ok, run} <- insert(Run, attrs) do
        run
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def create_stage_attempt(attrs), do: insert(StageAttempt, attrs)

  def transition_run(run_id, to, idempotency_key, attrs \\ %{}),
    do: Transitions.transition_run(run_id, to, idempotency_key, attrs)

  def record_stage_time(stage_attempt_id, active_delta_ms, wall_delta_ms, idempotency_key),
    do:
      Transitions.record_stage_time(
        stage_attempt_id,
        active_delta_ms,
        wall_delta_ms,
        idempotency_key
      )

  def create_environment(attrs) do
    with :ok <- validate_environment_port(attrs[:run_id], attrs[:port]) do
      insert(Environment, attrs)
    end
  end

  def create_agent_session(attrs), do: insert(AgentSession, attrs)
  def record_process(attrs), do: insert(ProcessRecord, attrs)

  def finish_process(process, exit_code, ended_at) do
    state = if exit_code == 0, do: "exited", else: "failed"

    process
    |> ProcessRecord.finish_changeset(%{state: state, exit_code: exit_code, ended_at: ended_at})
    |> Repo.update()
  end

  defp insert(schema, attrs) do
    schema.create_changeset(struct(schema), Map.put_new(attrs, :id, Identifier.generate()))
    |> Repo.insert()
  end

  defp snapshot_run(attrs) do
    with %Task{} = task <- Repo.get(Task, attrs[:task_id]),
         %Board{} = board <- Repo.get(Board, task.board_id),
         %WorkflowVersion{} = workflow <- Repo.get(WorkflowVersion, board.workflow_version_id),
         %ProjectConfigVersion{} = policy <-
           Repo.get(ProjectConfigVersion, attrs[:policy_snapshot_id]),
         :ok <- validate_run_snapshot(board, workflow, policy) do
      roles =
        Repo.all(
          from(role in RoleAssignment,
            where: role.board_id == ^board.id,
            order_by: role.role_key
          )
        )

      snapshot = %{
        "workflow_version_id" => workflow.id,
        "name" => workflow.name,
        "version" => workflow.version,
        "definition" => workflow.definition_json,
        "roles" =>
          Enum.map(roles, fn role ->
            %{
              "role_key" => role.role_key,
              "role_kind" => role.role_kind,
              "adapter_key" => role.adapter_key,
              "model_ref" => role.model_ref,
              "settings" => role.settings_json
            }
          end)
      }

      {:ok, Map.put(attrs, :workflow_snapshot_json, snapshot)}
    else
      nil -> {:error, :snapshot_source_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_run_snapshot(board, workflow, policy) do
    cond do
      workflow.project_id not in [nil, board.project_id] -> {:error, :workflow_project_mismatch}
      policy.project_id != board.project_id -> {:error, :policy_project_mismatch}
      is_nil(policy.trusted_at) -> {:error, :policy_not_trusted}
      true -> :ok
    end
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
