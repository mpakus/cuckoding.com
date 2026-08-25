defmodule AgentDesk.ReconcileAcceptanceTest do
  use AgentDesk.DataCase

  alias AgentDesk.A2A
  alias AgentDesk.A2A.Delivery
  alias AgentDesk.A2A.MessageRouter
  alias AgentDesk.A2A.Task
  alias AgentDesk.Agents
  alias AgentDesk.Clock
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Reconcile
  alias AgentDesk.Resources.Lease
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope
  alias AgentDesk.Security.Capability

  test "restart reconciliation revokes orphan capabilities, leases, and uncertain delivery" do
    repo = GitRepo.tmp_repo!("agentdesk-reconcile-acceptance")
    {:ok, project} = Projects.open_project(repo)
    on_exit(fn -> Projects.Supervisor.stop_runtime(project.id) end)
    project_scope = Scope.for_project(project)

    {:ok, sender} =
      Agents.create_session(project_scope, %{
        provider: "fake",
        display_name: "Sender",
        status: "idle"
      })

    {:ok, orphan} =
      Agents.create_session(project_scope, %{
        provider: "fake",
        display_name: "Orphan",
        status: "working",
        process_identity: %{"os_pid" => 999_999, "port" => "#Port<0.999>"}
      })

    orphan_scope = Scope.for_agent(project, orphan)
    {:ok, token, orphan} = Capability.issue(orphan)
    assert {:ok, _session} = Capability.authenticate(token)

    {:ok, [lease]} =
      Manager.claim(
        orphan_scope,
        [%{"type" => "file", "key" => "lib/orphan.ex", "mode" => "exclusive"}],
        ttl_seconds: 3_600,
        reason: "provider work"
      )

    {:ok, context} = A2A.create_context(Scope.for_agent(project, sender), %{title: "Recovery"})

    {:ok, task} =
      A2A.create_task(Scope.for_agent(project, sender), context, %{title: "Interrupted work"})

    task =
      task
      |> Task.changeset(%{assigned_agent_id: orphan.id, status: "working"})
      |> Repo.update!()

    {:ok, message} =
      A2A.send_direct_message(Scope.for_agent(project, sender), %{
        context_id: context.id,
        recipient_agent_id: orphan.id,
        body: "Continue after restart",
        idempotency_key: "reconcile-uncertain-delivery"
      })

    delivery =
      Repo.get_by!(Delivery, message_id: message.id, agent_session_id: orphan.id)

    delivery
    |> Delivery.changeset(%{
      state: "injected",
      attempt_count: 1,
      injected_at: Clock.utc_now()
    })
    |> Repo.update!()

    assert :ok = Projects.Supervisor.stop_runtime(project.id)

    assert AgentDesk.DataCase.wait_until(fn ->
             Projects.Runtime.fetch(project.id) == {:error, :not_started}
           end)

    assert {:ok, runtime} = Projects.Supervisor.start_runtime(project)
    assert Process.alive?(runtime)

    recovered_delivery = Repo.get!(Delivery, delivery.id)
    recovered_task = Repo.get!(Task, task.id)

    evidence = %{
      session_status: Repo.get!(Agents.Session, orphan.id).status,
      capability: capability_state(token),
      lease_status: Repo.get!(Lease, lease.id).status,
      task_status: recovered_task.status,
      task_reason: recovered_task.status_reason,
      delivery_state: recovered_delivery.state,
      delivery_marked_uncertain:
        is_binary(recovered_delivery.last_error) and
          String.contains?(recovered_delivery.last_error, "uncertain"),
      pending_delivery_ids: Enum.map(MessageRouter.pending(orphan.id), & &1.id)
    }

    assert evidence == %{
             session_status: "interrupted",
             capability: :unauthorized,
             lease_status: "expired",
             task_status: "blocked",
             task_reason: "interrupted by project restart",
             delivery_state: "pending",
             delivery_marked_uncertain: true,
             pending_delivery_ids: [delivery.id]
           }

    first_recovery = %{
      task_lock_version: recovered_task.lock_version,
      task_updated_at: recovered_task.updated_at,
      delivery_updated_at: recovered_delivery.updated_at
    }

    assert :ok = Reconcile.project(project)

    assert %{
             task_lock_version: Repo.get!(Task, task.id).lock_version,
             task_updated_at: Repo.get!(Task, task.id).updated_at,
             delivery_updated_at: Repo.get!(Delivery, delivery.id).updated_at
           } == first_recovery
  end

  test "reconciliation is project-scoped" do
    repo_a = GitRepo.tmp_repo!("agentdesk-reconcile-a")
    repo_b = GitRepo.tmp_repo!("agentdesk-reconcile-b")
    {:ok, project_a} = Projects.open_project(repo_a)
    {:ok, project_b} = Projects.open_project(repo_b)
    on_exit(fn -> Projects.Supervisor.stop_runtime(project_a.id) end)
    on_exit(fn -> Projects.Supervisor.stop_runtime(project_b.id) end)

    {:ok, session_a} =
      Agents.create_session(Scope.for_project(project_a), %{
        provider: "fake",
        display_name: "A",
        status: "working"
      })

    {:ok, session_b} =
      Agents.create_session(Scope.for_project(project_b), %{
        provider: "fake",
        display_name: "B",
        status: "working"
      })

    {:ok, token_a, session_a} = Capability.issue(session_a)
    {:ok, token_b, session_b} = Capability.issue(session_b)

    {:ok, [lease_a]} =
      Manager.claim(
        Scope.for_agent(project_a, session_a),
        [%{"type" => "file", "key" => "lib/a.ex", "mode" => "exclusive"}],
        ttl_seconds: 3_600
      )

    {:ok, [lease_b]} =
      Manager.claim(
        Scope.for_agent(project_b, session_b),
        [%{"type" => "file", "key" => "lib/b.ex", "mode" => "exclusive"}],
        ttl_seconds: 3_600
      )

    assert :ok = Reconcile.project(project_a)

    assert Repo.get!(Agents.Session, session_a.id).status == "interrupted"
    assert capability_state(token_a) == :unauthorized
    assert Repo.get!(Lease, lease_a.id).status == "expired"

    assert Repo.get!(Agents.Session, session_b.id).status == "working"
    assert match?({:ok, _session}, Capability.authenticate(token_b))
    assert Repo.get!(Lease, lease_b.id).status == "active"
  end

  defp capability_state(token) do
    case Capability.authenticate(token) do
      {:ok, _session} -> :authorized
      {:error, reason} -> reason
    end
  end
end
