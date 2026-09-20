defmodule Cuckoding.ProjectWorkflow do
  @moduledoc "Creates project boards and tasks, then prepares trusted task runs."

  import Ecto.Query

  alias Cuckoding.Clock
  alias Cuckoding.Execution
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.GitService
  alias Cuckoding.Execution.LocalProcessRunner
  alias Cuckoding.Execution.Run
  alias Cuckoding.Identifier
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows
  alias Cuckoding.Workflows.Definition
  alias Cuckoding.Workflows.RoleAssignment
  alias Cuckoding.Workflows.Task
  alias Cuckoding.Workflows.WorkflowVersion

  @agent_roles ~w(spec_writer implementer reviewer)
  @runnable_adapters ~w(codex claude_code cursor_agent fake)

  def connect_saved_agents(board_id, expected_revision) do
    EventStore.transaction(fn ->
      with board when not is_nil(board) <- Workflows.get_board(board_id),
           %{revision: ^expected_revision} = config <-
             Projects.latest_config_version(board.project_id),
           :ok <- connect_board_roles(board.id, config.config_json),
           {:ok, _event} <-
             EventStore.append_in_transaction("board:" <> board.id, %{
               event_type: "board.agents_connected",
               public_summary: "Board roles linked to saved agents",
               payload: %{
                 "board_id" => board.id,
                 "project_id" => board.project_id,
                 "config_revision" => config.revision
               }
             }) do
        board
      else
        {:error, reason} -> Repo.rollback(reason)
        _other -> Repo.rollback(:stale_configuration)
      end
    end)
  end

  defp connect_board_roles(board_id, config) do
    connections = Map.new(config["agent_connections"] || [], &{&1["key"], &1})

    Enum.reduce_while(Workflows.list_agent_roles(board_id), :ok, fn role, :ok ->
      connection = connections[role.settings_json["connection_key"]] || %{}
      id = connection["provider_account_id"]

      with :ok <- Cuckoding.AgentBindings.compatible(role.adapter_key, role.settings_json, id),
           {:ok, _role} <-
             role
             |> Ecto.Changeset.change(
               settings_json: Map.put(role.settings_json, "provider_account_id", id)
             )
             |> Repo.update() do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  def create_board(project_id, attrs) when is_binary(project_id) and is_map(attrs) do
    EventStore.transaction(fn ->
      with project when not is_nil(project) <- Projects.get_project(project_id),
           config when not is_nil(config) <- Projects.latest_config_version(project_id),
           {:ok, fields} <- board_fields(attrs),
           {:ok, workflow} <- default_workflow(project_id),
           {:ok, board} <-
             Workflows.create_board(
               Map.merge(fields, %{
                 project_id: project.id,
                 workflow_version_id: workflow.id
               })
             ),
           :ok <- assign_roles(board.id, config.config_json),
           {:ok, _event} <-
             EventStore.append_in_transaction("board:" <> board.id, %{
               event_type: "board.created",
               public_summary: "Project board created",
               payload: %{
                 "project_id" => project.id,
                 "board_id" => board.id,
                 "workflow_version_id" => workflow.id,
                 "config_revision" => config.revision
               }
             }) do
        board
      else
        nil -> Repo.rollback(:project_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def create_task(board_id, attrs) when is_binary(board_id) and is_map(attrs) do
    EventStore.transaction(fn ->
      with board when not is_nil(board) <- Workflows.get_board(board_id),
           {:ok, fields} <- task_fields(attrs),
           {:ok, task} <-
             Workflows.create_task(
               fields
               |> Map.put(:board_id, board.id)
               |> Map.put(:position, next_position(board.id))
             ),
           {:ok, _event} <-
             EventStore.append_in_transaction("task:" <> task.id, %{
               event_type: "task.created",
               public_summary: "Task added to board",
               payload: %{
                 "project_id" => board.project_id,
                 "board_id" => board.id,
                 "task_id" => task.id
               }
             }) do
        task
      else
        nil -> Repo.rollback(:board_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def create_task_intake(board_id, attrs) when is_binary(board_id) and is_map(attrs) do
    with {:ok, prompt} <- bounded_text(attrs["prompt"], :intake_prompt_required, 10_000),
         {:ok, role} <- intake_role(board_id, attrs["role_key"]),
         {:ok, task} <- create_intake_task(board_id, prompt, role.role_key),
         {:ok, %{result: %{"outcome" => "transitioned"}}} <-
           Workflows.transition_task(task.id, "ready", "intake:#{task.id}:ready"),
         {:ok, prepared} <- prepare_task(task.id) do
      {:ok, Map.put(prepared, :task, Repo.get!(Task, task.id))}
    else
      {:ok, %{result: %{"outcome" => "rejected", "reason" => reason}}} ->
        {:error, {:intake_transition_rejected, reason}}

      error ->
        error
    end
  end

  def prepare_task(task_id) when is_binary(task_id) do
    with %Task{state: "ready", active_run_id: nil} = task <- Workflows.get_task(task_id),
         board when not is_nil(board) <- Workflows.get_board(task.board_id),
         :ok <- active_board(board.status),
         project when not is_nil(project) <- Projects.get_project(board.project_id),
         policy when not is_nil(policy) <- Projects.latest_config_version(project.id),
         :ok <- trusted_policy(policy.trusted_at),
         :ok <- runnable_roles(board.id, task),
         :ok <- no_queued_run(task.id),
         {:ok, base_sha} <- GitService.capture_base(project),
         {:ok, run} <- Execution.create_run(run_attrs(task, policy, base_sha)),
         {:ok, environment} <- prepare_environment(project, run),
         {:ok, _event} <- run_prepared(project, board, task, run) do
      {:ok, %{run: run, environment: environment}}
    else
      %Task{} -> {:error, :task_not_ready}
      nil -> {:error, :task_not_found}
      error -> error
    end
  end

  defp prepare_environment(project, run) do
    with {:ok, environment} <- GitService.prepare(project, run),
         {:ok, environment} <- LocalProcessRunner.prepare(environment, []) do
      {:ok, environment}
    else
      {:error, reason} ->
        fail_preparation(run, reason)
        {:error, reason}
    end
  end

  defp fail_preparation(run, reason) do
    Execution.transition_run(
      run.id,
      "failed",
      "prepare:#{run.id}:failed",
      wait_reason: "run preparation failed: #{inspect(reason)}"
    )
  end

  defp run_prepared(project, board, task, run) do
    EventStore.append("task:" <> task.id, %{
      event_type: "run.prepared",
      public_summary: "Queued run and owned worktree prepared",
      payload: %{
        "project_id" => project.id,
        "board_id" => board.id,
        "task_id" => task.id,
        "run_id" => run.id
      }
    })
  end

  defp default_workflow(project_id) do
    case Repo.one(
           from(workflow in WorkflowVersion,
             where: workflow.project_id == ^project_id and workflow.name == "default",
             order_by: [desc: workflow.version],
             limit: 1
           )
         ) do
      %WorkflowVersion{} = workflow ->
        {:ok, workflow}

      nil ->
        Workflows.publish_workflow(%{
          project_id: project_id,
          name: "default",
          version: 1,
          definition_json: Definition.default(),
          published_at: Clock.wall_now()
        })
    end
  end

  defp assign_roles(board_id, config) do
    connections = Map.new(config["agent_connections"] || [], &{&1["key"], &1})
    roles = config["default_roles"] || []

    with :ok <- required_roles_present(roles),
         :ok <- assigned_roles(board_id, roles, connections),
         :ok <- assign_role(board_id, "approver", "human", nil, %{}),
         do: assign_role(board_id, "release", "system", nil, %{})
  end

  defp assigned_roles(board_id, roles, connections) do
    Enum.reduce_while(roles, :ok, &assign_project_role(&1, &2, board_id, connections))
  end

  defp assign_project_role(role, :ok, board_id, connections) do
    case connections[role["agent_connection_key"]] do
      nil ->
        {:halt, {:error, :roles_not_configured}}

      connection ->
        settings =
          Map.merge(connection["settings"] || %{}, %{
            "connection_key" => connection["key"],
            "connection_label" => connection["label"],
            "provider_account_id" => connection["provider_account_id"],
            "role_name" => role["name"],
            "instructions" => role["instructions"]
          })

        reduce_assignment(
          assign_role(board_id, role["key"], "agent", connection["adapter_key"], settings)
        )
    end
  end

  defp reduce_assignment(:ok), do: {:cont, :ok}
  defp reduce_assignment({:error, reason}), do: {:halt, {:error, reason}}

  defp assign_role(board_id, role_key, kind, adapter_key, settings) do
    case Workflows.assign_role(%{
           board_id: board_id,
           role_key: role_key,
           role_kind: kind,
           adapter_key: adapter_key,
           settings_json: settings
         }) do
      {:ok, _role} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp intake_role(board_id, role_key) when is_binary(role_key) do
    case Repo.get_by(RoleAssignment,
           board_id: board_id,
           role_key: role_key,
           role_kind: "agent"
         ) do
      %RoleAssignment{} = role -> {:ok, role}
      nil -> {:error, :intake_role_required}
    end
  end

  defp intake_role(_board_id, _role_key), do: {:error, :intake_role_required}

  defp create_intake_task(board_id, prompt, role_key) do
    EventStore.transaction(fn ->
      with board when not is_nil(board) <- Workflows.get_board(board_id),
           {:ok, task} <-
             Workflows.create_task(%{
               board_id: board.id,
               title: "Plan board tasks",
               description: prompt,
               priority: 0,
               position: next_position(board.id),
               kind: "board_intake",
               intake_role_key: role_key
             }),
           {:ok, _event} <-
             EventStore.append_in_transaction("task:" <> task.id, %{
               event_type: "task_intake.created",
               public_summary: "Board task-planning request created",
               payload: %{
                 "project_id" => board.project_id,
                 "board_id" => board.id,
                 "task_id" => task.id,
                 "role_key" => role_key
               }
             }) do
        task
      else
        nil -> Repo.rollback(:board_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp required_roles_present(roles) do
    keys = MapSet.new(roles, & &1["key"])

    if Enum.all?(@agent_roles, &MapSet.member?(keys, &1)),
      do: :ok,
      else: {:error, :roles_not_configured}
  end

  defp runnable_roles(board_id, %Task{kind: "board_intake", intake_role_key: role_key}) do
    case Repo.get_by(RoleAssignment,
           board_id: board_id,
           role_key: role_key,
           role_kind: "agent"
         ) do
      %RoleAssignment{adapter_key: adapter} when adapter in @runnable_adapters -> :ok
      %RoleAssignment{} -> {:error, :runtime_setup_only}
      nil -> {:error, :roles_not_configured}
    end
  end

  defp runnable_roles(board_id, %Task{}) do
    roles =
      Repo.all(
        from(role in RoleAssignment,
          where: role.board_id == ^board_id and role.role_key in ^@agent_roles
        )
      )

    cond do
      length(roles) != length(@agent_roles) ->
        {:error, :roles_not_configured}

      Enum.any?(roles, &(&1.adapter_key not in @runnable_adapters)) ->
        {:error, :runtime_setup_only}

      true ->
        :ok
    end
  end

  defp board_fields(attrs) do
    with {:ok, name} <- bounded_text(attrs["name"], :board_name_required, 120),
         {:ok, description} <-
           optional_text(attrs["description"], :invalid_board_description, 2_000),
         {:ok, concurrency} <- bounded_integer(attrs["concurrency_limit"], 1, 32) do
      {:ok, %{name: name, description: description, concurrency_limit: concurrency}}
    end
  end

  defp task_fields(attrs) do
    with {:ok, title} <- bounded_text(attrs["title"], :task_title_required, 200),
         {:ok, description} <-
           optional_text(attrs["description"], :invalid_task_description, 10_000),
         {:ok, priority} <- bounded_integer(attrs["priority"] || 0, -100, 100) do
      {:ok, %{title: title, description: description, priority: priority}}
    end
  end

  defp next_position(board_id) do
    Repo.one(from(task in Task, where: task.board_id == ^board_id, select: max(task.position)))
    |> Kernel.||(-1)
    |> Kernel.+(1)
  end

  defp run_attrs(task, policy, base_sha) do
    sequence =
      Repo.one(from(run in Run, where: run.task_id == ^task.id, select: max(run.sequence)))
      |> Kernel.||(0)
      |> Kernel.+(1)

    run_id = Identifier.generate()

    %{
      id: run_id,
      task_id: task.id,
      sequence: sequence,
      policy_snapshot_id: policy.id,
      plugin_snapshot_json: %{},
      branch: "feature/task-#{String.slice(task.id, 0, 8)}-#{String.slice(run_id, 0, 8)}",
      base_sha: base_sha
    }
  end

  defp active_board("active"), do: :ok
  defp active_board(_status), do: {:error, :board_not_active}
  defp trusted_policy(nil), do: {:error, :policy_not_trusted}
  defp trusted_policy(_trusted_at), do: :ok

  defp no_queued_run(task_id) do
    if Repo.exists?(from(run in Run, where: run.task_id == ^task_id and run.state == "queued")),
      do: {:error, :run_already_prepared},
      else: :ok
  end

  defp bounded_text(value, error, maximum) when is_binary(value) do
    value = String.trim(value)
    if value != "" and String.length(value) <= maximum, do: {:ok, value}, else: {:error, error}
  end

  defp bounded_text(_value, error, _maximum), do: {:error, error}

  defp optional_text(nil, _error, _maximum), do: {:ok, nil}

  defp optional_text(value, error, maximum) when is_binary(value) do
    case String.trim(value) do
      "" ->
        {:ok, nil}

      text when byte_size(text) <= maximum * 4 ->
        if String.length(text) <= maximum, do: {:ok, text}, else: {:error, error}

      _text ->
        {:error, error}
    end
  end

  defp optional_text(_value, error, _maximum), do: {:error, error}

  defp bounded_integer(value, minimum, maximum) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> bounded_integer(integer, minimum, maximum)
      _invalid -> {:error, :invalid_number}
    end
  end

  defp bounded_integer(value, minimum, maximum)
       when is_integer(value) and value >= minimum and value <= maximum,
       do: {:ok, value}

  defp bounded_integer(_value, _minimum, _maximum), do: {:error, :invalid_number}
end
