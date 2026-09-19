defmodule Cuckoding.GuidedRun do
  @moduledoc "Creates and launches the user-facing default workflow."

  alias Cuckoding.Adapters.ClaudeCode
  alias Cuckoding.Adapters.Codex
  alias Cuckoding.Adapters.CursorAgent
  alias Cuckoding.Adapters.FakeAdapter
  alias Cuckoding.Adapters.RuntimeConfiguration
  alias Cuckoding.Execution
  alias Cuckoding.Identifier
  alias Cuckoding.Repo
  alias Cuckoding.WalkingSkeleton

  @agent_roles ~w(spec_writer implementer reviewer)

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
    command_key = "guided:#{run_id}:running:#{Identifier.generate()}"

    with {:ok, skeleton} <- WalkingSkeleton.load(run_id),
         "queued" <- skeleton.run.state,
         {:ok, role_adapters} <- adapters(skeleton),
         {:ok, command} <-
           Execution.transition_run(run_id, "running", command_key),
         true <- command.result["outcome"] == "transitioned" do
      launch(skeleton, role_adapters, options)
    else
      state when is_binary(state) -> {:error, :run_not_queued}
      false -> {:error, :transition_rejected}
      error -> error
    end
  end

  def runtime_setup(run_id) when is_binary(run_id) do
    with {:ok, skeleton} <- WalkingSkeleton.load(run_id),
         {:ok, role} <- agent_role(skeleton) do
      runtime_setup(skeleton, role)
    end
  end

  def runtime_setups(run_id) when is_binary(run_id) do
    with {:ok, skeleton} <- WalkingSkeleton.load(run_id) do
      skeleton
      |> roles()
      |> Enum.reduce_while({:ok, []}, &collect_runtime_setup(&1, &2, skeleton))
      |> case do
        {:ok, setups} -> {:ok, Enum.reverse(setups)}
        error -> error
      end
    end
  end

  defp collect_runtime_setup(role, {:ok, setups}, skeleton) do
    case runtime_setup(skeleton, role) do
      {:ok, setup} -> {:cont, {:ok, [Map.put(setup, :role_key, role.role_key) | setups]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp launch(skeleton, role_adapters, options) do
    run = Repo.get!(Cuckoding.Execution.Run, skeleton.run.id)
    skeleton = %{skeleton | run: run}
    implementation = Map.fetch!(role_adapters, "implementer")

    work = fn ->
      result =
        WalkingSkeleton.run(skeleton,
          adapter: implementation.adapter,
          adapter_options: implementation.options,
          runtime_version: implementation.version,
          role_adapters: role_adapters,
          simulate_sleep_gap: false
        )

      if match?({:error, _reason}, result), do: block(run.id)
      result
    end

    if Keyword.get(options, :async, true) do
      case Task.Supervisor.start_child(Cuckoding.GuidedRunSupervisor, work) do
        {:ok, _pid} -> {:ok, :started}
        {:error, reason} -> block(run.id, {:worker_start_failed, reason})
      end
    else
      work.()
    end
  end

  defp adapters(skeleton) do
    skeleton
    |> roles()
    |> Enum.reduce_while({:ok, %{}}, fn role, {:ok, configured} ->
      case adapter(skeleton, role) do
        {:ok, module, options, version} ->
          value = %{
            adapter: module,
            options: options,
            version: version,
            settings: role.settings_json
          }

          {:cont, {:ok, Map.put(configured, role.role_key, value)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, configured} when map_size(configured) == length(@agent_roles) -> {:ok, configured}
      {:ok, _configured} -> {:error, :role_assignment_not_found}
      error -> error
    end
  end

  defp adapter(skeleton, role) do
    path = role.settings_json["executable_path"]

    case role.adapter_key do
      "codex" ->
        home = Path.join([skeleton.environment.run_dir, "agent", "codex", "home"])
        options = [path: path, codex_home: home, run_scoped_authenticated?: true]
        probe(Codex, options)

      "claude_code" ->
        options = [
          path: path,
          api_key_helper: role.settings_json["api_key_helper"],
          run_scoped_authenticated?: true
        ]

        probe(ClaudeCode, options)

      "cursor_agent" ->
        root = Path.join([skeleton.environment.run_dir, "agent", "cursor"])
        options = [path: path, cursor_home: root, run_scoped_authenticated?: true]
        probe(CursorAgent, options)

      "fake" ->
        {:ok, FakeAdapter, [], "test"}

      _other ->
        {:error, :unsupported_runtime}
    end
  end

  defp probe(module, options) do
    case module.probe(options) do
      {:ok, %{authenticated?: true, version: version}} -> {:ok, module, options, version}
      {:ok, _probe} -> {:error, :run_scoped_auth_required}
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
    skeleton.run.workflow_snapshot_json["roles"]
    |> Enum.filter(&(&1["role_key"] in @agent_roles))
    |> Enum.map(fn role ->
      %{
        role_key: role["role_key"],
        adapter_key: role["adapter_key"],
        settings_json: role["settings"] || %{}
      }
    end)
    |> Enum.sort_by(& &1.role_key)
  end

  defp runtime_setup(skeleton, role) do
    home = Path.join([skeleton.environment.run_dir, "agent", "codex", "home"])

    case role.adapter_key do
      "codex" ->
        :ok = File.mkdir_p(home)
        :ok = File.chmod(home, 0o700)

        {:ok,
         %{
           runtime: "Codex",
           connection: role.settings_json["connection_label"],
           executable: role.settings_json["executable_path"],
           home: home,
           login_args: "login --device-auth"
         }}

      "claude_code" ->
        {:ok,
         %{
           runtime: "Claude Code",
           connection: role.settings_json["connection_label"],
           executable: role.settings_json["executable_path"],
           helper: role.settings_json["api_key_helper"]
         }}

      "cursor_agent" ->
        root = Path.join([skeleton.environment.run_dir, "agent", "cursor"])
        home = Path.join(root, "home")
        config = Path.join(root, "config")
        claude = Path.join(root, "claude")

        Enum.each([root, home, config, claude], fn path ->
          :ok = File.mkdir_p(path)
          :ok = File.chmod(path, 0o700)
        end)

        {:ok,
         %{
           runtime: "Cursor Agent",
           connection: role.settings_json["connection_label"],
           executable: role.settings_json["executable_path"],
           environment: %{
             "HOME" => home,
             "CURSOR_CONFIG_DIR" => config,
             "CLAUDE_CONFIG_DIR" => claude
           },
           login_args: "login"
         }}

      "fake" ->
        {:ok,
         %{
           runtime: "Deterministic test adapter",
           connection: role.settings_json["connection_label"]
         }}

      _other ->
        {:error, :unsupported_runtime}
    end
  end

  defp workspace_root do
    Application.get_env(:cuckoding, :workspace_root) ||
      Application.fetch_env!(:cuckoding, Cuckoding.Repo)
      |> Keyword.fetch!(:database)
      |> Path.dirname()
      |> Path.join("workspaces")
  end

  defp block(run_id, reason \\ :workflow_failed) do
    case Execution.transition_run(run_id, "blocked", "guided:#{run_id}:blocked",
           wait_reason: "workflow failed; inspect the run evidence"
         ) do
      {:ok, _command} -> {:error, reason}
      {:error, transition_reason} -> {:error, {:block_failed, reason, transition_reason}}
    end
  end
end
