defmodule Cuckoding.ActivityStreamTest do
  use CuckodingWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cuckoding.ActivityStream
  alias Cuckoding.Adapters.Types
  alias Cuckoding.Execution
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows

  @now ~U[2026-09-17 22:00:00.000000Z]

  test "committed adapter events broadcast once and reconnect after the acknowledged sequence" do
    domain = domain_fixture()
    previous_metadata = Logger.metadata()
    Cuckoding.Correlation.put("activity-correlation")
    on_exit(fn -> Logger.reset_metadata(previous_metadata) end)

    assert {:ok, []} = ActivityStream.connect(domain.run.id, 0)
    first = provider_event("provider-1", 1, "Agent inspected the task")
    assert {:ok, first_command} = ActivityStream.record(domain.session, first)

    assert_receive {:activity_event, run_id, 1}
    assert run_id == domain.run.id
    persisted = Repo.get_by!(RunEvent, run_id: run_id, sequence: 1)
    assert persisted.payload["correlation"]["agent_session_id"] == domain.session.id
    refute inspect(persisted) =~ "must-not-persist"

    assert [stored] = ActivityStream.list(run_id, 0)
    assert stored.public_summary == "Agent inspected the task"
    assert stored.metadata["token"] == "[REDACTED]"

    assert stored.correlation == %{
             "project_id" => domain.project.id,
             "board_id" => domain.board.id,
             "task_id" => domain.task.id,
             "run_id" => domain.run.id,
             "stage_attempt_id" => domain.attempt.id,
             "agent_session_id" => domain.session.id,
             "role" => "implementer",
             "runtime" => "codex",
             "model" => "gpt-test",
             "correlation_id" => "activity-correlation"
           }

    stale_at = DateTime.add(stored.occurred_at, 61, :second)

    assert %{stale?: true, reconciling?: false} =
             ActivityStream.status([stored], stale_at, 60_000)

    assert {:ok, replayed} = ActivityStream.record(domain.session, first)
    assert replayed.id == first_command.id
    refute_receive {:activity_event, ^run_id, _sequence}, 50

    assert {:error, :invalid_activity_event} =
             ActivityStream.record(domain.session, %{first | metadata: []})

    :ok = Phoenix.PubSub.unsubscribe(Cuckoding.PubSub, "activity:#{run_id}")

    assert {:ok, _second} =
             ActivityStream.record(
               domain.session,
               provider_event("provider-2", 2, "Agent changed a file")
             )

    assert {:ok, [missed]} = ActivityStream.connect(run_id, 1)
    assert missed.sequence == 2
    assert ActivityStream.list(run_id, 2) == []
  end

  test "rolled-back events are neither persisted nor broadcast" do
    domain = domain_fixture()
    assert {:ok, []} = ActivityStream.connect(domain.run.id, 0)

    assert {:error, :forced_rollback} =
             EventStore.transaction(fn ->
               assert {:ok, {%RunEvent{}, nil}} =
                        EventStore.append_in_transaction(domain.run.id, %{
                          event_type: "agent.temporary",
                          public_summary: "Must roll back",
                          payload: %{}
                        })

               Repo.rollback(:forced_rollback)
             end)

    refute_receive {:activity_event, _, _}, 50
    assert ActivityStream.list(domain.run.id, 0) == []
  end

  test "LiveView renders sleep gaps and reconciling state in the activity table", %{conn: conn} do
    domain = domain_fixture()

    assert {:ok, {_event, nil}} =
             EventStore.append(domain.run.id, %{
               event_type: "run.reconciliation_continue",
               public_summary: "Run reconciled after an 8000 ms sleep gap: continue",
               payload: %{"gap_ms" => 8_000},
               occurred_at: Cuckoding.Clock.wall_now()
             })

    assert {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#activity-heading", "Recent activity")
    assert has_element?(view, "[aria-live=polite]", "Reconciling after sleep")
    assert has_element?(view, "table", "Sleep gap: 8000 ms")
    assert has_element?(view, "table", "Run reconciled after an 8000 ms sleep gap")
  end

  defp provider_event(id, sequence, summary) do
    %Types.Event{
      event_id: id,
      sequence: sequence,
      type: "agent.tool",
      public_summary: summary,
      metadata: %{"tool" => "read", "token" => "must-not-persist"},
      trust: :untrusted
    }
  end

  defp domain_fixture do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Activity Project #{suffix}",
        repo_path: "/tmp/activity-project-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/activity-workspaces-#{suffix}",
        port_range_start: 44_000,
        port_range_end: 44_100
      })

    {:ok, config} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: String.pad_leading(Integer.to_string(suffix, 16), 64, "0"),
        config_json: %{"version" => 1},
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
        name: "Activity Board #{suffix}",
        concurrency_limit: 1
      })

    {:ok, task} =
      Workflows.create_task(%{board_id: board.id, title: "Activity task", position: 0})

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: config.id,
        plugin_snapshot_json: %{},
        branch: "feature/activity-#{suffix}",
        base_sha: String.duplicate("a", 40)
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
        adapter_key: "codex",
        requested_model: "gpt-test",
        effective_grant_json: %{}
      })

    %{
      project: project,
      board: board,
      task: task,
      run: run,
      attempt: attempt,
      session: session
    }
  end
end
