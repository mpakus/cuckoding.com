defmodule AgentDesk.A2A.OrchestrationTest do
  use AgentDesk.DataCase

  alias AgentDesk.A2A
  alias AgentDesk.A2A.Orchestration
  alias AgentDesk.A2A.Task
  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Repo
  alias AgentDesk.Scope
  alias AgentDesk.Search
  alias AgentDesk.Search.Namespaces

  setup do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    on_exit(fn -> AgentDesk.Projects.Supervisor.stop_runtime(project.id) end)
    project_scope = Scope.for_project(project)

    {:ok, lead} =
      Agents.create_session(project_scope, %{
        provider: "fake",
        display_name: "Lead",
        role: "lead"
      })

    {:ok, backend} =
      Agents.create_session(project_scope, %{
        provider: "fake",
        display_name: "Backend",
        role: "backend"
      })

    {:ok, frontend} =
      Agents.create_session(project_scope, %{
        provider: "fake",
        display_name: "Frontend",
        role: "frontend"
      })

    {:ok, tester} =
      Agents.create_session(project_scope, %{
        provider: "fake",
        display_name: "Tester",
        role: "tester"
      })

    %{
      project: project,
      project_scope: project_scope,
      lead: lead,
      backend: backend,
      frontend: frontend,
      tester: tester,
      lead_scope: Scope.for_agent(project, lead),
      backend_scope: Scope.for_agent(project, backend)
    }
  end

  test "splits a goal into lane tasks, review, memory, and accepted delegations", %{
    lead_scope: lead_scope,
    backend: backend,
    frontend: frontend,
    tester: tester
  } do
    assert {:ok, result} =
             Orchestration.split(lead_scope, %{
               goal: "Ship passwordless auth",
               auto_accept: true,
               prompt_lead: false
             })

    assert length(result["lanes"]) == 3
    assert result["lead_agent_id"] == lead_scope.agent_session.id

    tasks = A2A.list_tasks(lead_scope)
    parent = Enum.find(tasks, &(&1.id == result["parent_task_id"]))
    review = Enum.find(tasks, &(&1.id == result["review_task_id"]))

    assert parent.metadata["orchestration"]["kind"] == "parent"
    assert review.assigned_agent_id == lead_scope.agent_session.id
    assert review.status == "blocked"

    assert {:error, :blocked_by_dependencies} =
             A2A.update_task(lead_scope, review, %{status: "completed"})

    assigned = Map.new(result["lanes"], &{&1["role"], &1["agent_id"]})
    assert assigned["backend"] == backend.id
    assert assigned["frontend"] == frontend.id
    assert assigned["tester"] == tester.id

    Enum.each(result["lanes"], fn lane ->
      task = Enum.find(tasks, &(&1.id == lane["task_id"]))
      assert task.status == "assigned"
      assert task.assigned_agent_id == lane["agent_id"]
      assert task.parent_task_id == parent.id
    end)

    {:ok, memories} =
      Search.recall(lead_scope, Namespaces.shared(lead_scope.project.id), %{"q" => "Crew plan"})

    assert Enum.any?(memories, fn memory ->
             to_string(memory[:text] || memory["text"] || "") =~ "Ship passwordless auth"
           end)
  end

  test "notifies the lead when a specialist completes a lane", %{
    lead_scope: lead_scope,
    backend_scope: backend_scope
  } do
    {:ok, result} =
      Orchestration.split(lead_scope, %{
        goal: "Add billing webhook",
        lanes: ["backend"],
        auto_accept: true,
        prompt_lead: false
      })

    [lane] = result["lanes"]
    task = Repo.get!(Task, lane["task_id"])

    assert {:ok, _updated} = A2A.update_task(backend_scope, task, %{status: "completed"})

    inbox = A2A.inbox(lead_scope)
    bodies = Enum.map(inbox, fn delivery -> delivery.message.body end)
    assert Enum.any?(bodies, &(&1 =~ "Add billing webhook" or &1 =~ "Backend"))
    assert Enum.any?(bodies, &(&1 =~ "completed"))
    assert Enum.any?(bodies, &(&1 =~ "All 1 lanes finished"))

    review = Repo.get!(Task, result["review_task_id"])
    assert review.status == "queued"
  end

  test "start_crew reuses role-matched sessions without spawning", %{
    project_scope: project_scope,
    lead: lead
  } do
    assert {:ok, result} =
             Orchestration.start_crew(project_scope, %{
               goal: "Fix dashboard",
               lead_session_id: lead.id,
               lanes: ["frontend"],
               spawn: false
             })

    assert [%{"role" => "frontend"}] = result["lanes"]
    assert result["lead_agent_id"] == lead.id
  end
end
