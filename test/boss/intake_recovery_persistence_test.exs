defmodule Boss.IntakeRecoveryPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Repo, Projects}
  alias Boss.Projects.Intake
  alias Boss.Projects.Intake.{Attempts, Request}
  @moduletag capture_log: true
  @base String.duplicate("a", 40)
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
    root = Path.join(System.tmp_dir!(), "boss-intake-storage-#{Ecto.UUID.generate()}")
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
    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)

    project =
      Repo.insert!(%Projects.Project{
        name: "Docs",
        root_path: root,
        git_common_dir: root <> "/.git",
        specs_path: root <> "/docs",
        base_branch: "main",
        intake_mode: "documentation"
      })

    %{project: project, repo: repo, opts: opts}
  end

  test "new admission pins planning version while historical UUID replay retains one attempt policy",
       c do
    old = legacy(c)

    assert {:ok, {:existing, ^old}} =
             Intake.admit(c.project.id, old.command_id, "true", "codex", true)

    assert old.planning_version == 0
    assert {:error, :legacy_planning} = Intake.begin_attempt(old.id)

    assert {:error, _} =
             Repo.query("UPDATE project_intakes SET planning_version=1 WHERE id=?", [old.id])

    {:ok, _} = Intake.interrupt(old.id)
    assert Repo.get!(Request, old.id).planning_version == 0
    assert Intake.attempts(old.id) == []
  end

  test "attempt intent pins catalog model and exact source before effects", c do
    r = request(c)
    assert r.planning_version == 1 and r.accepted_attempt_id == nil
    assert {:ok, a} = Intake.begin_attempt(r.id)
    assert a.number == 1 and a.status == "running" and a.receipt == %{}
    assert a.source_base == @base and a.previous_attempt_id == nil
    assert a.model_profile == @catalog["primary"]
    assert {:error, :attempt_running} = Intake.begin_attempt(r.id)
    assert {:error, _} = raw_attempt(r, 2, a.id, @catalog["resolver"])
    restart(c)
    assert Intake.attempts(r.id) == [a]

    assert {:ok, {:existing, saved}} =
             Intake.admit(c.project.id, r.command_id, "true", "codex", true)

    assert saved.id == r.id
  end

  test "clean validation failures alternate strong models and stop at three attempts", c do
    r = request(c)
    assert {:ok, a} = Intake.begin_attempt(r.id)
    {:ok, a} = Intake.finish_attempt(a.id, receipt())
    assert {:ok, b} = Intake.begin_attempt(r.id)

    assert b.number == 2 and b.previous_attempt_id == a.id and
             b.model_profile == @catalog["resolver"]

    {:ok, b} = Intake.finish_attempt(b.id, receipt())
    assert {:ok, last} = Intake.begin_attempt(r.id)

    assert last.number == 3 and last.previous_attempt_id == b.id and
             last.model_profile == hd(@catalog["fallbacks"])

    {:ok, _} = Intake.finish_attempt(last.id, receipt())
    assert {:error, :planning_attempts_exhausted} = Intake.begin_attempt(r.id)
    assert {:error, _} = raw_attempt(r, 4, last.id, @catalog["resolver"])
  end

  test "typed unavailable evidence excludes a model but generic task failure does not", c do
    r = request(c)
    {:ok, a} = Intake.begin_attempt(r.id)

    unavailable =
      receipt(%{
        "outcome" => "exited",
        "exit_code" => 0,
        "error_class" => "model_unavailable",
        "validation_code" => nil,
        "report_bytes" => nil
      })

    {:ok, _} = Intake.finish_attempt(a.id, unavailable)
    {:ok, b} = Intake.begin_attempt(r.id)
    assert b.model_profile == @catalog["resolver"]
    {:ok, _} = Intake.finish_attempt(b.id, receipt())
    assert {:error, :models_exhausted} = Intake.begin_attempt(r.id)
    assert {:error, _} = raw_attempt(r, 3, b.id, hd(@catalog["fallbacks"]))
  end

  test "shared provider failures never authorize another model", c do
    r = request(c)
    {:ok, a} = Intake.begin_attempt(r.id)

    for error <- ~w(auth rate_limit schema transport) do
      failed =
        receipt(%{
          "outcome" => "exited",
          "exit_code" => 1,
          "error_class" => error,
          "validation_code" => nil,
          "report_bytes" => nil
        })

      assert Attempts.valid_receipt?(failed)
      refute Attempts.recoverable?(%{a | status: "failed", receipt: failed})
    end

    {:ok, _} =
      Intake.finish_attempt(
        a.id,
        receipt(%{
          "outcome" => "exited",
          "exit_code" => 1,
          "error_class" => "auth",
          "validation_code" => nil,
          "report_bytes" => nil
        })
      )

    assert {:error, :attempt_not_recoverable} = Intake.begin_attempt(r.id)
    assert {:error, _} = raw_attempt(r, 2, a.id, @catalog["resolver"])
  end

  test "Stop preserves terminal transport receipt but bars retry and success", c do
    r = request(c)
    {:ok, a} = Intake.begin_attempt(r.id)
    Repo.update!(Ecto.Changeset.change(r, stop_requested: true))
    success = success([])
    assert {:ok, _} = Intake.finish_attempt(a.id, success)
    assert {:error, :cancelled} = Intake.begin_attempt(r.id)

    assert {:error, _} =
             Repo.query(
               "UPDATE project_intakes SET status='finished',cleanup='group_empty',accepted_attempt_id=? WHERE id=?",
               [a.id, r.id]
             )

    refute Intake.batch_allowed?(
             r.id,
             r.project_id,
             r.command_id,
             r.check_config,
             r.config_hash,
             r.reviewer
           )
  end

  test "restart quarantines unfinished attempt before releasing no execution slot", c do
    r = request(c)
    {:ok, a} = Intake.begin_attempt(r.id)
    restart(c)
    assert {:ok, [_]} = Intake.reconcile()
    assert %{status: "interrupted", cleanup: "unknown"} = Repo.get!(Request, r.id)

    assert [%{id: id, status: "interrupted", receipt: %{"cleanup" => "unknown"}}] =
             Intake.attempts(r.id)

    assert id == a.id
    assert Intake.quarantined?()
    assert {:error, :invalid_intent} = Intake.begin_attempt(r.id)

    assert {:error, _} =
             Repo.query(
               "UPDATE project_intakes SET status='failed',cleanup='group_empty' WHERE id=?",
               [r.id]
             )
  end

  test "unknown cleanup is persisted but cannot produce success or another attempt", c do
    r = request(c)
    {:ok, a} = Intake.begin_attempt(r.id)

    unknown =
      receipt(%{
        "status" => "interrupted",
        "cleanup" => "unknown",
        "outcome" => "failed",
        "exit_kind" => nil,
        "exit_code" => nil,
        "eof" => %{"stdout" => false, "stderr" => false},
        "report_bytes" => nil,
        "validation_code" => nil
      })

    assert {:ok, _} = Intake.finish_attempt(a.id, unknown)
    assert {:error, :attempt_not_recoverable} = Intake.begin_attempt(r.id)

    assert {:error, _} =
             Repo.query(
               "UPDATE project_intakes SET status='failed',cleanup='group_empty' WHERE id=?",
               [r.id]
             )

    assert {:ok, _} = Intake.interrupt(r.id)
    assert Intake.quarantined?()
  end

  test "receipts contain only fixed bounded metadata and cannot be rewritten", c do
    r = request(c)
    {:ok, a} = Intake.begin_attempt(r.id)

    for bad <- [
          Map.put(receipt(), "raw", "secret"),
          Map.put(receipt(), "usage", %{"private" => "secret"}),
          Map.put(receipt(), "validation_code", "arbitrary provider text"),
          Map.put(receipt(), "report_bytes", -1),
          Map.put(receipt(), "eof", %{"stdout" => 1, "stderr" => true}),
          Map.put(receipt(), "plan_hash", String.duplicate("a", 64))
        ] do
      assert {:error, :invalid_receipt} = Intake.finish_attempt(a.id, bad)

      assert {:error, _} =
               Repo.query(
                 "UPDATE project_intake_attempts SET status='failed',receipt=? WHERE id=?",
                 [JSON.encode!(bad), a.id]
               )
    end

    {:ok, saved} = Intake.finish_attempt(a.id, receipt())
    assert {:ok, ^saved} = Intake.finish_attempt(a.id, receipt())

    assert {:error, :immutable_receipt} =
             Intake.finish_attempt(a.id, receipt(%{"exit_code" => 1}))

    assert {:error, _} =
             Repo.query("UPDATE project_intake_attempts SET receipt='{}' WHERE id=?", [a.id])

    assert {:error, _} = Repo.query("DELETE FROM project_intake_attempts WHERE id=?", [a.id])
  end

  test "SQL cannot forge source, predecessor, model, successful cleanup or initial terminal attempt",
       c do
    r = request(c)
    assert {:error, _} = raw_attempt(r, 1, nil, @catalog["resolver"])
    assert {:error, _} = raw_attempt(r, 1, nil, @catalog["primary"], String.duplicate("b", 40))
    {:ok, a} = Intake.begin_attempt(r.id)
    {:ok, _} = Intake.finish_attempt(a.id, receipt())
    assert {:error, _} = raw_attempt(r, 2, Ecto.UUID.generate(), @catalog["resolver"])
    assert {:error, _} = raw_attempt(r, 2, a.id, @catalog["primary"])
    {:ok, b} = Intake.begin_attempt(r.id)

    for {key, value} <- [
          {"cleanup", "unknown"},
          {"exit_code", 7},
          {"eof", %{"stdout" => true, "stderr" => false}},
          {"plan_hash", nil},
          {"validation_code", "invalid_shape"}
        ] do
      bad = Map.put(success([]), key, value)
      assert {:error, :invalid_receipt} = Intake.finish_attempt(b.id, bad)

      assert {:error, _} =
               Repo.query(
                 "UPDATE project_intake_attempts SET status='finished',receipt=? WHERE id=?",
                 [JSON.encode!(bad), b.id]
               )
    end

    assert {:error, _} =
             Repo.query("UPDATE project_intake_attempts SET source_base=? WHERE id=?", [
               String.duplicate("b", 40),
               b.id
             ])
  end

  test "success binds exact transient tasks and latest attempt before final request handoff", c do
    r = request(c)
    tasks = [%{"id" => "one", "acceptance" => ["Exact"]}]
    {:ok, a} = Intake.begin_attempt(r.id)
    {:ok, _} = Intake.finish_attempt(a.id, success(tasks))

    assert {:ok, id} =
             Repo.transaction(fn -> Attempts.verified!(Repo.get!(Request, r.id), tasks) end)

    assert id == a.id

    assert {:error, :invalid_plan_evidence} =
             Repo.transaction(fn ->
               Attempts.verified!(Repo.get!(Request, r.id), [%{"id" => "different"}])
             end)

    assert Intake.batch_allowed?(
             r.id,
             r.project_id,
             r.command_id,
             r.check_config,
             r.config_hash,
             r.reviewer
           )

    assert {:error, _} =
             Repo.query(
               "UPDATE project_intakes SET status='finished',cleanup='group_empty' WHERE id=?",
               [r.id]
             )

    assert {:ok, _} =
             Repo.query(
               "UPDATE project_intakes SET status='finished',cleanup='group_empty',accepted_attempt_id=? WHERE id=?",
               [a.id, r.id]
             )

    assert Repo.get!(Request, r.id).accepted_attempt_id == a.id
    assert {:error, :invalid_intent} = Intake.begin_attempt(r.id)
  end

  test "concurrent begin attempts save one producer and no duplicate dispatch intent", c do
    r = request(c)

    result =
      for _ <- 1..2 do
        Task.async(fn ->
          Repo.put_dynamic_repo(c.repo)
          Intake.begin_attempt(r.id)
        end)
      end
      |> Task.await_many(2_000)

    assert Enum.count(result, &match?({:ok, _}, &1)) == 1
    assert Enum.count(result, &(&1 == {:error, :attempt_running})) == 1
    assert length(Intake.attempts(r.id)) == 1
  end

  test "attempt notifications follow commit and exact receipt replay stays silent", c do
    r = request(c)
    Phoenix.PubSub.subscribe(Boss.PubSub, Intake.topic(c.project.id))
    {:ok, a} = Intake.begin_attempt(r.id)
    assert_receive {:project_intake, _}, 2_000
    {:ok, saved} = Intake.finish_attempt(a.id, receipt())
    assert_receive {:project_intake, _}, 2_000
    assert {:ok, ^saved} = Intake.finish_attempt(a.id, receipt())
    refute_receive {:project_intake, _}, 50
  end

  test "empty recovery migration roundtrips but pinned policy refuses downgrade", c do
    assert :ok =
             Ecto.Migrator.down(
               Repo,
               20_261_106_150_000,
               Boss.Repo.Migrations.AddCheckpointRecovery,
               log: false
             )

    assert :ok =
             Ecto.Migrator.down(
               Repo,
               20_261_106_140_000,
               Boss.Repo.Migrations.AddExecutionRecovery,
               log: false
             )

    assert :ok =
             Ecto.Migrator.down(Repo, 20_261_106_130_000, Boss.Repo.Migrations.AddIntakeRecovery,
               log: false
             )

    assert :ok =
             Ecto.Migrator.up(Repo, 20_261_106_130_000, Boss.Repo.Migrations.AddIntakeRecovery,
               log: false
             )

    assert :ok =
             Ecto.Migrator.up(Repo, 20_261_106_140_000, Boss.Repo.Migrations.AddExecutionRecovery,
               log: false
             )

    request(c)

    assert :ok =
             Ecto.Migrator.down(
               Repo,
               20_261_106_150_000,
               Boss.Repo.Migrations.AddCheckpointRecovery,
               log: false
             )

    assert :ok =
             Ecto.Migrator.down(
               Repo,
               20_261_106_140_000,
               Boss.Repo.Migrations.AddExecutionRecovery,
               log: false
             )

    assert_raise RuntimeError, ~r/Refusing to discard intake recovery/, fn ->
      Ecto.Migrator.down(Repo, 20_261_106_130_000, Boss.Repo.Migrations.AddIntakeRecovery,
        log: false
      )
    end
  end

  test "report ownership uncertainty and timeout do not qualify as recoverable validation failures",
       c do
    r = request(c)
    {:ok, a} = Intake.begin_attempt(r.id)

    for code <- ~w(report_unavailable report_replaced) do
      refute Attempts.recoverable?(%{
               a
               | status: "failed",
                 receipt: receipt(%{"validation_code" => code})
             })
    end

    {:ok, _} =
      Intake.finish_attempt(a.id, receipt(%{"outcome" => "timeout", "validation_code" => nil}))

    assert {:error, :attempt_not_recoverable} = Intake.begin_attempt(r.id)
    assert {:error, _} = raw_attempt(r, 2, a.id, @catalog["resolver"])
  end

  test "two distinct generic startup failures stop before a third paid attempt", c do
    r = request(c)
    {:ok, a} = Intake.begin_attempt(r.id)

    startup =
      receipt(%{
        "outcome" => "exited",
        "exit_code" => 0,
        "error_class" => "unknown",
        "validation_code" => nil,
        "report_bytes" => nil
      })

    {:ok, _} = Intake.finish_attempt(a.id, startup)
    {:ok, b} = Intake.begin_attempt(r.id)
    {:ok, _} = Intake.finish_attempt(b.id, Map.put(startup, "exit_code", 7))
    assert {:error, :provider_startup} = Intake.begin_attempt(r.id)
    assert {:error, _} = raw_attempt(r, 3, b.id, hd(@catalog["fallbacks"]))
  end

  test "legacy planning cannot acquire another request's acceptance lineage", c do
    r = request(c)
    {:ok, attempt} = Intake.begin_attempt(r.id)
    {:ok, _} = Intake.finish_attempt(attempt.id, success([]))

    Repo.query!(
      "UPDATE project_intakes SET status='finished',cleanup='group_empty',accepted_attempt_id=? WHERE id=?",
      [attempt.id, r.id]
    )

    old = legacy(c)

    assert {:error, _} =
             Repo.query("UPDATE project_intakes SET accepted_attempt_id=? WHERE id=?", [
               attempt.id,
               old.id
             ])

    assert Repo.get!(Request, old.id) == old
    assert old.planning_version == 0 and old.accepted_attempt_id == nil
    assert Intake.attempts(old.id) == []

    assert {:ok, {:existing, ^old}} =
             Intake.admit(c.project.id, old.command_id, "true", "codex", true)
  end

  defp request(c) do
    {:ok, {:new, r}} = Intake.admit(c.project.id, Ecto.UUID.generate(), "true", "codex", false)
    {:ok, r} = Intake.set_model_catalog(r.id, @catalog)

    workspace = %{
      "project_id" => to_string(c.project.id),
      "run_id" => r.id,
      "repo_path" => c.project.root_path,
      "git_common_dir" => c.project.git_common_dir,
      "base_branch" => "main",
      "base_commit" => @base,
      "path" => c.project.root_path <> "/work",
      "branch" => "boss/" <> r.id
    }

    :ok = Intake.pin(r.id, workspace)
    Repo.get!(Request, r.id)
  end

  defp legacy(c) do
    {:ok, config, hash} = Boss.Checks.Command.parse("true")

    Repo.insert!(%Request{
      id: Ecto.UUID.generate(),
      project_id: c.project.id,
      command_id: Ecto.UUID.generate(),
      check_text: "true",
      check_config: config,
      config_hash: hash,
      reviewer: "codex"
    })
  end

  defp receipt(changes \\ %{}),
    do:
      Map.merge(
        %{
          "status" => "failed",
          "cleanup" => "group_empty",
          "outcome" => "invalid_report",
          "exit_kind" => "exit",
          "exit_code" => 0,
          "signal" => nil,
          "eof" => %{"stdout" => true, "stderr" => true},
          "usage" => %{"input_tokens" => 12},
          "error_class" => nil,
          "report_bytes" => 200,
          "validation_code" => "invalid_dependencies",
          "plan_hash" => nil
        },
        changes
      )

  defp success(tasks),
    do:
      receipt(%{
        "status" => "finished",
        "outcome" => "exited",
        "validation_code" => "valid",
        "plan_hash" => Intake.plan_hash(tasks)
      })

  defp raw_attempt(r, n, previous, profile, base \\ @base),
    do:
      Repo.query(
        "INSERT INTO project_intake_attempts(id,request_id,number,previous_attempt_id,source_base,model_profile,status,receipt,inserted_at,updated_at) VALUES(?,?,?,?,?,?,'running','{}',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",
        [Ecto.UUID.generate(), r.id, n, previous, base, JSON.encode!(profile)]
      )

  defp restart(c) do
    stop_supervised!(Repo)
    Repo.put_dynamic_repo(start_supervised!({Repo, c.opts}))
  end
end
