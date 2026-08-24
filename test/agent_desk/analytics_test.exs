defmodule AgentDesk.AnalyticsTest do
  use AgentDesk.DataCase, async: false

  alias AgentDesk.Analytics
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Scope
  alias AgentDesk.Search
  alias AgentDesk.Search.Namespaces

  test "reports sqlite, memory, xerj, and exchange from canonical rows" do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)

    {:ok, session} =
      AgentDesk.Agents.create_session(Scope.for_project(project), %{
        provider: "fake",
        display_name: "Analyst"
      })

    ns = Namespaces.shared(project.id)
    scope = Scope.for_agent(project, session)
    assert {:ok, _} = Search.remember(scope, ns, %{text: "prefer isolated worktrees"})

    report = Analytics.report(project)

    assert report.sqlite.bytes >= 0
    assert Enum.any?(report.sqlite.tables, &(&1["name"] == "sessions" and &1["rows"] >= 1))
    assert Enum.any?(report.sqlite.tables, &(&1["name"] == "memories" and &1["rows"] >= 1))
    assert report.memory.total >= 1
    assert Enum.any?(report.memory.namespaces, &(&1["kind"] == "shared"))
    assert report.xerj.adapter in ["Projection", "Disabled", "Xerj"]
    assert report.runtime.total > 0
    assert report.runtime.process_count >= 1
    assert report.exchange.sessions >= 1
    assert report.exchange.usage["total_tokens"] == 0
  end
end
