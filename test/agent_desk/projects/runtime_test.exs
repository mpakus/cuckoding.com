defmodule AgentDesk.Projects.RuntimeTest do
  use AgentDesk.DataCase

  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Projects.Runtime
  alias AgentDesk.Projects.Runtime.Slot
  alias AgentDesk.Providers
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Resources.Lease
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope
  alias AgentDesk.Security.Capability

  setup do
    repo = GitRepo.tmp_repo!("agentdesk-project-runtime")
    {:ok, project} = Projects.open_project(repo)
    on_exit(fn -> Projects.Supervisor.stop_runtime(project.id) end)
    %{project: project}
  end

  test "restarts a crashed project child without replacing siblings", %{project: project} do
    {:ok, runtime} = Runtime.fetch(project.id)
    a2a_supervisor = registry_pid(AgentDesk.A2ASupervisorRegistry, project.id)
    search_supervisor = registry_pid(AgentDesk.SearchSupervisorRegistry, project.id)
    provider_supervisor = registry_pid(AgentDesk.ProviderSupervisorRegistry, project.id)
    ref = Process.monitor(search_supervisor)

    Process.exit(search_supervisor, :kill)
    assert_receive {:DOWN, ^ref, :process, ^search_supervisor, :killed}

    assert AgentDesk.DataCase.wait_until(fn ->
             case Registry.lookup(AgentDesk.SearchSupervisorRegistry, project.id) do
               [{pid, _}] when pid != search_supervisor -> pid
               _ -> false
             end
           end)

    assert Runtime.fetch(project.id) == {:ok, runtime}
    assert Process.alive?(a2a_supervisor)
    assert Process.alive?(provider_supervisor)
  end

  test "restarts a crashed nested worker under its subsystem supervisor", %{project: project} do
    a2a_supervisor = registry_pid(AgentDesk.A2ASupervisorRegistry, project.id)
    hub = registry_pid(AgentDesk.HubRegistry, project.id)
    ref = Process.monitor(hub)

    Process.exit(hub, :kill)
    assert_receive {:DOWN, ^ref, :process, ^hub, :killed}

    assert AgentDesk.DataCase.wait_until(fn ->
             case Registry.lookup(AgentDesk.HubRegistry, project.id) do
               [{pid, _}] when pid != hub -> pid
               _ -> false
             end
           end)

    assert Process.alive?(a2a_supervisor)
  end

  test "runtime crash restarts the subtree and reconciles durable state", %{project: project} do
    {:ok, session} =
      Agents.create_session(Scope.for_project(project), %{
        provider: "fake",
        display_name: "Lost provider",
        status: "working"
      })

    {:ok, token, session} = Capability.issue(session)

    {:ok, [lease]} =
      Manager.claim(
        Scope.for_agent(project, session),
        [%{"type" => "file", "key" => "lib/lost.ex", "mode" => "exclusive"}],
        ttl_seconds: 3_600
      )

    {:ok, runtime} = Runtime.fetch(project.id)
    ref = Process.monitor(runtime)
    Process.exit(runtime, :kill)
    assert_receive {:DOWN, ^ref, :process, ^runtime, :killed}

    assert AgentDesk.DataCase.wait_until(fn ->
             case Runtime.fetch(project.id) do
               {:ok, pid} when pid != runtime ->
                 case Registry.lookup(AgentDesk.SearchSupervisorRegistry, project.id) do
                   [{search_supervisor, _}] when is_pid(search_supervisor) -> pid
                   _ -> false
                 end

               _ ->
                 false
             end
           end)

    assert AgentDesk.DataCase.wait_until(fn ->
             Repo.get!(Agents.Session, session.id).status == "interrupted"
           end)

    assert AgentDesk.DataCase.wait_until(fn ->
             Capability.authenticate(token) == {:error, :unauthorized}
           end)

    assert AgentDesk.DataCase.wait_until(fn ->
             Repo.get!(Lease, lease.id).status == "expired"
           end)
  end

  test "stopping a runtime stops its provider session workers", %{project: project} do
    assert {:ok, session} =
             Providers.start_session(Scope.for_project(project), %{
               provider: "fake",
               display_name: "Supervised provider"
             })

    assert {:ok, worker} = SessionWorker.fetch(session.id)
    ref = Process.monitor(worker)

    assert :ok = Projects.Supervisor.stop_runtime(project.id)
    assert_receive {:DOWN, ^ref, :process, ^worker, _reason}
    assert SessionWorker.fetch(session.id) == {:error, :not_started}
    assert Runtime.fetch(project.id) == {:error, :not_started}
  end

  test "concurrent crash and explicit stop cannot restart a closed runtime", %{project: project} do
    Enum.each(1..25, fn _iteration ->
      assert {:ok, runtime} = Projects.Supervisor.start_runtime(project)
      parent = self()

      crasher =
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go ->
              _ = Process.exit(runtime, :kill)
              :ok
          end
        end)

      stopper =
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> Projects.Supervisor.stop_runtime(project.id)
          end
        end)

      assert_receive {:ready, crasher_pid}
      assert_receive {:ready, stopper_pid}
      send(crasher_pid, :go)
      send(stopper_pid, :go)

      assert :ok = Task.await(crasher)
      assert :ok = Task.await(stopper)
      assert Runtime.fetch(project.id) == {:error, :not_started}
      assert Slot.fetch(project.id) == {:error, :not_started}
    end)
  end

  test "a project exhausting its restart budget does not collapse another runtime" do
    repo_a = GitRepo.tmp_repo!("agentdesk-project-isolation-a")
    repo_b = GitRepo.tmp_repo!("agentdesk-project-isolation-b")
    {:ok, project_a} = Projects.open_project(repo_a)
    {:ok, project_b} = Projects.open_project(repo_b)
    on_exit(fn -> Projects.Supervisor.stop_runtime(project_a.id) end)
    on_exit(fn -> Projects.Supervisor.stop_runtime(project_b.id) end)

    {:ok, slot_a} = Slot.fetch(project_a.id)
    {:ok, runtime_b} = Runtime.fetch(project_b.id)
    slot_ref = Process.monitor(slot_a)

    Enum.reduce(1..4, nil, fn iteration, previous ->
      runtime_a = await_runtime(project_a.id, previous)
      runtime_ref = Process.monitor(runtime_a)
      Process.exit(runtime_a, :kill)
      assert_receive {:DOWN, ^runtime_ref, :process, ^runtime_a, :killed}

      if iteration < 4, do: runtime_a
    end)

    assert_receive {:DOWN, ^slot_ref, :process, ^slot_a, :shutdown}
    assert Runtime.fetch(project_a.id) == {:error, :not_started}
    assert Runtime.fetch(project_b.id) == {:ok, runtime_b}
    assert Process.alive?(runtime_b)
    assert Process.alive?(Process.whereis(Projects.Supervisor))
  end

  test "restarts open projects and reruns reconciliation after project supervisor restart", %{
    project: project
  } do
    {:ok, session} =
      Agents.create_session(Scope.for_project(project), %{
        provider: "fake",
        display_name: "Restart orphan",
        status: "working"
      })

    assert :ok =
             Supervisor.terminate_child(AgentDesk.Supervisor, AgentDesk.Projects.Supervisor)

    assert {:ok, _supervisor} =
             Supervisor.restart_child(AgentDesk.Supervisor, AgentDesk.Projects.Supervisor)

    assert :ok = AgentDesk.Projects.Restorer.await()
    assert {:ok, runtime} = Runtime.fetch(project.id)
    assert Process.alive?(runtime)

    assert AgentDesk.DataCase.wait_until(fn ->
             Repo.get!(Agents.Session, session.id).status == "interrupted"
           end)
  end

  defp registry_pid(registry, project_id) do
    assert [{pid, _value}] = Registry.lookup(registry, project_id)
    pid
  end

  defp await_runtime(project_id, previous, attempts \\ 20_000)

  defp await_runtime(_project_id, _previous, 0) do
    flunk("project runtime did not restart")
  end

  defp await_runtime(project_id, previous, attempts) do
    case Runtime.fetch(project_id) do
      {:ok, pid} when pid != previous ->
        pid

      _other ->
        receive do
        after
          0 -> await_runtime(project_id, previous, attempts - 1)
        end
    end
  end
end
