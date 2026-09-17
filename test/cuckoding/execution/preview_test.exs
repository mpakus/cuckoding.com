defmodule Cuckoding.Execution.PreviewTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution
  alias Cuckoding.Execution.CommandPolicy
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.Leases
  alias Cuckoding.Execution.LocalHostInspector
  alias Cuckoding.Execution.LocalProcessRunner
  alias Cuckoding.Execution.PortAllocator
  alias Cuckoding.Execution.Preview
  alias Cuckoding.Execution.WorktreeOpener
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows

  @now ~U[2026-09-17 22:25:00.000000Z]

  defmodule FailingRunner do
    def start(_environment, _command, _options), do: {:error, :launch_failed}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "cuckoding-preview-#{System.unique_integer([:positive])}")
    fixture = Path.expand("../../fixtures/preview_project", __DIR__)
    File.cp_r!(fixture, root)
    git!(root, ["init", "-b", "main"])
    git!(root, ["config", "user.email", "fixture@example.test"])
    git!(root, ["config", "user.name", "Fixture"])
    git!(root, ["add", "--all"])
    git!(root, ["commit", "-m", "base"])

    first_port = free_range(6)
    domain = domain_fixture(root, first_port, first_port + 5)

    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root, domain: domain}
  end

  test "concurrent allocations never collide and release on hibernate", %{domain: domain} do
    environments = for sequence <- 1..6, do: run_environment(domain, sequence)

    allocations =
      environments
      |> Task.async_stream(
        fn {_run, environment} -> PortAllocator.allocate(domain.project, environment) end,
        ordered: false,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, {:ok, allocation}} -> allocation end)

    ports = Enum.map(allocations, & &1.environment.port)
    assert length(Enum.uniq(ports)) == 6
    assert Enum.all?(ports, &(&1 in domain.first_port..domain.last_port))
    assert Enum.all?(allocations, &(&1.token != &1.lease.token_hash))

    {_overflow_run, overflow_environment} = run_environment(domain, 7)

    assert {:error, :no_ports_available} =
             PortAllocator.allocate(domain.project, overflow_environment)

    assert {:ok, _renewed} = PortAllocator.heartbeat(hd(allocations), 60_000)

    Enum.each(allocations, fn allocation ->
      assert {:ok, %{state: "hibernated", port: nil, preview_url: nil}} =
               PortAllocator.release(allocation, "hibernated")

      refute Leases.active_for("port", "tcp:127.0.0.1:#{allocation.environment.port}")
    end)
  end

  test "declared sample server becomes healthy, is owned, stops, and reallocates", %{
    domain: domain
  } do
    {run, environment} = run_environment(domain, 1)
    assert {:ok, ^environment} = LocalProcessRunner.prepare(environment, [])
    assert {:ok, allocation} = PortAllocator.allocate(domain.project, environment)
    assert allocation.environment.preview_url == "http://127.0.0.1:#{allocation.environment.port}"

    assert {:ok, service} = Preview.start(run, allocation, termination_grace_ms: 25)

    on_exit(fn ->
      LocalProcessRunner.destroy(allocation.environment, grace_ms: 25)
      PortAllocator.release(allocation, "stopped")
    end)

    assert :ok = await_health(service)
    assert {:ok, :healthy} = Preview.health(service)

    assert {:ok, owner_pid, identity} =
             LocalHostInspector.port_owner(allocation.environment.port, [])

    assert owner_pid == service.handle.process.pid
    assert identity == service.handle.process.start_identity

    assert {:error, :non_loopback_preview_url} =
             Preview.probe("http://example.com:#{allocation.environment.port}")

    assert {:ok, stopped} = Preview.stop(service)
    assert stopped.state == "stopped"
    assert is_nil(stopped.port)
    assert PortAllocator.available?(allocation.environment.port)
    assert {:ok, :unavailable} = Preview.probe(allocation.environment.preview_url)

    resumed = Repo.get!(Environment, environment.id)
    assert {:ok, resumed_allocation} = PortAllocator.allocate(domain.project, resumed)
    assert resumed_allocation.lease.id != allocation.lease.id
    assert resumed_allocation.environment.state == "prepared"
    assert {:ok, _hibernated} = PortAllocator.release(resumed_allocation, "hibernated")
  end

  test "failed dev-server launch releases its allocation", %{domain: domain} do
    {run, environment} = run_environment(domain, 1)
    assert {:ok, allocation} = PortAllocator.allocate(domain.project, environment)

    assert {:error, :launch_failed} = Preview.start(run, allocation, runner: FailingRunner)
    refute Leases.active_for("port", "tcp:127.0.0.1:#{allocation.environment.port}")
    assert %{state: "failed", port: nil} = Repo.get!(Environment, environment.id)
  end

  test "worktree actions open only the recorded canonical directory", %{domain: domain} do
    {_run, environment} = run_environment(domain, 1)
    test_pid = self()

    launcher = fn executable, args ->
      send(test_pid, {:launch, executable, args})
      {"", 0}
    end

    assert :ok = WorktreeOpener.open(environment, :finder, launcher: launcher)
    assert_receive {:launch, "/usr/bin/open", [finder_path]}
    assert finder_path == physical_path(environment.worktree_path)

    assert :ok =
             WorktreeOpener.open(environment, :editor,
               launcher: launcher,
               editor_application: "Cursor"
             )

    assert_receive {:launch, "/usr/bin/open", ["-a", "Cursor", ^finder_path]}

    assert {:error, :invalid_editor_application} =
             WorktreeOpener.open(environment, :editor,
               launcher: launcher,
               editor_application: "Cursor\n--args"
             )

    refute_received {:launch, _, _}
  end

  defp domain_fixture(root, first_port, last_port) do
    {:ok, loaded} = CommandPolicy.load_project(Path.join(root, ".cuckoding/project.yml"))
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Preview project #{suffix}",
        repo_path: root,
        default_branch: "main",
        workspace_root: Path.dirname(root),
        port_range_start: first_port,
        port_range_end: last_port
      })

    {:ok, policy} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: loaded.source_hash,
        config_json: loaded.config,
        trusted_at: @now
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "default",
        version: 1,
        definition_json: %{"stages" => []},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Board",
        concurrency_limit: 4
      })

    %{
      project: project,
      policy: policy,
      board: board,
      base_sha: git!(root, ["rev-parse", "HEAD"]),
      root: root,
      first_port: first_port,
      last_port: last_port
    }
  end

  defp run_environment(domain, sequence) do
    {:ok, task} =
      Workflows.create_task(%{
        board_id: domain.board.id,
        title: "Preview #{sequence}",
        position: sequence
      })

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: domain.policy.id,
        plugin_snapshot_json: %{},
        branch: "feature/preview-#{System.unique_integer([:positive])}",
        base_sha: domain.base_sha
      })

    worktree = Path.join(domain.root, ".worktree-#{sequence}-#{run.id}")
    run_dir = Path.join(domain.root, ".run-#{sequence}-#{run.id}")
    File.mkdir_p!(worktree)
    File.mkdir_p!(run_dir)

    File.cp!(
      Path.join(domain.root, "preview_server.rb"),
      Path.join(worktree, "preview_server.rb")
    )

    {:ok, environment} =
      Execution.create_environment(%{
        run_id: run.id,
        runner_key: "local_process",
        kind: "local_process",
        worktree_path: worktree,
        run_dir: run_dir,
        base_sha: domain.base_sha,
        head_sha: domain.base_sha,
        ports_json: %{},
        isolation_claims_json: %{"sandbox" => false}
      })

    {run, environment}
  end

  defp free_range(size) do
    Enum.find(45_000..60_000, fn first ->
      Enum.all?(first..(first + size - 1), &PortAllocator.available?/1)
    end) || raise "no consecutive loopback ports available"
  end

  defp await_health(service, attempts \\ 50)
  defp await_health(_service, 0), do: {:error, :health_timeout}

  defp await_health(service, attempts) do
    case Preview.health(service, connect_timeout: 100, request_timeout: 100) do
      {:ok, :healthy} ->
        :ok

      _other ->
        Process.sleep(20)
        await_health(service, attempts - 1)
    end
  end

  defp git!(root, args) do
    case System.cmd("/usr/bin/git", ["-C", root | args], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "git failed (#{status}): #{output}"
    end
  end

  defp physical_path(path) do
    {resolved, 0} = System.cmd("/bin/pwd", ["-P"], cd: path)
    String.trim(resolved)
  end
end
