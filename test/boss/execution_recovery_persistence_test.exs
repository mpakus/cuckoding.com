defmodule Boss.ExecutionRecoveryPersistenceTest do
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
    {20_261_106_140_000, Boss.Repo.Migrations.AddExecutionRecovery}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-execution-storage-#{Ecto.UUID.generate()}")
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

  test "explicit timeout recovery copies immutable source and replay survives Repo restart", c do
    {parent, plan, implementation} = parent(c)
    old_steps = Deliveries.steps(parent.id)
    command = Ecto.UUID.generate()
    assert {:ok, {:new, child}} = Deliveries.admit_timeout_retry(c.project.id, parent.id, command)
    assert child.execution_recovery_version == 1 and parent.execution_recovery_version == 0
    assert child.retry_implementation_id == implementation.id
    assert child.admitted_version == parent.task_version + 1

    for field <- [
          :spec_revision_id,
          :check_config,
          :config_hash,
          :reviewer,
          :autonomy_version,
          :routing_version,
          :model_catalog
        ],
        do: assert(Map.fetch!(child, field) == Map.fetch!(parent, field))

    assert {:ok, source} = ExecutionRetry.source(child)

    assert source.parent == parent and source.plan.id == plan.id and
             source.implementation.id == implementation.id

    :ok = stop_supervised(Repo)
    Repo.put_dynamic_repo(start_supervised!({Repo, c.opts}))

    assert {:ok, {:existing, ^child}} =
             Deliveries.admit_timeout_retry(c.project.id, parent.id, command, true)

    assert Deliveries.steps(parent.id) == old_steps
    assert Repo.get!(Delivery, parent.id) == parent

    assert {:error, :idempotency_conflict} =
             Deliveries.admit(c.project.id, c.task.id, command, "true")

    assert {:error, :execution_retry_unavailable} =
             Deliveries.admit_retry(c.project.id, child.id, Ecto.UUID.generate())

    assert {:error, _} =
             Repo.query("UPDATE deliveries SET execution_recovery_version=0 WHERE id=?", [
               child.id
             ])

    assert {:error, _} =
             Repo.query("UPDATE deliveries SET retry_implementation_id=NULL WHERE id=?", [
               child.id
             ])
  end

  test "retained plan is typed evidence without process fiction and cannot approve delivery", c do
    {d, p, _} = child(c)
    assert p.receipt["outcome"] == "retained_plan"
    assert Enum.sort(Map.keys(p.receipt)) == ~w(cleanup outcome report status workspace)
    assert {:error, :missing_evidence} = Deliveries.complete(d.id, "ready_to_merge")

    assert {:error, :invalid_step} =
             Deliveries.begin_step(
               d.id,
               "implement",
               1,
               pins(d, %{
                 "workspace" => fresh(d.intent),
                 "plan_step_id" => p.id,
                 "parent_step_id" => p.id
               })
             )

    assert {:error, _} =
             raw_step(
               d,
               "implement",
               1,
               pins(d, %{
                 "workspace" => fresh(d.intent),
                 "plan_step_id" => p.id,
                 "parent_step_id" => p.id,
                 "model_profile" => @catalog["primary"]
               })
             )
  end

  test "snapshot check diagnosis and replacement bind retained commit and alternate model", c do
    {d, p, source} = child(c)
    check = timeout_check(d, p, source, 0)
    resolution = resolve(d, p, check)
    assert resolution.input["model_profile"] == @catalog["resolver"]
    input = implementation_input(d, p, resolution)

    assert {:error, :invalid_step} =
             Deliveries.begin_step(
               d.id,
               "implement",
               1,
               Map.put(input, "model_profile", @catalog["primary"])
             )

    assert {:error, _} =
             raw_step(d, "implement", 1, Map.put(input, "model_profile", @catalog["primary"]))

    replacement =
      finish(d, "implement", 1, input, %{"workspace" => input["workspace"], "head_commit" => @sha})

    assert replacement.input["model_profile"] == @catalog["resolver"]
    check = normal_check(d, p, replacement)
    review = review(d, p, check, "approved")
    assert {:ok, ready} = Deliveries.complete(d.id, "ready_to_merge")

    assert ready.status == "ready_to_merge" and
             review.receipt["report"]["acceptance"] == [
               %{"criterion" => "Saved criterion", "status" => "passed", "evidence" => "Verified"}
             ]
  end

  test "second Terra timeout switches diagnosis and replacement back to Sol", c do
    {d, p, source} = child(c)
    first = resolve(d, p, timeout_check(d, p, source, 0))
    failed = finish(d, "implement", 1, implementation_input(d, p, first), timeout())
    assert failed.input["model_profile"] == @catalog["resolver"]
    second = resolve(d, p, timeout_check(d, p, failed, 1))
    assert second.input["model_profile"] == hd(@catalog["fallbacks"])

    {:ok, implementation} =
      Deliveries.begin_step(d.id, "implement", 2, implementation_input(d, p, second))

    assert implementation.input["model_profile"] == hd(@catalog["fallbacks"])
  end

  test "ordinary rejection after timeout repair also alternates implementation source", c do
    {d, p, source} = child(c)
    first = resolve(d, p, timeout_check(d, p, source, 0))
    input = implementation_input(d, p, first)

    implementation =
      finish(d, "implement", 1, input, %{"workspace" => input["workspace"], "head_commit" => @sha})

    rejected = review(d, p, normal_check(d, p, implementation), "changes_requested")
    next = resolve(d, p, rejected)
    assert next.input["model_profile"] == hd(@catalog["fallbacks"])

    {:ok, replacement} =
      Deliveries.begin_step(d.id, "implement", 2, implementation_input(d, p, next))

    assert replacement.input["model_profile"] == hd(@catalog["fallbacks"])
  end

  for {label, attrs} <- [
        {"cancelled", %{"outcome" => "cancelled"}},
        {"unknown cleanup", %{"cleanup" => "unknown"}},
        {"missing EOF", %{"eof" => %{"stdout" => true, "stderr" => false}}},
        {"unknown exit", %{"exit_kind" => "unknown", "signal" => nil}}
      ] do
    test "#{label} never authorizes timeout recovery", c do
      {d, _, _} = parent(c, Map.merge(timeout(), unquote(Macro.escape(attrs))))

      assert {:error, :execution_retry_unavailable} =
               Deliveries.admit_timeout_retry(c.project.id, d.id, Ecto.UUID.generate())
    end
  end

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

  defp timeout_check(d, p, source, cycle) do
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
      %{"output_complete" => true, "output_hash" => @hash}
    )
  end

  defp resolve(d, p, source) do
    finish(
      d,
      "resolve",
      source.cycle,
      %{
        "parent_step_id" => source.id,
        "source_step_id" => source.id,
        "plan_step_id" => p.id,
        "workspace" => source.input["workspace"],
        "candidate_commit" => source.input["candidate_commit"],
        "resolution_attempt" => 1,
        "input_hash" => @hash,
        "feedback_hash" => @hash
      },
      %{
        "report" => %{
          "summary" => "Repair saved requirement",
          "steps" => ["Finish implementation"],
          "assumptions" => [],
          "external_action" => nil
        }
      }
    )
  end

  defp implementation_input(d, p, r),
    do:
      pins(d, %{
        "parent_step_id" => r.id,
        "resolution_step_id" => r.id,
        "source_step_id" => r.input["source_step_id"],
        "plan_step_id" => p.id,
        "workspace" => Map.put(fresh(d.intent), "base_commit", r.input["candidate_commit"])
      })

  defp normal_check(d, p, i) do
    w = %{"path" => d.intent["path"] <> "-candidate"}

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
      %{"output_complete" => true, "output_hash" => @hash}
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
