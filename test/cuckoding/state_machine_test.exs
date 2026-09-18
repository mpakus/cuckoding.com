defmodule Cuckoding.StateMachineTest do
  use Cuckoding.DataCase, async: false
  use ExUnitProperties

  import Ecto.Query

  alias Cuckoding.Execution
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows
  alias Cuckoding.Workflows.StateMachine
  alias Cuckoding.Workflows.Task

  @now ~U[2026-09-17 20:27:58.000000Z]

  property "every declared transition is accepted by its state machine" do
    generator =
      one_of(
        for kind <- [:task, :run] do
          kind
          |> StateMachine.transitions()
          |> Enum.map(&{kind, &1})
          |> member_of()
        end
      )

    check all({kind, {from, to}} <- generator) do
      reason = if to == "waiting", do: "approval"
      assert :ok = StateMachine.validate(kind, from, to, reason)
    end
  end

  property "every undeclared transition is rejected explicitly" do
    invalid_transitions =
      for kind <- [:task, :run],
          from <- StateMachine.states(kind),
          to <- StateMachine.states(kind),
          {from, to} not in StateMachine.transitions(kind),
          do: {kind, from, to}

    check all({kind, from, to} <- member_of(invalid_transitions)) do
      assert {:error, :invalid_transition} = StateMachine.validate(kind, from, to)
    end
  end

  test "run transitions update the task and append one ordered event exactly once" do
    domain = running_domain_fixture()
    start_key = domain.start_command.idempotency_key

    assert domain.start_command.result["outcome"] == "transitioned"
    assert domain.start_command.result["event_sequence"] == 1

    assert {:ok, replayed} =
             Execution.transition_run(domain.run.id, "waiting", start_key,
               wait_reason: "approval"
             )

    assert replayed.id == domain.start_command.id
    assert replayed.result == domain.start_command.result
    assert Repo.get!(Run, domain.run.id).state == "running"
    assert event_sequences(domain.run.id) == [1]

    assert {:ok, rejected} =
             Execution.transition_run(
               domain.run.id,
               "waiting",
               Ecto.UUID.generate()
             )

    assert rejected.result == %{
             "entity" => "run",
             "from" => "running",
             "id" => domain.run.id,
             "outcome" => "rejected",
             "reason" => "wait_reason_required",
             "to" => "waiting"
           }

    assert event_sequences(domain.run.id) == [1]

    assert {:ok, waiting} =
             Execution.transition_run(
               domain.run.id,
               "waiting",
               Ecto.UUID.generate(),
               wait_reason: "approval"
             )

    assert waiting.result["event_sequence"] == 2
    assert %{state: "waiting", wait_reason: "approval"} = Repo.get!(Run, domain.run.id)

    assert %{state: "waiting", wait_reason: "approval", active_run_id: run_id} =
             Repo.get!(Task, domain.task.id)

    assert run_id == domain.run.id

    assert {:ok, invalid} =
             Execution.transition_run(domain.run.id, "done", Ecto.UUID.generate())

    assert invalid.result["outcome"] == "rejected"
    assert invalid.result["reason"] == "invalid_transition"
    assert event_sequences(domain.run.id) == [1, 2]
  end

  test "standalone task transitions use a namespaced ordered event stream" do
    domain = domain_fixture()
    stream_id = "task:" <> domain.task.id
    key = Ecto.UUID.generate()

    assert {:ok, command} = Workflows.transition_task(domain.task.id, "ready", key)
    assert command.result["outcome"] == "transitioned"
    assert event_sequences(stream_id) == [1]

    assert {:ok, replayed} = Workflows.transition_task(domain.task.id, "ready", key)
    assert replayed.result == command.result
    assert event_sequences(stream_id) == [1]

    assert {:ok, rejected} =
             Workflows.transition_task(domain.task.id, "running", Ecto.UUID.generate())

    assert rejected.result["reason"] == "run_transition_required"
    assert event_sequences(stream_id) == [1]
  end

  test "stage timing keeps active and wall duration separate and is idempotent" do
    domain = running_domain_fixture()
    key = Ecto.UUID.generate()

    assert {:ok, command} = Execution.record_stage_time(domain.attempt.id, 250, 900, key)
    assert command.result["outcome"] == "recorded"

    assert %{active_ms: 250, wall_ms: 900} = Repo.get!(StageAttempt, domain.attempt.id)

    assert {:ok, replayed} = Execution.record_stage_time(domain.attempt.id, 250, 900, key)
    assert replayed.result == command.result
    assert %{active_ms: 250, wall_ms: 900} = Repo.get!(StageAttempt, domain.attempt.id)

    assert {:ok, rejected} =
             Execution.record_stage_time(domain.attempt.id, 901, 900, Ecto.UUID.generate())

    assert rejected.result["reason"] == "invalid_duration"
    assert event_sequences(domain.run.id) == [1, 2]
  end

  test "run creation freezes trusted workflow, role, and policy versions" do
    domain = domain_fixture()

    {:ok, role} =
      Workflows.assign_role(%{
        board_id: domain.board.id,
        role_key: "implementer",
        role_kind: "agent",
        adapter_key: "codex",
        model_ref: "configured",
        settings_json: %{"effort" => "high"}
      })

    {:ok, run} = create_run(domain, 1, domain.config.id)

    assert run.workflow_snapshot_json == %{
             "workflow_version_id" => domain.workflow.id,
             "name" => "default",
             "version" => 1,
             "definition" => domain.workflow.definition_json,
             "roles" => [
               %{
                 "role_key" => role.role_key,
                 "role_kind" => "agent",
                 "adapter_key" => "codex",
                 "model_ref" => "configured",
                 "settings" => %{"effort" => "high"}
               }
             ]
           }

    assert run.policy_snapshot_id == domain.config.id

    assert_raise Exqlite.Error, ~r/immutable/, fn ->
      Repo.update_all(
        from(workflow in Cuckoding.Workflows.WorkflowVersion,
          where: workflow.id == ^domain.workflow.id
        ),
        set: [name: "changed"]
      )
    end

    {:ok, untrusted} =
      Projects.add_config_version(%{
        project_id: domain.project.id,
        revision: 2,
        source_hash: String.duplicate("b", 64),
        config_json: %{"version" => 2}
      })

    assert {:error, :policy_not_trusted} = create_run(domain, 2, untrusted.id)
  end

  defp running_domain_fixture do
    domain = domain_fixture()
    {:ok, _ready} = Workflows.transition_task(domain.task.id, "ready", Ecto.UUID.generate())
    {:ok, run} = create_run(domain, 1, domain.config.id)

    {:ok, attempt} =
      Execution.create_stage_attempt(%{
        run_id: run.id,
        stage_key: "implementation",
        attempt: 1,
        role_key: "implementer",
        role_kind: "agent"
      })

    {:ok, start_command} =
      Execution.transition_run(run.id, "running", Ecto.UUID.generate())

    Map.merge(domain, %{run: run, attempt: attempt, start_command: start_command})
  end

  defp domain_fixture do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "State Project #{suffix}",
        repo_path: "/tmp/state-project-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/state-workspaces-#{suffix}",
        port_range_start: 42_000,
        port_range_end: 42_100
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
        name: "State Board #{suffix}",
        concurrency_limit: 1
      })

    {:ok, task} =
      Workflows.create_task(%{board_id: board.id, title: "State task", position: 0})

    %{project: project, config: config, workflow: workflow, board: board, task: task}
  end

  defp create_run(domain, sequence, policy_snapshot_id) do
    Execution.create_run(%{
      task_id: domain.task.id,
      sequence: sequence,
      workflow_snapshot_json: %{"forged" => true},
      policy_snapshot_id: policy_snapshot_id,
      plugin_snapshot_json: %{},
      branch: "feature/state-#{sequence}",
      base_sha: String.duplicate("a", 40)
    })
  end

  defp event_sequences(stream_id) do
    Repo.all(
      from(event in RunEvent,
        where: event.run_id == ^stream_id,
        order_by: event.sequence,
        select: event.sequence
      )
    )
  end
end
