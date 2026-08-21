defmodule AgentDesk.Containers do
  @moduledoc """
  Optional Docker Compose execution for an isolated agent worktree.

  Off by default. Never runs against the user's primary checkout. Compose files
  that publish `0.0.0.0` or use host networking are rejected. Commands are an
  executable plus argument array, never a shell string.
  """

  alias AgentDesk.Agents.Session
  alias AgentDesk.Isolation
  alias AgentDesk.Projects
  alias AgentDesk.Projects.Project
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Discovery
  alias AgentDesk.Providers.Fixture
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope
  alias AgentDesk.Storage
  alias AgentDesk.Worktrees

  @compose_names ~w(compose.yaml compose.yml docker-compose.yml docker-compose.yaml)
  @timeout_ms 30_000

  @spec enabled?(Session.t()) :: boolean()
  def enabled?(%Session{settings: settings}) do
    settings["container"] in [true, "true"]
  end

  @spec start(Project.t(), Session.t()) :: :ok | {:error, term()}
  def start(%Project{} = project, %Session{} = session) do
    if enabled?(session), do: start_stack(project, session), else: :ok
  end

  @spec stop(Session.t()) :: :ok
  def stop(%Session{} = session) do
    if enabled?(session), do: down(session), else: :ok
  end

  @spec reconcile(Project.t()) :: :ok
  def reconcile(%Project{} = project) do
    project.id
    |> AgentDesk.Agents.list_sessions()
    |> Enum.filter(&enabled?/1)
    |> Enum.reject(&live_status?/1)
    |> Enum.each(&stop/1)

    :ok
  end

  @spec record_path(Session.t()) :: String.t()
  def record_path(%Session{} = session) do
    Path.join(Storage.session_dir(session.project_id, session.id), "compose-last.json")
  end

  defp live_status?(%Session{status: status}) do
    status in ~w(queued starting idle working waiting blocked)
  end

  defp start_stack(project, session) do
    dir = Worktrees.working_copy_path(project, session)

    with :ok <- assert_isolated_worktree(project, dir),
         {:ok, file} <- compose_file(dir),
         :ok <- assert_safe_compose(file),
         :ok <- claim(project, session),
         {:ok, spec} <- command_spec("up", session, dir) do
      run(spec)
    else
      {:error, :no_compose} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp down(session) do
    case Projects.get_project(session.project_id) do
      {:ok, project} ->
        dir = Worktrees.working_copy_path(project, session)

        case command_spec("down", session, dir) do
          {:ok, spec} ->
            _ = run(spec)
            :ok

          {:error, _} ->
            :ok
        end

      _ ->
        :ok
    end
  end

  defp assert_isolated_worktree(%Project{} = project, dir) do
    cond do
      Worktrees.shared_mode?() -> {:error, :primary_tree}
      Path.expand(dir) == Path.expand(project.canonical_path) -> {:error, :primary_tree}
      worktree?(project, dir) -> :ok
      true -> {:error, :outside_worktree}
    end
  end

  defp worktree?(%Project{id: project_id}, path) do
    Enum.any?(Worktrees.list_project(project_id), fn tree ->
      Path.expand(tree.path) == Path.expand(path)
    end)
  end

  defp compose_file(dir) do
    case Enum.find(@compose_names, &File.regular?(Path.join(dir, &1))) do
      nil -> {:error, :no_compose}
      name -> {:ok, Path.join(dir, name)}
    end
  end

  defp assert_safe_compose(path) do
    text = File.read!(path)

    cond do
      String.contains?(text, "0.0.0.0") -> {:error, :non_loopback_publish}
      String.contains?(text, "network_mode: host") -> {:error, :host_network}
      String.contains?(text, "privileged:") -> {:error, :privileged}
      true -> :ok
    end
  end

  defp claim(project, session) do
    scope = Scope.for_agent(project, session)
    key = "compose:" <> Isolation.compose_project(session)
    req = [%{"type" => "service", "key" => key, "mode" => "exclusive"}]

    case Manager.claim(scope, req, reason: "compose project") do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp command_spec(action, session, dir) do
    name = Isolation.compose_project(session)

    if fixtures?() do
      {:ok, fixture_spec(action, name, dir, session)}
    else
      host_spec(action, name, dir)
    end
  end

  defp fixtures? do
    Application.get_env(:agent_desk, :providers, [])[:use_fixtures] == true
  end

  defp fixture_spec(action, name, dir, session) do
    %CommandSpec{
      executable: Fixture.elixir_executable(),
      args:
        Fixture.code_path_args() ++
          [
            "-e",
            "AgentDesk.Containers.Fixture.main(System.argv())",
            "--",
            action,
            name,
            dir,
            record_path(session)
          ],
      cwd: dir,
      env: runtime_env(session, dir)
    }
  end

  defp host_spec(action, name, dir) do
    with {:ok, docker} <- Discovery.find_executable("docker") do
      {:ok,
       %CommandSpec{
         executable: docker,
         args: compose_args(action, name, dir),
         cwd: dir,
         env: %{
           "COMPOSE_PROJECT_NAME" => name,
           "AGENTDESK_BIND" => "127.0.0.1",
           "AGENTDESK_WORKDIR" => dir
         }
       }}
    end
  end

  defp compose_args("up", name, dir) do
    ["compose", "-p", name, "--project-directory", dir, "up", "-d", "--pull", "never"]
  end

  defp compose_args("down", name, dir) do
    ["compose", "-p", name, "--project-directory", dir, "down", "--remove-orphans"]
  end

  defp runtime_env(session, dir) do
    %{
      "COMPOSE_PROJECT_NAME" => Isolation.compose_project(session),
      "AGENTDESK_BIND" => "127.0.0.1",
      "AGENTDESK_WORKDIR" => dir,
      "AGENTDESK_TEST_DATABASE" => Isolation.test_database(session),
      "AGENTDESK_TEST_SCHEMA" => Isolation.test_schema(session)
    }
  end

  defp run(%CommandSpec{} = spec) do
    env = Enum.map(spec.env, fn {key, value} -> {key, value} end)

    task =
      Task.async(fn ->
        System.cmd(spec.executable, spec.args, cd: spec.cwd, env: env, stderr_to_stdout: true)
      end)

    case Task.yield(task, @timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {_out, 0}} -> :ok
      {:ok, {out, code}} -> {:error, {:compose_failed, code, String.slice(out, 0, 2_000)}}
      nil -> {:error, :timeout}
    end
  end
end
