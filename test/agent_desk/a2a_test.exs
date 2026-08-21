defmodule AgentDesk.A2ATest do
  use AgentDesk.DataCase

  alias AgentDesk.A2A
  alias AgentDesk.A2A.Delivery
  alias AgentDesk.A2A.Task
  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  setup do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)
    on_exit(fn -> AgentDesk.Projects.Supervisor.stop_runtime(project.id) end)

    project_scope = Scope.for_project(project)

    {:ok, alice} =
      Agents.create_session(project_scope, %{provider: "fake", display_name: "Alice"})

    {:ok, bob} = Agents.create_session(project_scope, %{provider: "fake", display_name: "Bob"})

    %{
      project: project,
      alice: Scope.for_agent(project, alice),
      bob: Scope.for_agent(project, bob)
    }
  end

  test "registers and revises a safe agent card", %{alice: alice} do
    assert {:ok, card} =
             A2A.register_card(alice, %{
               name: "Implementer",
               description: "Writes Elixir",
               skills: [%{"name" => "elixir"}]
             })

    assert card.revision == 1

    assert {:ok, revised} = A2A.register_card(alice, %{name: "Implementer", availability: "busy"})
    assert revised.revision == 2
    assert revised.availability == "busy"
  end

  test "rejects agent cards that look like credential dumps", %{alice: alice} do
    assert {:error, changeset} =
             A2A.register_card(alice, %{
               name: "Bad",
               description: "nope",
               skills: [%{"token" => "secret-value"}]
             })

    assert "must not include credentials or hidden prompts" in errors_on(changeset).skills
  end

  test "proposes a delegation once and replays the same idempotency key", %{
    alice: alice,
    bob: bob
  } do
    {:ok, context} = A2A.create_context(alice, %{title: "Auth"})
    {:ok, task} = A2A.create_task(alice, context, %{title: "Add magic link"})

    attrs = %{
      task_id: task.id,
      to_agent_id: bob.agent_session.id,
      reason: "Please implement",
      idempotency_key: "delegate-1"
    }

    assert {:ok, first} = A2A.propose_delegation(alice, attrs)
    assert first.status == "proposed"
    assert {:ok, replayed} = A2A.propose_delegation(alice, attrs)
    assert replayed.id == first.id
  end

  test "idempotency conflict when the same key is reused with a different request", %{
    alice: alice,
    bob: bob
  } do
    {:ok, context} = A2A.create_context(alice, %{title: "Auth"})
    {:ok, task} = A2A.create_task(alice, context, %{title: "Add magic link"})

    assert {:ok, _} =
             A2A.propose_delegation(alice, %{
               task_id: task.id,
               to_agent_id: bob.agent_session.id,
               reason: "first",
               idempotency_key: "delegate-2"
             })

    assert {:error, :idempotency_conflict} =
             A2A.propose_delegation(alice, %{
               task_id: task.id,
               to_agent_id: bob.agent_session.id,
               reason: "different",
               idempotency_key: "delegate-2"
             })
  end

  test "accepting a delegation assigns the task in the same transaction", %{
    alice: alice,
    bob: bob
  } do
    {:ok, context} = A2A.create_context(alice, %{title: "Auth"})
    {:ok, task} = A2A.create_task(alice, context, %{title: "Add magic link"})

    {:ok, delegation} =
      A2A.propose_delegation(alice, %{
        task_id: task.id,
        to_agent_id: bob.agent_session.id,
        reason: "Please implement",
        idempotency_key: "delegate-3"
      })

    assert {:ok, accepted} =
             A2A.accept_delegation(bob, delegation.id, %{
               expected_version: 1,
               idempotency_key: "accept-3"
             })

    assert accepted.status == "accepted"
    task = Repo.get!(Task, task.id)
    assert task.status == "assigned"
    assert task.assigned_agent_id == bob.agent_session.id
    assert task.lock_version == 2
  end

  test "stale optimistic version is rejected", %{alice: alice, bob: bob} do
    {:ok, context} = A2A.create_context(alice, %{title: "Auth"})
    {:ok, task} = A2A.create_task(alice, context, %{title: "Add magic link"})

    {:ok, delegation} =
      A2A.propose_delegation(alice, %{
        task_id: task.id,
        to_agent_id: bob.agent_session.id,
        reason: "Please implement",
        idempotency_key: "delegate-4"
      })

    assert {:error, %Ecto.Changeset{} = changeset} =
             A2A.accept_delegation(bob, delegation.id, %{
               expected_version: 99,
               idempotency_key: "accept-4"
             })

    assert "stale version" in errors_on(changeset).lock_version
    assert Repo.get!(Task, task.id).status == "queued"
  end

  test "direct messages get a monotonic inbox sequence and can be acknowledged", %{
    alice: alice,
    bob: bob
  } do
    {:ok, context} = A2A.create_context(alice, %{title: "Auth"})

    assert {:ok, message} =
             A2A.send_direct_message(alice, %{
               context_id: context.id,
               recipient_agent_id: bob.agent_session.id,
               body: "Need a review",
               idempotency_key: "msg-1"
             })

    assert message.correlation_id

    delivery =
      Repo.get_by!(Delivery, message_id: message.id, agent_session_id: bob.agent_session.id)

    assert delivery.inbox_sequence == 1
    assert delivery.state == "pending"

    assert {:ok, acked} = A2A.acknowledge(bob, delivery.id)
    assert acked.state == "acknowledged"
  end

  test "publishes an integrity-checked local artifact and rejects remote URLs", %{
    alice: alice
  } do
    {:ok, context} = A2A.create_context(alice, %{title: "Auth"})

    sha = :sha256 |> :crypto.hash("hello") |> Base.encode16(case: :lower)

    assert {:ok, artifact} =
             A2A.publish_artifact(alice, %{
               context_id: context.id,
               kind: "plan",
               name: "plan.md",
               mime_type: "text/markdown",
               path: "artifacts/plan.md",
               sha256: sha,
               size_bytes: 5
             })

    assert artifact.state == "available"

    assert {:error, changeset} =
             A2A.publish_artifact(alice, %{
               context_id: context.id,
               kind: "file",
               name: "evil",
               mime_type: "text/plain",
               path: "https://example.test/x",
               sha256: sha,
               size_bytes: 1
             })

    assert "must be a local app-managed or project-relative path" in errors_on(changeset).path
  end

  test "broadcasts create one ordered delivery per peer", %{alice: alice, bob: bob} do
    {:ok, context} = A2A.create_context(alice, %{title: "Auth"})

    assert {:ok, message} =
             A2A.broadcast(alice, %{
               context_id: context.id,
               body: "stand-up",
               idempotency_key: "broadcast-1"
             })

    assert message.scope == "project"
    deliveries = Repo.all(Delivery)
    assert Enum.any?(deliveries, &(&1.agent_session_id == bob.agent_session.id))
  end

  test "rejects remote URL parts and supports revoke/redirect", %{alice: alice, bob: bob} do
    {:ok, context} = A2A.create_context(alice, %{title: "Auth"})
    {:ok, task} = A2A.create_task(alice, context, %{title: "Work"})

    assert {:error, :remote_url} =
             A2A.send_message(alice, %{
               context_id: context.id,
               recipient_agent_id: bob.agent_session.id,
               idempotency_key: "bad-part",
               parts: [%{"type" => "file_ref", "path" => "https://evil.test/x"}]
             })

    {:ok, delegation} =
      A2A.propose_delegation(alice, %{
        task_id: task.id,
        to_agent_id: bob.agent_session.id,
        reason: "please",
        idempotency_key: "del-rev"
      })

    {:ok, revoked} =
      A2A.revoke_delegation(alice, delegation.id, %{idempotency_key: "rev-1"})

    assert revoked.status == "revoked"

    {:ok, proposed} =
      A2A.propose_delegation(alice, %{
        task_id: task.id,
        to_agent_id: bob.agent_session.id,
        reason: "again",
        idempotency_key: "del-redir"
      })

    {:ok, redirected} =
      A2A.redirect_delegation(alice, proposed.id, %{
        idempotency_key: "redir-1",
        to_agent_id: alice.agent_session.id
      })

    assert redirected.to_agent_id == alice.agent_session.id
  end

  test "expired proposals are reaped by the hub ticker", %{alice: alice, bob: bob} do
    {:ok, context} = A2A.create_context(alice, %{title: "Auth"})
    {:ok, task} = A2A.create_task(alice, context, %{title: "Work"})

    {:ok, delegation} =
      A2A.propose_delegation(alice, %{
        task_id: task.id,
        to_agent_id: bob.agent_session.id,
        reason: "please",
        idempotency_key: "del-exp",
        expires_at: DateTime.add(AgentDesk.Clock.utc_now(), -5, :second)
      })

    :ok = A2A.expire_due_delegations(alice.project.id)
    assert Repo.get!(AgentDesk.A2A.Delegation, delegation.id).status == "expired"
  end

  test "get_artifact verifies bytes", %{alice: alice} do
    {:ok, context} = A2A.create_context(alice, %{title: "Auth"})
    dir = System.tmp_dir!()
    path = Path.join(dir, "artifact-#{System.unique_integer([:positive])}.txt")
    File.write!(path, "hello")
    sha = :sha256 |> :crypto.hash("hello") |> Base.encode16(case: :lower)

    {:ok, artifact} =
      A2A.publish_artifact(alice, %{
        context_id: context.id,
        kind: "report",
        name: "hello.txt",
        mime_type: "text/plain",
        path: path,
        sha256: sha,
        size_bytes: 5
      })

    assert {:ok, ^artifact} = A2A.get_artifact(alice, artifact.id)
    File.write!(path, "tampered")
    assert {:error, :artifact_integrity} = A2A.get_artifact(alice, artifact.id)
  end

  test "a dependency blocks until the prerequisite completes", %{alice: alice} do
    {:ok, context} = A2A.create_context(alice, %{title: "Graph"})
    {:ok, design} = A2A.create_task(alice, context, %{title: "Design"})
    {:ok, impl} = A2A.create_task(alice, context, %{title: "Implement", depends_on: [design.id]})

    impl = Repo.get!(Task, impl.id)
    assert impl.status == "blocked"
    assert {:error, :cycle} = AgentDesk.A2A.Graph.add_dependency(alice, design.id, impl.id)

    assert {:ok, _} = A2A.update_task(alice, design, %{status: "completed"})
    assert Repo.get!(Task, impl.id).status == "queued"
  end

  test "a reusable workflow instantiates a linear task graph", %{alice: alice} do
    {:ok, context} = A2A.create_context(alice, %{title: "Ship"})

    assert {:ok, [first, second | _rest]} =
             AgentDesk.A2A.Workflows.instantiate_linear(alice, context, "Ship", [
               "Design",
               "Implement",
               "Review"
             ])

    first = Repo.get!(Task, first.id)
    second = Repo.get!(Task, second.id)
    assert first.status == "queued"
    assert second.status == "blocked"
    assert [workflow] = AgentDesk.A2A.Workflows.list(alice)
    assert workflow.name == "Ship"
  end
end
