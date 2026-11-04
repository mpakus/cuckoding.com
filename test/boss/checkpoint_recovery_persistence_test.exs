defmodule Boss.CheckpointRecoveryPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo}
  alias Boss.Deliveries.{Delivery, ExecutionRetry}
  @moduletag capture_log: true
  @sha String.duplicate("a", 40)
  @hash String.duplicate("b", 64)

  @migrations [
    {20_261_025_180_000, Boss.Repo.Migrations.CreateProjects},
    {20_261_025_220_000, Boss.Repo.Migrations.CreateSpecRevisions},
    {20_261_025_230_000, Boss.Repo.Migrations.TrackMissingSpecs},
    {20_261_026_010_000, Boss.Repo.Migrations.CreateTaskEvents},
    {20_261_026_040_000, Boss.Repo.Migrations.CreateAgentRuns},
    {20_261_026_060_000, Boss.Repo.Migrations.AddManualChecks},
    {20_261_026_160_000, Boss.Repo.Migrations.AddManualReviews},
    {20_261_026_220_000, Boss.Repo.Migrations.CreateDeliveries},
    {20_261_027_010_000, Boss.Repo.Migrations.AddTaskRevisionAdoption},
    {20_261_027_020_000, Boss.Repo.Migrations.PreserveHistoricalRunPins},
    {20_261_027_030_000, Boss.Repo.Migrations.PinDeliveryReviewer},
    {20_261_027_040_000, Boss.Repo.Migrations.AddWorkflowQueue},
    {20_261_027_050_000, Boss.Repo.Migrations.AddMergeIntegrationEvidence},
    {20_261_027_060_000, Boss.Repo.Migrations.AddDeliveryScheduling},
    {20_261_027_070_000, Boss.Repo.Migrations.AddAutopilot},
    {20_261_031_220_000, Boss.Repo.Migrations.AddReviewRetries},
    {20_261_102_120_000, Boss.Repo.Migrations.AddCandidateRetries},
    {20_261_103_120_000, Boss.Repo.Migrations.AddProjectIntake},
    {20_261_104_120_000, Boss.Repo.Migrations.ContinueAutopilotAfterTaskFailure},
    {20_261_104_130_000, Boss.Repo.Migrations.AddAutonomousRecovery},
    {20_261_105_120_000, Boss.Repo.Migrations.AddCatalogRouting},
    {20_261_106_120_000, Boss.Repo.Migrations.ConvertProjectDocumentation},
    {20_261_106_130_000, Boss.Repo.Migrations.AddIntakeRecovery},
    {20_261_106_140_000, Boss.Repo.Migrations.AddExecutionRecovery},
    {20_261_106_150_000, Boss.Repo.Migrations.AddCheckpointRecovery}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-checkpoint-storage-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, lock} = Boss.DataDirectory.acquire(root)
    on_exit(fn -> Boss.DataDirectory.release(lock) end)

    opts = [
      name: nil,
      database: Path.join(root, "boss.db"),
      pool: DBConnection.ConnectionPool,
      pool_size: 2
    ]

    repo = start_supervised!({Repo, opts})
    Repo.put_dynamic_repo(repo)

    Ecto.Migrator.run(Repo, @migrations, :up,
      all: true,
      log: false
    )

    project =
      Repo.insert!(%Projects.Project{
        name: "Autonomy",
        root_path: root,
        git_common_dir: Path.join(root, ".git"),
        specs_path: root,
        base_branch: "main"
      })

    {:ok, %{task: task}} =
      Projects.record_spec(project.id, %{
        relative_path: "one.md",
        title: "One",
        original_text: "# One"
      })

    %{project: project, task: task, repo: repo, opts: opts}
  end

  @catalog %{
    "version" => 2,
    "primary" => %{"model" => "gpt-5.6-sol", "reasoning_effort" => "high"},
    "resolver" => %{"model" => "gpt-5.6-terra", "reasoning_effort" => "xhigh"},
    "small" => nil,
    "fallbacks" => [
      %{"model" => "gpt-5.6-sol", "reasoning_effort" => "xhigh"},
      %{"model" => "gpt-5.6-terra", "reasoning_effort" => "xhigh"}
    ]
  }

  test "new checkpoint pins source/network before effects and replays after restart", c do
    {parent, _, check, _} = failed_parent(c)
    oldsteps = Deliveries.steps(parent.id)
    command = Ecto.UUID.generate()
    {:ok, {:new, d}} = Deliveries.admit_checkpoint_retry(c.project.id, parent.id, command)

    assert d.checkpoint_recovery_version == 1 and d.execution_recovery_version == 1 and
             d.implementation_network_version == 1

    assert d.retry_source_check_id == check.id
    {:ok, source} = ExecutionRetry.source(d)

    assert source.parent.id == parent.id and source.check.id == check.id and
             source.candidate_commit == @sha

    :ok = stop_supervised(Repo)
    Repo.put_dynamic_repo(start_supervised!({Repo, c.opts}))

    assert {:ok, {:existing, ^d}} =
             Deliveries.admit_checkpoint_retry(c.project.id, parent.id, command, true)

    assert {:error, :idempotency_conflict} =
             Deliveries.admit_timeout_retry(c.project.id, parent.id, command)

    assert Deliveries.steps(parent.id) == oldsteps and Repo.get!(Delivery, parent.id) == parent

    for {field, value} <- [
          {"checkpoint_recovery_version", 0},
          {"implementation_network_version", 0},
          {"retry_source_check_id", nil}
        ],
        do:
          assert(
            {:error, _} =
              Repo.query("UPDATE deliveries SET " <> field <> "=? WHERE id=?", [value, d.id])
          )
  end

  test "checkpoint snapshot fresh checks and alternate implementation can reach Ready", c do
    {parent, _, _, _} = failed_parent(c)
    {d, p} = checkpoint(c, parent)

    check =
      checkpoint_check(d, p, %{
        "status" => "failed",
        "outcome" => "checks_failed",
        "exit_code" => 3
      })

    r = resolve(d, p, check)
    input = implementation_input(d, p, r)

    impl =
      finish(d, "implement", 1, input, %{"workspace" => input["workspace"], "head_commit" => @sha})

    assert impl.input["network_policy"] == Boss.Agents.NetworkPolicy.profile(1)
    assert impl.input["model_profile"] == @catalog["resolver"]
    passed = normal_check(d, p, impl)
    review(d, p, passed, "approved")
    assert {:ok, %{status: "ready_to_merge"}} = Deliveries.complete(d.id, "ready_to_merge")
  end

  test "terminal resolver retains immediate parent even when implementation belongs to ancestor",
       c do
    {d, p, ancestor} = child(c)
    check = timeout_check(d, p, ancestor, 0, check_timeout())
    {:ok, parent} = Deliveries.complete(d.id, "failed")

    assert {:error, :execution_retry_unavailable} =
             Deliveries.admit_timeout_retry(c.project.id, parent.id, Ecto.UUID.generate())

    {next, np} = checkpoint(c, parent)
    {:ok, source} = ExecutionRetry.source(next)

    assert source.parent.id == parent.id and source.implementation.id == ancestor.id and
             source.check.id == check.id

    fresh =
      checkpoint_check(next, np, %{
        "status" => "failed",
        "outcome" => "checks_failed",
        "exit_code" => 1
      })

    r =
      finish(next, "resolve", 0, resolution_input(next, np, fresh), %{
        "report" => resolution_report("Registry unavailable")
      })

    assert r.status == "finished"
    {:ok, next} = Deliveries.complete(next.id, "needs_input")
    {third, _} = checkpoint(c, next)
    {:ok, source} = ExecutionRetry.source(third)

    assert source.parent.id == next.id and source.plan.id == np.id and source.check.id == fresh.id and
             source.implementation.id == ancestor.id

    assert {:ok, {:existing, replayed}} =
             Deliveries.admit_checkpoint_retry(c.project.id, next.id, third.command_id, true)

    assert replayed == Repo.get!(Delivery, third.id)
  end

  test "honest reverified timeout permits diagnosis but cannot become review or approval", c do
    {parent, _, _, _} = failed_parent(c)
    {d, p} = checkpoint(c, parent)
    check = checkpoint_check(d, p, Map.put(check_timeout(), "candidate_verified", true))
    assert check.receipt["output_complete"] == false and check.receipt["output_hash"] == nil
    assert {:error, :missing_evidence} = Deliveries.complete(d.id, "ready_to_merge")

    assert {:error, :invalid_step} =
             Deliveries.begin_step(
               d.id,
               "review",
               0,
               pins(d, %{"check_step_id" => check.id, "plan_step_id" => p.id})
             )

    r = resolve(d, p, check)
    {:ok, impl} = Deliveries.begin_step(d.id, "implement", 1, implementation_input(d, p, r))
    assert impl.input["network_policy"] == Boss.Agents.NetworkPolicy.profile(1)
  end

  test "timeout without fresh candidate verification stays closed", c do
    {parent, _, _, _} = failed_parent(c)
    {d, p} = checkpoint(c, parent)
    check = checkpoint_check(d, p, check_timeout())
    input = resolution_input(d, p, check)
    assert {:error, :invalid_step} = Deliveries.begin_step(d.id, "resolve", 0, input)

    assert {:error, _} =
             raw_step(d, "resolve", 0, Map.put(input, "model_profile", @catalog["resolver"]))
  end

  test "pure timeout entry uses old capture semantics but new immutable network policy", c do
    {parent, _, implementation} = parent(c)
    {d, p} = checkpoint(c, parent)
    assert d.retry_source_check_id == nil
    {:ok, source} = ExecutionRetry.source(d)
    assert source.check == nil and source.candidate_commit == nil
    r = resolve(d, p, timeout_check(d, p, implementation, 0))
    {:ok, i} = Deliveries.begin_step(d.id, "implement", 1, implementation_input(d, p, r))
    assert i.input["network_policy"] == Boss.Agents.NetworkPolicy.profile(1)
  end

  test "SQL and context refuse caller-expanded network profile", c do
    {parent, _, _, _} = failed_parent(c)
    {d, p} = checkpoint(c, parent)
    r = resolve(d, p, checkpoint_check(d, p, %{}))
    i = Map.put(implementation_input(d, p, r), "model_profile", @catalog["resolver"])

    for policy <- [
          Map.put(Boss.Agents.NetworkPolicy.profile(1), "domains", ["*"]),
          Map.put(Boss.Agents.NetworkPolicy.profile(1), "version", 1.0),
          nil
        ] do
      forged = Map.put(i, "network_policy", policy)
      assert {:error, :invalid_step} = Deliveries.begin_step(d.id, "implement", 1, forged)
      assert {:error, _} = raw_step(d, "implement", 1, forged)
    end

    assert {:ok, impl} = Deliveries.begin_step(d.id, "implement", 1, i)
    assert impl.input["network_policy"] == Boss.Agents.NetworkPolicy.profile(1)
  end

  for {label, changed} <- [
        {"cancelled", %{"outcome" => "cancelled"}},
        {"unknown cleanup", %{"cleanup" => "unknown"}},
        {"missing EOF", %{"eof" => %{"stdout" => true, "stderr" => false}}},
        {"changed candidate", %{"outcome" => "candidate_changed"}},
        {"output limit", %{"outcome" => "output_limit"}}
      ] do
    test "#{label} check never becomes checkpoint source", c do
      {parent, _, _, _} =
        failed_parent(c, Map.merge(check_timeout(), unquote(Macro.escape(changed))))

      assert {:error, :checkpoint_retry_unavailable} =
               Deliveries.admit_checkpoint_retry(c.project.id, parent.id, Ecto.UUID.generate())
    end
  end

  test "migration roundtrip leaves original policy and receipts unchanged", c do
    {parent, _, _, _} = failed_parent(c)
    old = Deliveries.steps(parent.id)

    assert :ok =
             Ecto.Migrator.down(
               Repo,
               20_261_106_150_000,
               Boss.Repo.Migrations.AddCheckpointRecovery,
               log: false
             )

    assert :ok =
             Ecto.Migrator.up(
               Repo,
               20_261_106_150_000,
               Boss.Repo.Migrations.AddCheckpointRecovery,
               log: false
             )

    assert Repo.get!(Delivery, parent.id) == parent and Deliveries.steps(parent.id) == old
    assert parent.implementation_network_version == 0 and parent.checkpoint_recovery_version == 0

    {:ok, {:new, _}} =
      Deliveries.admit_checkpoint_retry(c.project.id, parent.id, Ecto.UUID.generate())

    assert_raise RuntimeError, ~r/Refusing to discard checkpoint recovery history/, fn ->
      Ecto.Migrator.down(Repo, 20_261_106_150_000, Boss.Repo.Migrations.AddCheckpointRecovery,
        log: false
      )
    end
  end

  test "later ordinary timeout repairs with different model and retains network version", c do
    {parent, _, _, _} = failed_parent(c)
    {d, p} = checkpoint(c, parent)
    first = resolve(d, p, checkpoint_check(d, p, %{}))
    input = implementation_input(d, p, first)

    impl =
      finish(d, "implement", 1, input, %{"workspace" => input["workspace"], "head_commit" => @sha})

    check = normal_check(d, p, impl, Map.put(check_timeout(), "candidate_verified", true))
    assert check.status == "failed" and check.receipt["output_complete"] == false
    r = resolve(d, p, check)
    assert r.input["model_profile"] == hd(@catalog["fallbacks"])
    {:ok, next} = Deliveries.begin_step(d.id, "implement", 2, implementation_input(d, p, r))
    assert next.input["model_profile"] == hd(@catalog["fallbacks"])
    assert next.input["network_policy"] == Boss.Agents.NetworkPolicy.profile(1)
  end

  test "old timeout policy cannot use new reverified-timeout diagnosis", c do
    {d, p, source} = child(c)
    check = timeout_check(d, p, source, 0, Map.put(check_timeout(), "candidate_verified", true))
    assert d.checkpoint_recovery_version == 0 and d.implementation_network_version == 0
    input = resolution_input(d, p, check)
    assert {:error, :invalid_step} = Deliveries.begin_step(d.id, "resolve", 0, input)

    assert {:error, _} =
             raw_step(d, "resolve", 0, Map.put(input, "model_profile", @catalog["resolver"]))
  end

  test "raw SQL cannot forge checkpoint source policy or copied configuration", c do
    {parent, plan, check, implementation} = failed_parent(c)

    for changes <- [
          %{retry_source_check_id: plan.id},
          %{retry_source_check_id: nil},
          %{retry_implementation_id: plan.id},
          %{checkpoint_recovery_version: 0},
          %{implementation_network_version: 0},
          %{execution_recovery_version: 0},
          %{config_hash: @hash},
          %{reviewer: "claude"},
          %{admitted_version: parent.task_version}
        ] do
      assert {:error, _} = raw_checkpoint(parent, check, implementation, changes)
    end

    assert {:ok, {:new, _}} =
             Deliveries.admit_checkpoint_retry(c.project.id, parent.id, Ecto.UUID.generate())
  end

  test "checkpoint retained plan and snapshot cannot select different source or base", c do
    {parent, source_plan, check, implementation} = failed_parent(c)

    {:ok, {:new, d}} =
      Deliveries.admit_checkpoint_retry(c.project.id, parent.id, Ecto.UUID.generate())

    {:ok, d} = Deliveries.set_intent(d.id, workspace(c, d.id))

    input =
      pins(d, %{
        "workspace" => d.intent,
        "source_implementation_id" => implementation.id,
        "source_plan_id" => source_plan.id,
        "source_check_id" => source_plan.id
      })

    assert {:error, :invalid_step} = Deliveries.begin_step(d.id, "plan", 0, input)
    assert {:error, _} = raw_step(d, "plan", 0, input)
    {:ok, p} = Deliveries.begin_step(d.id, "plan", 0, Map.put(input, "source_check_id", check.id))

    valid = %{
      "status" => "finished",
      "cleanup" => "group_empty",
      "outcome" => "retained_plan",
      "report" => source_plan.receipt["report"],
      "workspace" => d.intent
    }

    changed = put_in(valid, ["report", "acceptance"], ["Less work"])
    assert {:error, :invalid_receipt} = Deliveries.finish_step(p.id, changed)

    assert {:error, _} =
             Repo.query("UPDATE delivery_steps SET status='finished',receipt=? WHERE id=?", [
               JSON.encode!(changed),
               p.id
             ])

    {:ok, p} = Deliveries.finish_step(p.id, valid)
    id = Ecto.UUID.generate()
    run = Map.put(fresh(d.intent), "base_commit", String.duplicate("f", 40))

    i =
      pins(d, %{
        "run_workspace" => run,
        "check_id" => id,
        "source_check_id" => check.id,
        "implementation_step_id" => implementation.id,
        "source_candidate_commit" => @sha,
        "plan_step_id" => p.id
      })

    assert {:error, :invalid_step} = Deliveries.begin_step(d.id, "checkpoint_snapshot", 0, i)
    assert {:error, _} = raw_step(d, "checkpoint_snapshot", 0, i)
  end

  test "non-timeout incomplete check cannot acquire timeout eligibility through flag", c do
    {parent, _, _, _} = failed_parent(c)
    {d, p} = checkpoint(c, parent)

    check =
      checkpoint_check(d, p, %{
        "status" => "failed",
        "outcome" => "output_limit",
        "exit_kind" => "signal",
        "signal" => 9,
        "exit_code" => nil,
        "output_complete" => false,
        "output_hash" => nil,
        "candidate_verified" => true
      })

    i = resolution_input(d, p, check)
    assert {:error, :invalid_step} = Deliveries.begin_step(d.id, "resolve", 0, i)

    assert {:error, _} =
             raw_step(d, "resolve", 0, Map.put(i, "model_profile", @catalog["resolver"]))
  end

  for {label, changed} <- [
        {"numeric verification flag", %{"candidate_verified" => 1}},
        {"numeric EOF", %{"eof" => %{"stdout" => 1, "stderr" => true}}},
        {"contradictory signal and exit", %{"exit_code" => 0}},
        {"boolean exit", %{"exit_kind" => "exit", "exit_code" => false, "signal" => nil}}
      ] do
    test "#{label} cannot authorize timeout diagnosis through context or SQL", c do
      {parent, _, _, _} = failed_parent(c)
      {d, p} = checkpoint(c, parent)

      attrs =
        check_timeout()
        |> Map.put("candidate_verified", true)
        |> Map.merge(unquote(Macro.escape(changed)))

      check = checkpoint_check(d, p, attrs)
      input = resolution_input(d, p, check)
      assert {:error, :invalid_step} = Deliveries.begin_step(d.id, "resolve", 0, input)

      assert {:error, _} =
               raw_step(d, "resolve", 0, Map.put(input, "model_profile", @catalog["resolver"]))
    end
  end

  defp raw_checkpoint(parent, check, implementation, changes) do
    attrs =
      %{
        id: Ecto.UUID.generate(),
        project_id: parent.project_id,
        task_id: parent.task_id,
        spec_revision_id: parent.spec_revision_id,
        command_id: Ecto.UUID.generate(),
        admitted_version: parent.task_version + 1,
        task_version: parent.task_version + 1,
        check_config: JSON.encode!(parent.check_config),
        config_hash: parent.config_hash,
        reviewer: parent.reviewer,
        autonomy_version: parent.autonomy_version,
        routing_version: parent.routing_version,
        model_catalog: JSON.encode!(parent.model_catalog),
        execution_recovery_version: 1,
        checkpoint_recovery_version: 1,
        implementation_network_version: 1,
        retry_implementation_id: implementation.id,
        retry_source_check_id: check.id
      }
      |> Map.merge(changes)

    keys = Map.keys(attrs)

    Repo.query(
      "INSERT INTO deliveries (" <>
        Enum.map_join(keys, ",", &to_string/1) <>
        ",inserted_at,updated_at) VALUES(" <>
        Enum.map_join(keys, ",", fn _ -> "?" end) <> ",CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",
      Enum.map(keys, &Map.fetch!(attrs, &1))
    )
  end

  defp failed_parent(c, attrs \\ nil) do
    {:ok, {:new, d}} = Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true")
    {:ok, d} = Deliveries.set_model_catalog(d.id, @catalog)
    {:ok, d} = Deliveries.set_intent(d.id, workspace(c, d.id))
    p = finish(d, "plan", 0, %{"workspace" => d.intent}, %{"report" => plan()})
    w = fresh(d.intent)

    i =
      finish(
        d,
        "implement",
        1,
        %{"workspace" => w, "parent_step_id" => p.id, "plan_step_id" => p.id},
        %{"workspace" => w, "head_commit" => @sha}
      )

    check =
      normal_check(
        d,
        p,
        i,
        attrs || %{"status" => "failed", "outcome" => "checks_failed", "exit_code" => 1}
      )

    {:ok, d} = Deliveries.complete(d.id, "failed")
    {d, p, check, i}
  end

  defp checkpoint(c, parent) do
    {:ok, {:new, d}} =
      Deliveries.admit_checkpoint_retry(c.project.id, parent.id, Ecto.UUID.generate())

    {:ok, d} = Deliveries.set_intent(d.id, workspace(c, d.id))
    {:ok, source} = ExecutionRetry.source(d)

    {:ok, p} =
      Deliveries.begin_step(
        d.id,
        "plan",
        0,
        pins(d, %{
          "workspace" => d.intent,
          "source_implementation_id" => source.implementation.id,
          "source_plan_id" => source.plan.id,
          "source_check_id" => d.retry_source_check_id
        })
      )

    {:ok, p} =
      Deliveries.finish_step(p.id, %{
        "status" => "finished",
        "cleanup" => "group_empty",
        "outcome" => "retained_plan",
        "report" => source.plan.receipt["report"],
        "workspace" => d.intent
      })

    {d, p}
  end

  defp checkpoint_check(d, p, attrs) do
    id = Ecto.UUID.generate()
    {:ok, source} = ExecutionRetry.source(d)
    run = Map.put(fresh(d.intent), "base_commit", source.candidate_commit)

    w = %{
      "check_id" => id,
      "path" => Path.join(d.intent["repo_path"], "checks/" <> id),
      "ref" => "refs/boss/checks/" <> id,
      "run_workspace" => run
    }

    snap =
      finish(
        d,
        "checkpoint_snapshot",
        0,
        %{
          "run_workspace" => run,
          "check_id" => id,
          "source_check_id" => source.check.id,
          "implementation_step_id" => source.implementation.id,
          "source_candidate_commit" => source.candidate_commit,
          "plan_step_id" => p.id
        },
        %{"workspace" => w}
      )

    finish(
      d,
      "checkpoint_check",
      0,
      %{
        "snapshot_step_id" => snap.id,
        "source_check_id" => source.check.id,
        "implementation_step_id" => source.implementation.id,
        "plan_step_id" => p.id,
        "workspace" => w,
        "candidate_commit" => @sha
      },
      Map.merge(%{"output_complete" => true, "output_hash" => @hash}, attrs)
    )
  end

  defp check_timeout,
    do: Map.merge(timeout(), %{"signal" => 9, "output_complete" => false, "output_hash" => nil})

  defp parent(c, attrs \\ nil) do
    {:ok, {:new, d}} = Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true")
    {:ok, d} = Deliveries.set_model_catalog(d.id, @catalog)
    {:ok, d} = Deliveries.set_intent(d.id, workspace(c, d.id))
    p = finish(d, "plan", 0, %{"workspace" => d.intent}, %{"report" => plan()})

    i =
      finish(
        d,
        "implement",
        1,
        %{"workspace" => fresh(d.intent), "parent_step_id" => p.id, "plan_step_id" => p.id},
        attrs || timeout()
      )

    {:ok, d} = Deliveries.complete(d.id, "failed")
    {d, p, i}
  end

  defp child(c) do
    {parent, source_plan, source} = parent(c)

    {:ok, {:new, d}} =
      Deliveries.admit_timeout_retry(c.project.id, parent.id, Ecto.UUID.generate())

    {:ok, d} = Deliveries.set_intent(d.id, workspace(c, d.id))

    {:ok, p} =
      Deliveries.begin_step(
        d.id,
        "plan",
        0,
        pins(d, %{
          "workspace" => d.intent,
          "source_implementation_id" => source.id,
          "source_plan_id" => source_plan.id
        })
      )

    {:ok, p} =
      Deliveries.finish_step(p.id, %{
        "status" => "finished",
        "cleanup" => "group_empty",
        "outcome" => "retained_plan",
        "report" => source_plan.receipt["report"],
        "workspace" => d.intent
      })

    {d, p, source}
  end

  defp timeout_check(d, p, source, cycle, attrs \\ %{}) do
    id = Ecto.UUID.generate()

    w = %{
      "check_id" => id,
      "path" => Path.join(d.intent["repo_path"], id),
      "ref" => "refs/boss/checks/" <> id,
      "run_workspace" => source.input["workspace"]
    }

    snap =
      finish(
        d,
        "timeout_snapshot",
        cycle,
        %{"workspace" => w, "implementation_step_id" => source.id, "plan_step_id" => p.id},
        %{"workspace" => w, "candidate_commit" => @sha}
      )

    finish(
      d,
      "timeout_check",
      cycle,
      %{
        "snapshot_step_id" => snap.id,
        "implementation_step_id" => source.id,
        "plan_step_id" => p.id,
        "workspace" => w,
        "candidate_commit" => @sha
      },
      Map.merge(%{"output_complete" => true, "output_hash" => @hash}, attrs)
    )
  end

  defp resolve(d, p, source),
    do:
      finish(d, "resolve", source.cycle, resolution_input(d, p, source), %{
        "report" => resolution_report(nil)
      })

  defp resolution_input(d, p, source),
    do:
      pins(d, %{
        "parent_step_id" => source.id,
        "source_step_id" => source.id,
        "plan_step_id" => p.id,
        "workspace" => source.input["workspace"],
        "candidate_commit" => source.input["candidate_commit"],
        "resolution_attempt" => 1,
        "input_hash" => @hash,
        "feedback_hash" => @hash
      })

  defp resolution_report(action),
    do: %{
      "summary" => "Repair saved requirement",
      "steps" => ["Finish implementation"],
      "assumptions" => [],
      "external_action" => action
    }

  defp implementation_input(d, p, r),
    do:
      pins(d, %{
        "parent_step_id" => r.id,
        "resolution_step_id" => r.id,
        "source_step_id" => r.input["source_step_id"],
        "plan_step_id" => p.id,
        "workspace" => Map.put(fresh(d.intent), "base_commit", r.input["candidate_commit"])
      })

  defp normal_check(d, p, i, attrs \\ %{}) do
    id = Ecto.UUID.generate()

    w = %{
      "check_id" => id,
      "path" => d.intent["path"] <> "-candidate",
      "ref" => "refs/boss/checks/" <> id,
      "run_workspace" => i.input["workspace"]
    }

    s =
      finish(
        d,
        "snapshot",
        i.cycle,
        %{"implementation_step_id" => i.id, "plan_step_id" => p.id},
        %{"workspace" => w, "candidate_commit" => @sha}
      )

    finish(
      d,
      "check",
      i.cycle,
      %{
        "snapshot_step_id" => s.id,
        "plan_step_id" => p.id,
        "workspace" => w,
        "candidate_commit" => @sha
      },
      Map.merge(%{"output_complete" => true, "output_hash" => @hash}, attrs)
    )
  end

  defp review(d, p, c, verdict) do
    status = if verdict == "approved", do: "passed", else: "failed"

    issues =
      if verdict == "approved",
        do: [],
        else: [%{"criterion" => "Saved criterion", "message" => "Incomplete"}]

    finish(
      d,
      "review",
      c.cycle,
      %{
        "check_step_id" => c.id,
        "plan_step_id" => p.id,
        "workspace" => c.input["workspace"],
        "candidate_commit" => @sha,
        "original_base" => @sha,
        "input_hash" => @hash
      },
      %{
        "report" => %{
          "verdict" => verdict,
          "summary" => "Reviewed",
          "acceptance" => [
            %{"criterion" => "Saved criterion", "status" => status, "evidence" => "Verified"}
          ],
          "issues" => issues
        }
      }
    )
  end

  defp workspace(c, id),
    do: %{
      "run_id" => id,
      "project_id" => to_string(c.project.id),
      "repo_path" => c.project.root_path,
      "git_common_dir" => c.project.git_common_dir,
      "base_branch" => "main",
      "base_commit" => @sha,
      "path" => Path.join(c.project.root_path, id),
      "branch" => "codex/boss-run-" <> id
    }

  defp fresh(w) do
    id = Ecto.UUID.generate()

    Map.merge(w, %{
      "run_id" => id,
      "path" => Path.join(Path.dirname(w["path"]), id),
      "branch" => "codex/boss-run-" <> id
    })
  end

  defp plan,
    do: %{
      "summary" => "Implement saved requirement",
      "steps" => ["Use existing convention"],
      "acceptance" => ["Saved criterion"],
      "clarification" => nil
    }

  defp timeout,
    do: %{
      "status" => "failed",
      "outcome" => "timeout",
      "exit_kind" => "signal",
      "exit_code" => nil,
      "signal" => 15
    }

  defp pins(d, i),
    do: Map.merge(%{"config_hash" => d.config_hash, "spec_revision_id" => d.spec_revision_id}, i)

  defp receipt(attrs),
    do:
      Map.merge(
        %{
          "status" => "finished",
          "cleanup" => "group_empty",
          "exit_kind" => "exit",
          "exit_code" => 0,
          "signal" => nil,
          "eof" => %{"stdout" => true, "stderr" => true},
          "candidate_commit" => @sha
        },
        attrs
      )

  defp finish(d, k, c, i, r) do
    assert {:ok, s} = Deliveries.begin_step(d.id, k, c, pins(d, i))
    assert {:ok, s} = Deliveries.finish_step(s.id, receipt(r))
    s
  end

  defp raw_step(d, k, c, i),
    do:
      Repo.query(
        "INSERT INTO delivery_steps(id,delivery_id,number,kind,cycle,input,inserted_at,updated_at) VALUES(?,?,?,?,?,?,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",
        [Ecto.UUID.generate(), d.id, length(Deliveries.steps(d.id)) + 1, k, c, JSON.encode!(i)]
      )
end
