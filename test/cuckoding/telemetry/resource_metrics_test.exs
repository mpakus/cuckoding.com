defmodule Cuckoding.Telemetry.ResourceMetricsTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Identifier
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Telemetry.MetricRollup
  alias Cuckoding.Telemetry.ResourceRollups
  alias Cuckoding.Telemetry.ResourceSample
  alias Cuckoding.Telemetry.ResourceSampler
  alias Cuckoding.Workflows

  @now ~U[2026-09-17 22:30:00.000000Z]

  test "the supervised sampler can be disabled without starting a process" do
    assert :ignore = ResourceSampler.start_link(enabled: false)
  end

  defmodule FakeCollector do
    def sample(process, options) do
      send(Keyword.fetch!(options, :owner), {:sampled_process, process.id})
      Keyword.fetch!(options, :result)
    end
  end

  test "sampler attributes a measured group only to its recorded agent session" do
    domain = domain_fixture()

    result =
      {:ok,
       %{
         cpu_nanos: 12_000,
         memory_bytes: 4_096,
         process_count: 2,
         open_ports_json: [4_321]
       }}

    assert {:ok, %{recorded: 1, missing: 0, errors: []}} =
             ResourceSampler.sample_now(FakeCollector,
               owner: self(),
               result: result,
               now: @now
             )

    assert_receive {:sampled_process, process_id}
    assert process_id == domain.process.id

    assert %ResourceSample{} = sample = Repo.one!(ResourceSample)
    assert sample.agent_session_id == domain.session.id
    assert sample.process_id == domain.process.id
    assert sample.cpu_nanos == 12_000
    assert sample.memory_bytes == 4_096
    assert sample.process_count == 2
    assert sample.open_ports_json == [4_321]
    refute sample.limits_enforced

    assert {:ok, %{recorded: 0, missing: 1, errors: []}} =
             ResourceSampler.sample_now(FakeCollector,
               owner: self(),
               result: :missing,
               now: DateTime.add(@now, 3, :second)
             )

    assert Repo.aggregate(ResourceSample, :count) == 1
  end

  test "minute and stage rollups use measured rows only and keep timing distinct" do
    domain = domain_fixture()
    assert {:ok, _timing} = Execution.record_stage_time(domain.attempt.id, 200, 600, "timing")

    insert_sample(domain, 1, 1_000, 100, 1, [4_001])
    insert_sample(domain, 3, 2_000, 200, 2, [4_001, 4_002])
    insert_sample(domain, 8, 4_000, 300, 1, [4_002])

    assert {:ok, minute} = ResourceRollups.minute(domain.session.id, @now, now: @now)
    assert minute.scope_type == "agent_session"
    assert minute.window == "minute"
    assert minute.sample_count == 3
    assert minute.cpu_nanos == 3_000
    assert minute.average_memory_bytes == 200
    assert minute.maximum_memory_bytes == 300
    assert minute.maximum_process_count == 2
    assert minute.open_ports_json == [4_001, 4_002]
    assert minute.active_ms == nil
    assert minute.wall_ms == nil
    refute minute.limits_enforced

    assert {:error, :stage_not_finished} = ResourceRollups.stage(domain.attempt.id, now: @now)

    domain.attempt
    |> StageAttempt.transition_changeset(%{
      state: "succeeded",
      started_at: @now,
      finished_at: DateTime.add(@now, 30, :second)
    })
    |> Repo.update!()

    assert {:ok, stage} = ResourceRollups.stage(domain.attempt.id, now: @now)
    assert stage.scope_type == "stage_attempt"
    assert stage.sample_count == 3
    assert stage.active_ms == 200
    assert stage.wall_ms == 600

    assert {:ok, _same_bucket} =
             ResourceRollups.minute(domain.session.id, DateTime.add(@now, 25, :second), now: @now)

    assert Repo.aggregate(
             from(rollup in MetricRollup, where: rollup.window == "minute"),
             :count
           ) == 1

    assert {:ok, :missing} =
             ResourceRollups.minute(domain.session.id, DateTime.add(@now, 60, :second))

    assert {:ok, %{raw_samples: 2}} =
             ResourceRollups.prune(
               DateTime.add(@now, 4, :second),
               DateTime.add(@now, -30, :day)
             )

    assert Repo.aggregate(ResourceSample, :count) == 1
  end

  test "maintenance rolls up the completed minute and finished stages" do
    domain = domain_fixture()
    insert_sample(domain, 1, 1_000, 100, 1, [])
    insert_sample(domain, 4, 2_000, 200, 1, [4_003])

    domain.attempt
    |> StageAttempt.transition_changeset(%{
      state: "succeeded",
      started_at: @now,
      finished_at: DateTime.add(@now, 30, :second)
    })
    |> Repo.update!()

    assert {:ok,
            %{
              minute_rollups: 1,
              stage_rollups: 1,
              deleted: %{raw_samples: 0, rollups: 0}
            }} = ResourceRollups.maintain(now: DateTime.add(@now, 61, :second))

    assert Repo.aggregate(MetricRollup, :count) == 2
  end

  test "retention waits for a durable stage aggregate after a long interruption" do
    domain = domain_fixture()
    insert_sample(domain, 1, 1_000, 100, 1, [])
    later = DateTime.add(@now, 8, :day)

    assert {:ok, %{minute_rollups: 1, deleted: %{raw_samples: 0}}} =
             ResourceRollups.maintain(now: later)

    assert Repo.aggregate(ResourceSample, :count) == 1

    domain.attempt
    |> StageAttempt.transition_changeset(%{
      state: "succeeded",
      started_at: @now,
      finished_at: DateTime.add(@now, 60, :second)
    })
    |> Repo.update!()

    assert {:ok, %{minute_rollups: 0, stage_rollups: 1, deleted: %{raw_samples: 1}}} =
             ResourceRollups.maintain(now: later)

    assert Repo.aggregate(ResourceSample, :count) == 0

    assert %MetricRollup{sample_count: 1} =
             Repo.one!(from(rollup in MetricRollup, where: rollup.window == "stage"))
  end

  test "missed minutes catch up in bounded, restart-safe batches" do
    domain = domain_fixture()

    for minute <- 0..120 do
      insert_sample(domain, minute * 60 + 1, minute + 1, 100, 1, [])
    end

    later = DateTime.add(@now, 122 * 60, :second)

    assert {:ok, %{minute_rollups: 120}} = ResourceRollups.maintain(now: later)
    assert Repo.aggregate(MetricRollup, :count) == 120

    assert {:ok, %{minute_rollups: 1}} = ResourceRollups.maintain(now: later)
    assert Repo.aggregate(MetricRollup, :count) == 121

    assert {:ok, %{minute_rollups: 0}} = ResourceRollups.maintain(now: later)
    assert Repo.aggregate(MetricRollup, :count) == 121
  end

  test "retention does not discard a completed stage's missing minute" do
    domain = domain_fixture()
    insert_sample(domain, 1, 1_000, 100, 1, [])
    later = DateTime.add(@now, 8, :day)

    domain.attempt
    |> StageAttempt.transition_changeset(%{
      state: "succeeded",
      started_at: @now,
      finished_at: DateTime.add(@now, 30, :second)
    })
    |> Repo.update!()

    assert {:ok, %MetricRollup{}} = ResourceRollups.stage(domain.attempt.id, now: later)

    assert {:ok, %{raw_samples: 0}} =
             ResourceRollups.prune(DateTime.add(later, -7, :day), DateTime.add(later, -30, :day))

    assert Repo.aggregate(ResourceSample, :count) == 1
    assert {:ok, %MetricRollup{}} = ResourceRollups.minute(domain.session.id, @now, now: later)

    assert {:ok, %{raw_samples: 1}} =
             ResourceRollups.prune(DateTime.add(later, -7, :day), DateTime.add(later, -30, :day))
  end

  defp insert_sample(domain, seconds, cpu, memory, count, ports) do
    attrs = %{
      id: Identifier.generate(),
      agent_session_id: domain.session.id,
      process_id: domain.process.id,
      cpu_nanos: cpu,
      memory_bytes: memory,
      process_count: count,
      open_ports_json: ports,
      sampled_at: DateTime.add(@now, seconds, :second),
      limits_enforced: false
    }

    %ResourceSample{} |> ResourceSample.create_changeset(attrs) |> Repo.insert!()
  end

  defp domain_fixture do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Metrics Project #{suffix}",
        repo_path: "/tmp/metrics-project-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/metrics-workspaces-#{suffix}",
        port_range_start: 45_000,
        port_range_end: 45_100
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
        name: "Metrics Board #{suffix}",
        concurrency_limit: 1
      })

    {:ok, task} =
      Workflows.create_task(%{board_id: board.id, title: "Metrics task", position: 0})

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: config.id,
        plugin_snapshot_json: %{},
        branch: "feature/metrics-#{suffix}",
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

    {:ok, environment} =
      Execution.create_environment(%{
        run_id: run.id,
        runner_key: "local_process",
        kind: "local_process",
        worktree_path: "/tmp/metrics-worktree-#{suffix}",
        run_dir: "/tmp/metrics-run-#{suffix}",
        base_sha: run.base_sha,
        ports_json: %{},
        isolation_claims_json: %{}
      })

    {:ok, process} =
      Execution.record_process(%{
        environment_id: environment.id,
        agent_session_id: session.id,
        pid: suffix + 10_000,
        pgid: suffix + 10_000,
        start_identity: "fixture-#{suffix}",
        role: "agent:codex"
      })

    %{attempt: attempt, session: session, process: process}
  end
end
