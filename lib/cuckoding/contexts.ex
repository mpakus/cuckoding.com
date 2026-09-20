defmodule Cuckoding.Projects do
  @moduledoc "Owns project registration, configuration revisions, and repository identity."

  import Ecto.Query

  alias Cuckoding.Identifier
  alias Cuckoding.Projects.Project
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Repo

  def register(attrs), do: insert(Project, attrs)
  def add_config_version(attrs), do: insert(ProjectConfigVersion, attrs)

  def list_projects,
    do: Repo.all(from(project in Project, order_by: [asc: project.name, asc: project.id]))

  def get_project(id), do: Repo.get(Project, id)

  def latest_config_version(project_id) do
    Repo.one(
      from(config in ProjectConfigVersion,
        where: config.project_id == ^project_id,
        order_by: [desc: config.revision],
        limit: 1
      )
    )
  end

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
  alias Cuckoding.Workflows.Definition
  alias Cuckoding.Workflows.Finding
  alias Cuckoding.Workflows.RoleAssignment
  alias Cuckoding.Workflows.Task
  alias Cuckoding.Workflows.TaskDependency
  alias Cuckoding.Workflows.TaskProposal
  alias Cuckoding.Workflows.WorkflowVersion

  def publish_workflow(attrs) do
    with {:ok, definition} <- Definition.validate(attrs[:definition_json]) do
      insert(WorkflowVersion, Map.put(attrs, :definition_json, definition))
    end
  end

  def create_board(attrs) do
    workflow = Repo.get(WorkflowVersion, attrs[:workflow_version_id])

    if workflow && (is_nil(workflow.project_id) || workflow.project_id == attrs[:project_id]),
      do: insert(Board, attrs),
      else: {:error, :workflow_project_mismatch}
  end

  def list_boards, do: Repo.all(from(board in Board, order_by: [asc: board.name, asc: board.id]))

  def list_boards(project_id) when is_binary(project_id) do
    Repo.all(
      from(board in Board,
        where: board.project_id == ^project_id,
        order_by: [asc: board.name, asc: board.id]
      )
    )
  end

  def get_board(id), do: Repo.get(Board, id)

  def set_board_status(board_id, status) when status in ~w(active paused) do
    case Repo.get(Board, board_id) do
      %Board{status: ^status} = board ->
        {:ok, board}

      %Board{status: current} = board
      when {current, status} in [{"active", "paused"}, {"paused", "active"}] ->
        event = %{
          event_type: "board.transitioned",
          public_summary: "Board moved from #{current} to #{status}",
          payload: %{"board_id" => board.id, "from" => current, "to" => status}
        }

        projection = fn repo, _sequence ->
          repo.update(Board.status_changeset(board, %{status: status}))
        end

        case Cuckoding.Execution.EventStore.append("board:" <> board.id, event, projection) do
          {:ok, {_event, updated}} -> {:ok, updated}
          {:error, {:projection_failed, error}} -> {:error, error}
          {:error, reason} -> {:error, reason}
        end

      %Board{} ->
        {:error, :invalid_board_transition}

      nil ->
        {:error, :board_not_found}
    end
  end

  def set_board_status(_board_id, _status), do: {:error, :invalid_board_status}

  def assign_role(attrs), do: insert(RoleAssignment, attrs)

  def list_agent_roles(board_id) when is_binary(board_id) do
    Repo.all(
      from(role in RoleAssignment,
        where: role.board_id == ^board_id and role.role_kind == "agent",
        order_by: [asc: role.role_key, asc: role.id]
      )
    )
  end

  def create_task(attrs), do: insert(Task, attrs)

  def list_tasks(board_id) do
    Repo.all(
      from(task in Task,
        where: task.board_id == ^board_id and task.kind == "delivery",
        order_by: [desc: task.priority, asc: task.position, asc: task.id]
      )
    )
  end

  def list_task_proposals(intake_task_id) when is_binary(intake_task_id) do
    Repo.all(
      from(proposal in TaskProposal,
        where: proposal.intake_task_id == ^intake_task_id,
        order_by: [asc: proposal.position, asc: proposal.id]
      )
    )
  end

  def get_task(id), do: Repo.get(Task, id)

  def update_task(task_id, attrs) do
    case Repo.get(Task, task_id) do
      %Task{state: state} = task when state in ["draft", "ready"] -> edit_task(task, attrs)
      %Task{} -> {:error, :task_not_editable}
      nil -> {:error, :task_not_found}
    end
  end

  def allowed_task_transitions(%Task{} = task),
    do: Cuckoding.Execution.Transitions.allowed_task_transitions(task)

  def transition_task(task_id, to, idempotency_key, attrs \\ %{}),
    do: Cuckoding.Execution.Transitions.transition_task(task_id, to, idempotency_key, attrs)

  def request_approval(attrs) do
    Cuckoding.Execution.EventStore.transaction(fn ->
      with {:ok, approval} <- insert(Approval, attrs),
           {:ok, _event} <- approval_requested(approval) do
        approval
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp approval_requested(approval) do
    Cuckoding.Execution.EventStore.append_in_transaction(approval.run_id, %{
      event_type: "approval.requested",
      public_summary: "Human approval requested",
      payload: %{"approval_id" => approval.id, "kind" => approval.kind}
    })
  end

  defp edit_task(task, attrs) do
    changeset = Task.edit_changeset(task, attrs)

    with {:ok, validated} <- Ecto.Changeset.apply_action(changeset, :update) do
      event = %{
        event_type: "task.edited",
        public_summary: "Task details edited",
        payload: %{
          "task_id" => task.id,
          "fields" => changed_fields(task, validated)
        }
      }

      projection = fn repo, _sequence -> repo.update(Task.edit_changeset(task, attrs)) end

      case Cuckoding.Execution.EventStore.append("task:" <> task.id, event, projection) do
        {:ok, {_event, updated}} -> {:ok, updated}
        {:error, {:projection_failed, error}} -> {:error, error}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp changed_fields(before, updated) do
    ~w(title description priority)a
    |> Enum.filter(&(Map.get(before, &1) != Map.get(updated, &1)))
    |> Enum.map(&Atom.to_string/1)
  end

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

  def list_runs(task_id) when is_binary(task_id) do
    Repo.all(
      from(run in Run,
        where: run.task_id == ^task_id,
        order_by: [desc: run.sequence, desc: run.id]
      )
    )
  end

  def create_stage_attempt(attrs), do: insert(StageAttempt, attrs)

  def transition_run(run_id, to, idempotency_key, attrs \\ %{}),
    do: Transitions.transition_run(run_id, to, idempotency_key, attrs)

  def transition_stage_attempt(stage_attempt_id, to, idempotency_key),
    do: Transitions.transition_stage_attempt(stage_attempt_id, to, idempotency_key)

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

  def update_environment_preview(environment, attrs) do
    environment
    |> Environment.preview_changeset(attrs)
    |> Repo.update()
  end

  def checkpoint_stage_attempt(attempt, checkpoint) when is_map(checkpoint) do
    attrs = %{
      event_type: "stage.checkpointed",
      public_summary: "Stage checkpoint persisted",
      payload: %{"stage_attempt_id" => attempt.id}
    }

    projection = fn repo, _sequence ->
      repo.update(StageAttempt.checkpoint_changeset(attempt, %{checkpoint_json: checkpoint}))
    end

    Cuckoding.Execution.EventStore.append(attempt.run_id, attrs, projection)
  end

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

  import Ecto.Query

  alias Cuckoding.Adapters.ProviderAccount
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Identifier
  alias Cuckoding.Repo

  def observe_provider(attrs) do
    ProviderAccount.create_changeset(
      %ProviderAccount{},
      Map.put_new(attrs, :id, Identifier.generate())
    )
    |> Repo.insert()
  end

  def list_provider_accounts do
    accounts =
      Repo.all(from(account in ProviderAccount, order_by: [asc: account.label, asc: account.id]))

    by_id = Map.new(accounts, &{&1.id, &1})
    Enum.map(accounts, &with_authorization_status(&1, by_id))
  end

  def get_provider_account(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        case Repo.get(ProviderAccount, id) do
          nil -> nil
          account -> with_authorization_status(account)
        end

      :error ->
        nil
    end
  end

  def get_provider_account(_id), do: nil

  def authorization_id(account), do: account.authorization_account_id || account.id

  def authorization_account(%ProviderAccount{authorization_account_id: nil} = account),
    do: {:ok, account}

  def authorization_account(%ProviderAccount{} = account) do
    root = Repo.get(ProviderAccount, account.authorization_account_id)

    if compatible_authorization?(account, root),
      do: {:ok, root},
      else: {:error, :provider_account_mismatch}
  end

  defp compatible_authorization?(account, %ProviderAccount{authorization_account_id: nil} = root),
    do: account.adapter_key == root.adapter_key and auth_settings(account) == auth_settings(root)

  defp compatible_authorization?(_account, _root), do: false

  defp auth_settings(account),
    do: Map.take(account.capabilities_json["settings"] || %{}, ~w(executable_path api_key_helper))

  defp with_authorization_status(account, by_id \\ nil)
  defp with_authorization_status(%{authorization_account_id: nil} = account, _by_id), do: account

  defp with_authorization_status(account, by_id) do
    root =
      if by_id,
        do: by_id[account.authorization_account_id],
        else: Repo.get(ProviderAccount, account.authorization_account_id)

    if compatible_authorization?(account, root),
      do: %{account | status: root.status, probed_at: root.probed_at},
      else: %{account | status: "unknown", probed_at: nil}
  end

  def save_provider_account(attrs) when is_map(attrs) do
    EventStore.transaction(fn ->
      with {:ok, attrs} <- authorization_attrs(attrs),
           {:ok, account} <- persist_provider_account(attrs),
           {:ok, _event} <-
             EventStore.append_in_transaction("provider:" <> account.id, %{
               event_type: "provider.saved",
               public_summary: "Shared agent settings saved",
               payload: %{
                 "provider_account_id" => account.id,
                 "authorization_account_id" => authorization_id(account)
               }
             }) do
        with_authorization_status(account)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp authorization_attrs(%{id: id} = attrs) when is_binary(id) do
    case get_provider_account(id) do
      nil ->
        {:error, :provider_account_not_found}

      account ->
        requested = Map.get(attrs, :authorization_account_id)

        if requested in [nil, "", account.authorization_account_id, authorization_id(account)],
          do: {:ok, Map.delete(attrs, :authorization_account_id)},
          else: {:error, :authorization_identity_immutable}
    end
  end

  defp authorization_attrs(%{authorization_account_id: "new"} = attrs),
    do: {:ok, Map.put(attrs, :authorization_account_id, nil)}

  defp authorization_attrs(attrs) do
    candidate = struct(ProviderAccount, Map.take(attrs, [:adapter_key, :capabilities_json]))
    selected = Map.get(attrs, :authorization_account_id)

    root =
      if selected in [nil, "", "auto"] do
        list_provider_accounts()
        |> Enum.filter(&compatible_authorization?(candidate, &1))
        |> Enum.sort_by(&{&1.status != "authenticated", &1.inserted_at, &1.id})
        |> List.first()
      else
        get_provider_account(selected)
      end

    cond do
      candidate.adapter_key not in ["codex", "cursor_agent"] and selected in [nil, "", "auto"] ->
        {:ok, Map.put(attrs, :authorization_account_id, nil)}

      root && compatible_authorization?(candidate, root) ->
        {:ok, Map.put(attrs, :authorization_account_id, root.id)}

      is_nil(root) and selected in [nil, "", "auto"] ->
        {:ok, Map.put(attrs, :authorization_account_id, nil)}

      true ->
        {:error, :provider_account_mismatch}
    end
  end

  defp persist_provider_account(attrs) do
    case Map.get(attrs, :id) || Map.get(attrs, "id") do
      nil ->
        ProviderAccount.create_changeset(
          %ProviderAccount{},
          Map.put(attrs, :id, Identifier.generate())
        )
        |> Repo.insert()

      id ->
        case Repo.get(ProviderAccount, id) do
          %ProviderAccount{} = account ->
            update_provider_account(account, attrs)

          nil ->
            {:error, :provider_account_not_found}
        end
    end
  end

  defp update_provider_account(account, attrs) do
    changeset = ProviderAccount.update_changeset(account, attrs)

    changeset =
      if auth_settings(account) != auth_settings(Ecto.Changeset.apply_changes(changeset)),
        do: Ecto.Changeset.change(changeset, status: "unknown", probed_at: nil),
        else: changeset

    if Ecto.Changeset.changed?(changeset, :adapter_key),
      do: {:error, :provider_account_mismatch},
      else: Repo.update(changeset)
  end

  def record_provider_status(id, status, expected_settings \\ nil)
      when is_binary(id) and is_binary(status) do
    EventStore.transaction(fn ->
      with {:ok, account} <- update_provider_status(id, status, expected_settings),
           {:ok, _event} <-
             EventStore.append_in_transaction("provider:" <> id, %{
               event_type: "provider.authorization_checked",
               public_summary: "Shared agent authorization checked",
               payload: %{"provider_account_id" => id, "status" => status}
             }) do
        account
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp update_provider_status(id, status, expected_settings) do
    case Repo.get(ProviderAccount, id) do
      %ProviderAccount{capabilities_json: current}
      when expected_settings != nil and current != expected_settings ->
        {:error, :provider_configuration_changed}

      %ProviderAccount{} = account ->
        account
        |> ProviderAccount.update_changeset(%{
          status: status,
          probed_at: Cuckoding.Clock.wall_now()
        })
        |> Repo.update()

      nil ->
        {:error, :provider_account_not_found}
    end
  end

  def record_session_observation(session, observation) do
    effective_grant = Map.from_struct(observation.effective_grant)
    attempt = Repo.get!(StageAttempt, session.stage_attempt_id)

    changeset =
      Cuckoding.Execution.AgentSession.observation_changeset(session, %{
        actual_model: observation.actual_model,
        external_session_id: observation.external_session_id,
        effective_grant_json: effective_grant,
        state: observation.state
      })

    attrs = %{
      event_type: "agent.effective_grant_recorded",
      public_summary: "Agent runtime permission grant recorded",
      payload: %{
        "agent_session_id" => session.id,
        "requested_fields" => grant_fields(effective_grant.requested),
        "enforced_fields" => grant_fields(effective_grant.enforced),
        "unenforced_fields" => grant_fields(effective_grant.unenforced)
      }
    }

    projection = fn repo, _sequence -> repo.update(changeset) end

    case EventStore.append(attempt.run_id, attrs, projection) do
      {:ok, {_event, updated}} -> {:ok, updated}
      {:error, {:projection_failed, error}} -> {:error, error}
      {:error, error} -> {:error, error}
    end
  end

  defp grant_fields(grant), do: grant |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
end

defmodule Cuckoding.Plugins do
  @moduledoc "Owns plugin discovery, manifests, activation, capabilities, and health."

  alias Cuckoding.Plugins.Capability
  alias Cuckoding.Plugins.Contracts
  alias Cuckoding.Plugins.Registry

  defdelegate discover(options \\ []), to: Registry
  defdelegate refresh(), to: Registry
  defdelegate list(), to: Registry
  defdelegate get(id), to: Registry
  defdelegate enable(plugin_id, scope_type, scope_id, attrs), to: Registry
  defdelegate disable(plugin_id, scope_type, scope_id, actor, reason), to: Registry
  defdelegate issue_capability(plugin_id, run_id, options \\ []), to: Capability, as: :issue

  def invoke(kind, implementation, operation, input, context, options \\ []),
    do: Contracts.call(kind, implementation, operation, input, context, options)
end

defmodule Cuckoding.Knowledge do
  @moduledoc "Owns project knowledge, provenance, review, publication, and retrieval records."

  alias Cuckoding.Knowledge.Analytics
  alias Cuckoding.Knowledge.Consolidator
  alias Cuckoding.Knowledge.Extractor
  alias Cuckoding.Knowledge.Injection
  alias Cuckoding.Knowledge.PublicationService
  alias Cuckoding.Knowledge.Store
  alias Cuckoding.Knowledge.Sync

  defdelegate ensure_project_layout(project), to: Store
  defdelegate ensure_global_layout(options \\ []), to: Store
  defdelegate sync_project(project), to: Sync, as: :run_project
  defdelegate sync_global(options \\ []), to: Sync, as: :run_global
  defdelegate read_for_project(project_id, item_id, options \\ []), to: Store
  defdelegate accept_user_edit(project, item_id), to: Store
  defdelegate extract(run_id, options \\ []), to: Extractor, as: :run
  defdelegate consolidate(project_id, options \\ []), to: Consolidator, as: :run
  defdelegate list_candidates(project_id \\ nil), to: PublicationService
  defdelegate list_publications(project_id \\ nil), to: PublicationService
  defdelegate list_knowledge_approvals(), to: PublicationService, as: :list_approvals
  defdelegate knowledge_growth(), to: Analytics, as: :growth
  defdelegate knowledge_lineage(), to: Analytics, as: :lineage

  defdelegate review_candidate(candidate_id, decision, actor, reason, options \\ []),
    to: PublicationService,
    as: :review

  defdelegate request_publication(candidate_id), to: PublicationService
  defdelegate publish(candidate_id, approval_id, actor, options \\ []), to: PublicationService
  defdelegate request_revocation(publication_id), to: PublicationService
  defdelegate revoke(publication_id, approval_id, actor, options \\ []), to: PublicationService
  defdelegate request_rollback(publication_id, target_version), to: PublicationService

  defdelegate rollback(publication_id, target_version, approval_id, actor, options \\ []),
    to: PublicationService

  defdelegate prepare_injection(request, options \\ []), to: Injection, as: :prepare
  defdelegate record_injection(request), to: Injection

  defdelegate issue_retrieval_token(run_id, stage_attempt_id, options \\ []),
    to: Injection,
    as: :issue_token

  defdelegate retrieve(token, query, options \\ []), to: Injection
  defdelegate record_citations(run_id, stage_attempt_id, citations, options \\ []), to: Injection

  defdelegate record_knowledge_outcome(run_id, stage_attempt_id, item_id, kind, evidence \\ %{}),
    to: Injection,
    as: :record_outcome
end

defmodule Cuckoding.Power do
  @moduledoc "Owns power assertions, sleep-gap detection, and wake reconciliation."

  import Ecto.Query

  alias Cuckoding.Identifier
  alias Cuckoding.Power.PowerEvent
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Board

  def record_event(attrs) do
    attrs
    |> Map.put_new(:id, Identifier.generate())
    |> Map.put_new(:affected_runs_json, [])
    |> Map.put_new(:metadata_json, %{})
    |> Map.put_new(:occurred_at, Cuckoding.Clock.wall_now())
    |> then(&PowerEvent.create_changeset(%PowerEvent{}, &1))
    |> Repo.insert()
  end

  def set_unattended(%Board{} = board, until) do
    with :ok <- valid_unattended_until(board, until) do
      Repo.transaction(fn -> persist_unattended(board, until) end)
    end
  end

  defp persist_unattended(board, until) do
    updated =
      board
      |> Board.unattended_changeset(%{unattended_until: until})
      |> Repo.update!()

    kind = if until, do: "unattended_on", else: "unattended_off"

    {:ok, _event} =
      record_event(%{
        kind: kind,
        metadata_json: %{"board_id" => board.id, "unattended_until" => encode_time(until)}
      })

    updated
  end

  defp valid_unattended_until(_board, nil), do: :ok

  defp valid_unattended_until(board, %DateTime{} = until) do
    now = Cuckoding.Clock.wall_now()
    policy = unattended_policy(board.project_id)

    cond do
      policy.allowed? == false ->
        {:error, :unattended_mode_not_allowed}

      not DateTime.after?(until, now) ->
        {:error, :unattended_window_must_be_future}

      DateTime.diff(until, now, :second) > policy.max_window_hours * 3_600 ->
        {:error, :unattended_window_too_long}

      true ->
        :ok
    end
  end

  defp valid_unattended_until(_board, _until), do: {:error, :invalid_unattended_window}

  defp unattended_policy(project_id) do
    config =
      Repo.one(
        from(policy in ProjectConfigVersion,
          where: policy.project_id == ^project_id and not is_nil(policy.trusted_at),
          order_by: [desc: policy.revision],
          limit: 1,
          select: policy.config_json
        )
      ) || %{}

    %{
      allowed?: get_in(config, ["unattended", "allowed"]) != false,
      max_window_hours: positive_integer(get_in(config, ["unattended", "max_window_hours"]), 12)
    }
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp encode_time(nil), do: nil
  defp encode_time(time), do: DateTime.to_iso8601(time)
end

defmodule Cuckoding.Telemetry do
  @moduledoc "Owns normalized activity, measurements, estimates, and diagnostics."
end
