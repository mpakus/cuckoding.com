defmodule Cuckoding.GuidedRun do
  @moduledoc "Creates and launches the user-facing default workflow."

  alias Cuckoding.Adapters.ClaudeCode
  alias Cuckoding.Adapters.Codex
  alias Cuckoding.Adapters.FakeAdapter
  alias Cuckoding.Execution
  alias Cuckoding.Identifier
  alias Cuckoding.Repo
  alias Cuckoding.WalkingSkeleton
  alias Cuckoding.Workflows.RoleAssignment

  @runtimes ~w(codex claude_code)

  def create(attrs) when is_map(attrs) do
    with {:ok, runtime} <- runtime(attrs["runtime"]),
         {:ok, settings} <- settings(runtime, attrs) do
      WalkingSkeleton.create(%{
        name: attrs["name"],
        repo_path: attrs["repo_path"],
        default_branch: attrs["default_branch"],
        workspace_root: workspace_root(),
        board_name: "Product",
        task_title: attrs["task_title"],
        task_description: attrs["task_description"],
        adapter_key: runtime,
        adapter_settings: settings,
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
         {:ok, adapter, adapter_options, version} <- adapter(skeleton),
         {:ok, command} <-
           Execution.transition_run(run_id, "running", command_key),
         true <- command.result["outcome"] == "transitioned" do
      launch(skeleton, adapter, adapter_options, version, options)
    else
      state when is_binary(state) -> {:error, :run_not_queued}
      false -> {:error, :transition_rejected}
      error -> error
    end
  end

  def runtime_setup(run_id) when is_binary(run_id) do
    with {:ok, skeleton} <- WalkingSkeleton.load(run_id),
         {:ok, role} <- agent_role(skeleton.board.id) do
      home = Path.join([skeleton.environment.run_dir, "agent", "codex", "home"])

      case role.adapter_key do
        "codex" ->
          :ok = File.mkdir_p(home)
          :ok = File.chmod(home, 0o700)

          {:ok,
           %{
             runtime: "Codex",
             executable: role.settings_json["executable_path"],
             home: home,
             login_args: "login --device-auth"
           }}

        "claude_code" ->
          {:ok,
           %{
             runtime: "Claude Code",
             executable: role.settings_json["executable_path"],
             helper: role.settings_json["api_key_helper"]
           }}

        "fake" ->
          {:ok, %{runtime: "Deterministic test adapter"}}

        _other ->
          {:error, :unsupported_runtime}
      end
    end
  end

  defp launch(skeleton, adapter, adapter_options, version, options) do
    run = Repo.get!(Cuckoding.Execution.Run, skeleton.run.id)
    skeleton = %{skeleton | run: run}

    work = fn ->
      result =
        WalkingSkeleton.run(skeleton,
          adapter: adapter,
          adapter_options: adapter_options,
          runtime_version: version,
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

  defp adapter(skeleton) do
    with {:ok, role} <- agent_role(skeleton.board.id) do
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

        "fake" ->
          {:ok, FakeAdapter, [], "test"}

        _other ->
          {:error, :unsupported_runtime}
      end
    end
  end

  defp probe(module, options) do
    case module.probe(options) do
      {:ok, %{authenticated?: true, version: version}} -> {:ok, module, options, version}
      {:ok, _probe} -> {:error, :run_scoped_auth_required}
      error -> error
    end
  end

  defp agent_role(board_id) do
    case Repo.get_by(RoleAssignment, board_id: board_id, role_key: "implementer") do
      %RoleAssignment{} = role -> {:ok, role}
      nil -> {:error, :role_assignment_not_found}
    end
  end

  defp settings(runtime, attrs) do
    with {:ok, executable} <- executable(attrs["executable_path"]),
         {:ok, helper} <- helper(runtime, attrs["api_key_helper"]) do
      {:ok,
       %{"executable_path" => executable}
       |> maybe_put("api_key_helper", helper)}
    end
  end

  defp executable(path) when is_binary(path) do
    expanded = Path.expand(path)

    if Path.type(path) == :absolute do
      case File.stat(expanded) do
        {:ok, %{type: :regular, mode: mode}} when Bitwise.band(mode, 0o111) != 0 ->
          {:ok, expanded}

        _other ->
          {:error, :invalid_runtime_executable}
      end
    else
      {:error, :invalid_runtime_executable}
    end
  end

  defp executable(_path), do: {:error, :invalid_runtime_executable}

  defp helper("codex", _path), do: {:ok, nil}
  defp helper("claude_code", path), do: executable(path)

  defp runtime(runtime) when runtime in @runtimes, do: {:ok, runtime}
  defp runtime(_runtime), do: {:error, :unsupported_runtime}

  defp workspace_root do
    Application.get_env(:cuckoding, :workspace_root) ||
      Application.fetch_env!(:cuckoding, Cuckoding.Repo)
      |> Keyword.fetch!(:database)
      |> Path.dirname()
      |> Path.join("workspaces")
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp block(run_id, reason \\ :workflow_failed) do
    case Execution.transition_run(run_id, "blocked", "guided:#{run_id}:blocked",
           wait_reason: "workflow failed; inspect the run evidence"
         ) do
      {:ok, _command} -> {:error, reason}
      {:error, transition_reason} -> {:error, {:block_failed, reason, transition_reason}}
    end
  end
end
