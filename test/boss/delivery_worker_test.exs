defmodule Boss.DeliveryWorkerTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo, Tasks}
  alias Boss.Checks.Candidate
  alias Boss.Runs.Manager
  @moduletag skip: :os.type() != {:unix, :darwin}
  @moduletag capture_log: true
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

  setup context do
    root = Path.join(System.tmp_dir!(), "boss-delivery-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, lock} = Boss.DataDirectory.acquire(root)
    on_exit(fn -> Boss.DataDirectory.release(lock) end)
    old_data = Application.fetch_env!(:boss, :data_dir)
    Application.put_env(:boss, :data_dir, root)
    on_exit(fn -> Application.put_env(:boss, :data_dir, old_data) end)

    opts = [
      name: nil,
      database: Path.join(root, "boss.db"),
      pool: DBConnection.ConnectionPool,
      pool_size: 2
    ]

    repo = start_repo(opts)
    Repo.put_dynamic_repo(repo)
    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)
    source = Path.join(root, "source")
    File.mkdir!(source)
    {physical, 0} = System.cmd("/bin/pwd", ["-P"], cd: source)
    source = String.trim(physical)
    File.write!(Path.join(source, "result.txt"), "base")
    File.cp!(Path.expand("../fixtures/delivery_check.py", __DIR__), Path.join(source, "check.py"))

    for args <- [
          ["init", "-b", "main"],
          ["config", "user.name", "Fixture"],
          ["config", "user.email", "fixture@example.invalid"],
          ["add", "."],
          ["commit", "-m", "base"]
        ] do
      assert {_, 0} =
               System.cmd("git", args,
                 cd: source,
                 stderr_to_stdout: true,
                 env: [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"}]
               )
    end

    project =
      Repo.insert!(%Projects.Project{
        name: "Delivery",
        root_path: source,
        git_common_dir: Path.join(source, ".git"),
        specs_path: source,
        base_branch: "main"
      })

    {:ok, record} =
      Projects.record_spec(project.id, %{
        relative_path: "one.md",
        title: "One",
        original_text: "# One\nCreate result.txt"
      })

    bin = Path.join(root, "bin")
    File.mkdir!(bin)
    File.cp!(Path.expand("../fixtures/codex_delivery.py", __DIR__), Path.join(bin, "codex"))
    File.chmod!(Path.join(bin, "codex"), 0o700)
    File.cp!(Path.expand("../fixtures/claude_review.py", __DIR__), Path.join(bin, "claude"))
    File.chmod!(Path.join(bin, "claude"), 0o700)

    keys = [
      "PATH",
      "BOSS_DELIVERY_MODE",
      "BOSS_DELIVERY_FIXTURE",
      "BOSS_CLAUDE_MODE",
      "BOSS_MODEL_CATALOG"
    ]

    previous = Map.take(System.get_env(), keys)
    System.put_env("PATH", bin <> ":" <> System.fetch_env!("PATH"))
    System.delete_env("BOSS_DELIVERY_MODE")
    System.delete_env("BOSS_CLAUDE_MODE")
    System.delete_env("BOSS_MODEL_CATALOG")
    System.put_env("BOSS_DELIVERY_FIXTURE", root)

    on_exit(fn ->
      for key <- keys do
        if Map.has_key?(previous, key),
          do: System.put_env(key, previous[key]),
          else: System.delete_env(key)
      end
    end)

    %{
      root: root,
      repo: repo,
      opts: opts,
      project: project,
      task: record.task,
      source: source,
      autonomy: context[:autonomy] == true,
      routing: context[:routing] || 1
    }
  end

  @tag autonomy: true, routing: 2
  test "catalog routing pins installed models and resolves a question through a distinct model",
       ctx do
    System.put_env("BOSS_MODEL_CATALOG", "installed")
    System.put_env("BOSS_DELIVERY_MODE", "autonomy_plan")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "ready_to_merge", inspect({saved, Deliveries.steps(run.id)})
    assert saved.routing_version == 2
    assert saved.model_catalog["primary"]["model"] == "gpt-5.6-sol"
    assert saved.model_catalog["resolver"]["model"] == "gpt-5.6-terra"

    assert Enum.map(calls(ctx), & &1["model"]) ==
             ~w(gpt-5.6-sol gpt-5.6-terra gpt-5.6-sol gpt-5.6-sol gpt-5.6-sol)

    assert_no_raw(Deliveries.steps(run.id))
  end

  @tag autonomy: true, routing: 2
  test "catalog routing sends a rejected candidate to a distinct implementing model and fresh checks",
       ctx do
    System.put_env("BOSS_MODEL_CATALOG", "installed")
    System.put_env("BOSS_DELIVERY_MODE", "autonomy_review")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge" and saved.cycle == 2, inspect({saved, steps})
    [first, second] = Enum.filter(steps, &(&1.kind == "implement"))
    assert first.input["model_profile"]["model"] == "gpt-5.6-sol"
    assert second.input["model_profile"]["model"] == "gpt-5.6-terra"
    assert length(Enum.filter(steps, &(&1.kind == "check"))) == 2
    assert List.last(steps).receipt["report"]["verdict"] == "approved"
    assert_no_raw(steps)
  end

  @tag autonomy: true, routing: 2
  test "a shared authentication failure retains a typed cause without paying another model",
       ctx do
    System.put_env("BOSS_MODEL_CATALOG", "installed")
    System.put_env("BOSS_DELIVERY_MODE", "routing_auth")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "failed" and saved.cleanup == "group_empty"
    assert saved.failure_code == "provider_auth"
    assert Enum.map(calls(ctx), & &1["kind"]) == ["plan"]
    [step] = Deliveries.steps(run.id)
    assert step.receipt["summary"]["error_class"] == "auth"
    assert_no_raw([step])
  end

  @tag autonomy: true, routing: 2
  test "a semantic implementation error with exit zero gets a fresh experiment rather than approval",
       ctx do
    System.put_env("BOSS_MODEL_CATALOG", "installed")
    System.put_env("BOSS_DELIVERY_MODE", "routing_zero_error")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})
    [failed, replacement] = Enum.filter(steps, &(&1.kind == "implement"))
    assert failed.status == "failed" and failed.receipt["exit_code"] == 0
    assert failed.receipt["summary"]["error_class"] == "unknown"

    assert File.read!(Path.join(failed.input["workspace"]["path"], "partial-only.txt")) =~
             "retained"

    assert replacement.status == "finished"
    assert replacement.input["model_profile"]["model"] != failed.input["model_profile"]["model"]
    assert_no_raw(steps)
  end

  @tag autonomy: true, routing: 2
  test "invalid catalog data fails before any model request and retains no raw metadata", ctx do
    System.put_env("BOSS_MODEL_CATALOG", "invalid")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "failed" and saved.failure_code == "catalog_invalid"
    assert saved.model_catalog == %{} and saved.intent == %{}
    assert Deliveries.steps(run.id) == []
    refute File.exists?(Path.join(ctx.root, "calls"))
    refute inspect(saved) =~ "SECRET_SENTINEL"
  end

  @tag autonomy: true, routing: 2
  test "Stop interrupts catalog discovery directly without creating a workspace or model stage",
       ctx do
    System.put_env("BOSS_MODEL_CATALOG", "wait")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    eventually(fn -> File.exists?(Path.join(ctx.root, "catalog-waiting")) end)
    :sys.suspend(manager)

    try do
      assert :ok = Deliveries.stop(ctx.project.id, run.id, Boss.DeliveryTestsActive)
      eventually(fn -> not Deliveries.active?(Deliveries.get(ctx.project.id, run.id)) end)
    after
      :sys.resume(manager)
    end

    saved = await_delivery(ctx, run.id)
    assert saved.status == "cancelled" and saved.cleanup == "group_empty"
    assert saved.model_catalog == %{} and saved.intent == %{}
    assert Deliveries.steps(run.id) == []
    refute File.exists?(Path.join(ctx.root, "calls"))
  end

  @tag autonomy: true
  test "a planning question is resolved by Astra and a fresh plan proceeds without owner input",
       ctx do
    System.put_env("BOSS_DELIVERY_MODE", "autonomy_plan")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})
    assert saved.autonomy_version == 1
    assert Enum.map(steps, & &1.kind) == ~w(plan resolve plan implement snapshot check review)
    [original, resolution, replanned, implementation | _] = steps
    assert resolution.input["source_step_id"] == original.id
    assert replanned.input["parent_step_id"] == resolution.id
    assert implementation.input["plan_step_id"] == replanned.id

    assert Enum.map(calls(ctx), & &1["model"]) ==
             ~w(gpt-6.1-sol gpt-6-astra gpt-6.1-sol gpt-6.1-sol gpt-6.1-sol)

    assert_no_raw(steps)
  end

  @tag autonomy: true
  test "small initial implementations use Luna while review remains independent", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "autonomy_small")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    assert await_delivery(ctx, run.id).status == "ready_to_merge"
    assert Enum.map(calls(ctx), & &1["model"]) == ~w(gpt-6.1-sol gpt-6-luna gpt-6.1-sol)
    assert Enum.at(calls(ctx), 1)["reasoning_effort"] == "medium"
  end

  @tag autonomy: true
  test "an unclear review is diagnosed before a different implementation model fixes the candidate",
       ctx do
    System.put_env("BOSS_DELIVERY_MODE", "autonomy_review")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge" and saved.cycle == 2, inspect({saved, steps})
    [first, second] = Enum.filter(steps, &(&1.kind == "implement"))
    [resolution] = Enum.filter(steps, &(&1.kind == "resolve"))
    assert first.input["model_profile"]["model"] == "gpt-6.1-sol"

    assert second.input["model_profile"] == %{
             "model" => "gpt-6-astra",
             "reasoning_effort" => "xhigh"
           }

    assert second.input["parent_step_id"] == resolution.id
    assert second.input["workspace"]["base_commit"] == resolution.input["candidate_commit"]
    assert first.input["plan_step_id"] == second.input["plan_step_id"]

    assert Repo.get!(Projects.SpecRevision, saved.spec_revision_id).original_text ==
             "# One\nCreate result.txt"

    assert_no_raw(steps)
  end

  @tag autonomy: true
  test "a failed check gives complete transient output to resolution and the alternate implementer",
       ctx do
    System.put_env("BOSS_DELIVERY_MODE", "check_once")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})

    assert Enum.map(steps, & &1.kind) ==
             ~w(plan implement snapshot check resolve implement snapshot check review)

    failed = Enum.find(steps, &(&1.kind == "check"))
    resolver = Enum.find(steps, &(&1.kind == "resolve"))
    assert failed.receipt["exit_code"] == 3 and failed.receipt["output_complete"]
    assert resolver.input["source_step_id"] == failed.id
    assert resolver.input["candidate_commit"] == failed.input["candidate_commit"]

    assert Enum.map(Enum.filter(calls(ctx), &(&1["kind"] == "implement")), & &1["model"]) ==
             ~w(gpt-6.1-sol gpt-6-astra)

    assert_no_raw(steps)
  end

  @tag autonomy: true
  test "repeated unchanged rejection gets a new model attempt and can recover", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "autonomy_repeated")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_retry(ctx, run.id)
    assert saved.status == "ready_to_merge" and saved.cycle == 3, inspect(saved)
    implementation = Enum.filter(calls(ctx), &(&1["kind"] == "implement"))
    assert Enum.map(implementation, & &1["model"]) == ~w(gpt-6.1-sol gpt-6-astra gpt-6.1-sol)
    assert Enum.at(implementation, 2)["reasoning_effort"] == "xhigh"
    assert Enum.count(calls(ctx), &(&1["kind"] == "resolve")) == 2
  end

  @tag autonomy: true
  test "external action requires two model opinions and does not fabricate implementation", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "autonomy_external")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "needs_input", inspect({saved, Deliveries.steps(run.id)})
    assert Enum.map(calls(ctx), & &1["kind"]) == ~w(plan resolve resolve)
    assert Enum.map(Enum.drop(calls(ctx), 1), & &1["model"]) == ~w(gpt-6-astra gpt-6.1-sol)
    assert Repo.get!(Tasks.Task, ctx.task.id).state == "needs_input"
    assert File.read!(Path.join(ctx.source, "result.txt")) == "base"
  end

  for mode <- ~w(autonomy_invalid_plan autonomy_invalid_resolver) do
    @tag autonomy: true
    @autonomy_mode mode
    test "#{@autonomy_mode} recovers through validated alternate output", ctx do
      System.put_env("BOSS_DELIVERY_MODE", @autonomy_mode)

      if @autonomy_mode == "autonomy_invalid_resolver" do
        fixture = Path.join([ctx.root, "bin", "codex"])

        File.write!(
          fixture,
          String.replace(
            File.read!(fixture),
            "\"resolution_attempt\": data.get(\"resolution_attempt\"),",
            "\"resolution_attempt\": data.get(\"resolution_attempt\"), \"previous_resolution_diagnostic\": data.get(\"previous_resolution_diagnostic\"),"
          )
        )
      end

      manager = start_manager(ctx.repo)
      {:ok, run} = start(ctx, manager)
      saved = await_delivery(ctx, run.id)
      steps = Deliveries.steps(run.id)
      assert saved.status == "ready_to_merge", inspect({saved, steps})

      assert Enum.any?(
               steps,
               &(&1.status == "failed" and &1.receipt["outcome"] == "invalid_report")
             )

      assert_no_raw(steps)

      if @autonomy_mode == "autonomy_invalid_resolver" do
        [failed, passed] = Enum.filter(steps, &(&1.kind == "resolve"))
        assert failed.receipt["summary"]["validation_code"] == "invalid_steps"
        assert failed.receipt["summary"]["report_bytes"] in 1..32_768
        assert passed.receipt["summary"]["validation_code"] == "valid"
        [_first, second] = Enum.filter(calls(ctx), &(&1["kind"] == "resolve"))

        assert second["previous_resolution_diagnostic"] == %{
                 "outcome" => "invalid_report",
                 "validation_code" => "invalid_steps",
                 "report_bytes" => failed.receipt["summary"]["report_bytes"]
               }
      end
    end
  end

  @tag autonomy: true
  test "a model execution failure switches the replanner as well as recording the diagnosis",
       ctx do
    System.put_env("BOSS_DELIVERY_MODE", "autonomy_model_unavailable")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})
    assert hd(steps).receipt["exit_code"] == 7

    assert Enum.map(calls(ctx), & &1["model"]) ==
             ~w(gpt-6.1-sol gpt-6-astra gpt-6-astra gpt-6-astra gpt-6-astra)

    assert_no_raw(steps)
  end

  @tag autonomy: true
  test "a failed strong-model resolver obtains the second opinion from Sol", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "autonomy_resolver_unavailable")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})
    [first, second] = Enum.filter(steps, &(&1.kind == "resolve"))
    assert first.status == "failed" and first.receipt["exit_code"] == 7
    assert second.status == "finished"
    assert first.input["source_step_id"] == second.input["source_step_id"]
    assert first.input["model_profile"]["model"] == "gpt-6-astra"
    assert second.input["model_profile"]["model"] == "gpt-6.1-sol"
  end

  @tag autonomy: true
  test "a clean failed review execution is diagnosed without treating it as approval", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "autonomy_review_unavailable")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge" and saved.cycle == 2, inspect({saved, steps})
    [first, second] = Enum.filter(steps, &(&1.kind == "review"))
    assert first.status == "failed" and first.receipt["exit_code"] == 7
    refute first.receipt["report"]
    assert second.status == "finished" and second.receipt["report"]["verdict"] == "approved"
    assert_no_raw(steps)
  end

  @tag autonomy: true
  test "a persistently unavailable Sol route is excluded from all later stages", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "autonomy_persistent_sol")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})
    assert hd(steps).receipt["outcome"] == "exited" and hd(steps).receipt["exit_code"] == 7

    assert Enum.map(calls(ctx), & &1["model"]) ==
             ~w(gpt-6.1-sol gpt-6-astra gpt-6-astra gpt-6-astra gpt-6-astra)

    assert_no_raw(steps)
  end

  for mode <- ~w(autonomy_partial autonomy_luna_unavailable) do
    @tag autonomy: true
    @recovery_mode mode
    test "#{@recovery_mode} retains partial edits and retries from the verified base", ctx do
      System.put_env("BOSS_DELIVERY_MODE", @recovery_mode)
      manager = start_manager(ctx.repo)
      {:ok, run} = start(ctx, manager)
      saved = await_delivery(ctx, run.id)
      steps = Deliveries.steps(run.id)
      assert saved.status == "ready_to_merge" and saved.cycle == 2, inspect({saved, steps})
      [failed, replacement] = Enum.filter(steps, &(&1.kind == "implement"))
      [resolution] = Enum.filter(steps, &(&1.kind == "resolve"))
      assert failed.status == "failed" and failed.receipt["exit_code"] == 7
      assert failed.receipt["outcome"] == "exited" and failed.receipt["cleanup"] == "group_empty"

      assert File.read!(Path.join(failed.input["workspace"]["path"], "partial-only.txt")) ==
               "retained failed implementation\n"

      assert File.read!(Path.join(failed.input["workspace"]["path"], "result.txt")) ==
               "unverified partial work\n"

      base = failed.input["workspace"]["base_commit"]
      assert resolution.input["candidate_commit"] == base
      assert resolution.input["workspace"]["base_commit"] == base
      assert resolution.input["workspace"]["path"] != failed.input["workspace"]["path"]
      assert replacement.input["workspace"]["base_commit"] == base
      assert replacement.input["workspace"]["path"] != failed.input["workspace"]["path"]
      assert replacement.input["parent_step_id"] == resolution.id
      assert replacement.input["model_profile"]["model"] != failed.input["model_profile"]["model"]
      refute File.exists?(Path.join(replacement.input["workspace"]["path"], "partial-only.txt"))
      check = steps |> Enum.filter(&(&1.kind == "check")) |> List.last()
      review = List.last(steps)
      assert check.receipt["exit_code"] == 0 and check.receipt["output_complete"]
      assert check.input["candidate_commit"] == review.input["candidate_commit"]
      assert :ok == Candidate.verify(check.input["workspace"], check.input["candidate_commit"])
      refute File.exists?(Path.join(check.input["workspace"]["path"], "partial-only.txt"))
      assert_no_raw(steps)
    end
  end

  @tag autonomy: true
  test "two unavailable strong models produce an explicit finite outcome without using Luna",
       ctx do
    System.put_env("BOSS_DELIVERY_MODE", "autonomy_models_exhausted")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "failed" and saved.cleanup == "group_empty", inspect(saved)
    assert saved.reason =~ "No eligible model remains"
    assert Enum.map(calls(ctx), & &1["model"]) == ~w(gpt-6.1-sol gpt-6-astra)
    refute Enum.any?(calls(ctx), &(&1["kind"] == "implement"))
    assert_no_raw(Deliveries.steps(run.id))
  end

  for mode <- ~w(autonomy_zero_error autonomy_malformed_wait) do
    @tag autonomy: true
    @transport_mode mode
    test "#{@transport_mode} never becomes successful provider evidence", ctx do
      System.put_env("BOSS_DELIVERY_MODE", @transport_mode)
      {:ok, config, _} = Boss.Checks.Command.parse("python3 check.py")

      {:ok, prompt} =
        Boss.Deliveries.Protocol.prompt(:plan, %{
          "specification" => "# One\nCreate result.txt",
          "check_config" => config
        })

      receipt =
        Boss.Deliveries.Worker.run_agent(
          :plan,
          ctx.source,
          prompt,
          &Boss.Deliveries.Protocol.plan/1,
          %{"model" => "gpt-6.1-sol", "reasoning_effort" => "high"}
        )

      assert receipt["status"] == "failed" and receipt["cleanup"] == "group_empty"
      refute receipt["report"]

      if @transport_mode == "autonomy_zero_error" do
        assert receipt["exit_code"] == 0 and receipt["outcome"] == "exited"
      else
        assert receipt["outcome"] == "cancelled"
      end

      refute inspect(receipt, limit: :infinity) =~ "SECRET_SENTINEL"
    end
  end

  for mode <- ~w(autonomy_wait_resolve autonomy_partial_wait_resolve) do
    @tag autonomy: true
    @stop_mode mode
    test "#{@stop_mode}: Stop reaches the resolver without waiting for Manager", ctx do
      System.put_env("BOSS_DELIVERY_MODE", @stop_mode)
      manager = start_manager(ctx.repo)
      {:ok, run} = start(ctx, manager)
      eventually(fn -> File.exists?(Path.join(ctx.root, "resolver-waiting")) end)
      :sys.suspend(manager)

      try do
        assert :ok = Deliveries.stop(ctx.project.id, run.id, Boss.DeliveryTestsActive)
        eventually(fn -> not Deliveries.active?(Deliveries.get(ctx.project.id, run.id)) end)
      after
        :sys.resume(manager)
      end

      saved = await_delivery(ctx, run.id)
      assert saved.status == "cancelled" and saved.cleanup == "group_empty"

      expected =
        if @stop_mode == "autonomy_wait_resolve",
          do: ~w(plan implement review resolve),
          else: ~w(plan implement resolve)

      assert Enum.map(calls(ctx), & &1["kind"]) == expected
    end
  end

  test "complete plan, implementation, check and review are durable without raw output", ctx do
    manager = start_manager(ctx.repo)
    command = Ecto.UUID.generate()
    {:ok, run} = start(ctx, manager, command)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "ready_to_merge", inspect({saved, Deliveries.steps(run.id)})
    steps = Deliveries.steps(run.id)
    assert Enum.map(steps, & &1.kind) == ~w(plan implement snapshot check review)
    assert Enum.all?(steps, &(&1.status == "finished"))
    assert List.last(steps).receipt["report"]["verdict"] == "approved"
    assert Repo.get!(Tasks.Task, ctx.task.id).state == "ready_to_merge"
    assert Repo.aggregate(Boss.Runs.Run, :count) == 0
    assert File.read!(Path.join(ctx.source, "result.txt")) == "base"
    assert_no_raw(steps)
    :ok = stop_supervised(Manager)
    :ok = stop_supervised(Repo)
    repo = start_repo(ctx.opts)
    Repo.put_dynamic_repo(repo)
    manager = start_manager(repo)
    assert Deliveries.get(ctx.project.id, run.id) == saved
    assert {:ok, ^saved} = start(ctx, manager, command)
    assert length(calls(ctx)) == 3
  end

  test "Claude reviews complete supplied evidence and cannot finish the task on CLI success",
       ctx do
    manager = start_manager(ctx.repo)
    command = Ecto.UUID.generate()
    {:ok, run} = start_claude(ctx, manager, command)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})
    assert saved.reviewer == "claude"
    assert Enum.map(calls(ctx), & &1["kind"]) == ~w(plan implement claude_review)
    review = List.last(steps)
    assert review.receipt["report"]["verdict"] == "approved"
    assert review.receipt["summary"]["usage"]["input_tokens"] == 12
    assert Repo.get!(Tasks.Task, ctx.task.id).state == "ready_to_merge"
    assert File.read!(Path.join(ctx.source, "result.txt")) == "base"
    [claude] = Enum.filter(calls(ctx), &(&1["kind"] == "claude_review"))
    refute File.exists?(claude["cwd"])
    assert_no_raw(steps)
    assert {:ok, ^saved} = start_claude(ctx, manager, command)
    assert {:error, :idempotency_conflict} = start(ctx, manager, command)
    assert length(calls(ctx)) == 3
  end

  test "missing selected Claude fails before any Codex work or workspace preparation", ctx do
    bin = Path.join(ctx.root, "bin")
    File.rename!(Path.join(bin, "claude"), Path.join(bin, "claude-disabled"))
    System.put_env("PATH", bin <> ":/usr/bin:/bin")
    assert is_nil(System.find_executable("claude"))
    manager = start_manager(ctx.repo)
    {:ok, run} = start_claude(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "failed" and saved.reason =~ "Claude is unavailable"
    assert saved.intent == %{}
    assert Deliveries.steps(run.id) == []
    refute File.exists?(Path.join(ctx.root, "calls"))
  end

  test "Claude rejection feeds Codex fix and another fresh Claude review", ctx do
    System.put_env("BOSS_CLAUDE_MODE", "reject_once")
    manager = start_manager(ctx.repo)
    {:ok, run} = start_claude(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})
    assert saved.cycle == 2

    assert Enum.map(calls(ctx), & &1["kind"]) ==
             ~w(plan implement claude_review implement claude_review)

    [first, second] = Enum.filter(steps, &(&1.kind == "review"))
    assert first.receipt["report"]["verdict"] == "changes_requested"
    assert second.receipt["report"]["verdict"] == "approved"
    assert first.input["candidate_commit"] != second.input["candidate_commit"]
    assert first.input["original_base"] == second.input["original_base"]
    assert_no_raw(steps)
  end

  for mode <-
        ~w(malformed oversized unsafe_init external_tool denied error missing_report coverage duplicate truncated nonzero refusal aborted) do
    @claude_mode mode
    test "Claude #{@claude_mode} halts without fallback or automatic repair", ctx do
      System.put_env("BOSS_CLAUDE_MODE", @claude_mode)
      manager = start_manager(ctx.repo)
      {:ok, run} = start_claude(ctx, manager)
      saved = await_delivery(ctx, run.id)
      assert saved.status == "failed", inspect({saved, Deliveries.steps(run.id)})
      assert Enum.map(calls(ctx), & &1["kind"]) == ~w(plan implement claude_review)
      assert List.last(Deliveries.steps(run.id)).status == "failed"
      assert_no_raw(Deliveries.steps(run.id))
    end
  end

  test "Stop reaches Claude directly while Manager is suspended", ctx do
    System.put_env("BOSS_CLAUDE_MODE", "wait")
    manager = start_manager(ctx.repo)
    {:ok, run} = start_claude(ctx, manager)
    eventually(fn -> File.exists?(Path.join(ctx.root, "claude-waiting")) end)
    :sys.suspend(manager)

    try do
      assert :ok = Deliveries.stop(ctx.project.id, run.id, Boss.DeliveryTestsActive)
      eventually(fn -> not Deliveries.active?(Deliveries.get(ctx.project.id, run.id)) end)
    after
      :sys.resume(manager)
    end

    saved = await_delivery(ctx, run.id)
    assert saved.status == "cancelled" and saved.cleanup == "group_empty"
    assert Enum.map(calls(ctx), & &1["kind"]) == ~w(plan implement claude_review)
    refute Map.has_key?(List.last(Deliveries.steps(run.id)).receipt, "report")
  end

  test "review rejection fixes a new worktree from the rejected candidate with full-base review",
       ctx do
    System.put_env("BOSS_DELIVERY_MODE", "reject_once")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})
    assert saved.cycle == 2
    [first, second] = Enum.filter(steps, &(&1.kind == "snapshot"))
    [_, fix] = Enum.filter(steps, &(&1.kind == "implement"))
    assert fix.input["workspace"]["base_commit"] == first.receipt["candidate_commit"]
    refute first.receipt["workspace"]["path"] == second.receipt["workspace"]["path"]

    assert File.read!(Path.join(first.receipt["workspace"]["path"], "result.txt")) ==
             "candidate-1\n"

    assert File.read!(Path.join(second.receipt["workspace"]["path"], "result.txt")) ==
             "candidate-2\n"

    assert :ok == Candidate.verify(first.receipt["workspace"], first.receipt["candidate_commit"])

    assert :ok ==
             Candidate.verify(second.receipt["workspace"], second.receipt["candidate_commit"])

    assert_no_raw(steps)
  end

  test "complete check failure consumes a cycle and provides full output to the fix", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "check_once")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    steps = Deliveries.steps(run.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})

    assert Enum.map(steps, & &1.kind) ==
             ~w(plan implement snapshot check implement snapshot check review)

    failed = Enum.find(steps, &(&1.kind == "check"))
    assert failed.status == "failed" and failed.receipt["output_complete"]
    assert failed.receipt["exit_code"] == 3
    assert_no_raw(steps)
  end

  test "repeated unchanged feedback stops before the three-cycle maximum", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "repeated")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "blocked", inspect(saved)
    assert saved.cycle == 2
    assert saved.reason =~ "same failure"
    assert length(Enum.filter(calls(ctx), &(&1["kind"] == "implement"))) == 2
  end

  test "different rejected trees still stop after three total cycles", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "reject_always")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "blocked", inspect(saved)
    assert saved.cycle == 3
    assert saved.reason =~ "budget"
    assert length(Enum.filter(calls(ctx), &(&1["kind"] == "implement"))) == 3
  end

  @tag timeout: 120_000
  test "explicit retry retains rejected content and review with fresh plan and check output",
       ctx do
    manager = start_manager(ctx.repo)
    parent = rejected_delivery(ctx, manager)
    parent_steps = Deliveries.steps(parent.id)
    old_review = List.last(parent_steps)
    old_sha = old_review.input["candidate_commit"]
    old_workspace = old_review.input["workspace"]
    System.delete_env("BOSS_DELIVERY_MODE")

    {:ok, retry} = retry(ctx, manager, parent.id)
    saved = await_retry(ctx, retry.id)
    steps = Deliveries.steps(saved.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})
    assert saved.cycle == 1 and saved.retry_review_id == old_review.id
    assert saved.intent["base_commit"] == parent.intent["base_commit"]

    assert Enum.map(steps, & &1.kind) ==
             ~w(plan retry_snapshot retry_check implement snapshot check review)

    [plan, snapshot, check, implementation, _, final_check, review] = steps
    assert Enum.all?(steps, &(&1.status == "finished"))

    assert plan.receipt["report"]["acceptance"] ==
             hd(parent_steps).receipt["report"]["acceptance"]

    assert snapshot.input["source_candidate_commit"] == old_sha
    assert check.input["snapshot_step_id"] == snapshot.id
    assert check.receipt["output_complete"] and check.receipt["exit_code"] == 0
    assert check.receipt["stdout_bytes"] > 0 and check.receipt["stderr_bytes"] > 0
    assert implementation.input["parent_step_id"] == check.id
    assert implementation.input["workspace"]["base_commit"] == check.input["candidate_commit"]
    assert implementation.input["source_review_id"] == old_review.id
    assert review.input["original_base"] == parent.intent["base_commit"]
    assert review.input["check_step_id"] == final_check.id
    assert Deliveries.get(ctx.project.id, parent.id) == parent
    assert Deliveries.steps(parent.id) == parent_steps
    assert :ok = Candidate.verify(old_workspace, old_sha)
    assert_no_raw(steps)

    retry_calls = Enum.drop(calls(ctx), 7)
    assert Enum.map(retry_calls, & &1["kind"]) == ~w(plan implement review)
    assert hd(retry_calls)["has_previous_review"]
    assert hd(retry_calls)["previous_candidate_commit"] == old_sha
    assert Enum.at(retry_calls, 1)["source_review_id"] == old_review.id
    assert File.read!(Path.join(ctx.source, "result.txt")) == "base"
    count = length(calls(ctx))
    :ok = stop_supervised(Manager)
    :ok = stop_supervised(Repo)
    repo = start_repo(ctx.opts)
    Repo.put_dynamic_repo(repo)
    manager = start_manager(repo)

    assert {:ok, ^saved} =
             Boss.Deliveries.Retry.start(ctx.project.id, parent.id, saved.command_id, manager)

    assert {:ok, _} = Boss.Deliveries.Retry.source(saved)
    assert length(calls(ctx)) == count
  end

  test "retry snapshot refuses a dirty or advanced seed before capture", ctx do
    for kind <- [:dirty, :advanced] do
      {:ok, seed} = Boss.Agents.Workspace.plan(ctx.project, Ecto.UUID.generate())
      seed = Map.new(seed, fn {key, value} -> {to_string(key), value} end)
      {:ok, _} = Boss.Agents.Workspace.prepare(seed)
      File.write!(Path.join(seed["path"], "result.txt"), "unexpected seed change")

      if kind == :advanced do
        {:ok, _} = Boss.Agents.Workspace.git(seed["path"], ["add", "result.txt"])

        {:ok, _} =
          Boss.Agents.Workspace.git(seed["path"], ["commit", "-m", "unexpected seed advance"])
      end

      check_id = Ecto.UUID.generate()

      assert catch_throw(
               Boss.Deliveries.Worker.prepare_retry_snapshot(seed, check_id, seed["base_commit"])
             ) ==
               {:halt, :candidate_changed}

      assert {:error, {:git_exit, 1}} =
               Boss.Agents.Workspace.git(
                 ctx.source,
                 ["show-ref", "--verify", "--quiet", "refs/boss/checks/#{check_id}"]
               )
    end
  end

  @tag timeout: 120_000
  test "explicit timeout retry captures partial work before distinct-model repair and fresh review",
       ctx do
    parent = timed_out_delivery(ctx)
    parent_steps = Deliveries.steps(parent.id)
    [old_plan, old_implementation] = parent_steps
    old_workspace = old_implementation.input["workspace"]
    assert parent.execution_recovery_version == 0

    assert File.read!(Path.join(old_workspace["path"], "timeout-only.txt")) ==
             "retained partial work\n"

    {:ok, original_status} =
      Boss.Agents.Workspace.git(old_workspace["path"], ["status", "--porcelain=v1"])

    manager = start_manager(ctx.repo)
    command = Ecto.UUID.generate()

    assert {:ok, child} =
             Boss.Deliveries.Retry.start_timeout(ctx.project.id, parent.id, command, manager)

    saved = await_retry(ctx, child.id)
    steps = Deliveries.steps(child.id)
    assert saved.status == "ready_to_merge", inspect({saved, steps})
    assert saved.execution_recovery_version == 1
    assert saved.intent["base_commit"] == parent.intent["base_commit"]
    assert saved.check_config == parent.check_config

    assert Enum.map(steps, & &1.kind) ==
             ~w(plan timeout_snapshot timeout_check resolve implement snapshot check review)

    [plan, snapshot, check, resolution, implementation, _, final_check, review] = steps
    assert plan.receipt["outcome"] == "retained_plan"
    assert plan.receipt["report"] == old_plan.receipt["report"]
    refute Map.has_key?(plan.input, "model_profile")
    refute Map.has_key?(plan.receipt, "exit_code")
    assert snapshot.input["implementation_step_id"] == old_implementation.id
    assert snapshot.input["workspace"]["run_workspace"] == old_workspace
    assert check.input["snapshot_step_id"] == snapshot.id
    assert resolution.cycle == 0 and implementation.cycle == 1
    assert resolution.input["source_step_id"] == check.id
    assert implementation.input["resolution_step_id"] == resolution.id
    assert implementation.input["workspace"]["base_commit"] == check.input["candidate_commit"]

    for step <- [resolution, implementation] do
      assert step.input["model_profile"]["model"] == "gpt-5.6-terra"
    end

    assert check.receipt["output_complete"] and check.receipt["exit_code"] == 3
    assert check.status == "failed" and check.receipt["outcome"] == "checks_failed"
    assert review.input["check_step_id"] == final_check.id
    assert review.input["original_base"] == parent.intent["base_commit"]
    assert review.receipt["report"]["verdict"] == "approved"

    assert File.read!(Path.join(final_check.input["workspace"]["path"], "timeout-only.txt")) ==
             "retained partial work\n"

    assert Deliveries.get(ctx.project.id, parent.id) == parent
    assert Deliveries.steps(parent.id) == parent_steps

    assert {:ok, ^original_status} =
             Boss.Agents.Workspace.git(old_workspace["path"], ["status", "--porcelain=v1"])

    assert Enum.map(Enum.drop(calls(ctx), 2), & &1["kind"]) == ~w(resolve implement review)
    count = length(calls(ctx))

    assert {:ok, ^saved} =
             Boss.Deliveries.Retry.start_timeout(ctx.project.id, parent.id, command, manager)

    assert length(calls(ctx)) == count
    assert_no_raw(steps)
  end

  @tag timeout: 120_000
  test "timeout capture refuses incomplete fresh check evidence before another model", ctx do
    parent = timed_out_delivery(ctx)
    System.put_env("BOSS_DELIVERY_MODE", "check_invalid_utf8")
    manager = start_manager(ctx.repo)

    assert {:ok, child} =
             Boss.Deliveries.Retry.start_timeout(
               ctx.project.id,
               parent.id,
               Ecto.UUID.generate(),
               manager
             )

    saved = await_retry(ctx, child.id)
    assert saved.status == "failed", inspect({saved, Deliveries.steps(child.id)})

    assert Enum.map(Deliveries.steps(child.id), & &1.kind) ==
             ~w(plan timeout_snapshot timeout_check)

    assert length(calls(ctx)) == 2
  end

  @tag timeout: 120_000
  test "Stop during timeout diagnosis starts no replacement implementation", ctx do
    parent = timed_out_delivery(ctx)
    System.put_env("BOSS_DELIVERY_MODE", "autonomy_wait_resolve")
    manager = start_manager(ctx.repo)

    assert {:ok, child} =
             Boss.Deliveries.Retry.start_timeout(
               ctx.project.id,
               parent.id,
               Ecto.UUID.generate(),
               manager
             )

    eventually(fn -> File.exists?(Path.join(ctx.root, "resolver-waiting")) end)
    assert :ok = Deliveries.stop(ctx.project.id, child.id, Boss.DeliveryTestsActive)
    saved = await_retry(ctx, child.id)
    assert saved.status == "cancelled" and saved.cleanup == "group_empty"

    assert Enum.map(Deliveries.steps(child.id), & &1.kind) ==
             ~w(plan timeout_snapshot timeout_check resolve)

    assert Enum.map(Enum.drop(calls(ctx), 2), & &1["kind"]) == ["resolve"]
  end

  @tag timeout: 120_000
  test "retry plan cannot weaken the original accepted criteria before implementation", ctx do
    manager = start_manager(ctx.repo)
    parent = rejected_delivery(ctx, manager)
    System.put_env("BOSS_DELIVERY_MODE", "retry_plan_changed")
    {:ok, retry} = retry(ctx, manager, parent.id)
    saved = await_retry(ctx, retry.id)
    assert saved.status == "failed", inspect(saved)
    assert Enum.map(Deliveries.steps(saved.id), & &1.kind) == ~w(plan)
    assert Enum.map(Enum.drop(calls(ctx), 7), & &1["kind"]) == ~w(plan)
    assert_no_raw(Deliveries.steps(saved.id))
  end

  @tag timeout: 120_000
  test "incomplete retry check output halts before a paid implementation", ctx do
    manager = start_manager(ctx.repo)
    parent = rejected_delivery(ctx, manager)
    System.put_env("BOSS_DELIVERY_MODE", "check_invalid_utf8")
    {:ok, retry} = retry(ctx, manager, parent.id)
    saved = await_retry(ctx, retry.id)
    assert saved.status == "failed", inspect(saved)

    assert Enum.map(Deliveries.steps(saved.id), & &1.kind) ==
             ~w(plan retry_snapshot retry_check)

    assert Enum.map(Enum.drop(calls(ctx), 7), & &1["kind"]) == ~w(plan)
    assert_no_raw(Deliveries.steps(saved.id))
  end

  @tag timeout: 120_000
  test "an explicit retry has at most three implementation cycles", ctx do
    manager = start_manager(ctx.repo)
    parent = rejected_delivery(ctx, manager)
    System.put_env("BOSS_DELIVERY_MODE", "retry_reject_always")
    {:ok, retry} = retry(ctx, manager, parent.id)
    saved = await_retry(ctx, retry.id)
    assert saved.status == "blocked" and saved.cycle == 3
    assert saved.reason =~ "budget"
    retry_calls = Enum.drop(calls(ctx), 7)
    assert Enum.count(retry_calls, &(&1["kind"] == "implement")) == 3
    assert Enum.count(retry_calls, &(&1["kind"] == "review")) == 3
    assert length(Deliveries.steps(saved.id)) == 15
  end

  @tag timeout: 120_000
  test "an unchanged retry rejection starts no second automatic fix", ctx do
    manager = start_manager(ctx.repo)
    parent = rejected_delivery(ctx, manager)
    System.put_env("BOSS_DELIVERY_MODE", "retry_unchanged")
    {:ok, retry} = retry(ctx, manager, parent.id)
    saved = await_retry(ctx, retry.id)
    assert saved.status == "blocked" and saved.cycle == 1
    assert saved.reason =~ "same failure"
    assert length(Deliveries.steps(saved.id)) == 7
    assert Enum.map(Enum.drop(calls(ctx), 7), & &1["kind"]) == ~w(plan implement review)
  end

  test "repeated complete check failure stops on the unchanged tree despite fresh commit IDs",
       ctx do
    System.put_env("BOSS_DELIVERY_MODE", "check_repeated")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "blocked", inspect(saved)
    assert saved.cycle == 2 and saved.reason =~ "same failure"
    assert Enum.count(calls(ctx), &(&1["kind"] == "implement")) == 2
    refute Enum.any?(calls(ctx), &(&1["kind"] == "review"))
  end

  for mode <- ~w(plan_dirty plan_invalid coverage check_invalid_utf8 check_dirty) do
    @mode mode
    test "#{mode} halts without automatic repair", ctx do
      System.put_env("BOSS_DELIVERY_MODE", @mode)
      manager = start_manager(ctx.repo)
      {:ok, run} = start(ctx, manager)
      saved = await_delivery(ctx, run.id)
      assert saved.status == "failed", inspect(saved)

      if @mode in ~w(plan_dirty check_dirty),
        do: assert(saved.reason =~ "files, HEAD or retained ref changed")

      assert length(Enum.filter(calls(ctx), &(&1["kind"] == "implement"))) <= 1
      assert_no_raw(Deliveries.steps(run.id))
    end
  end

  test "planning asks a concrete question before dispatching implementation", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "needs_plan")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "needs_input"
    assert saved.reason =~ "Which feature should this workflow deliver?"
    assert saved.reason =~ "Next:"
    assert Enum.map(calls(ctx), & &1["kind"]) == ["plan"]
    assert Repo.get!(Boss.Tasks.Task, run.task_id).attention_reason == saved.reason
  end

  test "unclear specification requests input without modifying the pinned source", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "needs_spec")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "needs_input", inspect(saved)
    assert saved.reason =~ "Clarify expected output"
    assert saved.reason =~ "adopt the new revision"

    assert Repo.get!(Projects.SpecRevision, saved.spec_revision_id).original_text ==
             "# One\nCreate result.txt"
  end

  test "Stop reaches implementation while the Manager is suspended and starts no later stage",
       ctx do
    System.put_env("BOSS_DELIVERY_MODE", "wait")
    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    eventually(fn -> File.exists?(Path.join(ctx.root, "waiting")) end)
    :sys.suspend(manager)

    try do
      assert :ok = Deliveries.stop(ctx.project.id, run.id, Boss.DeliveryTestsActive)
      eventually(fn -> not Deliveries.active?(Deliveries.get(ctx.project.id, run.id)) end)
    after
      :sys.resume(manager)
    end

    saved = await_delivery(ctx, run.id)
    assert saved.status == "cancelled" and saved.cleanup == "group_empty"
    assert Enum.map(Deliveries.steps(run.id), & &1.kind) == ~w(plan implement)
  end

  test "lost implementation intent prevents the effect and quarantines delivery", ctx do
    Repo.query!(
      "CREATE TRIGGER fixture_stop_implement BEFORE INSERT ON delivery_steps WHEN NEW.kind='implement' BEGIN SELECT RAISE(ABORT, 'fixture'); END"
    )

    manager = start_manager(ctx.repo)
    {:ok, run} = start(ctx, manager)
    saved = await_delivery(ctx, run.id)
    assert saved.status == "interrupted" and saved.cleanup == "unknown"
    assert Enum.map(calls(ctx), & &1["kind"]) == ["plan"]
    assert {:error, :busy} = start(ctx, manager)
  end

  @tag autonomy: true
  test "Repo loss interrupts delivery and replay never respawns the abandoned worker", ctx do
    System.put_env("BOSS_DELIVERY_MODE", "wait")
    manager = start_manager(ctx.repo)
    monitor = Process.monitor(manager)
    command = Ecto.UUID.generate()
    {:ok, run} = start(ctx, manager, command)
    eventually(fn -> File.exists?(Path.join(ctx.root, "waiting")) end)
    pid = ctx.root |> Path.join("waiting") |> File.read!() |> String.to_integer()
    Process.exit(ctx.repo, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^manager, :run_storage_lost}, 3_000

    eventually(fn ->
      case System.cmd("/bin/ps", ["-p", to_string(pid), "-o", "stat="]) do
        {_, 1} -> true
        {status, 0} -> String.contains?(status, "Z")
      end
    end)

    repo = start_repo(ctx.opts)
    Repo.put_dynamic_repo(repo)
    manager = start_manager(repo)
    saved = Deliveries.get(ctx.project.id, run.id)
    assert saved.status == "interrupted" and saved.cleanup == "unknown"
    assert {:ok, ^saved} = start(ctx, manager, command)
    assert {:error, :busy} = start(ctx, manager)
    assert Enum.map(calls(ctx), & &1["kind"]) == ~w(plan implement)
  end

  defp start(ctx, manager, command \\ Ecto.UUID.generate()) do
    cond do
      ctx.routing == 2 ->
        Deliveries.start(ctx.project.id, ctx.task.id, command, "python3 check.py", manager)

      ctx.autonomy ->
        legacy_start(ctx, manager, command, "codex", 1)

      true ->
        legacy_start(ctx, manager, command, "codex")
    end
  end

  defp rejected_delivery(ctx, manager) do
    System.put_env("BOSS_DELIVERY_MODE", "reject_always")
    {:ok, run} = start(ctx, manager)
    saved = await_retry(ctx, run.id)
    assert saved.status == "blocked" and saved.cycle == 3
    saved
  end

  defp timed_out_delivery(ctx) do
    alias Boss.Agents.{ModelCatalog, Workspace}
    alias Boss.Deliveries.{Protocol, Worker}
    System.put_env("BOSS_MODEL_CATALOG", "installed")

    File.write!(
      Path.join(ctx.source, "check.py"),
      "\nif text == 'base' and Path('timeout-only.txt').exists():\n    sys.exit(3)\n",
      [:append]
    )

    assert {:ok, _} = Workspace.git(ctx.source, ["add", "check.py"])
    assert {:ok, _} = Workspace.git(ctx.source, ["commit", "-m", "Check partial timeout work"])

    fixture = Path.join([ctx.root, "bin", "codex"])

    File.write!(
      fixture,
      fixture
      |> File.read!()
      |> String.replace(
        "    while True:\n        time.sleep(0.1)\n\nif kind == \"implement\":",
        "    Path(\"timeout-only.txt\").write_text(\"retained partial work\\n\")\n    while True:\n        time.sleep(0.1)\n\nif kind == \"implement\":"
      )
      |> String.replace(
        "        feedback = data[\"previous_feedback\"]\n        if feedback[\"kind\"] == \"implementation\":",
        "        feedback = data[\"previous_feedback\"]\n        if feedback[\"kind\"] == \"implementation_timeout\":\n            assert feedback[\"implementation_receipt\"][\"outcome\"] == \"timeout\"\n            assert feedback[\"check_receipt\"][\"exit_code\"] == 3\n            assert Path(\"timeout-only.txt\").read_text() == \"retained partial work\\n\"\n        if feedback[\"kind\"] == \"implementation\":"
      )
    )

    assert {:ok, {:new, d}} =
             Deliveries.admit(
               ctx.project.id,
               ctx.task.id,
               Ecto.UUID.generate(),
               "python3 check.py"
             )

    assert {:ok, catalog} = ModelCatalog.discover()
    assert {:ok, d} = Deliveries.set_model_catalog(d.id, catalog)
    assert {:ok, workspace} = Workspace.plan(ctx.project, d.id)
    intent = Map.new(workspace, fn {key, value} -> {to_string(key), value} end)
    assert {:ok, d} = Deliveries.set_intent(d.id, intent)
    pins = %{"spec_revision_id" => d.spec_revision_id, "config_hash" => d.config_hash}

    assert {:ok, plan} =
             Deliveries.begin_step(d.id, "plan", 0, Map.put(pins, "workspace", intent))

    assert {:ok, _} = Workspace.prepare(intent)

    input = %{
      "specification" => "# One\nCreate result.txt",
      "base_commit" => intent["base_commit"],
      "check_config" => d.check_config
    }

    assert {:ok, prompt} = Protocol.prompt(:plan, input)

    receipt =
      Worker.run_agent(
        :plan,
        intent["path"],
        prompt,
        &Protocol.plan/1,
        plan.input["model_profile"]
      )

    assert {:ok, plan} = Deliveries.finish_step(plan.id, Map.put(receipt, "workspace", intent))
    assert plan.status == "finished"
    assert {:ok, workspace} = Workspace.plan(ctx.project, Ecto.UUID.generate())
    workspace = Map.new(workspace, fn {key, value} -> {to_string(key), value} end)

    input =
      Map.merge(pins, %{
        "workspace" => workspace,
        "plan_step_id" => plan.id,
        "parent_step_id" => plan.id
      })

    assert {:ok, implementation} = Deliveries.begin_step(d.id, "implement", 1, input)
    assert {:ok, _} = Workspace.prepare(workspace)

    input = %{
      "specification" => "# One\nCreate result.txt",
      "plan" => plan.receipt["report"],
      "cycle" => 1,
      "base_commit" => workspace["base_commit"],
      "check_config" => d.check_config
    }

    assert {:ok, prompt} = Protocol.prompt(:implement, input)
    System.put_env("BOSS_DELIVERY_MODE", "wait")

    receipt =
      Worker.run_agent(
        :implement,
        workspace["path"],
        prompt,
        nil,
        implementation.input["model_profile"],
        deadline_ms: System.monotonic_time(:millisecond) + 6000
      )

    assert receipt["status"] == "failed" and receipt["outcome"] == "timeout"
    assert receipt["cleanup"] == "group_empty" and receipt["signal"] == 15
    assert receipt["eof"] == %{"stdout" => true, "stderr" => true}

    assert {:ok, _} =
             Deliveries.finish_step(implementation.id, Map.put(receipt, "workspace", workspace))

    assert {:ok, parent} =
             Deliveries.complete(d.id, "failed", "Implementation exceeded its bounded deadline.")

    System.delete_env("BOSS_DELIVERY_MODE")
    parent
  end

  defp retry(ctx, manager, parent, command \\ Ecto.UUID.generate(), remaining \\ 100)
  defp retry(_, _, _, _, 0), do: flunk("Previous fixture worker did not exit")

  defp retry(ctx, manager, parent, command, remaining) do
    case Boss.Deliveries.Retry.start(ctx.project.id, parent, command, manager) do
      {:error, :busy} ->
        Process.sleep(20)
        retry(ctx, manager, parent, command, remaining - 1)

      result ->
        result
    end
  end

  defp start_claude(ctx, manager, command \\ Ecto.UUID.generate()),
    do: legacy_start(ctx, manager, command, "claude")

  # Saved pre-upgrade requests exercise the legacy execution contract unchanged.
  defp legacy_start(ctx, manager, command, reviewer, autonomy \\ 0) do
    case Boss.Deliveries.Queue.admit(
           ctx.project.id,
           ctx.task.id,
           command,
           "python3 check.py",
           reviewer,
           autonomy,
           1
         ) do
      {:ok, request} ->
        # Replaying the saved request through the public entrypoint wakes dispatch.
        assert {:ok, ^request} =
                 Boss.Deliveries.Queue.enqueue(
                   ctx.project.id,
                   ctx.task.id,
                   command,
                   "python3 check.py",
                   reviewer,
                   manager
                 )

        eventually(fn -> Repo.get!(Boss.Deliveries.Request, request.id).delivery_id != nil end)
        request = Repo.get!(Boss.Deliveries.Request, request.id)
        {:ok, Deliveries.get(ctx.project.id, request.delivery_id)}

      error ->
        error
    end
  end

  defp assert_no_raw(steps), do: refute(inspect(steps, limit: :infinity) =~ "SECRET_SENTINEL")

  defp calls(ctx),
    do:
      ctx.root
      |> Path.join("calls")
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

  defp start_repo(opts),
    do: start_supervised!(Supervisor.child_spec({Repo, opts}, restart: :temporary))

  defp start_manager(repo),
    do:
      start_supervised!(
        Supervisor.child_spec(
          {Manager, [name: nil, registry: Boss.DeliveryTestsActive, repo: repo]},
          restart: :temporary
        )
      )

  defp await_delivery(ctx, id) do
    eventually(fn -> not Deliveries.active?(Deliveries.get(ctx.project.id, id)) end)
    Deliveries.get(ctx.project.id, id)
  end

  # Retry fixtures run two complete workflows; bound each owned stage's progress.
  defp await_retry(ctx, id, previous_number \\ 0) do
    eventually(fn ->
      delivery = Deliveries.get(ctx.project.id, id)

      not Deliveries.active?(delivery) or
        Enum.any?(Deliveries.steps(id), &(&1.number > previous_number))
    end)

    delivery = Deliveries.get(ctx.project.id, id)

    if Deliveries.active?(delivery) do
      number = Deliveries.steps(id) |> List.last() |> Map.fetch!(:number)
      assert number in 1..48
      await_retry(ctx, id, number)
    else
      delivery
    end
  end

  defp eventually(predicate, left \\ 1500)
  defp eventually(_, 0), do: flunk("Delivery did not settle within fixture deadline")

  defp eventually(predicate, left) do
    if predicate.(),
      do: :ok,
      else:
        (
          Process.sleep(20)
          eventually(predicate, left - 1)
        )
  end
end
