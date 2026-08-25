defmodule AgentDesk.SearchTest do
  use AgentDesk.DataCase

  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.MCP.Protocol
  alias AgentDesk.Projects
  alias AgentDesk.Providers
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope
  alias AgentDesk.Search
  alias AgentDesk.Search.Indexer
  alias AgentDesk.Search.Namespaces

  setup do
    repo = GitRepo.tmp_repo!()
    File.write!(Path.join(repo, "DECISIONS.md"), "Use SQLite as canonical store.\n")
    File.write!(Path.join(repo, ".env"), "SECRET=should-not-index\n")
    File.mkdir_p!(Path.join(repo, "deps/foo"))
    File.write!(Path.join(repo, "deps/foo/lib.ex"), "should not index\n")
    {:ok, project} = Projects.open_project(repo)

    {:ok, alice} =
      Agents.create_session(Scope.for_project(project), %{provider: "fake", display_name: "Alice"})

    {:ok, project: project, alice: alice, repo: repo}
  end

  test "disabled search is unavailable, not an indexer error", %{project: project} do
    put_search_config(adapter: :disabled)

    assert {:error, :unavailable} = Indexer.index_project(project)
    status = Search.status(project)
    assert status.status == "unavailable"
    assert status.adapter == "Disabled"
    assert is_nil(status.error)
  end

  test "missing project state returns a tagged index status error without raising", %{
    project: project
  } do
    missing = %{project | id: Ecto.UUID.generate()}

    assert {:error, {:index_status_unavailable, _reason}} =
             Indexer.index_project(missing)
  end

  test "closing stops the debouncer before the project directory is deleted", %{
    project: project,
    repo: repo
  } do
    assert [{debouncer, _value}] = Registry.lookup(AgentDesk.SearchRegistry, project.id)
    ref = Process.monitor(debouncer)

    assert :ok = Projects.close_project(project)
    assert_receive {:DOWN, ^ref, :process, ^debouncer, _reason}

    File.rm_rf!(repo)
    assert Registry.lookup(AgentDesk.SearchRegistry, project.id) == []
    assert Registry.lookup(AgentDesk.SearchSupervisorRegistry, project.id) == []
  end

  test "indexes a fixture repository and returns bounded attributed results", %{
    project: project
  } do
    assert :ok = Indexer.index_project(project)

    assert {:ok, results} = Search.search(Scope.for_project(project), %{"q" => "canonical"})
    assert [%{source: "project_file", source_id: "DECISIONS.md", passage: passage} | _] = results
    assert String.contains?(passage, "SQLite")
    assert byte_size(passage) <= 1_200

    refute Enum.any?(results, &String.contains?(&1.passage || "", "SECRET"))
    refute Enum.any?(results, &(&1.source_id == "deps/foo/lib.ex"))
  end

  test "auto search uses the SQLite projection when XERJ is off", %{project: project} do
    put_search_config(adapter: :auto)
    AgentDesk.Search.put_xerj(false)

    assert Search.adapter() == AgentDesk.Search.Projection
    assert :ok = Indexer.index_project(project)
    status = Search.status(project)
    assert status.adapter == "Projection"
    assert status.status in ["ready", "indexing"]
    refute status.status == "error"
  end

  test "namespace authorization denies cross-project memory", %{project: project, alice: alice} do
    scope = Scope.for_agent(project, alice)
    ns = Namespaces.shared(project.id)
    other = Namespaces.shared(Ecto.UUID.generate())

    assert {:ok, memory} = Search.remember(scope, ns, %{text: "prefer isolated worktrees"})
    assert {:ok, [hit]} = Search.recall(scope, ns, %{"q" => "worktrees"})
    assert hit.text =~ "isolated"
    assert :ok = Search.forget(scope, ns, memory.id)
    assert {:ok, []} = Search.recall(scope, ns, %{"q" => "worktrees"})
    assert {:error, :forbidden} = Search.recall(scope, other, %{"q" => "worktrees"})
  end

  test "deleting search data and rebuilding leaves sessions and leases intact", %{
    project: project,
    alice: alice
  } do
    scope = Scope.for_agent(project, alice)
    assert :ok = Indexer.index_project(project)

    {:ok, [lease]} =
      Manager.claim(scope, [%{"type" => "file", "key" => "README.md", "mode" => "shared"}])

    assert :ok = Search.rebuild(project)
    assert {:ok, results} = Search.search(Scope.for_project(project), %{"q" => "fixture"})
    assert Enum.any?(results, &(&1.source_id == "README.md"))

    {:ok, session} = Agents.get_session(Scope.for_project(project), alice.id)
    assert session.id == alice.id
    assert [%{id: id}] = Manager.list_project(project.id)
    assert id == lease.id
  end

  test "provider sessions continue while search is unavailable", %{project: project} do
    put_search_config(adapter: :disabled)

    assert {:error, :unavailable} = Search.search(Scope.for_project(project), %{"q" => "x"})

    {:ok, session} =
      Providers.start_session(Scope.for_project(project), %{
        provider: "fake",
        display_name: "Scout"
      })

    assert {:ok, pid} = SessionWorker.fetch(session.id)
    assert Process.alive?(pid)
  end

  test "MCP search tools return unavailable when search is disabled", %{alice: alice} do
    put_search_config(adapter: :disabled)

    assert {:ok, %{"result" => %{"error" => "unavailable"}}} =
             Protocol.handle(alice, %{
               "id" => 9,
               "method" => "tools/call",
               "params" => %{"name" => "project_search", "arguments" => %{"q" => "sqlite"}}
             })
  end

  test "four simultaneous fake sessions record process identity", %{project: project} do
    sessions =
      Enum.map(1..4, fn n ->
        {:ok, session} =
          Providers.start_session(Scope.for_project(project), %{
            provider: "fake",
            display_name: "Agent #{n}"
          })

        session
      end)

    Enum.each(sessions, fn session ->
      assert {:ok, pid} = SessionWorker.fetch(session.id)
      assert Process.alive?(pid)
      reloaded = AgentDesk.Repo.get!(AgentDesk.Agents.Session, session.id)
      assert is_integer(reloaded.process_identity["os_pid"])
    end)
  end

  defp put_search_config(config) do
    previous = Application.fetch_env(:agent_desk, :search)
    Application.put_env(:agent_desk, :search, config)
    on_exit(fn -> restore_search_config(previous) end)
  end

  defp restore_search_config({:ok, config}),
    do: Application.put_env(:agent_desk, :search, config)

  defp restore_search_config(:error), do: Application.delete_env(:agent_desk, :search)
end
