defmodule Cuckoding.GuidedRun do
  @moduledoc "Creates and launches the user-facing default workflow."

  import Ecto.Query

  alias Cuckoding.Adapters.RuntimeConfiguration
  alias Cuckoding.AgentRuntime
  alias Cuckoding.Execution
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Identifier
  alias Cuckoding.OrchestrationFailure
  alias Cuckoding.Repo
  alias Cuckoding.RunControl
  alias Cuckoding.WalkingSkeleton
  alias Cuckoding.Workflows.Definition

  def create(attrs) when is_map(attrs) do
    with {:ok, configuration} <- RuntimeConfiguration.validate(attrs) do
      WalkingSkeleton.create(%{
        name: attrs["name"],
        repo_path: attrs["repo_path"],
        default_branch: attrs["default_branch"],
        workspace_root: workspace_root(),
        board_name: "Product",
        task_title: attrs["task_title"],
        task_description: attrs["task_description"],
        adapter_key: configuration.runtime,
        adapter_settings: configuration.settings,
        start_run: false,
        port_range_start: 43_000,
        port_range_end: 43_999
      })
    end
  end

  def start(run_id, options \\ []) when is_binary(run_id) do
    mode = Keyword.get(options, :completion_mode, "manual")

    with true <- mode in ["manual", "local"],
         {:ok, skeleton} <- WalkingSkeleton.load(run_id),
         "queued" <- skeleton.run.state,
         {:ok, role_adapters} <- adapters(skeleton),
         {:ok, _policy} <-
           RunControl.admit(run_id, fn -> start_with_policy(run_id, mode, options) end) do
      launch(skeleton, role_adapters, options)
    else
      state when is_binary(state) -> {:error, :run_not_queued}
      false -> {:error, :invalid_completion_mode}
      error -> error
    end
  end

  def completion_policy(run_id) do
    Repo.one(
      from event in RunEvent,
        where: event.run_id == ^run_id and event.event_type == "run.completion_policy",
        order_by: [desc: event.sequence],
        limit: 1,
        select: event.payload
    ) || %{"mode" => "manual"}
  end

  defp start_with_policy(run_id, mode, options) do
    key = "guided:#{run_id}:running:#{Identifier.generate()}"
    actor = Keyword.get(options, :completion_actor, "local_user")

    EventStore.transaction(fn ->
      with {:ok, command} <- Execution.transition_run(run_id, "running", key),
           true <- command.result["outcome"] == "transitioned",
           {:ok, event} <-
             EventStore.append_in_transaction(run_id, %{
               event_type: "run.completion_policy",
               public_summary:
                 if(mode == "local",
                   do: "User authorized local completion after a passing review",
                   else: "A passing review will wait for the user's completion decision"
                 ),
               payload: %{
                 "mode" => mode,
                 "actor" => actor,
                 "release_handoff" => "requires_approval"
               }
             }) do
        event
      else
        false -> Repo.rollback(:transition_rejected)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def runtime_setup(run_id) when is_binary(run_id) do
    with {:ok, skeleton} <- WalkingSkeleton.load(run_id),
         {:ok, role} <- agent_role(skeleton) do
      AgentRuntime.setup(skeleton, role.role_key)
    end
  end

  def runtime_setups(run_id) when is_binary(run_id) do
    with {:ok, skeleton} <- WalkingSkeleton.load(run_id) do
      skeleton
      |> roles()
      |> Enum.reduce_while({:ok, []}, &collect_runtime_setup(&1, &2, skeleton))
      |> case do
        {:ok, setups} -> {:ok, setups |> Enum.reverse() |> AgentRuntime.group_setups()}
        error -> error
      end
    end
  end

  defp collect_runtime_setup(role, {:ok, setups}, skeleton) do
    case AgentRuntime.setup(skeleton, role.role_key) do
      {:ok, setup} -> {:cont, {:ok, [setup | setups]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp launch(skeleton, role_adapters, options) do
    run = Repo.get!(Cuckoding.Execution.Run, skeleton.run.id)
    skeleton = %{skeleton | run: run}
    implementation = Map.fetch!(role_adapters, "implementer")

    work = fn ->
      RunControl.track(run.id, :workflow, fn ->
        WalkingSkeleton.run(skeleton,
          adapter: implementation.adapter,
          adapter_options: implementation.options,
          runtime_version: implementation.version,
          role_adapters: role_adapters,
          simulate_sleep_gap: false
        )
      end)
    end

    if Keyword.get(options, :async, true) do
      case Task.Supervisor.start_child(Cuckoding.GuidedRunSupervisor, work) do
        {:ok, _pid} ->
          {:ok, :started}

        {:error, reason} ->
          :ok = OrchestrationFailure.fail(run.id, :workflow, {:worker_start_failed, reason})
          {:error, {:worker_start_failed, reason}}
      end
    else
      work.()
    end
  end

  defp adapters(skeleton) do
    required = Definition.agent_role_keys(skeleton.run.workflow_snapshot_json["definition"])

    AgentRuntime.resolve_roles(skeleton, roles(skeleton))
    |> case do
      {:ok, configured} when map_size(configured) == length(required) -> {:ok, configured}
      {:ok, _configured} -> {:error, :role_assignment_not_found}
      error -> error
    end
  end

  defp agent_role(skeleton) do
    case Enum.find(roles(skeleton), &(&1.role_key == "implementer")) do
      role when not is_nil(role) -> {:ok, role}
      nil -> {:error, :role_assignment_not_found}
    end
  end

  defp roles(skeleton) do
    keys = Definition.agent_role_keys(skeleton.run.workflow_snapshot_json["definition"])

    skeleton.run.workflow_snapshot_json["roles"]
    |> Enum.filter(&(&1["role_key"] in keys))
    |> Enum.map(fn role ->
      %{
        role_key: role["role_key"],
        adapter_key: role["adapter_key"],
        settings_json: role["settings"] || %{}
      }
    end)
    |> Enum.sort_by(& &1.role_key)
  end

  defp workspace_root do
    Application.get_env(:cuckoding, :workspace_root) ||
      Application.fetch_env!(:cuckoding, Cuckoding.Repo)
      |> Keyword.fetch!(:database)
      |> Path.dirname()
      |> Path.join("workspaces")
  end
end
