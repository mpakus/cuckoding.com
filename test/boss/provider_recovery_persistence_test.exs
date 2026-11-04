defmodule Boss.ProviderRecoveryPersistenceTest do
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
    {20_261_106_150_000, Boss.Repo.Migrations.AddCheckpointRecovery},
    {20_261_106_160_000, Boss.Repo.Migrations.AddProviderRecovery}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-provider-storage-#{Ecto.UUID.generate()}")
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

  test "explicit provider recovery pins immutable source and replays after pooled restart", c do
    {parent, _, implementation} = parent(c)
    oldsteps = Deliveries.steps(parent.id)
    command = Ecto.UUID.generate()
    assert parent.provider_recovery_version == 0
    assert {:error, :checkpoint_retry_unavailable} = ExecutionRetry.checkpoint_parent(parent)
    {:ok, {:new, d}} = Deliveries.admit_checkpoint_retry(c.project.id, parent.id, command)
    assert d.provider_recovery_version == 1 and d.checkpoint_recovery_version == 1
    assert d.execution_recovery_version == 1 and d.implementation_network_version == 1
    assert d.retry_implementation_id == implementation.id and is_nil(d.retry_source_check_id)
    assert d.admitted_version == parent.task_version + 1

    assert {:ok, %{source_kind: :rate_limit, parent: ^parent, check: nil, candidate_commit: nil}} =
             ExecutionRetry.source(d)

    :ok = stop_supervised(Repo)
    Repo.put_dynamic_repo(start_supervised!({Repo, c.opts}))

    assert {:ok, {:existing, ^d}} =
             Deliveries.admit_checkpoint_retry(c.project.id, parent.id, command, true)

    assert Repo.get!(Delivery, parent.id) == parent and Deliveries.steps(parent.id) == oldsteps

    assert {:error, _} =
             Repo.query("UPDATE deliveries SET provider_recovery_version=0 WHERE id=?", [d.id])

    assert {:error, :idempotency_conflict} =
             Deliveries.admit_timeout_retry(c.project.id, parent.id, command)
  end

  test "retained plan, fresh capture/check and alternate model can reach Ready", c do
    {parent, _, _} = parent(c)
    {d, p} = checkpoint(c, parent)

    check =
      checkpoint_check(d, p, %{
        "status" => "failed",
        "outcome" => "checks_failed",
        "exit_code" => 3
      })

    assert {:error, :missing_evidence} = Deliveries.complete(d.id, "ready_to_merge")
    r = resolve(d, p, check)
    assert r.input["model_profile"] == @catalog["resolver"]
    input = implementation_input(d, p, r)

    impl =
      finish(d, "implement", 1, input, %{"workspace" => input["workspace"], "head_commit" => @sha})

    assert impl.input["model_profile"] == @catalog["resolver"]
    assert impl.input["network_policy"] == Boss.Agents.NetworkPolicy.profile(1)
    review(d, p, normal_check(d, p, impl), "approved")
    assert {:ok, %{status: "ready_to_merge"}} = Deliveries.complete(d.id, "ready_to_merge")
  end

  test "provider error cannot start an automatic capture in its failed delivery", c do
    {parent, p, implementation} = parent(c)
    input = snapshot_input(parent, p, implementation)

    assert {:error, :not_active} =
             Deliveries.begin_step(parent.id, "checkpoint_snapshot", 0, input)

    assert {:error, _} = raw_step(parent, "checkpoint_snapshot", 0, input)

    assert {:error, :execution_retry_unavailable} =
             Deliveries.admit_timeout_retry(c.project.id, parent.id, Ecto.UUID.generate())
  end

  test "SQL refuses omitted provider policy and changed source pins", c do
    {parent, p, implementation} = parent(c)

    for changed <- [
          %{provider_recovery_version: 0},
          %{provider_recovery_version: 2},
          %{retry_implementation_id: p.id},
          %{retry_source_check_id: p.id},
          %{admitted_version: parent.task_version},
          %{config_hash: @hash},
          %{reviewer: "claude"},
          %{checkpoint_recovery_version: 0},
          %{execution_recovery_version: 0},
          %{implementation_network_version: 0}
        ] do
      assert {:error, _} = raw_provider(parent, implementation, changed)
    end

    assert {:ok, {:new, _}} =
             Deliveries.admit_checkpoint_retry(c.project.id, parent.id, Ecto.UUID.generate())
  end

  test "snapshot intent cannot substitute workspace, base, source, or an existing candidate", c do
    {parent, _, implementation} = parent(c)
    {d, p} = checkpoint(c, parent)
    valid = snapshot_input(d, p, implementation)

    for input <- [
          put_in(valid, ["run_workspace", "base_commit"], String.duplicate("f", 40)),
          put_in(valid, ["run_workspace", "path"], "/foreign"),
          Map.put(valid, "implementation_step_id", p.id),
          Map.put(valid, "source_check_id", p.id),
          Map.put(valid, "source_candidate_commit", @sha),
          Map.put(valid, "check_id", String.duplicate("z", 36))
        ] do
      assert {:error, :invalid_step} =
               Deliveries.begin_step(d.id, "checkpoint_snapshot", 0, input)

      assert {:error, _} = raw_step(d, "checkpoint_snapshot", 0, input)
    end

    {:ok, s} = Deliveries.begin_step(d.id, "checkpoint_snapshot", 0, valid)

    w = %{
      "check_id" => valid["check_id"],
      "ref" => "refs/boss/checks/" <> valid["check_id"],
      "run_workspace" => valid["run_workspace"],
      "path" => valid["run_workspace"]["path"]
    }

    forged = receipt(%{"workspace" => w})
    assert {:error, :invalid_receipt} = Deliveries.finish_step(s.id, forged)

    assert {:error, _} =
             Repo.query("UPDATE delivery_steps SET status='finished',receipt=? WHERE id=?", [
               JSON.encode!(forged),
               s.id
             ])
  end

  test "retained acceptance cannot change and implementation cannot bypass fresh check and resolver",
       c do
    {parent, source_plan, implementation} = parent(c)

    {:ok, {:new, d}} =
      Deliveries.admit_checkpoint_retry(c.project.id, parent.id, Ecto.UUID.generate())

    {:ok, d} = Deliveries.set_intent(d.id, workspace(c, d.id))

    {:ok, p} =
      Deliveries.begin_step(
        d.id,
        "plan",
        0,
        pins(d, %{
          "workspace" => d.intent,
          "source_implementation_id" => implementation.id,
          "source_plan_id" => source_plan.id,
          "source_check_id" => nil
        })
      )

    forged = %{
      "status" => "finished",
      "cleanup" => "group_empty",
      "outcome" => "retained_plan",
      "report" => Map.put(source_plan.receipt["report"], "acceptance", ["Less"]),
      "workspace" => d.intent
    }

    assert {:error, :invalid_receipt} = Deliveries.finish_step(p.id, forged)

    assert {:error, _} =
             Repo.query("UPDATE delivery_steps SET status='finished',receipt=? WHERE id=?", [
               JSON.encode!(forged),
               p.id
             ])

    {:ok, p} =
      Deliveries.finish_step(p.id, Map.put(forged, "report", source_plan.receipt["report"]))

    input =
      pins(d, %{
        "parent_step_id" => p.id,
        "plan_step_id" => p.id,
        "workspace" => fresh(d.intent),
        "model_profile" => @catalog["resolver"],
        "network_policy" => Boss.Agents.NetworkPolicy.profile(1)
      })

    assert {:error, :invalid_step} = Deliveries.begin_step(d.id, "implement", 1, input)
    assert {:error, _} = raw_step(d, "implement", 1, input)
  end

  test "a later checkpoint follows immediate provider parent with ancestor implementation", c do
    {ancestor, _, implementation} = parent(c)
    {d, p} = checkpoint(c, ancestor)

    check =
      checkpoint_check(d, p, %{
        "status" => "failed",
        "outcome" => "checks_failed",
        "exit_code" => 1
      })

    {:ok, d} = Deliveries.complete(d.id, "failed")
    {next, _} = checkpoint(c, d)
    assert next.provider_recovery_version == 0 and next.retry_source_check_id == check.id

    assert {:ok, source} = ExecutionRetry.source(next)

    assert source.parent == d and source.check.id == check.id and
             source.implementation.id == implementation.id
  end

  for {label, attrs, code} <- [
        {"auth", %{"summary" => %{"error_class" => "auth"}}, "provider_rate_limit"},
        {"unknown", %{"summary" => %{"error_class" => "unknown"}}, "provider_rate_limit"},
        {"missing typed class", %{"summary" => %{}}, "provider_rate_limit"},
        {"wrong terminal code", %{}, "provider_auth"},
        {"untyped terminal", %{}, nil},
        {"Stop", %{"outcome" => "cancelled"}, "provider_rate_limit"},
        {"unknown cleanup", %{"cleanup" => "unknown"}, "provider_rate_limit"},
        {"missing EOF", %{"eof" => %{"stdout" => true, "stderr" => false}},
         "provider_rate_limit"},
        {"zero exit", %{"exit_code" => 0}, "provider_rate_limit"},
        {"boolean exit", %{"exit_code" => true}, "provider_rate_limit"},
        {"float exit", %{"exit_code" => 1.0}, "provider_rate_limit"},
        {"signal contradiction", %{"signal" => 15}, "provider_rate_limit"}
      ] do
    test "#{label} cannot authorize provider recovery through API or SQL", c do
      {parent, _, implementation} = parent(c, unquote(Macro.escape(attrs)), unquote(code))
      assert {:error, :checkpoint_retry_unavailable} = ExecutionRetry.provider_parent(parent)

      assert {:error, :checkpoint_retry_unavailable} =
               Deliveries.admit_checkpoint_retry(c.project.id, parent.id, Ecto.UUID.generate())

      assert {:error, _} = raw_provider(parent, implementation, %{})
    end
  end

  test "actual timeout keeps the previous explicit recovery policy", c do
    {parent, _, implementation} = parent(c, %{"outcome" => "timeout"})
    assert {:error, :checkpoint_retry_unavailable} = ExecutionRetry.provider_parent(parent)
    assert {:error, _} = raw_provider(parent, implementation, %{})

    assert {:ok, {:new, d}} =
             Deliveries.admit_checkpoint_retry(c.project.id, parent.id, Ecto.UUID.generate())

    assert d.provider_recovery_version == 0
  end

  test "migration roundtrip preserves old terminal rows and refuses new history loss", c do
    {parent, _, _} = parent(c)
    oldsteps = Deliveries.steps(parent.id)

    assert :ok =
             Ecto.Migrator.down(
               Repo,
               20_261_106_160_000,
               Boss.Repo.Migrations.AddProviderRecovery,
               log: false
             )

    assert :ok =
             Ecto.Migrator.up(Repo, 20_261_106_160_000, Boss.Repo.Migrations.AddProviderRecovery,
               log: false
             )

    assert Repo.get!(Delivery, parent.id) == parent and Deliveries.steps(parent.id) == oldsteps

    {:ok, {:new, _}} =
      Deliveries.admit_checkpoint_retry(c.project.id, parent.id, Ecto.UUID.generate())

    assert_raise RuntimeError, ~r/Refusing to discard provider recovery history/, fn ->
      Ecto.Migrator.down(Repo, 20_261_106_160_000, Boss.Repo.Migrations.AddProviderRecovery,
        log: false
      )
    end
  end

  defp parent(c, attrs \\ %{}, code \\ "provider_rate_limit") do
    {:ok, {:new, d}} = Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true")
    {:ok, d} = Deliveries.set_model_catalog(d.id, @catalog)
    {:ok, d} = Deliveries.set_intent(d.id, workspace(c, d.id))
    p = finish(d, "plan", 0, %{"workspace" => d.intent}, %{"report" => plan()})

    r =
      Map.merge(
        %{
          "status" => "failed",
          "outcome" => "exited",
          "exit_code" => 1,
          "summary" => %{"error_class" => "rate_limit"}
        },
        attrs
      )

    i =
      finish(
        d,
        "implement",
        1,
        %{"workspace" => fresh(d.intent), "parent_step_id" => p.id, "plan_step_id" => p.id},
        r
      )

    {:ok, d} = Deliveries.complete(d.id, "failed", nil, code)
    {d, p, i}
  end

  defp snapshot_input(d, p, i),
    do:
      pins(d, %{
        "run_workspace" => i.input["workspace"],
        "check_id" => Ecto.UUID.generate(),
        "source_check_id" => nil,
        "source_candidate_commit" => nil,
        "implementation_step_id" => i.id,
        "plan_step_id" => p.id
      })

  defp raw_provider(parent, implementation, changes) do
    attrs =
      Map.merge(
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
          provider_recovery_version: 1,
          implementation_network_version: 1,
          retry_implementation_id: implementation.id,
          retry_source_check_id: nil
        },
        changes
      )

    keys = Map.keys(attrs)

    Repo.query(
      "INSERT INTO deliveries (" <>
        Enum.map_join(keys, ",", &to_string/1) <>
        ",inserted_at,updated_at) VALUES(" <>
        Enum.map_join(keys, ",", fn _ -> "?" end) <> ",CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",
      Enum.map(keys, &Map.fetch!(attrs, &1))
    )
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

    run =
      if source.check,
        do: Map.put(fresh(d.intent), "base_commit", source.candidate_commit),
        else: source.implementation.input["workspace"]

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
          "source_check_id" => if(source.check, do: source.check.id),
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
        "source_check_id" => if(source.check, do: source.check.id),
        "implementation_step_id" => source.implementation.id,
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
