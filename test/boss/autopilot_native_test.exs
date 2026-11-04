defmodule Boss.AutopilotNativeTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo, Tasks}
  alias Boss.Deliveries.{Autopilot, AutopilotBatch}
  alias Boss.Runs.Manager
  @moduletag skip: :os.type() != {:unix, :darwin}
  @moduletag capture_log: true
  @moduletag timeout: 120_000
  @registry Boss.AutopilotNativeActive
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

  setup context do
    root = Path.join(System.tmp_dir!(), "boss-autopilot-native-#{Ecto.UUID.generate()}")
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

    if context[:timeout_recovery] || context[:network_recovery] do
      File.write!(Path.join(source, "check.py"), ~S"""
      from pathlib import Path
      import sys
      print("CHECK_OUTPUT_FOR_TIMEOUT_REPAIR", flush=True)
      if Path("result.txt").read_text() == "partial\n":
          sys.exit(7)
      """)
    end

    if context[:documentation] || context[:convert_documentation] do
      File.mkdir!(Path.join(source, "docs"))

      File.write!(
        Path.join(source, "docs/product.md"),
        "# Product\nAlready implemented: existing.txt.\n## Work\nWrite one, then two."
      )

      File.write!(
        Path.join(source, "docs/architecture.md"),
        "# Architecture\nresult.txt stores the output."
      )

      File.write!(Path.join(source, "existing.txt"), "implemented")
    end

    if context[:convert_documentation] do
      for name <- ~w(one two three) do
        File.write!(
          Path.join(source, "docs/#{name}.md"),
          "---\nid: #{name}\n---\n# #{name}\nGeneral development instructions."
        )
      end
    end

    for args <- [
          ["init", "-b", "main"],
          ["config", "user.name", "Fixture"],
          ["config", "user.email", "fixture@example.invalid"],
          ["add", "."],
          ["commit", "-m", "base"]
        ],
        do: git(source, args)

    {project, tasks} =
      if context[:documentation] do
        {:ok, project} =
          Projects.create_project(%{
            root_path: source,
            specs_path: "docs",
            intake_mode: "documentation"
          })

        {project, []}
      else
        git(source, ["switch", "-c", "user-work"])

        project =
          Repo.insert!(%Projects.Project{
            name: "Native Autopilot",
            root_path: source,
            git_common_dir: Path.join(source, ".git"),
            specs_path:
              if(context[:convert_documentation], do: Path.join(source, "docs"), else: source),
            base_branch: "main"
          })

        tasks =
          for name <-
                if(context[:continue_on_failure] || context[:convert_documentation],
                  do: ~w(one two three),
                  else: ~w(one two)
                ) do
            {:ok, record} =
              Projects.record_spec(project.id, %{
                relative_path: "#{name}.md",
                explicit_id: name,
                title: name,
                original_text:
                  "---\nid: #{name}\n#{if name == "two" and !context[:independent] and !context[:convert_documentation], do: "depends_on: [one]\n", else: ""}---\n# #{name}\nCreate result.txt"
              })

            record.task
          end

        {project, tasks}
      end

    gates = Path.join(root, "gates")
    bin = Path.join(root, "bin")
    File.mkdir!(gates)
    File.mkdir!(bin)
    File.cp!(Path.expand("../fixtures/codex_autopilot.py", __DIR__), Path.join(bin, "codex"))
    File.chmod!(Path.join(bin, "codex"), 0o700)

    env = %{
      "PATH" => bin <> ":" <> System.fetch_env!("PATH"),
      "BOSS_AUTOPILOT_GATES" => gates,
      "BOSS_DELIVERY_FIXTURE" => root,
      "BOSS_AUTOPILOT_MODE" => "approved"
    }

    previous = Map.take(System.get_env(), Map.keys(env))
    System.put_env(env)

    on_exit(fn ->
      for key <- Map.keys(env) do
        if Map.has_key?(previous, key),
          do: System.put_env(key, previous[key]),
          else: System.delete_env(key)
      end
    end)

    %{
      root: root,
      gates: gates,
      repo: repo,
      opts: opts,
      source: source,
      project: project,
      tasks: tasks
    }
  end

  test "all Backlog tasks integrate sequentially; dependency sees actual Done and retained target",
       c do
    manager = start_manager(c.repo)
    original = git(c.source, ["rev-parse", "HEAD"])
    command = Ecto.UUID.generate()
    ids = Enum.reverse(Enum.map(c.tasks, & &1.id))

    {:ok, batch} =
      Autopilot.start(c.project.id, command, ids, "python3 check.py", "codex", manager)

    one = wait_for_implementation(c, "one", 1)
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1

    assert {:ok, replay} =
             Autopilot.start(c.project.id, command, ids, "python3 check.py", "codex", manager)

    assert replay.id == batch.id
    assert :sys.get_state(manager).active |> map_size() == 1
    release(c, "one", 1)
    two = wait_for_implementation(c, "two", 1)
    [first, second] = c.tasks
    assert Repo.get!(Tasks.Task, first.id).state == "done"
    done = Deliveries.get(c.project.id, one.id)
    assert done.status == "done"
    assert two.intent["base_commit"] == done.integration_intent["candidate_commit"]
    refute two.intent["base_commit"] == original
    release(c, "two", 1)
    eventually(fn -> Repo.get!(AutopilotBatch, batch.id).status == "completed" end, 3000)
    assert Repo.get!(Tasks.Task, second.id).state == "done"
    assert Repo.aggregate(Deliveries.Delivery, :count) == 2

    for d <- Repo.all(Deliveries.Delivery) do
      assert d.cleanup == "group_empty"

      assert Enum.map(Deliveries.steps(d.id), & &1.kind) ==
               ~w(plan implement snapshot check review publish post_check)

      assert d.integration_command_id != nil
    end

    assert git(c.source, ["branch", "--show-current"]) == "user-work"
    assert git(c.source, ["rev-parse", "HEAD"]) == original
    assert git(c.source, ["status", "--porcelain"]) == ""

    assert {:ok, replay} =
             Autopilot.start(c.project.id, command, ids, "python3 check.py", "codex", manager)

    assert replay.status == "completed"
  end

  @tag documentation: true
  test "one Start derives tasks from committed docs and code, then runs both through Done", c do
    alias Boss.Projects.Intake
    assert Projects.list_spec_entries(c.project.id) == []
    assert c.project.base_branch =~ "boss/autopilot/"
    assert git(c.source, ["branch", "--show-current"]) == "main"
    base = git(c.source, ["rev-parse", "HEAD"])
    manager = start_manager(c.repo)
    command = Ecto.UUID.generate()
    {:ok, request} = Intake.start(c.project.id, command, "python3 check.py", "codex", manager)

    eventually(fn -> Intake.latest(c.project.id).status == "finished" end, 3000)
    saved = Intake.latest(c.project.id)
    assert saved.id == request.id
    assert saved.workspace["base_commit"] == base
    assert saved.batch_id

    assert {:ok, replay} =
             Intake.start(c.project.id, command, "python3 check.py", "codex", manager)

    assert replay.id == request.id

    assert {:error, :idempotency_conflict} =
             Intake.start(c.project.id, command, "python3 other.py", "codex", manager)

    entries = Projects.list_spec_entries(c.project.id)
    assert Enum.map(entries, & &1.title) == ["two", "one"]
    assert {:error, _} = Projects.SpecImporter.sync(c.project.id)
    assert Projects.list_spec_entries(c.project.id) == entries
    c = %{c | tasks: Enum.map(entries, &Repo.get!(Tasks.Task, &1.task_id))}
    one = wait_for_implementation(c, "one", 1)
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
    release(c, "one", 1)
    two = wait_for_implementation(c, "two", 1)
    done = Deliveries.get(c.project.id, one.id)
    assert done.status == "done"
    assert two.intent["base_commit"] == done.integration_intent["candidate_commit"]
    release(c, "two", 1)
    eventually(fn -> Repo.get!(AutopilotBatch, saved.batch_id).status == "completed" end, 3000)
    assert Enum.all?(Projects.list_spec_entries(c.project.id), &(&1.state == "done"))
    assert git(c.source, ["rev-parse", "HEAD"]) == base
    assert git(c.source, ["status", "--porcelain"]) == ""

    assert git(c.source, ["rev-parse", c.project.base_branch]) ==
             Deliveries.get(c.project.id, two.id).integration_intent["candidate_commit"]

    assert File.read!(Path.join(c.root, "calls"))
           |> String.split("\n")
           |> Enum.count(&String.contains?(&1, ~s("kind": "intake"))) == 1
  end

  test "Autopilot resolves a planning question with its catalog resolver and publishes both dependencies",
       c do
    System.put_env("BOSS_AUTOPILOT_MODE", "autonomy_plan")
    manager = start_manager(c.repo)
    original = git(c.source, ["rev-parse", "HEAD"])
    ids = Enum.map(c.tasks, & &1.id)

    assert {:ok, batch} =
             Autopilot.start(
               c.project.id,
               Ecto.UUID.generate(),
               ids,
               "python3 check.py",
               "codex",
               manager
             )

    first = wait_for_implementation(c, "one", 1)
    assert first.autonomy_version == 1
    stages = Deliveries.steps(first.id)
    assert Enum.map(stages, & &1.kind) == ~w(plan resolve plan implement)
    resolution = Enum.find(stages, &(&1.kind == "resolve"))
    assert resolution.status == "finished"

    assert resolution.input["model_profile"] == %{
             "model" => "gpt-5.6-terra",
             "reasoning_effort" => "xhigh"
           }

    assert resolution.receipt["report"]["external_action"] == nil

    assert Enum.at(stages, 0).receipt["report"]["acceptance"] ==
             Enum.at(stages, 2).receipt["report"]["acceptance"]

    release(c, "one", 1)
    second = wait_for_implementation(c, "two", 1)
    first = Deliveries.get(c.project.id, first.id)
    assert first.status == "done"
    assert second.intent["base_commit"] == first.integration_intent["candidate_commit"]
    release(c, "two", 1)
    eventually(fn -> Repo.get!(AutopilotBatch, batch.id).status == "completed" end, 3000)

    assert Enum.all?(c.tasks, &(Repo.get!(Tasks.Task, &1.id).state == "done"))

    calls =
      c.root
      |> Path.join("calls")
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

    assert Enum.any?(
             calls,
             &(&1["kind"] == "resolve" && &1["model"] == "gpt-5.6-terra" &&
                 &1["reasoning_effort"] == "xhigh")
           )

    assert Enum.count(calls, &(&1["task"] == "one" && &1["kind"] == "plan")) == 2
    assert git(c.source, ["rev-parse", "HEAD"]) == original
    assert git(c.source, ["status", "--porcelain"]) == ""
  end

  @tag documentation: true
  test "an invalid generated dependency creates neither tasks nor a batch", c do
    alias Boss.Projects.Intake
    System.put_env("BOSS_AUTOPILOT_MODE", "invalid_intake")
    manager = start_manager(c.repo)

    {:ok, _} =
      Intake.start(c.project.id, Ecto.UUID.generate(), "python3 check.py", "codex", manager)

    eventually(fn -> Intake.latest(c.project.id).status == "failed" end)
    assert Projects.list_spec_entries(c.project.id) == []
    assert Repo.aggregate(AutopilotBatch, :count) == 0
    assert Repo.aggregate(Deliveries.Delivery, :count) == 0
  end

  @tag documentation: true, intake_recovery: true
  test "an oversized intake hands off to another model before generated tasks publish", c do
    alias Boss.Projects.Intake
    System.put_env("BOSS_AUTOPILOT_MODE", "intake_repair")
    manager = start_manager(c.repo)
    command = Ecto.UUID.generate()

    assert {:ok, request} =
             Intake.start(c.project.id, command, "python3 check.py", "codex", manager)

    assert request.planning_version == 1
    eventually(fn -> Intake.latest(c.project.id).status == "finished" end, 3000)
    saved = Intake.latest(c.project.id)
    attempts = Intake.attempts(request.id)
    assert length(attempts) == 2
    [rejected, accepted] = attempts
    assert rejected.status == "failed"
    assert rejected.receipt["validation_code"] == "report_too_large"
    assert rejected.receipt["report_bytes"] > 32_768
    assert rejected.receipt["exit_code"] == 0
    assert accepted.previous_attempt_id == rejected.id
    assert accepted.status == "finished"
    assert accepted.receipt["validation_code"] == "valid"
    assert saved.accepted_attempt_id == accepted.id
    entries = Projects.list_spec_entries(c.project.id)
    assert Enum.sort(Enum.map(entries, & &1.title)) == ~w(one two)
    c = %{c | tasks: Enum.map(entries, &Repo.get!(Tasks.Task, &1.task_id))}
    first = wait_for_implementation(c, "one", 1)
    release(c, "one", 1)
    second = wait_for_implementation(c, "two", 1)
    done = Deliveries.get(c.project.id, first.id)
    assert done.status == "done"
    assert second.intent["base_commit"] == done.integration_intent["candidate_commit"]
    release(c, "two", 1)
    eventually(fn -> Repo.get!(AutopilotBatch, saved.batch_id).status == "completed" end, 3000)
    assert Enum.all?(c.tasks, &(Repo.get!(Tasks.Task, &1.id).state == "done"))

    calls =
      File.read!(Path.join(c.root, "calls"))
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    intake_calls = Enum.filter(calls, &(&1["kind"] == "intake"))
    assert Enum.map(intake_calls, & &1["model"]) == ["gpt-5.6-sol", "gpt-5.6-terra"]
    assert intake_calls |> Enum.map(& &1["input_hash"]) |> Enum.uniq() |> length() == 1

    assert {:ok, replay} =
             Intake.start(c.project.id, command, "python3 check.py", "codex", manager)

    assert replay.id == request.id
    assert Intake.attempts(request.id) == attempts
  end

  @tag documentation: true, intake_recovery: true
  test "three invalid intake reports exhaust the saved budget without partial tasks", c do
    alias Boss.Projects.Intake
    System.put_env("BOSS_AUTOPILOT_MODE", "intake_exhausted")
    manager = start_manager(c.repo)
    command = Ecto.UUID.generate()

    assert {:ok, request} =
             Intake.start(c.project.id, command, "python3 check.py", "codex", manager)

    eventually(fn -> Intake.latest(c.project.id).status == "failed" end, 3000)
    attempts = Intake.attempts(request.id)
    assert length(attempts) == 3

    assert Enum.all?(
             attempts,
             &(&1.status == "failed" and &1.receipt["validation_code"] == "report_too_large")
           )

    assert Projects.list_spec_entries(c.project.id) == []
    assert Repo.aggregate(AutopilotBatch, :count) == 0
    assert Repo.aggregate(Deliveries.Delivery, :count) == 0

    assert {:ok, replay} =
             Intake.start(c.project.id, command, "python3 check.py", "codex", manager)

    assert replay.id == request.id and replay.status == "failed"
    assert Intake.attempts(request.id) == attempts

    calls =
      File.read!(Path.join(c.root, "calls"))
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    assert Enum.map(calls, & &1["model"]) == ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-sol"]
  end

  @tag convert_documentation: true
  test "failed instruction imports become history while a fresh dependent plan repairs and publishes",
       c do
    alias Boss.Projects.{Documentation, Intake}
    old_deliveries = fail_instruction_tasks(c.project.id, c.tasks)
    old_tasks = Enum.map(c.tasks, &Repo.get!(Tasks.Task, &1.id))
    old_specs = Repo.all(Projects.Spec)
    old_revisions = Repo.all(Projects.SpecRevision)
    old_events = Repo.all(Tasks.Event)
    base = git(c.source, ["rev-parse", "HEAD"])
    manager = start_manager(c.repo)
    command = Ecto.UUID.generate()
    assert {:ok, receipt} = Documentation.convert(c.project.id, command, manager)
    assert {:ok, ^receipt} = Documentation.convert(c.project.id, command, manager)
    refute File.exists?(Path.join(c.root, "calls"))
    assert {:ok, []} = Autopilot.selection(c.project.id)
    assert Enum.all?(Projects.list_spec_entries(c.project.id), & &1.reference_only)
    assert {:error, _} = Projects.SpecImporter.sync(c.project.id)

    System.put_env("BOSS_AUTOPILOT_MODE", "repair")
    start_command = Ecto.UUID.generate()

    assert {:ok, request} =
             Intake.start(c.project.id, start_command, "python3 check.py", "codex", manager)

    eventually(fn -> Intake.latest(c.project.id).status == "finished" end, 3000)
    saved = Intake.latest(c.project.id)
    assert saved.id == request.id
    assert saved.workspace["base_commit"] == base

    assert {:ok, replay} =
             Intake.start(c.project.id, start_command, "python3 check.py", "codex", manager)

    assert replay.id == request.id
    entries = Projects.list_spec_entries(c.project.id)
    generated = Enum.reject(entries, & &1.reference_only)
    assert Enum.sort(Enum.map(generated, & &1.title)) == ~w(one two)
    assert Enum.count(entries, & &1.reference_only) == 3
    c = %{c | tasks: Enum.map(generated, &Repo.get!(Tasks.Task, &1.task_id))}
    first = wait_for_implementation(c, "one", 1)
    release(c, "one", 1)
    fixed = wait_for_implementation(c, "one", 2)
    assert fixed.id == first.id
    assert fixed.integration_command_id == nil
    implementations = Enum.filter(Deliveries.steps(fixed.id), &(&1.kind == "implement"))

    assert Enum.map(implementations, & &1.input["model_profile"]["model"]) ==
             ["gpt-5.6-sol", "gpt-5.6-terra"]

    release(c, "one", 2)
    second = wait_for_implementation(c, "two", 1)
    done = Deliveries.get(c.project.id, first.id)
    assert done.status == "done"
    assert second.intent["base_commit"] == done.integration_intent["candidate_commit"]
    release(c, "two", 1)
    eventually(fn -> Repo.get!(AutopilotBatch, saved.batch_id).status == "completed" end, 3000)
    assert Enum.all?(c.tasks, &(Repo.get!(Tasks.Task, &1.id).state == "done"))
    assert Enum.map(old_tasks, &Repo.get!(Tasks.Task, &1.id)) == old_tasks
    assert Enum.map(old_specs, &Repo.get!(Projects.Spec, &1.id)) == old_specs
    assert Enum.map(old_revisions, &Repo.get!(Projects.SpecRevision, &1.id)) == old_revisions
    assert Enum.map(old_events, &Repo.get!(Tasks.Event, &1.id)) == old_events
    assert Enum.map(old_deliveries, &Repo.get!(Deliveries.Delivery, &1.id)) == old_deliveries
    assert Repo.aggregate(Deliveries.Delivery, :count) == 5
    assert git(c.source, ["rev-parse", "HEAD"]) == base
    assert git(c.source, ["status", "--porcelain"]) == ""
    assert git(c.source, ["show", "main:result.txt"]) == "two-1"

    for delivery <- [first, second] do
      steps = Deliveries.steps(delivery.id)
      assert Enum.any?(steps, &(&1.kind == "publish" and &1.status == "finished"))
      assert Enum.any?(steps, &(&1.kind == "post_check" and &1.status == "finished"))
    end

    calls =
      File.read!(Path.join(c.root, "calls"))
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    assert Enum.count(calls, &(&1["kind"] == "intake")) == 1
    refute Enum.any?(calls, &(&1["task"] == "three"))
  end

  @tag convert_documentation: true
  test "invalid planning after conversion retains history without partial replacement tasks", c do
    alias Boss.Projects.{Documentation, Intake}
    failures = fail_instruction_tasks(c.project.id, c.tasks)
    old_entries = Projects.list_spec_entries(c.project.id)
    manager = start_manager(c.repo)
    assert {:ok, _} = Documentation.convert(c.project.id, Ecto.UUID.generate(), manager)
    System.put_env("BOSS_AUTOPILOT_MODE", "invalid_intake")

    assert {:ok, _} =
             Intake.start(
               c.project.id,
               Ecto.UUID.generate(),
               "python3 check.py",
               "codex",
               manager
             )

    eventually(fn -> Intake.latest(c.project.id).status == "failed" end)
    entries = Projects.list_spec_entries(c.project.id)

    assert Enum.map(entries, &Map.delete(&1, :reference_only)) ==
             Enum.map(old_entries, &Map.delete(&1, :reference_only))

    assert Enum.all?(entries, & &1.reference_only)
    assert Repo.aggregate(AutopilotBatch, :count) == 0
    assert Enum.map(failures, &Repo.get!(Deliveries.Delivery, &1.id)) == failures
    assert Repo.aggregate(Deliveries.Delivery, :count) == 3
  end

  defp fail_instruction_tasks(project, tasks) do
    for {task, status} <- Enum.zip(tasks, ~w(failed blocked needs_input)) do
      {:ok, {:new, delivery}} =
        Deliveries.admit(project, task.id, Ecto.UUID.generate(), "python3 check.py")

      {:ok, failed} = Deliveries.complete(delivery.id, status, "Historical instruction import")
      failed
    end
  end

  test "review rejection returns to implementation and automatic publication waits for the repaired candidate",
       c do
    System.put_env("BOSS_AUTOPILOT_MODE", "repair")
    manager = start_manager(c.repo)

    {:ok, batch} =
      Autopilot.start(
        c.project.id,
        Ecto.UUID.generate(),
        Enum.map(c.tasks, & &1.id),
        "python3 check.py",
        "codex",
        manager
      )

    one = wait_for_implementation(c, "one", 1)
    release(c, "one", 1)
    fixed = wait_for_implementation(c, "one", 2)
    assert fixed.id == one.id
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
    assert Deliveries.get(c.project.id, one.id).integration_command_id == nil
    release(c, "one", 2)
    wait_for_implementation(c, "two", 1)
    assert Deliveries.get(c.project.id, one.id).status == "done"
    assert Deliveries.get(c.project.id, one.id).cycle == 2
    {:ok, current} = Autopilot.current(c.project.id)
    assert {:ok, _} = Autopilot.cancel(c.project.id, batch.id, current.version, @registry)
    eventually(fn -> :sys.get_state(manager).active == %{} end)
    refute Repo.get!(Tasks.Task, List.last(c.tasks).id).state == "done"
  end

  @tag :independent
  test "a fresh all-Failed batch repairs with another model and publishes without altering old evidence",
       c do
    failures =
      for task <- c.tasks do
        {:ok, {:new, delivery}} =
          Deliveries.admit(c.project.id, task.id, Ecto.UUID.generate(), "python3 check.py")

        {:ok, failed} =
          Deliveries.complete(delivery.id, "failed", "Earlier known-clean task failure")

        failed
      end

    assert Enum.all?(c.tasks, &(Repo.get!(Tasks.Task, &1.id).state == "failed"))
    System.put_env("BOSS_AUTOPILOT_MODE", "repair")
    manager = start_manager(c.repo)
    original = git(c.source, ["rev-parse", "HEAD"])

    {:ok, batch} =
      Autopilot.start(
        c.project.id,
        Ecto.UUID.generate(),
        Enum.map(c.tasks, & &1.id),
        "python3 check.py",
        "codex",
        manager
      )

    assert batch.routing_version == 2
    first = wait_for_implementation(c, "one", 1)
    release(c, "one", 1)
    fixed = wait_for_implementation(c, "one", 2)
    assert fixed.id == first.id
    assert fixed.integration_command_id == nil
    stages = Deliveries.steps(fixed.id)
    attempts = Enum.filter(stages, &(&1.kind == "implement"))
    assert Enum.map(attempts, & &1.cycle) == [1, 2]

    assert Enum.map(attempts, & &1.input["model_profile"]["model"]) == [
             "gpt-5.6-sol",
             "gpt-5.6-terra"
           ]

    assert Enum.any?(stages, &(&1.kind == "resolve" and &1.status == "finished"))

    assert Enum.any?(
             stages,
             &(&1.kind == "review" and &1.receipt["report"]["verdict"] == "changes_requested")
           )

    release(c, "one", 2)
    second = wait_for_implementation(c, "two", 1)
    assert Deliveries.get(c.project.id, first.id).status == "done"
    release(c, "two", 1)
    eventually(fn -> Repo.get!(AutopilotBatch, batch.id).status == "completed" end, 3000)
    assert Enum.all?(c.tasks, &(Repo.get!(Tasks.Task, &1.id).state == "done"))
    assert Enum.map(failures, &Repo.get!(Deliveries.Delivery, &1.id)) == failures

    for delivery <- [first, second] do
      done = Deliveries.get(c.project.id, delivery.id)
      assert done.status == "done"
      steps = Deliveries.steps(done.id)
      assert Enum.any?(steps, &(&1.kind == "publish" and &1.status == "finished"))
      assert Enum.any?(steps, &(&1.kind == "post_check" and &1.status == "finished"))
    end

    assert git(c.source, ["rev-parse", "main"]) ==
             Deliveries.get(c.project.id, second.id).integration_intent["candidate_commit"]

    assert git(c.source, ["rev-parse", "HEAD"]) == original
    assert git(c.source, ["status", "--porcelain"]) == ""
    assert Repo.aggregate(Deliveries.Delivery, :count) == 4
    assert {:ok, []} = Autopilot.selection(c.project.id)
  end

  @tag :continue_on_failure
  test "exhausted planning recovery gates its dependent while independent work reaches Done",
       c do
    git(c.source, ["switch", "main"])
    manager = start_manager(c.repo)
    ids = Enum.map(c.tasks, & &1.id)

    {:ok, batch} =
      Autopilot.start(
        c.project.id,
        Ecto.UUID.generate(),
        ids,
        "python3 check.py",
        "codex",
        manager
      )

    eventually(fn -> Repo.get!(AutopilotBatch, batch.id).status == "blocked" end)
    assert Repo.get!(AutopilotBatch, batch.id).reason =~ "checked out"
    refute File.exists?(Path.join(c.root, "calls"))
    assert Repo.aggregate(Deliveries.Delivery, :count) == 0
    git(c.source, ["switch", "user-work"])
    System.put_env("BOSS_AUTOPILOT_MODE", "invalid_first")

    {:ok, failed} =
      Autopilot.start(
        c.project.id,
        Ecto.UUID.generate(),
        ids,
        "python3 check.py",
        "codex",
        manager
      )

    independent = wait_for_implementation(c, "three", 1)
    [first, dependent, _] = c.tasks
    assert Repo.get!(Tasks.Task, first.id).state == "failed"
    assert Repo.get!(Tasks.Task, dependent.id).state == "new"
    release(c, "three", 1)
    eventually(fn -> Repo.get!(AutopilotBatch, failed.id).status == "blocked" end)

    assert Deliveries.get(c.project.id, independent.id).status == "done"
    assert Repo.get!(Tasks.Task, dependent.id).state == "new"
    assert Repo.aggregate(Deliveries.Delivery, :count) == 2

    calls = Path.join(c.root, "calls") |> File.read!() |> String.split("\n", trim: true)
    decoded = Enum.map(calls, &Jason.decode!/1)
    assert Enum.map(decoded, & &1["task"]) == ~w(one one one one one three three three)

    assert decoded |> Enum.filter(&(&1["task"] == "one")) |> Enum.map(& &1["kind"]) ==
             ~w(plan resolve plan resolve plan)
  end

  @tag timeout_recovery: true
  test "retained native timeout repairs checks and review through another model to exact Done",
       c do
    alias Boss.Deliveries.{Retry, Step}
    {parent, failed} = timeout_source(c)
    old = Deliveries.get(c.project.id, parent.id)
    old_task = Repo.get!(Tasks.Task, parent.task_id)
    assert old.status == "failed" and old.cleanup == "group_empty"
    assert failed.receipt["outcome"] == "timeout"
    assert failed.receipt["signal"] == 15
    assert failed.receipt["eof"] == %{"stdout" => true, "stderr" => true}
    assert File.read!(Path.join(failed.input["workspace"]["path"], "result.txt")) == "partial\n"
    System.put_env("BOSS_AUTOPILOT_MODE", "timeout_repair")
    manager = start_manager(c.repo)
    command = Ecto.UUID.generate()
    {:ok, child} = Retry.start_timeout(c.project.id, parent.id, command, manager)
    first = wait_for_implementation(c, "one", 1)
    assert first.id == child.id
    steps = Deliveries.steps(child.id)
    implementation = List.last(steps)
    assert implementation.input["model_profile"]["model"] == "gpt-5.6-terra"
    assert Enum.any?(steps, &(&1.kind == "timeout_check" and &1.status == "failed"))
    assert Enum.any?(steps, &(&1.kind == "resolve" and &1.status == "finished"))
    assert {:ok, replay} = Retry.start_timeout(c.project.id, parent.id, command, manager)
    assert replay.id == child.id
    assert Repo.get!(Step, failed.id) == failed
    assert Deliveries.get(c.project.id, parent.id) == old
    assert Repo.get!(Tasks.Task, old_task.id).spec_revision_id == old_task.spec_revision_id
    release(c, "one", 1)
    second = wait_for_implementation(c, "one", 2)
    assert second.id == child.id
    assert List.last(Deliveries.steps(child.id)).input["model_profile"]["model"] == "gpt-5.6-sol"
    release(c, "one", 2)
    eventually(fn -> Deliveries.get(c.project.id, child.id).status == "ready_to_merge" end, 3000)
    ready = Deliveries.get(c.project.id, child.id)
    integration = Ecto.UUID.generate()
    {:ok, _} = Deliveries.integrate(c.project.id, child.id, integration, manager)
    eventually(fn -> Deliveries.get(c.project.id, child.id).status == "done" end, 3000)
    done = Deliveries.get(c.project.id, child.id)
    assert Repo.get!(Tasks.Task, parent.task_id).state == "done"
    assert git(c.source, ["rev-parse", "main"]) == done.integration_intent["candidate_commit"]
    assert File.read!(Path.join(failed.input["workspace"]["path"], "result.txt")) == "partial\n"
    assert Deliveries.get(c.project.id, parent.id) == old
    assert ready.intent["base_commit"] == old.intent["base_commit"]
    assert Enum.count(Deliveries.steps(child.id), &(&1.kind == "review")) == 2

    assert Enum.any?(
             Deliveries.steps(child.id),
             &(&1.kind == "post_check" and &1.status == "finished")
           )

    assert {:ok, replay} = Retry.start_timeout(c.project.id, parent.id, command, manager)
    assert replay.id == child.id
  end

  @tag network_recovery: true
  test "explicit checkpoint resumes network-blocked native work through model repair to exact Done",
       c do
    alias Boss.Deliveries.{Retry, Step}
    System.put_env("BOSS_AUTOPILOT_MODE", "network_source")
    manager = start_manager(c.repo)

    {:ok, parent} =
      Deliveries.start(
        c.project.id,
        hd(c.tasks).id,
        Ecto.UUID.generate(),
        "python3 check.py",
        manager
      )

    eventually(fn -> Deliveries.get(c.project.id, parent.id).status == "needs_input" end, 3000)
    parent_steps = Deliveries.steps(parent.id)
    failed = Enum.find(parent_steps, &(&1.kind == "check" and &1.status == "failed"))
    source_implementation = Enum.find(parent_steps, &(&1.kind == "implement"))
    source_workspace = source_implementation.input["workspace"]
    assert failed.receipt["outcome"] == "checks_failed"
    assert failed.receipt["exit_code"] == 7
    assert source_implementation.status == "finished"
    assert Enum.count(parent_steps, &(&1.kind == "resolve")) == 2
    old = Deliveries.get(c.project.id, parent.id)
    old_task = Repo.get!(Tasks.Task, parent.task_id)
    assert old.status == "needs_input" and old.cleanup == "group_empty"
    assert failed.receipt["eof"] == %{"stdout" => true, "stderr" => true}
    assert File.read!(Path.join(source_workspace["path"], "result.txt")) == "partial\n"
    System.put_env("BOSS_AUTOPILOT_MODE", "network_repair")
    command = Ecto.UUID.generate()
    {:ok, child} = Retry.start_checkpoint(c.project.id, parent.id, command, manager)
    assert child.implementation_network_version == 1
    assert child.checkpoint_recovery_version == 1
    assert child.retry_source_check_id == failed.id
    first = wait_for_implementation(c, "one", 1)
    assert first.id == child.id
    steps = Deliveries.steps(child.id)
    implementation = List.last(steps)
    assert implementation.input["model_profile"]["model"] == "gpt-5.6-terra"
    assert implementation.input["network_policy"] == Boss.Agents.NetworkPolicy.profile(1)
    assert Enum.any?(steps, &(&1.kind == "checkpoint_check" and &1.status == "failed"))
    assert Enum.any?(steps, &(&1.kind == "resolve" and &1.status == "finished"))
    assert {:ok, replay} = Retry.start_checkpoint(c.project.id, parent.id, command, manager)
    assert replay.id == child.id
    assert Repo.get!(Step, failed.id).receipt == failed.receipt
    assert Deliveries.get(c.project.id, parent.id) == old
    assert Repo.get!(Tasks.Task, old_task.id).spec_revision_id == old_task.spec_revision_id
    release(c, "one", 1)
    second = wait_for_implementation(c, "one", 2)
    assert second.id == child.id
    assert List.last(Deliveries.steps(child.id)).input["model_profile"]["model"] == "gpt-5.6-sol"
    release(c, "one", 2)
    eventually(fn -> Deliveries.get(c.project.id, child.id).status == "ready_to_merge" end, 3000)
    ready = Deliveries.get(c.project.id, child.id)
    integration = Ecto.UUID.generate()
    {:ok, _} = Deliveries.integrate(c.project.id, child.id, integration, manager)
    eventually(fn -> Deliveries.get(c.project.id, child.id).status == "done" end, 3000)
    done = Deliveries.get(c.project.id, child.id)
    assert Repo.get!(Tasks.Task, parent.task_id).state == "done"
    assert git(c.source, ["rev-parse", "main"]) == done.integration_intent["candidate_commit"]
    assert File.read!(Path.join(source_workspace["path"], "result.txt")) == "partial\n"
    assert Deliveries.get(c.project.id, parent.id) == old
    assert Deliveries.steps(parent.id) == parent_steps
    assert ready.intent["base_commit"] == old.intent["base_commit"]
    assert Enum.count(Deliveries.steps(child.id), &(&1.kind == "review")) == 2

    assert Enum.any?(
             Deliveries.steps(child.id),
             &(&1.kind == "post_check" and &1.status == "finished")
           )

    assert {:ok, replay} = Retry.start_checkpoint(c.project.id, parent.id, command, manager)
    assert replay.id == child.id
  end

  defp timeout_source(c) do
    alias Boss.Agents.{ModelCatalog, Workspace}
    alias Boss.Deliveries.{Protocol, Worker}
    task = hd(c.tasks)

    {:ok, {:new, delivery}} =
      Deliveries.admit(
        c.project.id,
        task.id,
        Ecto.UUID.generate(),
        "python3 check.py",
        "codex",
        false,
        1,
        2
      )

    {:ok, catalog} = ModelCatalog.discover()
    {:ok, delivery} = Deliveries.set_model_catalog(delivery.id, catalog)
    {:ok, workspace} = Workspace.plan(c.project, delivery.id)
    intent = Map.new(workspace, fn {k, v} -> {Atom.to_string(k), v} end)
    {:ok, _} = Workspace.prepare(intent)
    {:ok, delivery} = Deliveries.set_intent(delivery.id, intent)
    source = "# one\nCreate result.txt"

    input = %{
      "specification" => source,
      "base_commit" => intent["base_commit"],
      "check_config" => delivery.check_config
    }

    {:ok, prompt} = Protocol.prompt(:plan, input)

    {:ok, plan} =
      Deliveries.begin_step(delivery.id, "plan", 0, %{
        "workspace" => intent,
        "spec_revision_id" => delivery.spec_revision_id,
        "config_hash" => delivery.config_hash,
        "input_hash" => Protocol.digest(input)
      })

    receipt =
      Worker.run_agent(
        :plan,
        intent["path"],
        prompt,
        &Protocol.plan/1,
        plan.input["model_profile"]
      )

    {:ok, plan} = Deliveries.finish_step(plan.id, Map.put(receipt, "workspace", intent))
    {:ok, workspace} = Workspace.plan(c.project, Ecto.UUID.generate())
    intent = Map.new(workspace, fn {k, v} -> {Atom.to_string(k), v} end)
    {:ok, _} = Workspace.prepare(intent)

    input = %{
      "specification" => source,
      "plan" => plan.receipt["report"],
      "cycle" => 1,
      "base_commit" => intent["base_commit"],
      "check_config" => delivery.check_config,
      "previous_feedback" => nil
    }

    {:ok, prompt} = Protocol.prompt(:implement, input)

    {:ok, step} =
      Deliveries.begin_step(delivery.id, "implement", 1, %{
        "workspace" => intent,
        "spec_revision_id" => delivery.spec_revision_id,
        "config_hash" => delivery.config_hash,
        "plan_step_id" => plan.id,
        "parent_step_id" => plan.id,
        "resolution_step_id" => nil,
        "source_step_id" => nil,
        "feedback_hash" => Protocol.digest(nil),
        "input_hash" => Protocol.digest(input)
      })

    System.put_env("BOSS_AUTOPILOT_MODE", "timeout_source")

    receipt =
      Worker.run_agent(:implement, intent["path"], prompt, nil, step.input["model_profile"],
        deadline_ms: System.monotonic_time(:millisecond) + 6000
      )

    {:ok, failed} = Deliveries.finish_step(step.id, Map.put(receipt, "workspace", intent))
    {:ok, delivery} = Deliveries.complete(delivery.id, "failed", "Implementation timed out.")
    {delivery, Repo.get!(Boss.Deliveries.Step, failed.id)}
  end

  defp wait_for_implementation(c, name, cycle) do
    eventually(fn -> File.exists?(Path.join(c.gates, "#{name}-#{cycle}.waiting")) end, 3000)
    task = Enum.find(c.tasks, &(&1.title == name))
    import Ecto.Query

    Repo.one!(
      from d in Deliveries.Delivery, where: d.task_id == ^task.id and d.status == "implementing"
    )
  end

  defp release(c, name, cycle),
    do: File.write!(Path.join(c.gates, "#{name}-#{cycle}.release"), "")

  defp start_repo(opts),
    do: start_supervised!(Supervisor.child_spec({Repo, opts}, restart: :temporary))

  defp start_manager(repo),
    do:
      start_supervised!(
        Supervisor.child_spec({Manager, [name: nil, registry: @registry, repo: repo]},
          restart: :temporary
        )
      )

  defp git(path, args) do
    {output, status} =
      System.cmd("git", args,
        cd: path,
        stderr_to_stdout: true,
        env: [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"}]
      )

    assert status == 0, inspect({args, output})
    String.trim(output)
  end

  defp eventually(predicate, left \\ 1500)
  defp eventually(_, 0), do: flunk("Autopilot did not settle within fixture deadline")

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
