defmodule Cuckoding.Execution.SchedulerTest do
  use Cuckoding.DataCase, async: false

  import Ecto.Query

  alias Cuckoding.Execution
  alias Cuckoding.Execution.BoardControl
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Execution.Scheduler
  alias Cuckoding.Power
  alias Cuckoding.Power.Manager
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Definition

  @now ~U[2026-09-18 02:30:00.000000Z]

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Scheduler #{suffix}",
        repo_path: "/tmp/scheduler-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/scheduler-workspaces-#{suffix}",
        port_range_start: 52_000,
        port_range_end: 52_010
      })

    {:ok, policy} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: String.pad_leading(Integer.to_string(suffix, 16), 64, "0"),
        config_json: %{
          "resources" => %{
            "per_project" => %{"max_active_runs" => 2},
            "per_run" => %{"memory_mb_ceiling" => 1}
          },
          "unattended" => %{"allowed" => true, "max_window_hours" => 12}
        },
        trusted_at: @now
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "default",
        version: 1,
        definition_json: Definition.default(),
        published_at: @now
      })

    {:ok, board_a} = board(project.id, workflow.id, "Product")
    {:ok, board_b} = board(project.id, workflow.id, "Maintenance")
    {:ok, task_a} = ready_task(board_a.id, "Product task", 5)
    {:ok, task_b} = ready_task(board_b.id, "Maintenance task", 1)

    %{
      project: project,
      policy: policy,
      workflow: workflow,
      board_a: board_a,
      board_b: board_b,
      task_a: task_a,
      task_b: task_b
    }
  end

  test "admits two boards concurrently without crossing ownership", fixture do
    assert {:ok, plan} =
             Scheduler.plan(
               global_limit: 2,
               resource_probe: probe(8, 4)
             )

    assert MapSet.new(Enum.map(plan.candidates, & &1.board.id)) ==
             MapSet.new([fixture.board_a.id, fixture.board_b.id])

    assert Enum.all?(plan.candidates, &(&1.task.board_id == &1.board.id))

    parent = self()

    assert {:ok, dispatched} =
             Scheduler.dispatch(
               global_limit: 2,
               resource_probe: probe(8, 4),
               dispatcher: %{
                 start: fn candidate ->
                   send(parent, {:started, candidate})
                   {:ok, :started}
                 end
               }
             )

    assert length(dispatched.dispatches) == 2
    assert_receive {:started, %{board: %{id: board_id_1}, task: %{board_id: board_id_1}}}
    assert_receive {:started, %{board: %{id: board_id_2}, task: %{board_id: board_id_2}}}
  end

  test "rotates toward an unscheduled board and honors dependencies", fixture do
    run = run_task(fixture.task_a, fixture.policy, "done")
    assert Repo.get!(Execution.Run, run.id).state == "done"

    {:ok, newer_a} = ready_task(fixture.board_a.id, "Next product task", 100)

    {:ok, prerequisite} =
      Workflows.create_task(%{board_id: fixture.board_b.id, title: "Prerequisite", position: 10})

    {:ok, blocked} = ready_task(fixture.board_b.id, "Blocked task", 200)
    assert {:ok, _dependency} = Workflows.add_dependency(blocked.id, prerequisite.id)

    assert {:ok, plan} =
             Scheduler.plan(global_limit: 1, resource_probe: probe(8, 4))

    assert [%{task: %{id: selected_id}, board: %{id: selected_board_id}}] = plan.candidates
    assert selected_id == fixture.task_b.id
    assert selected_board_id == fixture.board_b.id
    assert Enum.any?(plan.deferred, &(&1.task_id == blocked.id and &1.reason == :dependency))
    refute Enum.any?(plan.candidates, &(&1.task.id in [newer_a.id, blocked.id]))
  end

  test "fails closed on project, port, and memory headroom", fixture do
    _run = run_task(fixture.task_a, fixture.policy, "running")
    {:ok, second_a} = ready_task(fixture.board_a.id, "Second product task", 9)

    {:ok, _stricter} =
      Projects.add_config_version(%{
        project_id: fixture.project.id,
        revision: 2,
        source_hash: String.duplicate("f", 64),
        config_json: %{
          "resources" => %{
            "per_project" => %{"max_active_runs" => 1},
            "per_run" => %{"memory_mb_ceiling" => 2}
          }
        },
        trusted_at: @now
      })

    assert {:ok, limited} = Scheduler.plan(global_limit: 4, resource_probe: probe(8, 4))

    assert Enum.any?(
             limited.deferred,
             &(&1.task_id == fixture.task_b.id and &1.reason == :project_concurrency_limit)
           )

    assert {:ok, cannot_raise_policy} =
             Scheduler.plan(
               global_limit: 4,
               resource_probe: probe(8, 4),
               project_limits: %{fixture.project.id => 8}
             )

    assert Enum.any?(
             cannot_raise_policy.deferred,
             &(&1.task_id == fixture.task_b.id and &1.reason == :project_concurrency_limit)
           )

    assert Enum.any?(
             limited.deferred,
             &(&1.task_id == second_a.id and &1.reason == :board_concurrency_limit)
           )

    finish_run_for_test(fixture.task_a)

    assert {:ok, no_port} = Scheduler.plan(global_limit: 4, resource_probe: probe(8, 0))
    assert Enum.all?(no_port.deferred, &(&1.reason in [:no_port_headroom, :dependency]))

    assert {:ok, no_memory} = Scheduler.plan(global_limit: 4, resource_probe: probe(1, 4))
    assert Enum.all?(no_memory.deferred, &(&1.reason in [:memory_headroom, :dependency]))
  end

  test "an active agent session consumes the global slot", fixture do
    run = run_task(fixture.task_a, fixture.policy, "done")

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
        effective_grant_json: %{}
      })

    assert {:ok, plan} = Scheduler.plan(global_limit: 1, resource_probe: probe(8, 4))
    assert plan.candidates == []

    assert Enum.any?(
             plan.deferred,
             &(&1.task_id == fixture.task_b.id and &1.reason == :global_session_limit)
           )
  end

  test "pauses one board before delegating hibernation and leaves the other board active",
       fixture do
    run = run_task(fixture.task_a, fixture.policy, "running")
    parent = self()

    assert {:ok, result} =
             BoardControl.control(fixture.board_a.id, :hibernate,
               run_controller: %{
                 hibernate: fn controlled ->
                   send(parent, {:hibernate, controlled.id})
                   {:ok, :hibernated}
                 end
               }
             )

    assert result.board.status == "paused"
    assert_receive {:hibernate, run_id}
    assert run_id == run.id
    assert Repo.get!(Board, fixture.board_b.id).status == "active"
    assert {:ok, %{status: "active"}} = BoardControl.resume(fixture.board_a.id)

    assert Repo.exists?(
             from(event in RunEvent,
               where: event.run_id == ^("board:" <> fixture.board_a.id),
               where: event.event_type == "board.transitioned"
             )
           )
  end

  test "overnight unattended window queues approval notification and releases assertion on expiry",
       fixture do
    run = run_task(fixture.task_a, fixture.policy, "waiting")

    {:ok, approval} =
      Workflows.request_approval(%{run_id: run.id, kind: "release"})

    future = DateTime.add(Cuckoding.Clock.wall_now(), 3_600, :second)
    assert {:ok, unattended} = Power.set_unattended(fixture.board_a, future)

    assert {:error, :unattended_window_too_long} =
             Power.set_unattended(unattended, DateTime.add(Cuckoding.Clock.wall_now(), 13, :hour))

    parent = self()

    notifier = %{
      notify: fn notification ->
        send(parent, {:notification, notification})
        :ok
      end
    }

    dispatcher = %{start: fn _candidate -> {:ok, :started} end}

    assert {:ok, dispatched} =
             Scheduler.dispatch(
               global_limit: 4,
               resource_probe: probe(8, 4),
               dispatcher: dispatcher,
               notifier: notifier
             )

    assert_receive {:notification,
                    %{
                      approval_id: approval_id,
                      idempotency_key: idempotency_key,
                      kind: :approval_waiting
                    }}

    assert approval_id == approval.id
    assert idempotency_key == "unattended:approval:#{approval.id}"
    assert [{%{approval_id: ^approval_id}, :ok}] = dispatched.notification_results

    assertion_driver = %{
      hold: fn _owner_pid, _options ->
        send(parent, :assertion_held)
        {:ok, %{pid: 123}}
      end,
      release: fn _assertion ->
        send(parent, :assertion_released)
        :ok
      end
    }

    {:ok, manager} =
      Manager.start_link(
        name: nil,
        enabled: true,
        tick_ms: :infinity,
        clock: fn -> {:ok, %{continuous_ms: 1_000, uptime_ms: 1_000}} end,
        assertion_module: assertion_driver,
        reconciler: fn _options -> {:error, :unexpected_reconciliation} end
      )

    assert {:ok, %{assertion_held?: true}} = Manager.tick(manager)
    assert_receive :assertion_held

    expired = DateTime.add(Cuckoding.Clock.wall_now(), -1, :second)

    assert {:ok, _board} =
             Repo.update(Board.unattended_changeset(unattended, %{unattended_until: expired}))

    assert {:ok, %{assertion_held?: false}} = Manager.tick(manager)
    assert_receive :assertion_released
  end

  defp board(project_id, workflow_id, name) do
    Workflows.create_board(%{
      project_id: project_id,
      workflow_version_id: workflow_id,
      name: name,
      concurrency_limit: 1
    })
  end

  defp ready_task(board_id, title, priority) do
    position = System.unique_integer([:positive])

    with {:ok, task} <-
           Workflows.create_task(%{
             board_id: board_id,
             title: title,
             priority: priority,
             position: position
           }),
         {:ok, %{result: %{"outcome" => "transitioned"}}} <-
           Workflows.transition_task(task.id, "ready", "scheduler:#{task.id}:ready") do
      {:ok, Repo.reload(task)}
    end
  end

  defp run_task(task, policy, state) do
    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: policy.id,
        plugin_snapshot_json: %{},
        branch: "feature/scheduler-#{task.id}",
        base_sha: String.duplicate("a", 40)
      })

    {:ok, _command} = Execution.transition_run(run.id, "running", "scheduler:#{run.id}:running")

    case state do
      "running" ->
        :ok

      "waiting" ->
        {:ok, _command} =
          Execution.transition_run(run.id, "waiting", "scheduler:#{run.id}:waiting", %{
            wait_reason: "approval"
          })

      "done" ->
        {:ok, _command} = Execution.transition_run(run.id, "done", "scheduler:#{run.id}:done")
    end

    Repo.reload(run)
  end

  defp finish_run_for_test(task) do
    run = Repo.get!(Execution.Run, Repo.get!(Workflows.Task, task.id).active_run_id)
    {:ok, _command} = Execution.transition_run(run.id, "done", "scheduler:#{run.id}:done")
  end

  defp probe(memory_mb, ports) do
    %{
      memory_available_bytes: fn -> {:ok, memory_mb * 1_048_576} end,
      available_ports: fn _project -> {:ok, ports} end
    }
  end
end
