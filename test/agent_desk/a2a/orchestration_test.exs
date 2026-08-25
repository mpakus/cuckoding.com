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

  test "agent splits create proposed delegations that require recipient acceptance", %{
    lead_scope: lead_scope,
    backend: backend,
    frontend: frontend,
    tester: tester
  } do
    assert {:ok, result} =
             Orchestration.split(lead_scope, %{
               goal: "Ship passwordless auth",
               prompt_lead: false
             })

    assert length(result["lanes"]) == 3
    assert result["lead_agent_id"] == lead_scope.agent_session.id

    tasks = A2A.list_tasks(lead_scope)
    parent = Enum.find(tasks, &(&1.id == result["parent_task_id"]))
    review = Enum.find(tasks, &(&1.id == result["review_task_id"]))

    assert parent.metadata["orchestration"]["kind"] == "parent"
    assert is_nil(review.assigned_agent_id)
    assert review.status == "blocked"

    assert {:error, :blocked_by_dependencies} =
             A2A.update_task(lead_scope, review, %{status: "completed"})

    assigned = Map.new(result["lanes"], &{&1["role"], &1["agent_id"]})
    assert assigned["backend"] == backend.id
    assert assigned["frontend"] == frontend.id
    assert assigned["tester"] == tester.id

    Enum.each(result["lanes"], fn lane ->
      task = Enum.find(tasks, &(&1.id == lane["task_id"]))
      assert task.status == "queued"
      assert is_nil(task.assigned_agent_id)
      assert task.parent_task_id == parent.id
    end)

    assert Enum.all?(A2A.list_delegations(lead_scope), &(&1.status == "proposed"))

    {:ok, memories} =
      Search.recall(lead_scope, Namespaces.shared(lead_scope.project.id), %{"q" => "Crew plan"})

    assert Enum.any?(memories, fn memory ->
             to_string(memory[:text] || memory["text"] || "") =~ "Ship passwordless auth"
           end)
  end

  test "notifies the lead when a specialist completes a lane", %{
    project_scope: project_scope,
    lead: lead,
    lead_scope: lead_scope,
    backend_scope: backend_scope
  } do
    {:ok, result} =
      Orchestration.start_crew(project_scope, %{
        goal: "Add billing webhook",
        lead_session_id: lead.id,
        lanes: ["backend"],
        spawn: false
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

  test "user-started crew reuses active specialists and auto-accepts assignments", %{
    project_scope: project_scope,
    lead: lead,
    frontend: frontend
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

    tasks = A2A.list_tasks(project_scope)
    lane = Enum.find(tasks, &(&1.id == hd(result["lanes"])["task_id"]))
    review = Enum.find(tasks, &(&1.id == result["review_task_id"]))

    assert lane.assigned_agent_id == frontend.id
    assert lane.status == "assigned"
    assert review.assigned_agent_id == lead.id
    assert Enum.all?(A2A.list_delegations(project_scope), &(&1.status == "accepted"))
  end

  test "crew targeting rejects role-mismatched, terminated, and hidden recipients", %{
    lead_scope: lead_scope,
    backend: backend,
    frontend: frontend
  } do
    assert {:error, :forbidden} =
             Orchestration.split(lead_scope, %{
               goal: "Target arbitrary session",
               lanes: [
                 %{
                   "key" => "frontend",
                   "role" => "frontend",
                   "recipient_agent_id" => backend.id
                 }
               ]
             })

    {:ok, terminated_backend} = Agents.update_session(backend, %{status: "terminated"})

    assert {:error, :forbidden} =
             Orchestration.split(lead_scope, %{
               goal: "Target terminated specialist",
               lanes: [
                 %{
                   "key" => "backend",
                   "role" => "backend",
                   "recipient_agent_id" => terminated_backend.id
                 }
               ]
             })

    {:ok, hidden_frontend} = Agents.hide_tab(frontend)

    assert {:error, :forbidden} =
             Orchestration.split(lead_scope, %{
               goal: "Target hidden specialist",
               lanes: [
                 %{
                   "key" => "frontend",
                   "role" => "frontend",
                   "recipient_agent_id" => hidden_frontend.id
                 }
               ]
             })

    assert A2A.list_tasks(lead_scope) == []
  end
end
