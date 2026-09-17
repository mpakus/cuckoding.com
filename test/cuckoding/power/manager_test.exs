defmodule Cuckoding.Power.ManagerTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution
  alias Cuckoding.Execution.LocalHostInspector
  alias Cuckoding.Power
  alias Cuckoding.Power.Caffeinate
  alias Cuckoding.Power.MacOSClock
  alias Cuckoding.Power.Manager
  alias Cuckoding.Power.PowerEvent
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows
  alias Cuckoding.Workflows.Approval

  @now ~U[2026-09-17 23:30:00.000000Z]

  test "records one simulated sleep gap and holds assertions only while eligible" do
    domain = running_domain()
    parent = self()

    samples = [
      %{continuous_ms: 2_000, uptime_ms: 3_000},
      %{continuous_ms: 12_000, uptime_ms: 5_000},
      %{continuous_ms: 13_000, uptime_ms: 6_000},
      %{continuous_ms: 14_000, uptime_ms: 7_000},
      %{continuous_ms: 15_000, uptime_ms: 8_000}
    ]

    {:ok, clock} = Agent.start_link(fn -> samples end)
    {:ok, assertion_counter} = Agent.start_link(fn -> 0 end)

    sample = fn ->
      Agent.get_and_update(clock, fn [current | remaining] ->
        {{:ok, current}, remaining}
      end)
    end

    assertion_driver = %{
      hold: fn owner_pid, options ->
        pid = Agent.get_and_update(assertion_counter, &{&1 + 10_000, &1 + 1})
        send(parent, {:assertion_held, owner_pid, options, pid})
        {:ok, %{pid: pid}}
      end,
      release: fn assertion ->
        send(parent, {:assertion_released, assertion.pid})
        :ok
      end
    }

    reconciler = fn options ->
      send(parent, {:reconciled, options})

      {:ok,
       %{
         extended_leases: 1,
         expired_leases: [],
         recovered_commands: 0,
         dispatched_commands: 0,
         decisions: []
       }}
    end

    {:ok, manager} =
      Manager.start_link(
        name: nil,
        enabled: true,
        tick_ms: :infinity,
        tolerance_ms: 1_000,
        clock: sample,
        assertion_module: assertion_driver,
        reconciler: reconciler
      )

    assert {:ok, %{assertion_held?: true}} = Manager.tick(manager)
    assert_receive {:assertion_held, owner_pid, [prevent_display_sleep: false], first_pid}
    assert owner_pid == System.pid()

    assert {:ok, %{assertion_held?: true}} = Manager.tick(manager)
    assert_receive {:reconciled, reconciliation}
    assert reconciliation[:gap_ms] == 8_000
    assert reconciliation[:run_ids] == [domain.run.id]
    refute_received {:assertion_held, _, _, _}

    events = Repo.all(from(event in PowerEvent, order_by: event.occurred_at))
    assert Enum.count(events, &(&1.kind == "sleep_gap")) == 1
    assert Enum.count(events, &(&1.kind == "wake_reconciled")) == 1
    assert Enum.find(events, &(&1.kind == "sleep_gap")).gap_ms == 8_000
    assert Repo.aggregate(Cuckoding.Execution.StageAttempt, :count, :id) == 1

    {:ok, _command} =
      Execution.transition_run(domain.run.id, "waiting", "wait-#{domain.run.id}", %{
        wait_reason: "approval"
      })

    {:ok, approval} =
      Workflows.request_approval(%{
        run_id: domain.run.id,
        stage_attempt_id: domain.attempt.id,
        kind: "policy_exception"
      })

    assert {:ok, %{assertion_held?: false}} = Manager.tick(manager)
    assert_receive {:assertion_released, ^first_pid}
    assert Repo.get!(Approval, approval.id).decision == "pending"

    future = DateTime.add(Cuckoding.Clock.wall_now(), 3_600, :second)
    assert {:ok, unattended_board} = Power.set_unattended(domain.board, future)
    assert unattended_board.unattended_until == future

    assert {:ok, %{assertion_held?: true}} = Manager.tick(manager)
    assert_receive {:assertion_held, _, _, second_pid}
    assert Repo.get!(Approval, approval.id).decision == "pending"

    assert {:ok, _board} = Power.set_unattended(unattended_board, nil)
    assert {:ok, %{assertion_held?: false}} = Manager.tick(manager)
    assert_receive {:assertion_released, ^second_pid}
  end

  test "macOS clock and caffeinate driver expose and release owned resources" do
    assert {:ok, %{continuous_ms: continuous, uptime_ms: uptime}} = MacOSClock.sample()
    assert continuous > 0
    assert uptime > 0

    assert {:ok, assertion} = Caffeinate.hold(System.pid())
    assert {:ok, identity} = LocalHostInspector.process_identity(assertion.pid, [])
    assert identity == assertion.start_identity
    assert :ok = Caffeinate.release(assertion)
    assert :gone = await_gone(assertion.pid)
  end

  test "failed wake reconciliation retries the same durable gap cycle" do
    parent = self()

    {:ok, clock} =
      Agent.start_link(fn ->
        [
          %{continuous_ms: 1_000, uptime_ms: 1_000},
          %{continuous_ms: 7_000, uptime_ms: 2_000},
          %{continuous_ms: 8_000, uptime_ms: 3_000}
        ]
      end)

    sample = fn ->
      Agent.get_and_update(clock, fn [current | remaining] ->
        {{:ok, current}, remaining}
      end)
    end

    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    reconciler = fn options ->
      attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})
      send(parent, {:reconciliation_attempt, attempt, options[:cycle_id]})

      if attempt == 1 do
        {:error, :temporary_probe_failure}
      else
        {:ok,
         %{
           extended_leases: 0,
           expired_leases: [],
           recovered_commands: 0,
           dispatched_commands: 0,
           decisions: []
         }}
      end
    end

    assertion_driver = %{
      hold: fn _owner, _options -> {:ok, %{pid: 1}} end,
      release: fn _assertion -> :ok end
    }

    {:ok, manager} =
      Manager.start_link(
        name: nil,
        enabled: true,
        tick_ms: :infinity,
        clock: sample,
        assertion_module: assertion_driver,
        reconciler: reconciler
      )

    assert {:ok, _status} = Manager.tick(manager)

    assert {:error, :temporary_probe_failure} = Manager.tick(manager)
    assert %{wake_reconciliation_pending?: true} = Manager.status(manager)
    assert_receive {:reconciliation_attempt, 1, cycle_id}

    assert {:ok, %{wake_reconciliation_pending?: false}} = Manager.tick(manager)
    assert_receive {:reconciliation_attempt, 2, ^cycle_id}

    assert Repo.aggregate(from(event in PowerEvent, where: event.kind == "sleep_gap"), :count) ==
             1

    assert Repo.aggregate(
             from(event in PowerEvent, where: event.kind == "wake_reconciled"),
             :count
           ) == 1
  end

  test "gap detection ignores equal clock movement and its tolerance boundary" do
    previous = %{continuous_ms: 1_000, uptime_ms: 2_000}
    assert Manager.gap_ms(previous, %{continuous_ms: 5_000, uptime_ms: 6_000}, 1_000) == 0
    assert Manager.gap_ms(previous, %{continuous_ms: 6_000, uptime_ms: 6_000}, 1_000) == 0
    assert Manager.gap_ms(previous, %{continuous_ms: 6_001, uptime_ms: 6_000}, 1_000) == 1_001
  end

  defp running_domain do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Power #{suffix}",
        repo_path: "/tmp/power-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/power-workspaces-#{suffix}",
        port_range_start: 48_000,
        port_range_end: 48_100
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
        definition_json: %{"stages" => []},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Board",
        concurrency_limit: 1
      })

    {:ok, task} =
      Workflows.create_task(%{board_id: board.id, title: "Power task", position: 1})

    {:ok, _command} = Workflows.transition_task(task.id, "ready", "ready-#{task.id}")

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: policy.id,
        plugin_snapshot_json: %{},
        branch: "feature/power-#{suffix}",
        base_sha: String.duplicate("a", 40)
      })

    {:ok, _command} = Execution.transition_run(run.id, "running", "running-#{run.id}")

    {:ok, attempt} =
      Execution.create_stage_attempt(%{
        run_id: run.id,
        stage_key: "implementation",
        attempt: 1,
        role_key: "implementer",
        role_kind: "agent"
      })

    {:ok, _session} =
      Execution.create_agent_session(%{
        stage_attempt_id: attempt.id,
        adapter_key: "fake",
        runtime_version: "1",
        requested_model: "fake",
        effective_grant_json: %{}
      })

    %{board: board, run: Repo.get!(Cuckoding.Execution.Run, run.id), attempt: attempt}
  end

  defp await_gone(pid, attempts \\ 100)
  defp await_gone(_pid, 0), do: {:error, :still_running}

  defp await_gone(pid, attempts) do
    case LocalHostInspector.process_identity(pid, []) do
      :gone ->
        :gone

      _other ->
        Process.sleep(10)
        await_gone(pid, attempts - 1)
    end
  end
end
