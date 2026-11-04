defmodule Boss.AutonomyPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo}
  alias Boss.Deliveries.{Autopilot, AutopilotBatch, Queue, Request}
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
    {20_261_106_120_000, Boss.Repo.Migrations.ConvertProjectDocumentation}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-autonomy-storage-#{Ecto.UUID.generate()}")
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

  test "admission and queued replay preserve the original policy across Repo restart", c do
    command = Ecto.UUID.generate()
    assert {:ok, request} = Queue.admit(c.project.id, c.task.id, command, "true", "codex", 0)
    assert request.autonomy_version == 0
    assert {:ok, ^request} = Queue.admit(c.project.id, c.task.id, command, "true", "codex")
    assert {:ok, {:started, saved, delivery}} = Queue.claim(request.id)
    assert delivery.autonomy_version == 0

    assert {:error, _} =
             Repo.query("UPDATE deliveries SET autonomy_version=1 WHERE id=?", [delivery.id])

    assert {:error, _} =
             Repo.query("UPDATE delivery_requests SET autonomy_version=1 WHERE id=?", [request.id])

    :ok = stop_supervised(Repo)
    Repo.put_dynamic_repo(start_supervised!({Repo, c.opts}))
    assert Repo.get!(Request, request.id) == saved
    assert {:ok, {:existing, ^saved, ^delivery}} = Queue.claim(request.id)

    assert {:ok, {:existing, ^delivery}} =
             Deliveries.admit(c.project.id, c.task.id, command, "true")
  end

  test "new direct, batch and intake admissions pin policy before effects", c do
    assert {:ok, {:new, d}} =
             Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true")

    assert d.autonomy_version == 1
    assert Deliveries.steps(d.id) == []
    assert {:ok, _} = Deliveries.complete(d.id, "cancelled")

    {:ok, %{task: task}} =
      Projects.record_spec(c.project.id, %{
        relative_path: "two.md",
        title: "Two",
        original_text: "# Two"
      })

    assert {:ok, batch} =
             Autopilot.admit(c.project.id, Ecto.UUID.generate(), [task.id], "true", "codex")

    assert Repo.get!(AutopilotBatch, batch.id).autonomy_version == 1
    assert Repo.get_by!(Request, task_id: task.id).autonomy_version == 1
    assert {:ok, _} = Autopilot.cancel(c.project.id, batch.id, batch.version)

    project =
      Repo.insert!(%Projects.Project{
        name: "Docs",
        root_path: c.project.root_path <> "/docs-project",
        git_common_dir: c.project.git_common_dir <> "/docs-project",
        specs_path: c.project.specs_path <> "/docs-project",
        base_branch: "main",
        intake_mode: "documentation"
      })

    assert {:ok, {:new, intake}} =
             Projects.Intake.admit(project.id, Ecto.UUID.generate(), "true", "codex", false)

    assert intake.autonomy_version == 1
    assert intake.workspace == %{}
  end

  test "clarification resolution retains criteria and rejects forged model or report evidence",
       c do
    d = delivery(c)

    plan =
      finish(d, "plan", 0, %{"workspace" => d.intent}, %{
        "report" => plan("Which existing option should be used?")
      })

    input = resolution_input(d, plan)

    assert {:error, :invalid_step} =
             Deliveries.begin_step(
               d.id,
               "resolve",
               0,
               Map.put(input, "model_profile", %{
                 "model" => "gpt-6-luna",
                 "reasoning_effort" => "low"
               })
             )

    assert {:error, _} = raw_step(d, "resolve", 0, input)
    assert {:ok, step} = Deliveries.begin_step(d.id, "resolve", 0, input)

    assert step.input["model_profile"] == %{
             "model" => "gpt-6-astra",
             "reasoning_effort" => "xhigh"
           }

    malformed = receipt(%{"report" => Map.delete(resolution(), "external_action")})
    assert {:error, :invalid_receipt} = Deliveries.finish_step(step.id, malformed)

    assert {:error, _} =
             Repo.query("UPDATE delivery_steps SET status='finished',receipt=? WHERE id=?", [
               JSON.encode!(malformed),
               step.id
             ])

    oversized =
      receipt(%{
        "report" =>
          Map.put(resolution(), "steps", List.duplicate(String.duplicate("x", 1800), 20))
      })

    assert {:error, :invalid_receipt} = Deliveries.finish_step(step.id, oversized)

    assert {:error, _} =
             Repo.query("UPDATE delivery_steps SET status='finished',receipt=? WHERE id=?", [
               JSON.encode!(oversized),
               step.id
             ])

    assert {:ok, step} = Deliveries.finish_step(step.id, receipt(%{"report" => resolution()}))
    assert {:error, :missing_evidence} = Deliveries.complete(d.id, "ready_to_merge")

    replan_input = %{
      "workspace" => d.intent,
      "parent_step_id" => step.id,
      "plan_step_id" => plan.id
    }

    assert {:ok, fresh} = Deliveries.begin_step(d.id, "plan", 0, replan_input)
    weakened = receipt(%{"report" => Map.put(plan(nil), "acceptance", ["Different requirement"])})
    assert {:error, :invalid_receipt} = Deliveries.finish_step(fresh.id, weakened)

    assert {:error, _} =
             Repo.query("UPDATE delivery_steps SET status='finished',receipt=? WHERE id=?", [
               JSON.encode!(weakened),
               fresh.id
             ])

    assert {:ok, fresh} = Deliveries.finish_step(fresh.id, receipt(%{"report" => plan(nil)}))

    assert {:ok, implement} =
             Deliveries.begin_step(d.id, "implement", 1, %{"plan_step_id" => fresh.id})

    assert implement.input["model_profile"]["model"] == "gpt-6.1-sol"
  end

  test "second opinion binds the same problem and unavailable evidence cannot authorize work",
       c do
    d = delivery(c)
    plan = finish(d, "plan", 0, %{"workspace" => d.intent}, %{"report" => plan("Which option?")})

    first =
      finish(d, "resolve", 0, resolution_input(d, plan), %{
        "report" => Map.put(resolution(), "external_action", "Need repository access")
      })

    input =
      resolution_input(d, plan)
      |> Map.merge(%{"parent_step_id" => first.id, "resolution_attempt" => 2})

    assert {:error, :invalid_step} =
             Deliveries.begin_step(d.id, "plan", 0, %{
               "workspace" => d.intent,
               "parent_step_id" => first.id,
               "plan_step_id" => plan.id
             })

    assert {:error, :invalid_step} =
             Deliveries.begin_step(
               d.id,
               "resolve",
               0,
               Map.put(input, "source_step_id", Ecto.UUID.generate())
             )

    assert {:ok, second} = Deliveries.begin_step(d.id, "resolve", 0, input)

    assert second.input["model_profile"] == %{
             "model" => "gpt-6.1-sol",
             "reasoning_effort" => "xhigh"
           }

    assert {:ok, second} = Deliveries.finish_step(second.id, receipt(%{"report" => resolution()}))

    assert {:error, :invalid_step} =
             Deliveries.begin_step(
               d.id,
               "resolve",
               0,
               Map.merge(input, %{"parent_step_id" => second.id, "resolution_attempt" => 3})
             )

    assert {:ok, _} =
             Deliveries.begin_step(d.id, "plan", 0, %{
               "workspace" => d.intent,
               "parent_step_id" => second.id,
               "plan_step_id" => plan.id
             })
  end

  test "unknown cleanup cannot start resolution and legacy deliveries cannot acquire new stages",
       c do
    d = delivery(c)
    assert {:ok, plan} = Deliveries.begin_step(d.id, "plan", 0, %{"workspace" => d.intent})

    assert {:ok, plan} =
             Deliveries.finish_step(plan.id, %{"status" => "interrupted", "cleanup" => "unknown"})

    assert {:error, :cleanup_unknown} =
             Deliveries.begin_step(d.id, "resolve", 0, resolution_input(d, plan))

    assert {:error, _} =
             raw_step(
               d,
               "resolve",
               0,
               Map.put(resolution_input(d, plan), "model_profile", %{
                 "model" => "gpt-6-astra",
                 "reasoning_effort" => "xhigh"
               })
             )
  end

  test "legacy policy keeps old budgets and new stages cannot be inserted directly", c do
    d = delivery(c, 0)
    plan = finish(d, "plan", 0, %{"workspace" => d.intent}, %{"report" => plan("Which option?")})

    assert {:error, :invalid_step} =
             Deliveries.begin_step(d.id, "resolve", 0, resolution_input(d, plan))

    assert {:error, _} = raw_step(d, "resolve", 0, resolution_input(d, plan))
    assert {:error, _} = raw_step(d, "implement", 4, %{})

    assert {:error, _} =
             Repo.query(
               "INSERT INTO delivery_steps(id,delivery_id,number,kind,cycle,input,inserted_at,updated_at) VALUES(?,?,21,'check',3,'{}',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",
               [Ecto.UUID.generate(), d.id]
             )
  end

  test "migration roundtrip preserves legacy policy and refuses to discard new authorizations",
       c do
    {:ok, request} =
      Queue.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true", "codex", 0)

    # Remove later cross-workflow guards before exercising the old schema.
    assert :ok =
             Ecto.Migrator.down(
               Repo,
               20_261_106_120_000,
               Boss.Repo.Migrations.ConvertProjectDocumentation, log: false)

    # Remove the independent later routing guards before exercising the old schema.
    assert :ok =
             Ecto.Migrator.down(Repo, 20_261_105_120_000, Boss.Repo.Migrations.AddCatalogRouting,
               log: false
             )

    migration = Boss.Repo.Migrations.AddAutonomousRecovery
    assert :ok = Ecto.Migrator.down(Repo, 20_261_104_130_000, migration, log: false)
    assert {:ok, %{rows: [[request_id]]}} = Repo.query("SELECT id FROM delivery_requests", [])
    assert request_id == request.id
    assert :ok = Ecto.Migrator.up(Repo, 20_261_104_130_000, migration, log: false)

    assert :ok =
             Ecto.Migrator.up(Repo, 20_261_105_120_000, Boss.Repo.Migrations.AddCatalogRouting,
               log: false
             )

    assert :ok =
             Ecto.Migrator.up(
               Repo,
               20_261_106_120_000,
               Boss.Repo.Migrations.ConvertProjectDocumentation, log: false)

    assert Repo.get!(Request, request.id).autonomy_version == 0
    {:ok, _} = Queue.cancel(c.project.id, request.id)

    {:ok, {:new, delivery}} =
      Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true")

    assert_raise RuntimeError, ~r/Refusing to discard autonomous workflow history/, fn ->
      Ecto.Migrator.down(Repo, 20_261_104_130_000, migration, log: false)
    end

    assert Repo.get!(Deliveries.Delivery, delivery.id).autonomy_version == 1
  end

  test "failed checks require a candidate-bound resolution before another implementation", c do
    d = delivery(c)
    plan = finish(d, "plan", 0, %{"workspace" => d.intent}, %{"report" => plan(nil)})

    implementation =
      finish(d, "implement", 1, %{"plan_step_id" => plan.id}, %{
        "workspace" => d.intent,
        "head_commit" => @sha
      })

    candidate = %{"path" => "/retained/candidate", "base_commit" => @sha}

    snapshot =
      finish(
        d,
        "snapshot",
        1,
        %{"plan_step_id" => plan.id, "implementation_step_id" => implementation.id},
        %{"workspace" => candidate, "candidate_commit" => @sha}
      )

    check =
      finish(
        d,
        "check",
        1,
        %{
          "plan_step_id" => plan.id,
          "snapshot_step_id" => snapshot.id,
          "workspace" => candidate,
          "candidate_commit" => @sha
        },
        %{
          "status" => "failed",
          "exit_code" => 1,
          "outcome" => "checks_failed",
          "output_complete" => true,
          "output_hash" => @hash
        }
      )

    repair = %{"plan_step_id" => plan.id, "parent_step_id" => check.id, "workspace" => candidate}
    assert {:error, :invalid_step} = Deliveries.begin_step(d.id, "implement", 2, repair)

    assert {:error, _} =
             raw_step(
               d,
               "implement",
               2,
               Map.put(repair, "model_profile", %{
                 "model" => "gpt-6-astra",
                 "reasoning_effort" => "xhigh"
               })
             )

    input =
      resolution_input(d, check)
      |> Map.merge(%{"plan_step_id" => plan.id, "workspace" => candidate})

    assert {:ok, resolution_step} = Deliveries.begin_step(d.id, "resolve", 1, input)
    wrong = receipt(%{"report" => resolution(), "candidate_commit" => String.duplicate("f", 40)})
    assert {:error, :invalid_receipt} = Deliveries.finish_step(resolution_step.id, wrong)

    assert {:error, _} =
             Repo.query("UPDATE delivery_steps SET status='finished',receipt=? WHERE id=?", [
               JSON.encode!(wrong),
               resolution_step.id
             ])

    assert {:ok, resolution_step} =
             Deliveries.finish_step(resolution_step.id, receipt(%{"report" => resolution()}))

    repair =
      Map.merge(repair, %{
        "parent_step_id" => resolution_step.id,
        "resolution_step_id" => resolution_step.id,
        "source_step_id" => check.id
      })

    assert {:ok, next} = Deliveries.begin_step(d.id, "implement", 2, repair)
    assert next.input["model_profile"]["model"] == "gpt-6-astra"
  end

  test "invalid reports do not exclude a model and a failed resolver gets another opinion", c do
    d = delivery(c)

    failed =
      finish(d, "plan", 0, %{"workspace" => d.intent}, %{
        "status" => "failed",
        "outcome" => "invalid_report",
        "exit_code" => 0
      })

    first =
      finish(d, "resolve", 0, resolution_input(d, failed), %{
        "status" => "failed",
        "outcome" => "exited",
        "exit_code" => 2
      })

    input =
      resolution_input(d, failed)
      |> Map.merge(%{"parent_step_id" => first.id, "resolution_attempt" => 2})

    second = finish(d, "resolve", 0, input, %{"report" => resolution()})
    input = %{"workspace" => d.intent, "parent_step_id" => second.id, "plan_step_id" => failed.id}

    assert {:error, :invalid_step} =
             Deliveries.begin_step(
               d.id,
               "plan",
               0,
               Map.put(input, "model_profile", %{
                 "model" => "gpt-6.1-sol",
                 "reasoning_effort" => "high"
               })
             )

    assert {:ok, replan} = Deliveries.begin_step(d.id, "plan", 0, input)

    assert replan.input["model_profile"] == %{
             "model" => "gpt-6.1-sol",
             "reasoning_effort" => "xhigh"
           }

    assert {:ok, _} = Deliveries.finish_step(replan.id, receipt(%{"report" => plan(nil)}))
  end

  test "unavailable models stay excluded after restart and cannot be forced through SQL", c do
    d = delivery(c)

    failed =
      finish(d, "plan", 0, %{"workspace" => d.intent}, %{
        "status" => "failed",
        "outcome" => "exited",
        "exit_code" => 7
      })

    resolved = finish(d, "resolve", 0, resolution_input(d, failed), %{"report" => resolution()})

    fresh =
      finish(
        d,
        "plan",
        0,
        %{"workspace" => d.intent, "parent_step_id" => resolved.id, "plan_step_id" => failed.id},
        %{"report" => plan(nil)}
      )

    assert fresh.input["model_profile"]["model"] == "gpt-6-astra"

    :ok = stop_supervised(Repo)
    Repo.put_dynamic_repo(start_supervised!({Repo, c.opts}))
    assert {:ok, profile} = Deliveries.model_profile(d, :implement, 1, fresh.id)
    assert profile == %{"model" => "gpt-6-astra", "reasoning_effort" => "xhigh"}
    assert {:ok, ^profile} = Deliveries.model_profile(d, :review, 1, fresh.id)

    input = %{
      "plan_step_id" => fresh.id,
      "model_profile" => %{"model" => "gpt-6.1-sol", "reasoning_effort" => "high"}
    }

    assert {:error, :invalid_step} = Deliveries.begin_step(d.id, "implement", 1, input)
    assert {:error, _} = raw_step(d, "implement", 1, input)

    assert {:ok, implementation} =
             Deliveries.begin_step(d.id, "implement", 1, Map.delete(input, "model_profile"))

    assert implementation.input["model_profile"] == profile
  end

  test "a failed implementation resolves from a fresh saved base without adopting partial work",
       c do
    d = delivery(c)
    plan = finish(d, "plan", 0, %{"workspace" => d.intent}, %{"report" => plan(nil)})
    old = fresh_workspace(d.intent)

    failed =
      finish(
        d,
        "implement",
        1,
        %{"plan_step_id" => plan.id, "parent_step_id" => plan.id, "workspace" => old},
        %{
          "status" => "failed",
          "outcome" => "exited",
          "exit_code" => 7,
          "workspace" => old
        }
      )

    workspace = fresh_workspace(old)

    input =
      resolution_input(d, failed)
      |> Map.merge(%{"plan_step_id" => plan.id, "workspace" => workspace})

    profile = %{"model" => "gpt-6-astra", "reasoning_effort" => "xhigh"}

    for invalid <- [
          Map.put(input, "workspace", old),
          put_in(input, ["workspace", "repo_path"], "/other/repository"),
          Map.put(input, "candidate_commit", String.duplicate("c", 40))
        ] do
      assert {:error, :invalid_step} = Deliveries.begin_step(d.id, "resolve", 1, invalid)
      assert {:error, _} = raw_step(d, "resolve", 1, Map.put(invalid, "model_profile", profile))
    end

    resolved = finish(d, "resolve", 1, input, %{"report" => resolution()})

    next = %{
      "plan_step_id" => plan.id,
      "parent_step_id" => resolved.id,
      "resolution_step_id" => resolved.id,
      "source_step_id" => failed.id,
      "workspace" => fresh_workspace(workspace)
    }

    assert {:error, :invalid_step} =
             Deliveries.begin_step(
               d.id,
               "implement",
               2,
               put_in(next, ["workspace", "base_commit"], String.duplicate("c", 40))
             )

    assert {:error, _} =
             raw_step(
               d,
               "implement",
               2,
               put_in(
                 Map.put(next, "model_profile", profile),
                 ["workspace", "base_commit"],
                 String.duplicate("c", 40)
               )
             )

    assert {:ok, implementation} = Deliveries.begin_step(d.id, "implement", 2, next)
    assert implementation.input["workspace"]["base_commit"] == old["base_commit"]
    assert implementation.input["model_profile"] == profile
    assert Repo.get!(Deliveries.Step, failed.id).input["workspace"] == old
  end

  test "exhausted strong models stop without reusing a failed model", c do
    d = delivery(c)

    failed =
      finish(d, "plan", 0, %{"workspace" => d.intent}, %{
        "status" => "failed",
        "outcome" => "exited",
        "exit_code" => 7
      })

    first =
      finish(d, "resolve", 0, resolution_input(d, failed), %{
        "status" => "failed",
        "outcome" => "exited",
        "exit_code" => 7
      })

    input =
      resolution_input(d, failed)
      |> Map.merge(%{"parent_step_id" => first.id, "resolution_attempt" => 2})

    assert {:error, :models_exhausted} = Deliveries.model_profile(d, :resolve, 2, failed.id)
    assert {:error, :models_exhausted} = Deliveries.begin_step(d.id, "resolve", 0, input)

    assert {:error, _} =
             raw_step(
               d,
               "resolve",
               0,
               Map.put(input, "model_profile", %{
                 "model" => "gpt-6.1-sol",
                 "reasoning_effort" => "xhigh"
               })
             )

    assert length(Deliveries.steps(d.id)) == 2
  end

  test "a second opinion cannot silently reuse the first model when the other is unavailable",
       c do
    d = delivery(c)

    failed =
      finish(d, "plan", 0, %{"workspace" => d.intent}, %{
        "status" => "failed",
        "outcome" => "exited",
        "exit_code" => 7
      })

    first =
      finish(d, "resolve", 0, resolution_input(d, failed), %{
        "report" => Map.put(resolution(), "external_action", "Need repository access")
      })

    input =
      resolution_input(d, failed)
      |> Map.merge(%{"parent_step_id" => first.id, "resolution_attempt" => 2})

    assert {:error, :models_exhausted} = Deliveries.begin_step(d.id, "resolve", 0, input)

    assert {:error, _} =
             raw_step(
               d,
               "resolve",
               0,
               Map.put(input, "model_profile", %{
                 "model" => "gpt-6-astra",
                 "reasoning_effort" => "xhigh"
               })
             )
  end

  test "failed implementation recovery retains a complete SHA-256 base identity", c do
    sha = String.duplicate("c", 64)
    d = delivery(c, 1, sha)
    plan = finish(d, "plan", 0, %{"workspace" => d.intent}, %{"report" => plan(nil)})
    workspace = fresh_workspace(d.intent)

    failed =
      finish(
        d,
        "implement",
        1,
        %{"plan_step_id" => plan.id, "parent_step_id" => plan.id, "workspace" => workspace},
        %{
          "status" => "failed",
          "outcome" => "exited",
          "exit_code" => 7,
          "workspace" => workspace
        }
      )

    input =
      resolution_input(d, failed)
      |> Map.merge(%{
        "plan_step_id" => plan.id,
        "workspace" => fresh_workspace(workspace),
        "candidate_commit" => sha
      })

    resolved =
      finish(d, "resolve", 1, input, %{"report" => resolution(), "candidate_commit" => sha})

    assert resolved.input["candidate_commit"] == sha
  end

  test "failed implementation recovery cannot trust a forged base or predecessor", c do
    for field <- ["base_commit", "parent_step_id"] do
      d = delivery(c)
      plan = finish(d, "plan", 0, %{"workspace" => d.intent}, %{"report" => plan(nil)})
      workspace = fresh_workspace(d.intent)

      source_input = %{
        "plan_step_id" => plan.id,
        "parent_step_id" => plan.id,
        "workspace" => workspace
      }

      source_input =
        if field == "base_commit",
          do: put_in(source_input, ["workspace", "base_commit"], String.duplicate("f", 40)),
          else: Map.put(source_input, "parent_step_id", Ecto.UUID.generate())

      failed =
        finish(d, "implement", 1, source_input, %{
          "status" => "failed",
          "outcome" => "exited",
          "exit_code" => 7
        })

      input =
        resolution_input(d, failed)
        |> Map.merge(%{
          "plan_step_id" => plan.id,
          "workspace" => fresh_workspace(source_input["workspace"]),
          "candidate_commit" => source_input["workspace"]["base_commit"]
        })

      assert {:error, :invalid_step} = Deliveries.begin_step(d.id, "resolve", 1, input)

      assert {:error, _} =
               raw_step(
                 d,
                 "resolve",
                 1,
                 Map.put(input, "model_profile", %{
                   "model" => "gpt-6-astra",
                   "reasoning_effort" => "xhigh"
                 })
               )

      assert {:ok, _} = Deliveries.complete(d.id, "failed")
    end
  end

  defp delivery(c, version \\ 1, sha \\ @sha) do
    {:ok, {:new, d}} =
      Deliveries.admit(
        c.project.id,
        c.task.id,
        Ecto.UUID.generate(),
        "true",
        "codex",
        false,
        version
      )

    intent = %{
      "run_id" => d.id,
      "project_id" => to_string(c.project.id),
      "repo_path" => c.project.root_path,
      "git_common_dir" => c.project.git_common_dir,
      "base_branch" => "main",
      "base_commit" => sha,
      "path" => Path.join(c.project.root_path, d.id),
      "branch" => "codex/boss-run-#{d.id}"
    }

    {:ok, d} = Deliveries.set_intent(d.id, intent)
    d
  end

  defp fresh_workspace(old) do
    id = Ecto.UUID.generate()

    Map.merge(old, %{
      "run_id" => id,
      "path" => Path.join(Path.dirname(old["path"]), id),
      "branch" => "codex/boss-run-#{id}"
    })
  end

  defp plan(question),
    do: %{
      "summary" => "Implement saved requirement",
      "steps" => ["Use the existing option"],
      "acceptance" => ["Saved criterion"],
      "clarification" => question
    }

  defp resolution,
    do: %{
      "summary" => "Use repository convention",
      "steps" => ["Follow existing option"],
      "assumptions" => ["Existing behavior is the intended default"],
      "external_action" => nil
    }

  defp resolution_input(d, source),
    do: %{
      "parent_step_id" => source.id,
      "source_step_id" => source.id,
      "plan_step_id" => source.id,
      "workspace" => d.intent,
      "candidate_commit" => @sha,
      "config_hash" => d.config_hash,
      "spec_revision_id" => d.spec_revision_id,
      "input_hash" => @hash,
      "feedback_hash" => @hash,
      "resolution_attempt" => 1
    }

  defp receipt(attrs),
    do:
      Map.merge(
        %{
          "status" => "finished",
          "cleanup" => "group_empty",
          "exit_kind" => "exit",
          "exit_code" => 0,
          "eof" => %{"stdout" => true, "stderr" => true},
          "candidate_commit" => @sha
        },
        attrs
      )

  defp finish(d, kind, cycle, input, attrs) do
    input =
      Map.merge(
        %{"spec_revision_id" => d.spec_revision_id, "config_hash" => d.config_hash},
        input
      )

    assert {:ok, s} = Deliveries.begin_step(d.id, kind, cycle, input)
    assert {:ok, s} = Deliveries.finish_step(s.id, receipt(attrs))
    s
  end

  defp raw_step(d, kind, cycle, input),
    do:
      Repo.query(
        "INSERT INTO delivery_steps(id,delivery_id,number,kind,cycle,input,inserted_at,updated_at) VALUES(?,?,?,?,?,?,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",
        [
          Ecto.UUID.generate(),
          d.id,
          length(Deliveries.steps(d.id)) + 1,
          kind,
          cycle,
          JSON.encode!(input)
        ]
      )
end
