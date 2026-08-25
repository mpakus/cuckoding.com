defmodule AgentDesk.A2A.ReliabilityAcceptanceTest do
  use AgentDesk.DataCase

  alias AgentDesk.A2A
  alias AgentDesk.A2A.Artifact
  alias AgentDesk.A2A.Delegation
  alias AgentDesk.A2A.Delivery
  alias AgentDesk.A2A.Message
  alias AgentDesk.A2A.Participant
  alias AgentDesk.A2A.Task, as: A2ATask
  alias AgentDesk.Agents
  alias AgentDesk.Agents.Session
  alias AgentDesk.Clock
  alias AgentDesk.GitRepo
  alias AgentDesk.Ids
  alias AgentDesk.MCP.Protocol
  alias AgentDesk.Projects
  alias AgentDesk.Providers
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Repo
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope
  alias AgentDesk.Worktrees

  @read_only_mcp_tools ~w(
    hub_list_agents
    hub_get_agent_card
    hub_find_agents
    hub_list_tasks
    hub_get_task
    hub_list_delegations
    hub_list_task_graph
    hub_list_workflows
    hub_crew_status
    hub_list_roles
    hub_list_resources
    hub_isolation
    hub_list_inbox
    hub_get_artifact
    hub_list_merge_queue
    project_search
    memory_recall
  )

  setup do
    repo = GitRepo.tmp_repo!("a2a-reliability")
    {:ok, project} = Projects.open_project(repo)
    on_exit(fn -> AgentDesk.Projects.Supervisor.stop_runtime(project.id) end)

    project_scope = Scope.for_project(project)
    {:ok, alice} = Agents.create_session(project_scope, session_attrs("Alice"))
    {:ok, bob} = Agents.create_session(project_scope, session_attrs("Bob"))
    {:ok, charlie} = Agents.create_session(project_scope, session_attrs("Charlie"))

    %{
      project: project,
      project_scope: project_scope,
      alice: Scope.for_agent(project, alice),
      bob: Scope.for_agent(project, bob),
      charlie: Scope.for_agent(project, charlie)
    }
  end

  test "direct messages cannot cross project boundaries and create no delivery", %{
    alice: alice
  } do
    foreign_repo = GitRepo.tmp_repo!("a2a-foreign")
    {:ok, foreign_project} = Projects.open_project(foreign_repo)
    on_exit(fn -> AgentDesk.Projects.Supervisor.stop_runtime(foreign_project.id) end)

    {:ok, foreign_session} =
      Agents.create_session(Scope.for_project(foreign_project), session_attrs("Foreign"))

    {:ok, context} = A2A.create_context(alice, %{title: "Project-local coordination"})
    message_count = Repo.aggregate(Message, :count, :id)
    delivery_count = Repo.aggregate(Delivery, :count, :id)

    result =
      A2A.send_direct_message(alice, %{
        context_id: context.id,
        recipient_agent_id: foreign_session.id,
        body: "must remain in the sender project",
        idempotency_key: "cross-project-message"
      })

    assert {
             result,
             Repo.aggregate(Message, :count, :id),
             Repo.aggregate(Delivery, :count, :id)
           } == {{:error, :forbidden}, message_count, delivery_count}
  end

  test "context and task messages require active senders and exclude departed recipients", %{
    alice: alice,
    bob: bob,
    charlie: charlie
  } do
    {:ok, context} = A2A.create_context(alice, %{title: "Active participants"})
    {:ok, task} = A2A.create_task(alice, context, %{title: "Scoped discussion"})
    bob_participant = join_context!(context.id, bob.agent_session.id)
    charlie_participant = join_context!(context.id, charlie.agent_session.id)

    assert {:ok, context_message} =
             A2A.send_message(bob, %{
               context_id: context.id,
               scope: "context",
               body: "active context message",
               idempotency_key: "active-context-message"
             })

    assert delivery_recipient_ids(context_message.id) |> Enum.sort() ==
             [alice.agent_session.id, charlie.agent_session.id] |> Enum.sort()

    depart_context!(charlie_participant)

    assert {:ok, task_message} =
             A2A.send_message(bob, %{
               context_id: context.id,
               task_id: task.id,
               scope: "task",
               body: "active task message",
               idempotency_key: "active-task-message"
             })

    assert delivery_recipient_ids(task_message.id) == [alice.agent_session.id]

    depart_context!(bob_participant)

    for {scope, task_id} <- [{"context", nil}, {"task", task.id}] do
      assert {:error, :forbidden} =
               A2A.send_message(bob, %{
                 context_id: context.id,
                 task_id: task_id,
                 scope: scope,
                 body: "departed sender",
                 idempotency_key: "departed-sender-#{scope}"
               })
    end
  end

  test "an unassigned agent cannot update, cancel, or complete another agent's task", %{
    alice: alice,
    bob: bob
  } do
    attempts =
      for {tool, status} <- [
            {"hub_update_task", "working"},
            {"hub_cancel_task", "cancelled"},
            {"hub_complete_task", "completed"}
          ] do
        task = assigned_task!(alice, tool)
        _participant = join_context!(task.context_id, bob.agent_session.id)

        arguments =
          %{
            "task_id" => task.id,
            "expected_version" => task.lock_version,
            "idempotency_key" => "unauthorized-#{tool}"
          }
          |> maybe_put_status(tool, status)

        result = protocol_call(bob.agent_session, tool, arguments)
        persisted = Repo.get!(A2ATask, task.id)

        {tool, result, persisted.status, persisted.assigned_agent_id}
      end

    assert Enum.all?(attempts, fn {_tool, result, status, assignee} ->
             forbidden_error?(result) and status == "assigned" and
               assignee == alice.agent_session.id
           end),
           "unauthorized task mutation outcomes: #{inspect(attempts)}"
  end

  test "ordinary context participants cannot propose delegation for another agent's task", %{
    alice: alice,
    bob: bob,
    charlie: charlie
  } do
    task = assigned_task!(alice, "delegation-authority")
    _participant = join_context!(task.context_id, bob.agent_session.id)
    delegation_count = Repo.aggregate(Delegation, :count, :id)

    assert {:error, :forbidden} =
             A2A.propose_delegation(bob, %{
               task_id: task.id,
               to_agent_id: charlie.agent_session.id,
               reason: "not Bob's task to delegate",
               idempotency_key: "unauthorized-delegation-proposal"
             })

    assert Repo.aggregate(Delegation, :count, :id) == delegation_count

    assert {:ok, %Delegation{status: "proposed"}} =
             A2A.propose_delegation(alice, %{
               task_id: task.id,
               to_agent_id: charlie.agent_session.id,
               reason: "assignee delegates explicitly",
               idempotency_key: "authorized-delegation-proposal"
             })
  end

  test "ordinary participants cannot create tasks or mutate another task graph", %{
    alice: alice,
    bob: bob
  } do
    {:ok, context} = A2A.create_context(alice, %{title: "Graph authority"})
    {:ok, prerequisite} = A2A.create_task(alice, context, %{title: "Prerequisite"})
    {:ok, dependent} = A2A.create_task(alice, context, %{title: "Dependent"})
    _participant = join_context!(context.id, bob.agent_session.id)

    assert {:error, :forbidden} =
             A2A.create_task(bob, context, %{title: "Unauthorized task"})

    assert {:error, :forbidden} =
             AgentDesk.A2A.Graph.add_dependency(bob, dependent.id, prerequisite.id)

    assert forbidden_error?(
             protocol_call(bob.agent_session, "hub_create_task", %{
               "context_id" => context.id,
               "title" => "Unauthorized MCP task",
               "idempotency_key" => "unauthorized-task-create"
             })
           )

    assert forbidden_error?(
             protocol_call(bob.agent_session, "hub_add_task_dependency", %{
               "task_id" => dependent.id,
               "depends_on_id" => prerequisite.id,
               "idempotency_key" => "unauthorized-graph-mutation"
             })
           )

    assert {:ok, _edge} =
             AgentDesk.A2A.Graph.add_dependency(alice, dependent.id, prerequisite.id)

    assert {:error, :forbidden} =
             AgentDesk.A2A.Graph.ensure_dependency(bob, dependent.id, prerequisite.id)

    assert length(AgentDesk.A2A.Graph.list_edges(alice.project.id)) == 1
    refute Enum.any?(A2A.list_tasks(alice), &(&1.title =~ "Unauthorized"))
  end

  test "an active assignee and reviewer have their scoped graph authority", %{
    alice: alice,
    bob: bob,
    charlie: charlie
  } do
    {:ok, context} = A2A.create_context(alice, %{title: "Scoped graph authority"})
    {:ok, prerequisite} = A2A.create_task(alice, context, %{title: "Prerequisite"})
    {:ok, assigned} = A2A.create_task(alice, context, %{title: "Assigned"})
    _assignee_participant = join_context!(context.id, bob.agent_session.id)
    _reviewer_participant = join_context!(context.id, charlie.agent_session.id, "reviewer")

    {:ok, assigned} =
      A2A.update_task(alice, assigned, %{
        status: "assigned",
        assigned_agent_id: bob.agent_session.id
      })

    assert {:ok, _edge} =
             AgentDesk.A2A.Graph.add_dependency(bob, assigned.id, prerequisite.id)

    assert {:ok, reviewer_task} =
             A2A.create_task(charlie, context, %{title: "Reviewer-created task"})

    assert {:ok, _edge} =
             AgentDesk.A2A.Graph.add_dependency(charlie, reviewer_task.id, assigned.id)
  end

  test "departed context authorities cannot create tasks or mutate dependencies", %{
    alice: alice,
    bob: bob
  } do
    {:ok, context} = A2A.create_context(alice, %{title: "Departed authority"})
    {:ok, prerequisite} = A2A.create_task(alice, context, %{title: "Prerequisite"})
    {:ok, dependent} = A2A.create_task(alice, context, %{title: "Dependent"})

    owner =
      Repo.get_by!(Participant,
        context_id: context.id,
        agent_session_id: alice.agent_session.id
      )

    depart_context!(owner)

    assert {:error, :forbidden} =
             A2A.create_task(alice, context, %{title: "Created after departure"})

    assert {:error, :forbidden} =
             AgentDesk.A2A.Graph.add_dependency(alice, dependent.id, prerequisite.id)

    assert {:error, :forbidden} =
             A2A.update_task(alice, dependent, %{status: "working"})

    assert {:error, :forbidden} =
             A2A.propose_delegation(alice, %{
               task_id: dependent.id,
               to_agent_id: bob.agent_session.id,
               reason: "departed creator",
               idempotency_key: "departed-delegation"
             })

    assert forbidden_error?(
             protocol_call(alice.agent_session, "hub_add_task_dependency", %{
               "task_id" => dependent.id,
               "depends_on_id" => prerequisite.id,
               "idempotency_key" => "departed-graph-mutation"
             })
           )

    assert AgentDesk.A2A.Graph.list_edges(alice.project.id) == []
  end

  test "normal delegation rejects hidden and inactive recipients", %{
    alice: alice,
    bob: bob,
    charlie: charlie
  } do
    {:ok, context} = A2A.create_context(alice, %{title: "Recipient eligibility"})
    {:ok, task} = A2A.create_task(alice, context, %{title: "Eligible recipients only"})
    _bob_participant = join_context!(context.id, bob.agent_session.id)
    _charlie_participant = join_context!(context.id, charlie.agent_session.id)

    {:ok, _bob_card} =
      A2A.register_card(bob, %{name: "Bob", description: "Hidden", skills: []})

    {:ok, _charlie_card} =
      A2A.register_card(charlie, %{name: "Charlie", description: "Inactive", skills: []})

    {:ok, proposal} =
      A2A.propose_delegation(alice, %{
        task_id: task.id,
        to_agent_id: charlie.agent_session.id,
        reason: "explicit acceptance required",
        idempotency_key: "active-recipient"
      })

    {:ok, hidden_bob} = Agents.hide_tab(bob.agent_session)

    assert {:error, :forbidden} =
             A2A.propose_delegation(alice, %{
               task_id: task.id,
               to_agent_id: hidden_bob.id,
               reason: "hidden recipient",
               idempotency_key: "hidden-recipient"
             })

    assert {:error, :forbidden} =
             A2A.send_direct_message(alice, %{
               context_id: context.id,
               recipient_agent_id: hidden_bob.id,
               body: "hidden recipient",
               idempotency_key: "message-hidden-recipient"
             })

    assert {:error, :forbidden} =
             A2A.redirect_delegation(alice, proposal.id, %{
               to_agent_id: hidden_bob.id,
               idempotency_key: "redirect-hidden-recipient"
             })

    {:ok, terminated_charlie} =
      Agents.update_session(charlie.agent_session, %{status: "terminated"})

    assert {:error, :forbidden} =
             A2A.accept_delegation(
               Scope.for_agent(alice.project, terminated_charlie),
               proposal.id,
               %{
                 expected_version: proposal.lock_version,
                 idempotency_key: "terminated-acceptance"
               }
             )

    assert {:ok, fanout} =
             A2A.send_message(alice, %{
               context_id: context.id,
               scope: "context",
               body: "active recipients only",
               idempotency_key: "eligible-context-fanout"
             })

    assert delivery_recipient_ids(fanout.id) == []
    assert A2A.list_agents(alice) == []
    assert Repo.get!(Delegation, proposal.id).status == "proposed"
    assert is_nil(Repo.get!(A2ATask, task.id).assigned_agent_id)
  end

  test "dependency edges cannot cross context boundaries", %{alice: alice} do
    {:ok, first_context} = A2A.create_context(alice, %{title: "First context"})
    {:ok, second_context} = A2A.create_context(alice, %{title: "Second context"})
    {:ok, dependent} = A2A.create_task(alice, first_context, %{title: "Dependent"})
    {:ok, foreign_prerequisite} = A2A.create_task(alice, second_context, %{title: "Foreign"})

    assert {:error, :forbidden} =
             AgentDesk.A2A.Graph.add_dependency(alice, dependent.id, foreign_prerequisite.id)

    assert AgentDesk.A2A.Graph.list_edges(alice.project.id) == []
  end

  test "unknown delegation IDs return tagged errors instead of raising", %{
    alice: alice,
    bob: bob
  } do
    for {missing_id, suffix} <- [{Ecto.UUID.generate(), "missing"}, {"not-a-uuid", "malformed"}] do
      assert {:error, :not_found} =
               A2A.accept_delegation(bob, missing_id, %{
                 expected_version: 1,
                 idempotency_key: "accept-#{suffix}-delegation"
               })

      assert {:error, :not_found} =
               A2A.redirect_delegation(alice, missing_id, %{
                 to_agent_id: bob.agent_session.id,
                 idempotency_key: "redirect-#{suffix}-delegation"
               })
    end
  end

  test "malformed A2A UUIDs return protocol errors without crashing", %{alice: alice} do
    calls = [
      {"hub_get_agent_card", %{"agent_id" => "not-a-uuid"}},
      {"hub_create_task",
       %{
         "context_id" => "not-a-uuid",
         "title" => "invalid",
         "idempotency_key" => "malformed-task"
       }},
      {"hub_add_task_dependency",
       %{
         "task_id" => "not-a-uuid",
         "depends_on_id" => "also-not-a-uuid",
         "idempotency_key" => "malformed-edge"
       }},
      {"hub_crew_status", %{"parent_task_id" => "not-a-uuid"}}
    ]

    results =
      Enum.map(calls, fn {tool, arguments} ->
        {tool, protocol_call(alice.agent_session, tool, arguments)}
      end)

    assert Enum.all?(results, fn {_tool, result} -> not_found_error?(result) end),
           "malformed UUID outcomes: #{inspect(results)}"
  end

  test "message idempotency includes parts, kind, causation, and reply identity", %{
    alice: alice,
    bob: bob
  } do
    {:ok, context} = A2A.create_context(alice, %{title: "Message identity"})

    {:ok, parent} =
      A2A.send_message(alice, %{
        context_id: context.id,
        recipient_agent_id: bob.agent_session.id,
        scope: "direct",
        kind: "request",
        parts: [%{"type" => "text", "text" => "parent"}],
        idempotency_key: "message-parent"
      })

    changes = [
      parts: %{parts: [%{"type" => "text", "text" => "changed"}]},
      kind: %{kind: "warning"},
      causation_id: %{causation_id: Ecto.UUID.generate()},
      reply_to_message_id: %{reply_to_message_id: parent.id}
    ]

    conflicts =
      Enum.map(changes, fn {field, change} ->
        key = "message-semantic-#{field}"

        attrs = %{
          context_id: context.id,
          recipient_agent_id: bob.agent_session.id,
          scope: "direct",
          kind: "request",
          parts: [%{"type" => "text", "text" => "base"}],
          causation_id: nil,
          reply_to_message_id: nil,
          idempotency_key: key
        }

        assert {:ok, _message} = A2A.send_message(alice, attrs)
        {field, A2A.send_message(alice, Map.merge(attrs, change))}
      end)

    assert Enum.all?(conflicts, fn {_field, result} ->
             result == {:error, :idempotency_conflict}
           end),
           "message idempotency outcomes: #{inspect(conflicts)}"
  end

  test "every exposed mutating MCP schema requires caller idempotency keys", %{alice: alice} do
    assert {:ok, %{"result" => %{"tools" => tools}}} =
             Protocol.handle(alice.agent_session, %{
               "id" => "schemas",
               "method" => "tools/list",
               "params" => %{}
             })

    schemas =
      tools
      |> Enum.reject(&(&1["name"] in @read_only_mcp_tools))
      |> Enum.map(fn tool -> {tool["name"], tool["inputSchema"]} end)

    violations =
      Enum.reject(schemas, fn {_name, schema} ->
        is_map(schema) and "idempotency_key" in List.wrap(schema["required"]) and
          get_in(schema, ["properties", "idempotency_key", "type"]) == "string"
      end)

    assert schemas != []

    assert violations == [],
           """
           every exposed tool not classified as read-only must require a caller-supplied \
           string idempotency_key; violations: #{inspect(violations)}
           """
  end

  test "mutating MCP tools reject a missing idempotency key", %{
    alice: alice,
    bob: bob
  } do
    {:ok, context} = A2A.create_context(alice, %{title: "MCP idempotency"})
    {:ok, task} = A2A.create_task(alice, context, %{title: "Delegated work"})

    {:ok, delegation} =
      A2A.propose_delegation(alice, %{
        task_id: task.id,
        to_agent_id: bob.agent_session.id,
        reason: "accept through MCP",
        idempotency_key: "mcp-delegation"
      })

    calls = [
      {alice.agent_session, "hub_send_message",
       %{
         "context_id" => context.id,
         "recipient_agent_id" => bob.agent_session.id,
         "scope" => "direct",
         "kind" => "request",
         "parts" => [%{"type" => "text", "text" => "missing key"}]
       }},
      {alice.agent_session, "hub_claim_resources",
       %{
         "resources" => [
           %{"type" => "file", "key" => "lib/missing_key.ex", "mode" => "exclusive"}
         ],
         "reason" => "missing key"
       }},
      {bob.agent_session, "hub_accept_delegation",
       %{"delegation_id" => delegation.id, "expected_version" => delegation.lock_version}}
    ]

    results =
      Enum.map(calls, fn {session, tool, arguments} ->
        {tool, protocol_call(session, tool, arguments)}
      end)

    assert Enum.all?(results, fn {_tool, result} -> missing_idempotency_error?(result) end),
           "missing idempotency outcomes: #{inspect(results)}"
  end

  test "artifact associations and retrieval stay within authorized project and task scopes", %{
    project: project,
    alice: alice,
    bob: bob,
    charlie: charlie
  } do
    {:ok, context} = A2A.create_context(alice, %{title: "Local artifacts"})
    {:ok, task} = A2A.create_task(alice, context, %{title: "Owned artifact task"})
    _participant = join_context!(context.id, bob.agent_session.id)
    {:ok, worktree} = Worktrees.ensure_for_session(project, alice.agent_session)
    local_path = Path.join(worktree.path, "local-artifact.txt")
    File.write!(local_path, "local")

    assert {:ok, local_artifact} =
             A2A.publish_artifact(
               alice,
               artifact_attrs(context.id, local_path, "local", task_id: task.id)
             )

    assert {:error, :forbidden} = A2A.get_artifact(bob, local_artifact.id)
    assert {:error, :forbidden} = A2A.get_artifact(charlie, local_artifact.id)
    assert {:ok, ^local_artifact} = A2A.get_artifact(alice, local_artifact.id)

    revision_path = Path.join(worktree.path, "local-artifact-v2.txt")
    File.write!(revision_path, "local-v2")
    revision_sha = "local-v2" |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)

    assert {:ok, %{"result" => %{"id" => revision_id}}} =
             protocol_call(alice.agent_session, "hub_publish_artifact", %{
               "context_id" => context.id,
               "task_id" => task.id,
               "kind" => "file",
               "name" => "local-artifact-v2.txt",
               "mime_type" => "text/plain",
               "path" => revision_path,
               "sha256" => revision_sha,
               "size_bytes" => byte_size("local-v2"),
               "revision_of_id" => local_artifact.id,
               "idempotency_key" => "publish-local-v2"
             })

    assert Repo.get!(Artifact, revision_id).revision_of_id == local_artifact.id

    foreign_repo = GitRepo.tmp_repo!("a2a-artifact-foreign")
    {:ok, foreign_project} = Projects.open_project(foreign_repo)
    on_exit(fn -> AgentDesk.Projects.Supervisor.stop_runtime(foreign_project.id) end)
    foreign_project_scope = Scope.for_project(foreign_project)

    {:ok, foreign_session} =
      Agents.create_session(foreign_project_scope, session_attrs("Foreign artifact owner"))

    foreign_scope = Scope.for_agent(foreign_project, foreign_session)
    {:ok, foreign_context} = A2A.create_context(foreign_scope, %{title: "Foreign artifacts"})

    {:ok, foreign_task} =
      A2A.create_task(foreign_scope, foreign_context, %{title: "Foreign task"})

    {:ok, foreign_worktree} =
      Worktrees.ensure_for_session(foreign_project, foreign_scope.agent_session)

    foreign_path = Path.join(foreign_worktree.path, "foreign-artifact.txt")
    File.write!(foreign_path, "foreign")

    assert {:ok, foreign_artifact} =
             A2A.publish_artifact(
               foreign_scope,
               artifact_attrs(foreign_context.id, foreign_path, "foreign",
                 task_id: foreign_task.id
               )
             )

    project_artifact_count =
      Repo.aggregate(from(a in Artifact, where: a.project_id == ^project.id), :count)

    invalid_associations = [
      artifact_attrs(foreign_context.id, local_path, "local"),
      artifact_attrs(context.id, local_path, "local", task_id: foreign_task.id),
      artifact_attrs(context.id, local_path, "local", revision_of_id: foreign_artifact.id),
      artifact_attrs("not-a-uuid", local_path, "local"),
      artifact_attrs(context.id, local_path, "local", task_id: "not-a-uuid"),
      artifact_attrs(context.id, local_path, "local", revision_of_id: "not-a-uuid")
    ]

    assert Enum.all?(invalid_associations, fn attrs ->
             match?({:error, _reason}, A2A.publish_artifact(alice, attrs))
           end)

    assert Repo.aggregate(from(a in Artifact, where: a.project_id == ^project.id), :count) ==
             project_artifact_count

    assert {:error, :not_found} = A2A.get_artifact(alice, foreign_artifact.id)
    assert {:error, :not_found} = A2A.get_artifact(alice, "not-a-uuid")
  end

  test "simultaneous exclusive claims for one resource have exactly one winner", %{
    alice: alice,
    bob: bob,
    project: project
  } do
    resource = [%{"type" => "file", "key" => "lib/race.ex", "mode" => "exclusive"}]

    results =
      race([
        fn -> Manager.claim(alice, resource, reason: "alice") end,
        fn -> Manager.claim(bob, resource, reason: "bob") end
      ])

    active =
      project.id
      |> Manager.list_project()
      |> Enum.filter(&(&1.resource_key == "lib/race.ex" and &1.status == "active"))

    assert Enum.count(results, &match?({:ok, [_]}, &1)) == 1,
           "exclusive claim outcomes: #{inspect(results)}"

    assert Enum.count(results, &match?({:error, {:conflict, [_ | _]}}, &1)) == 1,
           "exclusive claim outcomes: #{inspect(results)}"

    assert length(active) == 1
  end

  test "a dead provider port cannot acknowledge a pending delivery", %{
    alice: alice,
    project: project,
    project_scope: project_scope
  } do
    Phoenix.PubSub.subscribe(AgentDesk.PubSub, "project:" <> project.id <> ":sessions")

    {:ok, recipient} =
      Providers.start_session(project_scope, %{provider: "fake", display_name: "Dead port"})

    _ready =
      await_session(recipient.id, fn session ->
        present?(session.provider_session_id) and session.status == "idle"
      end)

    {:ok, worker} = SessionWorker.fetch(recipient.id)
    state = :sys.get_state(worker)

    {:ok, request_payload, decode} =
      state.adapter.encode({:prompt, "simulated safe boundary"}, state.decode)

    request_payload = request_payload |> IO.iodata_to_binary() |> String.trim()
    request_id = request_payload |> Jason.decode!() |> Map.fetch!("id")
    response = Jason.encode!(%{"jsonrpc" => "2.0", "id" => request_id, "result" => %{}}) <> "\n"
    dead_port = closed_port()
    original_port = state.port

    persisted =
      try do
        :sys.replace_state(worker, &%{&1 | port: dead_port, decode: decode})

        {:ok, context} = A2A.create_context(alice, %{title: "Safe-boundary delivery"})

        {:ok, message} =
          A2A.send_direct_message(alice, %{
            context_id: context.id,
            recipient_agent_id: recipient.id,
            body: "do not acknowledge a failed injection",
            idempotency_key: "dead-port-delivery"
          })

        delivery = Repo.get_by!(Delivery, message_id: message.id, agent_session_id: recipient.id)
        assert delivery.state == "pending"

        send(worker, {dead_port, {:data, response}})
        _barrier = :sys.get_state(worker)
        Repo.get!(Delivery, delivery.id)
      after
        if Process.alive?(worker) do
          :sys.replace_state(worker, &%{&1 | port: original_port})
        end
      end

    assert persisted.state == "pending"
    assert is_nil(persisted.acknowledged_at)
    assert persisted.last_error
  end

  test "competing delegation acceptances assign a task to exactly one recipient", %{
    alice: alice,
    bob: bob,
    charlie: charlie
  } do
    {:ok, context} = A2A.create_context(alice, %{title: "Delegation race"})
    {:ok, task} = A2A.create_task(alice, context, %{title: "Single assignee"})

    {:ok, bob_delegation} =
      A2A.propose_delegation(alice, %{
        task_id: task.id,
        to_agent_id: bob.agent_session.id,
        reason: "Bob may accept",
        idempotency_key: "delegate-bob"
      })

    {:ok, charlie_delegation} =
      A2A.propose_delegation(alice, %{
        task_id: task.id,
        to_agent_id: charlie.agent_session.id,
        reason: "Charlie may accept",
        idempotency_key: "delegate-charlie"
      })

    results =
      race([
        fn ->
          A2A.accept_delegation(bob, bob_delegation.id, %{
            expected_version: bob_delegation.lock_version,
            idempotency_key: "accept-bob"
          })
        end,
        fn ->
          A2A.accept_delegation(charlie, charlie_delegation.id, %{
            expected_version: charlie_delegation.lock_version,
            idempotency_key: "accept-charlie"
          })
        end
      ])

    delegations =
      [bob_delegation.id, charlie_delegation.id]
      |> Enum.map(&Repo.get!(Delegation, &1))

    accepted = Enum.filter(delegations, &(&1.status == "accepted"))
    persisted_task = Repo.get!(A2ATask, task.id)

    assert Enum.count(results, &match?({:ok, %Delegation{}}, &1)) == 1,
           "delegation acceptance outcomes: #{inspect(results)}"

    assert [%Delegation{to_agent_id: winner_id}] = accepted
    assert persisted_task.status == "assigned"
    assert persisted_task.assigned_agent_id == winner_id

    assert Repo.exists?(
             from participant in Participant,
               where:
                 participant.context_id == ^context.id and
                   participant.agent_session_id == ^winner_id and
                   is_nil(participant.left_at)
           )
  end

  defp join_context!(context_id, session_id, role \\ "participant") do
    %Participant{}
    |> Participant.changeset(%{
      id: Ids.generate(),
      context_id: context_id,
      agent_session_id: session_id,
      role: role,
      joined_at: Clock.utc_now()
    })
    |> Repo.insert!()
  end

  defp depart_context!(participant) do
    participant
    |> Ecto.Changeset.change(left_at: Clock.utc_now())
    |> Repo.update!()
  end

  defp delivery_recipient_ids(message_id) do
    Delivery
    |> where([delivery], delivery.message_id == ^message_id)
    |> select([delivery], delivery.agent_session_id)
    |> Repo.all()
  end

  defp artifact_attrs(context_id, path, bytes, overrides \\ []) do
    overrides = Map.new(overrides)

    Map.merge(
      %{
        context_id: context_id,
        kind: "file",
        name: Path.basename(path),
        mime_type: "application/octet-stream",
        path: path,
        sha256: bytes |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower),
        size_bytes: byte_size(bytes)
      },
      overrides
    )
  end

  defp session_attrs(name), do: %{provider: "fake", display_name: name}

  defp assigned_task!(owner, suffix) do
    {:ok, context} = A2A.create_context(owner, %{title: "Authorization #{suffix}"})
    {:ok, task} = A2A.create_task(owner, context, %{title: "Owned #{suffix}"})

    {:ok, task} =
      A2A.update_task(owner, task, %{
        status: "assigned",
        assigned_agent_id: owner.agent_session.id
      })

    task
  end

  defp maybe_put_status(arguments, "hub_update_task", status),
    do: Map.put(arguments, "status", status)

  defp maybe_put_status(arguments, _tool, _status), do: arguments

  defp protocol_call(session, tool, arguments) do
    try do
      Protocol.handle(session, %{
        "id" => tool,
        "method" => "tools/call",
        "params" => %{"name" => tool, "arguments" => arguments}
      })
    rescue
      error -> {:protocol_crash, Exception.message(error)}
    catch
      kind, reason -> {:protocol_crash, {kind, reason}}
    end
  end

  defp forbidden_error?({:error, %{"error" => %{"message" => message}}})
       when is_binary(message) do
    message |> String.downcase() |> String.contains?("forbidden")
  end

  defp forbidden_error?(_result), do: false

  defp not_found_error?({:error, %{"error" => %{"message" => message}}})
       when is_binary(message) do
    message |> String.downcase() |> String.contains?("not_found")
  end

  defp not_found_error?(_result), do: false

  defp missing_idempotency_error?({:error, %{"error" => %{"message" => message}}})
       when is_binary(message) do
    String.contains?(String.downcase(message), "idempotency")
  end

  defp missing_idempotency_error?(_result), do: false

  defp race(functions) do
    parent = self()

    tasks =
      Enum.map(functions, fn function ->
        Task.async(fn ->
          send(parent, {:race_ready, self()})

          receive do
            :race_go -> safe_call(function)
          end
        end)
      end)

    Enum.each(tasks, fn task ->
      pid = task.pid
      assert_receive {:race_ready, ^pid}, 5_000
    end)

    Enum.each(tasks, &send(&1.pid, :race_go))
    Enum.map(tasks, &Task.await(&1, 10_000))
  end

  defp safe_call(function) do
    try do
      function.()
    rescue
      error -> {:raised, error.__struct__, Exception.message(error)}
    catch
      kind, reason -> {:caught, kind, reason}
    end
  end

  defp await_session(session_id, predicate) do
    receive do
      {:session_updated, %Session{id: ^session_id} = session} ->
        if predicate.(session), do: session, else: await_session(session_id, predicate)

      _other ->
        await_session(session_id, predicate)
    after
      10_000 -> flunk("provider session #{session_id} did not reach the expected state")
    end
  end

  defp closed_port do
    dir = owned_tmp_dir!("closed-port")
    executable = Path.join(dir, "wait-for-stdin")
    File.write!(executable, "#!/bin/sh\nwhile IFS= read -r _line; do :; done\n")
    File.chmod!(executable, 0o755)

    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :use_stdio
      ])

    true = Port.close(port)
    nil = Port.info(port)
    port
  end

  defp owned_tmp_dir!(name) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "agentdesk-#{name}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(dir)

    on_exit(fn ->
      File.rm_rf!(dir)
      refute File.exists?(dir)
    end)

    dir
  end

  defp present?(value), do: is_binary(value) and value != ""
end
