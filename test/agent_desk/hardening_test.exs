defmodule AgentDesk.HardeningTest do
  use AgentDesk.DataCase

  alias AgentDesk.A2A
  alias AgentDesk.Agents
  alias AgentDesk.Backup
  alias AgentDesk.Circuit
  alias AgentDesk.Clock
  alias AgentDesk.Diagnostics
  alias AgentDesk.Events
  alias AgentDesk.GitRepo
  alias AgentDesk.MCP.Protocol
  alias AgentDesk.Projects
  alias AgentDesk.Projects.Supervisor, as: ProjectSupervisor
  alias AgentDesk.Providers
  alias AgentDesk.Reconcile
  alias AgentDesk.Repo
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope
  alias AgentDesk.Security.Capability
  alias AgentDesk.Security.Loopback
  alias AgentDesk.Worktrees

  setup do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)

    {:ok, alice} =
      Agents.create_session(Scope.for_project(project), %{provider: "fake", display_name: "Alice"})

    {:ok, project: project, alice: alice, repo: repo}
  end

  test "HTTP control plane is loopback-only" do
    assert Loopback.loopback?(Loopback.endpoint_ip())
    assert :ok = Loopback.assert!()
  end

  test "reconciliation expires leases and tokens without resurrecting them", %{
    project: project,
    alice: alice
  } do
    scope = Scope.for_agent(project, alice)

    {:ok, [lease]} =
      Manager.claim(scope, [%{"type" => "file", "key" => "a.ex", "mode" => "shared"}])

    {:ok, token, alice} = Capability.issue(alice)

    past = DateTime.add(Clock.utc_now(), -10, :second)

    lease
    |> Ecto.Changeset.change(%{expires_at: past})
    |> Repo.update!()

    alice
    |> Ecto.Changeset.change(%{capability_expires_at: past})
    |> Repo.update!()

    assert :ok = Reconcile.project(project)
    assert Manager.list_project(project.id) == []
    assert {:error, :unauthorized} = Capability.authenticate(token)
  end

  test "observer profile cannot claim resources", %{alice: alice} do
    {:ok, alice} =
      Agents.update_session(alice, %{settings: %{"permission_profile" => "observer"}})

    assert {:error, %{"error" => %{"message" => message}}} =
             Protocol.handle(alice, %{
               "id" => 1,
               "method" => "tools/call",
               "params" => %{
                 "name" => "hub_claim_resources",
                 "arguments" => %{"resources" => []}
               }
             })

    assert message =~ "forbidden"
  end

  test "rotating a capability invalidates the previous token", %{alice: alice} do
    {:ok, token, alice} = Capability.issue(alice)
    {:ok, _new_token, _} = Capability.rotate(alice)
    assert {:error, :unauthorized} = Capability.authenticate(token)
  end

  test "circuit opens after repeated provider failures" do
    Circuit.reset("provider:fake")
    Enum.each(1..5, fn _ -> Circuit.failure("provider:fake") end)
    refute Circuit.allow?("provider:fake")
    Circuit.reset("provider:fake")
    assert Circuit.allow?("provider:fake")
  end

  test "diagnostic export redacts secret fixtures", %{project: project} do
    {:ok, _} =
      Events.append(%{
        project_id: project.id,
        type: "provider.debug",
        source: "test",
        payload: %{"api_key" => "sk-secretfixturevalue", "note" => "ok"}
      })

    assert {:ok, path} = Diagnostics.export(project)
    body = File.read!(path)
    refute body =~ "sk-secretfixturevalue"
    assert body =~ "[REDACTED]"
  end

  test "sqlite snapshot copy lands in the backup directory" do
    src =
      Path.join(System.tmp_dir!(), "agentdesk-src-#{System.unique_integer([:positive])}.sqlite3")

    File.write!(src, "fixture")
    previous = Application.get_env(:agent_desk, AgentDesk.Repo)

    try do
      Application.put_env(:agent_desk, AgentDesk.Repo, Keyword.put(previous, :database, src))
      assert {:ok, path} = Backup.snapshot()
      assert File.exists?(path)
      assert path =~ "backups"
      assert File.read!(path) == "fixture"
    after
      Application.put_env(:agent_desk, AgentDesk.Repo, previous)
    end
  end

  test "stopping a runtime preserves a dirty worktree", %{project: project} do
    {:ok, session} =
      Providers.start_session(Scope.for_project(project), %{provider: "fake", display_name: "WT"})

    worktree = Worktrees.get_for_session(session.id)
    File.write!(Path.join(worktree.path, "keep.txt"), "preserve me\n")
    :ok = ProjectSupervisor.stop_runtime(project.id)
    assert File.read!(Path.join(worktree.path, "keep.txt")) == "preserve me\n"
  end

  test "four agents can broadcast without exceeding a local budget", %{project: project} do
    sessions =
      Enum.map(1..4, fn n ->
        {:ok, session} =
          Providers.start_session(Scope.for_project(project), %{
            provider: "fake",
            display_name: "Load #{n}"
          })

        session
      end)

    [first | _] = sessions
    scope = Scope.for_agent(project, first)

    {:ok, _card} =
      A2A.register_card(scope, %{
        name: first.display_name,
        description: "load",
        skills: [%{"name" => "elixir"}]
      })

    {:ok, context} = A2A.create_context(scope, %{title: "Load"})

    {us, {:ok, _}} =
      :timer.tc(fn ->
        A2A.broadcast(scope, %{
          context_id: context.id,
          body: "status",
          idempotency_key: "load-broadcast"
        })
      end)

    assert us < 5_000_000
    assert match?([_ | _], A2A.list_agents(Scope.for_project(project)))
  end
end
