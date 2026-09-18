defmodule Cuckoding.ReconcilerTest do
  use Cuckoding.DataCase, async: false
  use ExUnitProperties

  alias Cuckoding.Execution
  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.Leases
  alias Cuckoding.Execution.ProcessRecord
  alias Cuckoding.Execution.Reconciler
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Execution.UnavailableRecoveryInspector
  alias Cuckoding.FakeRecoveryInspector
  alias Cuckoding.Projects
  alias Cuckoding.Workflows
  alias Cuckoding.Workflows.Task

  @now ~U[2026-09-17 20:42:53.000000Z]

  test "a surviving process continues exactly once when every identity matches" do
    fixture = running_fixture()
    options = healthy_inspection(fixture)

    assert {:ok, summary} = Reconciler.run(options)
    assert [continue_result] = summary.decisions
    assert {:ok, command} = continue_result
    assert command.result["outcome"] == "continue"
    assert Repo.get!(Run, fixture.run.id).state == "running"
    assert Repo.get!(ProcessRecord, fixture.process.id).state == "running"

    assert Repo.aggregate(
             from(event in RunEvent,
               where:
                 event.run_id == ^fixture.run.id and
                   event.event_type == "run.reconciliation_continue"
             ),
             :count
           ) == 1

    assert {:ok, %{decisions: [{:ok, replayed}]}} = Reconciler.run(options)
    assert replayed.id == command.id
    assert count_attempts(fixture.run.id) == 1
  end

  property "interrupted process fixtures recover without starting a duplicate stage" do
    check all(_variation <- integer(1..20), max_runs: 20) do
      fixture = running_fixture()

      options =
        inspection_options(fixture,
          process: :gone,
          port: :free,
          worktree: :present
        )

      assert {:ok, %{decisions: [{:ok, command}]}} = Reconciler.run(options)
      assert command.result["outcome"] == "recover"
      assert command.result["reasons"] == ["process_missing"]

      assert %{state: "waiting", wait_reason: "reconciliation"} =
               Repo.get!(Run, fixture.run.id)

      assert %{state: "waiting", wait_reason: "reconciliation"} =
               Repo.get!(Task, fixture.task.id)

      assert Repo.get!(ProcessRecord, fixture.process.id).state == "lost"
      assert Repo.get!(Environment, fixture.environment.id).state == "failed"
      assert Repo.get!(StageAttempt, fixture.attempt.id).state == "waiting"
      assert Repo.get!(AgentSession, fixture.session.id).state == "interrupted"
      assert count_attempts(fixture.run.id) == 1
    end
  end

  test "a reused PID blocks the run without adopting or changing the process record" do
    fixture = running_fixture()

    options =
      inspection_options(fixture,
        process: {:ok, "different-process"},
        port: {:ok, fixture.process.pid, "different-process"},
        worktree: :present
      )

    assert {:ok, %{decisions: [{:ok, command}]}} = Reconciler.run(options)
    assert command.result["outcome"] == "block"
    assert command.result["reasons"] == ["process_identity_mismatch"]
    assert Repo.get!(Run, fixture.run.id).state == "blocked"
    assert Repo.get!(Task, fixture.task.id).state == "blocked"
    assert Repo.get!(ProcessRecord, fixture.process.id).state == "running"
    assert count_attempts(fixture.run.id) == 1
  end

  test "worktree drift and unknown port ownership block instead of guessing" do
    drifted = running_fixture()

    assert {:ok, %{decisions: [{:ok, drift_command}]}} =
             Reconciler.run(
               inspection_options(drifted,
                 process: {:ok, drifted.process.start_identity},
                 port: {:ok, drifted.process.pid, drifted.process.start_identity},
                 worktree: {:drift, :base_sha_changed}
               )
             )

    assert drift_command.result["reasons"] == ["worktree_drift"]

    conflicted = running_fixture()

    assert {:ok, %{decisions: [{:ok, conflict_command}]}} =
             Reconciler.run(
               inspection_options(conflicted,
                 process: {:ok, conflicted.process.start_identity},
                 port: {:ok, 65_000, "unknown-owner"},
                 worktree: :present
               )
             )

    assert conflict_command.result["outcome"] == "block"
    assert conflict_command.result["reasons"] == ["port_ownership_conflict"]
  end

  test "an unavailable host inspector blocks an active environment" do
    fixture = running_fixture()

    assert {:ok, %{decisions: [{:ok, command}]}} =
             Reconciler.run(
               now: @now,
               cycle_id: "unavailable",
               run_ids: [fixture.run.id],
               inspector: UnavailableRecoveryInspector
             )

    assert command.result["outcome"] == "block"
    assert command.result["reasons"] == ["worktree_unverified"]
    assert Repo.get!(ProcessRecord, fixture.process.id).state == "running"
  end

  test "sleep-gap leases extend before expiry and the run records the measured gap" do
    fixture = running_fixture()
    lease_start = DateTime.add(@now, -10_000, :millisecond)

    assert {:ok, lease, _token} =
             Leases.acquire("run", fixture.run.id, "reconciler-test", 5_000, now: lease_start)

    assert {:ok, summary} =
             Reconciler.run(
               healthy_inspection(fixture,
                 now: @now,
                 gap_ms: 10_000,
                 cycle_id: "sleep-test"
               )
             )

    assert summary.extended_leases == 1
    assert summary.expired_leases == 0
    assert is_nil(Repo.get!(Cuckoding.Execution.Lease, lease.id).released_at)

    event =
      Repo.one!(
        from(event in RunEvent,
          where: event.run_id == ^fixture.run.id and event.event_type == "run.resumed_after_sleep"
        )
      )

    assert event.payload["gap_ms"] == 10_000
  end

  test "a killed database transaction leaves no invented transition or event" do
    path =
      Path.join(
        System.tmp_dir!(),
        "cuckoding-power-loss-#{System.unique_integer([:positive])}.sqlite3"
      )

    on_exit(fn -> File.rm(path) end)

    {:ok, connection} = Exqlite.Sqlite3.open(path)
    :ok = Exqlite.Sqlite3.execute(connection, "CREATE TABLE projections (state TEXT)")
    :ok = Exqlite.Sqlite3.execute(connection, "CREATE TABLE events (summary TEXT)")
    :ok = Exqlite.Sqlite3.close(connection)

    parent = self()

    pid =
      spawn(fn ->
        {:ok, connection} = Exqlite.Sqlite3.open(path)
        :ok = Exqlite.Sqlite3.execute(connection, "BEGIN IMMEDIATE")
        :ok = Exqlite.Sqlite3.execute(connection, "INSERT INTO projections VALUES ('blocked')")
        :ok = Exqlite.Sqlite3.execute(connection, "INSERT INTO events VALUES ('blocked')")
        send(parent, :transaction_open)
        Process.sleep(:infinity)
      end)

    assert_receive :transaction_open
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}

    {:ok, connection} = Exqlite.Sqlite3.open(path)
    assert table_count(connection, "projections") == 0
    assert table_count(connection, "events") == 0
    :ok = Exqlite.Sqlite3.close(connection)
  end

  defp running_fixture do
    suffix = System.unique_integer([:positive])
    port = 45_000 + rem(suffix, 10_000)
    pid = 10_000 + rem(suffix, 50_000)
    identity = "start-#{suffix}"

    {:ok, project} =
      Projects.register(%{
        name: "Recovery Project #{suffix}",
        repo_path: "/tmp/recovery-project-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/recovery-workspaces-#{suffix}",
        port_range_start: port,
        port_range_end: port
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
        name: "recovery",
        version: 1,
        definition_json: %{"stages" => []},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Recovery Board #{suffix}",
        concurrency_limit: 1
      })

    {:ok, task} =
      Workflows.create_task(%{board_id: board.id, title: "Recover", position: 0})

    {:ok, _command} = Workflows.transition_task(task.id, "ready", Ecto.UUID.generate())

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: config.id,
        plugin_snapshot_json: %{},
        branch: "feature/recovery-#{suffix}",
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
        adapter_key: "fake",
        requested_model: "fake",
        effective_grant_json: %{}
      })

    worktree_path = "/tmp/recovery-worktree-#{suffix}"

    {:ok, environment} =
      Execution.create_environment(%{
        run_id: run.id,
        runner_key: "fake",
        kind: "local_process",
        worktree_path: worktree_path,
        run_dir: "/tmp/recovery-run-#{suffix}",
        base_sha: String.duplicate("a", 40),
        port: port,
        ports_json: %{"preview" => port},
        isolation_claims_json: %{"kind" => "trusted-host"}
      })

    environment = environment |> Ecto.Changeset.change(state: "running") |> Repo.update!()

    {:ok, process} =
      Execution.record_process(%{
        environment_id: environment.id,
        agent_session_id: session.id,
        pid: pid,
        pgid: pid,
        start_identity: identity,
        role: "agent"
      })

    {:ok, _command} = Execution.transition_run(run.id, "running", Ecto.UUID.generate())

    %{
      run: Repo.get!(Run, run.id),
      task: Repo.get!(Task, task.id),
      attempt: attempt,
      session: session,
      environment: environment,
      process: process,
      port: port,
      worktree_path: worktree_path
    }
  end

  defp healthy_inspection(fixture, extra \\ []) do
    inspection_options(
      fixture,
      [
        process: {:ok, fixture.process.start_identity},
        port: {:ok, fixture.process.pid, fixture.process.start_identity},
        worktree: :present
      ] ++ extra
    )
  end

  defp inspection_options(fixture, options) do
    [
      inspector: FakeRecoveryInspector,
      inspector_options: [
        processes: %{fixture.process.pid => Keyword.fetch!(options, :process)},
        ports: %{fixture.port => Keyword.fetch!(options, :port)},
        worktrees: %{fixture.worktree_path => Keyword.fetch!(options, :worktree)}
      ],
      now: Keyword.get(options, :now, @now),
      gap_ms: Keyword.get(options, :gap_ms, 0),
      cycle_id: Keyword.get(options, :cycle_id, "test-cycle"),
      run_ids: [fixture.run.id]
    ]
  end

  defp count_attempts(run_id) do
    Repo.aggregate(from(attempt in StageAttempt, where: attempt.run_id == ^run_id), :count)
  end

  defp table_count(connection, table) do
    {:ok, statement} = Exqlite.Sqlite3.prepare(connection, "SELECT COUNT(*) FROM #{table}")
    {:row, [count]} = Exqlite.Sqlite3.step(connection, statement)
    :ok = Exqlite.Sqlite3.release(connection, statement)
    count
  end
end
