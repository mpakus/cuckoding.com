defmodule Cuckoding.Adapters.AgentAdapterTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Adapters
  alias Cuckoding.Adapters.EventStream
  alias Cuckoding.Adapters.FakeAdapter
  alias Cuckoding.Adapters.Types
  alias Cuckoding.Execution
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows

  @now ~U[2026-09-17 23:50:00.000000Z]

  setup do
    run_dir =
      Path.join(System.tmp_dir!(), "cuckoding-adapter-#{System.unique_integer([:positive])}")

    worktree = Path.join(run_dir, "worktree")
    File.mkdir_p!(worktree)
    on_exit(fn -> File.rm_rf!(run_dir) end)

    request = %Types.StageRequest{
      project_id: Ecto.UUID.generate(),
      board_id: Ecto.UUID.generate(),
      task_id: Ecto.UUID.generate(),
      run_id: Ecto.UUID.generate(),
      stage_key: "implementation",
      attempt_id: Ecto.UUID.generate(),
      objective: "Implement the assigned change",
      worktree_path: worktree,
      run_dir: run_dir,
      requested_model: "requested-model",
      grant: %{
        "tools" => ["read", "write"],
        "paths" => [worktree],
        "approval_mode" => "default",
        "network" => "deny",
        "resource_limits" => %{"memory" => "advisory"}
      },
      knowledge: [%{"id" => "project:adapter-contract", "path" => "knowledge/adapter.md"}],
      plugins: [%{"id" => "test-skill", "kind" => "instruction"}],
      required_output_schema: %{"type" => "object"},
      correlation_id: Ecto.UUID.generate(),
      idempotency_key: "stage:#{Ecto.UUID.generate()}"
    }

    {:ok, request: request}
  end

  test "workflow runs through the fake contract with explicit unavailable facts", %{
    request: request
  } do
    assert {:ok, %Types.Probe{available?: true, authenticated?: true}} = FakeAdapter.probe([])
    assert {:ok, %Types.Capabilities{native_resume?: true}} = FakeAdapter.capabilities([])

    assert {:ok, grant} = FakeAdapter.render_config(request, [])
    assert grant.enforced["tools"] == ["read", "write"]
    assert grant.unenforced["network"] == "deny"

    config_path = Path.join([request.run_dir, "agent", "fake-adapter.json"])
    assert File.stat!(config_path).mode |> Bitwise.band(0o777) == 0o600
    config = config_path |> File.read!() |> Jason.decode!()
    assert config["knowledge"] == request.knowledge
    assert config["plugins"] == request.plugins
    assert config["grant"]["unenforced"]["network"] == "deny"

    assert {:ok, session} = FakeAdapter.start(request, [])
    assert session.requested_model == "requested-model"
    assert is_nil(session.actual_model)
    assert session.external_session_id == "fake-session"

    assert {:ok, event} =
             FakeAdapter.send(
               session,
               %{"summary" => "token secret-canary", "finding" => "none"},
               redact: ["secret-canary"]
             )

    assert event.trust == :untrusted
    refute event.public_summary =~ "secret-canary"

    assert {:ok, checkpoint} = FakeAdapter.pause(session, [])
    assert checkpoint["session_id"] == session.session_id
    assert {:ok, resumed} = FakeAdapter.resume(session, checkpoint, [])
    assert resumed.session_id == session.session_id

    assert {:ok, ^resumed} =
             FakeAdapter.recover(resumed, %{process: :matching, session: :available}, [])

    assert {:ok, recovered} =
             FakeAdapter.recover(resumed, %{process: :gone, session: :unavailable}, [])

    assert recovered.session_id == resumed.session_id

    assert {:ok, cancelled} = FakeAdapter.cancel(resumed, [])
    assert cancelled.state == "cancelled"

    assert {:ok, %Types.Usage{source: "unavailable", confidence: "unavailable"}} =
             FakeAdapter.collect_usage(session, [])

    assert {:ok, usage} =
             FakeAdapter.collect_usage(session,
               usage: %{
                 source: "provider",
                 confidence: "reported",
                 input_tokens: 10,
                 output_tokens: 5,
                 cost_micros: 12,
                 currency: "USD"
               }
             )

    assert usage.source == "provider"
    assert usage.input_tokens == 10

    assert {:error, %Types.Error{code: :cancelled, retryable?: false}} =
             FakeAdapter.cancel(session, failures: %{cancel: :cancelled})
  end

  test "events reorder, deduplicate, redact, and reject unknown provider output", %{
    request: request
  } do
    events = [
      event("two", 2, "tool.completed"),
      event("one", 1, "session.started"),
      event("two", 2, "tool.completed")
    ]

    assert {:ok, normalized} = EventStream.normalize(FakeAdapter, events)
    assert Enum.map(normalized, & &1.event_id) == ["one", "two"]
    assert Enum.all?(normalized, &(&1.trust == :untrusted))

    assert {:ok, citation} =
             FakeAdapter.decode_event(
               %{
                 "event_id" => "citation",
                 "sequence" => 3,
                 "type" => "knowledge.cited",
                 "summary" => "Used project:adapter-contract",
                 "metadata" => %{
                   "knowledge_id" => "project:adapter-contract",
                   "token" => "secret-canary"
                 }
               },
               redact: ["secret-canary"]
             )

    assert citation.metadata["knowledge_id"] == "project:adapter-contract"
    assert citation.metadata["token"] == "[REDACTED]"

    assert {:error, %Types.Error{code: :unknown_event, retryable?: false}} =
             FakeAdapter.decode_event(event("bad", 3, "provider.hidden_reasoning"), [])

    assert {:error, %Types.Error{code: :malformed_event}} =
             FakeAdapter.decode_event(%{"type" => "session.started"}, [])

    assert {:error, %Types.Error{code: :malformed_event}} =
             FakeAdapter.decode_event("not an event", [])

    assert {:error, %Types.Error{code: :timeout, category: :transient, retryable?: true}} =
             FakeAdapter.start(request, failures: %{start: :timeout})
  end

  test "configuration refuses a symlinked agent directory", %{request: request} do
    outside = request.run_dir <> "-outside"
    File.mkdir_p!(outside)
    on_exit(fn -> File.rm_rf!(outside) end)
    File.ln_s!(outside, Path.join(request.run_dir, "agent"))

    assert {:error, %Types.Error{code: :config_path_symlink, retryable?: false}} =
             FakeAdapter.render_config(request, [])

    refute File.exists?(Path.join(outside, "fake-adapter.json"))
  end

  test "bounded continuation fallback and effective grant observation remain explicit", %{
    request: request
  } do
    attributes = %{
      run_id: request.run_id,
      stage_key: request.stage_key,
      attempt_id: request.attempt_id,
      task_revision: 3,
      spec: %{"acceptance" => ["adapter conformance passes"]},
      summary: "Continue from the reviewed checkpoint",
      artifact_hashes: [String.duplicate("a", 64)],
      completed_checks: ["focused tests"],
      open_findings: []
    }

    assert {:ok, package} = Types.ContinuationPackage.build(attributes)

    assert {:ok, continued} =
             FakeAdapter.resume(package, %{"reason" => "process_lost"},
               requested_model: request.requested_model
             )

    assert continued.requested_model == request.requested_model
    assert is_nil(continued.actual_model)
    assert is_nil(continued.external_session_id)

    assert {:error, %Types.Error{code: :continuation_too_large}} =
             Types.ContinuationPackage.build(
               %{attributes | summary: String.duplicate("x", 100)},
               64
             )

    session_record = session_record_fixture()
    {:ok, observed} = FakeAdapter.start(request, actual_model: "actual-model")
    assert {:ok, recorded} = Adapters.record_session_observation(session_record, observed)
    assert recorded.requested_model == "requested-model"
    assert recorded.actual_model == "actual-model"
    assert recorded.external_session_id == "fake-session"

    persisted = Repo.reload!(recorded)
    assert persisted.effective_grant_json["unenforced"]["network"] == "deny"

    audit =
      Repo.get_by!(RunEvent,
        run_id: Repo.get!(Cuckoding.Execution.StageAttempt, recorded.stage_attempt_id).run_id,
        event_type: "agent.effective_grant_recorded"
      )

    assert audit.payload["agent_session_id"] == recorded.id
    assert audit.payload["unenforced_fields"] == ["network", "resource_limits"]
    refute inspect(audit.payload) =~ request.worktree_path
  end

  defp event(id, sequence, type) do
    %{
      "event_id" => id,
      "sequence" => sequence,
      "type" => type,
      "summary" => "Public #{type}",
      "metadata" => %{}
    }
  end

  defp session_record_fixture do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Adapter #{suffix}",
        repo_path: "/tmp/adapter-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/adapter-workspace-#{suffix}",
        port_range_start: 49_000,
        port_range_end: 49_100
      })

    {:ok, policy} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: String.pad_leading(Integer.to_string(suffix, 16), 64, "0"),
        config_json: %{"version" => 2},
        trusted_at: @now
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "default",
        version: 1,
        definition_json: %{"stages" => [%{"key" => "implementation", "role" => "implementer"}]},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Board",
        concurrency_limit: 1
      })

    {:ok, task} = Workflows.create_task(%{board_id: board.id, title: "Adapter", position: 1})

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: policy.id,
        plugin_snapshot_json: %{},
        branch: "feature/adapter-#{suffix}",
        base_sha: String.duplicate("b", 40)
      })

    {:ok, attempt} =
      Execution.create_stage_attempt(%{
        run_id: run.id,
        stage_key: "implementation",
        attempt: 1,
        role_key: "implementer",
        role_kind: "agent"
      })

    {:ok, session} =
      Execution.create_agent_session(%{
        stage_attempt_id: attempt.id,
        adapter_key: "fake",
        requested_model: "requested-model",
        effective_grant_json: %{}
      })

    Repo.get!(Cuckoding.Execution.AgentSession, session.id)
  end
end
