defmodule Boss.CatalogRoutingPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo}
  alias Boss.Deliveries.{AutopilotBatch, Delivery, Queue, Request}
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
    {20_261_105_120_000, Boss.Repo.Migrations.AddCatalogRouting}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-catalog-storage-#{Ecto.UUID.generate()}")
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

    Repo.put_dynamic_repo(start_supervised!({Repo, opts}))
    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)

    project =
      Repo.insert!(%Projects.Project{
        name: "Routing",
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

    %{project: project, task: task, opts: opts}
  end

  test "new routing is pinned before effects while queued legacy replay keeps its policy", c do
    command = Ecto.UUID.generate()
    {:ok, old} = Queue.admit(c.project.id, c.task.id, command, "true", "codex", 1, 1)
    assert {:ok, ^old} = Queue.admit(c.project.id, c.task.id, command, "true", "codex")
    assert {:ok, {:started, _, legacy}} = Queue.claim(old.id)
    assert legacy.routing_version == 1 and legacy.model_catalog == %{}

    assert {:error, _} =
             Repo.query("UPDATE deliveries SET routing_version=2 WHERE id=?", [legacy.id])

    assert {:ok, _} = Deliveries.complete(legacy.id, "failed")
    {:ok, queued} = Queue.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true", "codex")
    assert queued.routing_version == 2
    assert {:ok, {:started, started, delivery}} = Queue.claim(queued.id)
    assert delivery.routing_version == 2 and delivery.model_catalog == %{}
    restart(c)
    assert Repo.get!(Request, queued.id) == started
    assert {:ok, {:existing, ^started, ^delivery}} = Queue.claim(queued.id)
  end

  test "a catalog is validated, immutable and required before model stages", c do
    d = delivery(c)

    assert {:error, :catalog_invalid} =
             Deliveries.begin_step(d.id, "plan", 0, %{"workspace" => d.intent})

    assert {:error, _} =
             raw_step(d, "plan", 0, %{
               "workspace" => d.intent,
               "model_profile" => catalog()["primary"]
             })

    for forged <- [
          Map.put(catalog(), "extra", true),
          Map.put(catalog(), "resolver", catalog()["primary"]),
          put_in(catalog(), ["primary", "model"], "unregistered-model"),
          Map.put(catalog(), "fallbacks", [catalog()["resolver"], catalog()["primary"]])
        ] do
      assert {:error, :catalog_invalid} = Deliveries.set_model_catalog(d.id, forged)

      assert {:error, _} =
               Repo.query("UPDATE deliveries SET model_catalog=? WHERE id=?", [
                 JSON.encode!(forged),
                 d.id
               ])
    end

    assert {:ok, saved} = Deliveries.set_model_catalog(d.id, catalog())
    assert {:ok, ^saved} = Deliveries.set_model_catalog(d.id, catalog())

    assert {:error, :immutable_model_catalog} =
             Deliveries.set_model_catalog(d.id, Map.put(catalog(), "small", nil))

    assert {:error, _} = Repo.query("UPDATE deliveries SET model_catalog='{}' WHERE id=?", [d.id])

    assert {:error, _} =
             raw_step(d, "plan", 0, %{
               "workspace" => d.intent,
               "model_profile" => profile("gpt-6.1-sol", "high")
             })

    assert {:ok, step} = Deliveries.begin_step(d.id, "plan", 0, %{"workspace" => d.intent})
    assert step.input["model_profile"] == catalog()["primary"]
  end

  test "typed unavailable model at exit zero stays excluded after restart", c do
    d = delivery(c, 2, true)

    failed =
      finish(d, "plan", 0, %{"workspace" => d.intent}, %{
        "status" => "failed",
        "outcome" => "exited",
        "exit_code" => 0,
        "summary" => %{"error_class" => "model_unavailable"}
      })

    resolution = finish(d, "resolve", 0, resolution_input(d, failed), %{"report" => resolution()})
    assert resolution.input["model_profile"] == catalog()["resolver"]
    restart(c)
    assert {:ok, expected} = Deliveries.model_profile(d, :review, 1, failed.id)
    assert expected == catalog()["resolver"]

    input = %{
      "workspace" => d.intent,
      "parent_step_id" => resolution.id,
      "plan_step_id" => failed.id
    }

    assert {:error, :invalid_step} =
             Deliveries.begin_step(
               d.id,
               "plan",
               0,
               Map.put(input, "model_profile", catalog()["primary"])
             )

    assert {:error, _} =
             raw_step(d, "plan", 0, Map.put(input, "model_profile", catalog()["primary"]))

    assert {:ok, replan} = Deliveries.begin_step(d.id, "plan", 0, input)
    assert replan.input["model_profile"] == catalog()["resolver"]
  end

  test "an unknown nonzero exit does not permanently exclude the model", c do
    d = delivery(c, 2, true)

    finish(d, "plan", 0, %{"workspace" => d.intent}, %{
      "status" => "failed",
      "outcome" => "exited",
      "exit_code" => 1,
      "summary" => %{"error_class" => "unknown"}
    })

    assert {:ok, primary} = Deliveries.model_profile(d, :review, 1)
    assert primary == catalog()["primary"]
  end

  test "semantic zero-exit implementation failure resolves at its verified base", c do
    d = delivery(c, 2, true)
    plan = finish(d, "plan", 0, %{"workspace" => d.intent}, %{"report" => plan()})
    old = workspace(d.intent)

    failed =
      finish(
        d,
        "implement",
        1,
        %{"workspace" => old, "parent_step_id" => plan.id, "plan_step_id" => plan.id},
        %{
          "status" => "failed",
          "outcome" => "exited",
          "exit_code" => 0,
          "summary" => %{"error_class" => "unknown"},
          "workspace" => old
        }
      )

    input =
      resolution_input(d, failed)
      |> Map.merge(%{"plan_step_id" => plan.id, "workspace" => workspace(old)})

    assert {:ok, resolution} = Deliveries.begin_step(d.id, "resolve", 1, input)
    assert resolution.input["model_profile"] == catalog()["resolver"]
  end

  test "shared provider failures cannot trigger another resolver and terminal code is immutable",
       c do
    d = delivery(c, 2, true)

    failed =
      finish(d, "plan", 0, %{"workspace" => d.intent}, %{
        "status" => "failed",
        "outcome" => "exited",
        "exit_code" => 1,
        "summary" => %{"error_class" => "auth"}
      })

    input = resolution_input(d, failed)
    assert {:error, :invalid_step} = Deliveries.begin_step(d.id, "resolve", 0, input)

    assert {:error, _} =
             raw_step(d, "resolve", 0, Map.put(input, "model_profile", catalog()["resolver"]))

    assert {:error, :invalid_receipt} =
             Deliveries.complete(d.id, "failed", "Authentication failed", "arbitrary")

    assert {:ok, saved} =
             Deliveries.complete(d.id, "failed", "Authentication failed", "provider_auth")

    restart(c)
    assert Repo.get!(Delivery, d.id).failure_code == "provider_auth"

    assert {:error, _} =
             Repo.query("UPDATE deliveries SET failure_code=NULL WHERE id=?", [saved.id])
  end

  test "routing two selection adds failed tasks without changing legacy selection or history",
       c do
    d = delivery(c)
    assert {:ok, old} = Deliveries.complete(d.id, "failed", "Retained failed task")

    {:ok, %{task: next}} =
      Projects.record_spec(c.project.id, %{
        relative_path: "two.md",
        title: "Two",
        original_text: "# Two"
      })

    assert Queue.autopilot_candidates(c.project.id, 1) == [next.id]
    assert Queue.autopilot_candidates(c.project.id, 2) == [c.task.id, next.id]

    attrs = %{
      id: Ecto.UUID.generate(),
      project_id: c.project.id,
      command_id: Ecto.UUID.generate(),
      task_ids: [c.task.id, next.id],
      check_config: d.check_config,
      config_hash: d.config_hash,
      reviewer: "codex",
      autonomy_version: 1
    }

    assert_raise Exqlite.Error, fn -> Repo.insert!(struct(AutopilotBatch, attrs)) end
    batch = Repo.insert!(struct(AutopilotBatch, Map.put(attrs, :routing_version, 2)))
    assert batch.routing_version == 2
    assert Repo.get!(Delivery, old.id) == old

    assert {:error, _} =
             Repo.query("UPDATE autopilots SET routing_version=1 WHERE id=?", [batch.id])
  end

  test "intake pins routing and its own catalog without changing the workspace shape", c do
    project =
      Repo.insert!(%Projects.Project{
        name: "Docs",
        root_path: c.project.root_path <> "/docs",
        git_common_dir: c.project.git_common_dir <> "/docs",
        specs_path: c.project.specs_path <> "/docs",
        base_branch: "main",
        intake_mode: "documentation"
      })

    {:ok, {:new, request}} =
      Projects.Intake.admit(project.id, Ecto.UUID.generate(), "true", "codex", false)

    assert request.routing_version == 2 and request.workspace == %{}
    assert {:error, :catalog_invalid} = Projects.Intake.pin(request.id, %{"base_commit" => @sha})

    assert {:error, _} =
             Repo.query("UPDATE project_intakes SET workspace=? WHERE id=?", [
               JSON.encode!(%{"base_commit" => @sha}),
               request.id
             ])

    assert {:ok, saved} = Projects.Intake.set_model_catalog(request.id, catalog())
    assert saved.workspace == %{} and saved.model_catalog == catalog()

    assert {:error, _} =
             Repo.query("UPDATE project_intakes SET model_catalog='{}' WHERE id=?", [saved.id])
  end

  test "migration roundtrip retains historical routing and refuses new authorizations", c do
    {:ok, old} = Queue.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true", "codex", 1, 1)

    assert :ok =
             Ecto.Migrator.down(Repo, 20_261_105_120_000, Boss.Repo.Migrations.AddCatalogRouting,
               log: false
             )

    assert :ok =
             Ecto.Migrator.up(Repo, 20_261_105_120_000, Boss.Repo.Migrations.AddCatalogRouting,
               log: false
             )

    assert Repo.get!(Request, old.id).routing_version == 1
    {:ok, _} = Queue.cancel(c.project.id, old.id)
    {:ok, {:new, _}} = Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true")

    assert_raise RuntimeError, ~r/Refusing to discard catalog routing history/, fn ->
      Ecto.Migrator.down(Repo, 20_261_105_120_000, Boss.Repo.Migrations.AddCatalogRouting,
        log: false
      )
    end
  end

  test "independent routing schema preserves an older strict Autopilot guard" do
    routing = Boss.Repo.Migrations.AddCatalogRouting
    continuation = Boss.Repo.Migrations.ContinueAutopilotAfterTaskFailure
    assert :ok = Ecto.Migrator.down(Repo, 20_261_105_120_000, routing, log: false)
    assert :ok = Ecto.Migrator.down(Repo, 20_261_104_120_000, continuation, log: false)

    before =
      Repo.query!("SELECT sql FROM sqlite_schema WHERE name='autopilot_delivery_guard'").rows

    assert :ok = Ecto.Migrator.up(Repo, 20_261_105_120_000, routing, log: false)

    assert Repo.query!("SELECT sql FROM sqlite_schema WHERE name='autopilot_delivery_guard'").rows ==
             before

    assert :ok = Ecto.Migrator.down(Repo, 20_261_105_120_000, routing, log: false)

    assert Repo.query!("SELECT sql FROM sqlite_schema WHERE name='autopilot_delivery_guard'").rows ==
             before
  end

  defp restart(c) do
    :ok = stop_supervised(Repo)
    Repo.put_dynamic_repo(start_supervised!({Repo, c.opts}))
  end

  defp delivery(c, routing \\ 2, pin \\ false) do
    {:ok, {:new, d}} =
      Deliveries.admit(
        c.project.id,
        c.task.id,
        Ecto.UUID.generate(),
        "true",
        "codex",
        false,
        1,
        routing
      )

    intent = %{
      "run_id" => d.id,
      "project_id" => to_string(c.project.id),
      "repo_path" => c.project.root_path,
      "git_common_dir" => c.project.git_common_dir,
      "base_branch" => "main",
      "base_commit" => @sha,
      "path" => Path.join(c.project.root_path, d.id),
      "branch" => "codex/boss-run-#{d.id}"
    }

    {:ok, d} = Deliveries.set_intent(d.id, intent)
    if pin, do: elem(Deliveries.set_model_catalog(d.id, catalog()), 1), else: d
  end

  defp catalog,
    do: %{
      "version" => 2,
      "primary" => profile("gpt-5.6-sol", "high"),
      "resolver" => profile("gpt-5.6-terra", "xhigh"),
      "small" => profile("gpt-5.6-luna", "medium"),
      "fallbacks" => [profile("gpt-5.6-sol", "xhigh"), profile("gpt-5.6-terra", "xhigh")]
    }

  defp profile(model, effort), do: %{"model" => model, "reasoning_effort" => effort}

  defp plan,
    do: %{
      "summary" => "Saved requirement",
      "steps" => ["Implement it"],
      "acceptance" => ["Saved criterion"],
      "clarification" => nil
    }

  defp resolution,
    do: %{
      "summary" => "Use existing convention",
      "steps" => ["Implement existing behavior"],
      "assumptions" => [],
      "external_action" => nil
    }

  defp workspace(old) do
    id = Ecto.UUID.generate()

    Map.merge(old, %{
      "run_id" => id,
      "path" => Path.join(Path.dirname(old["path"]), id),
      "branch" => "codex/boss-run-#{id}"
    })
  end

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

  defp finish(d, kind, cycle, input, attrs) do
    assert {:ok, s} =
             Deliveries.begin_step(
               d.id,
               kind,
               cycle,
               Map.merge(
                 %{"spec_revision_id" => d.spec_revision_id, "config_hash" => d.config_hash},
                 input
               )
             )

    assert {:ok, s} =
             Deliveries.finish_step(
               s.id,
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
             )

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
