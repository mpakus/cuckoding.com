defmodule Boss.DocumentationConversionTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo, Runs, Tasks}
  alias Boss.Projects.{Documentation, Intake}
  alias Boss.Deliveries.Queue
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
    {20_261_106_140_000, Boss.Repo.Migrations.AddExecutionRecovery},
    {20_261_106_150_000, Boss.Repo.Migrations.AddCheckpointRecovery},
    {20_261_106_160_000, Boss.Repo.Migrations.AddProviderRecovery}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-documentation-#{Ecto.UUID.generate()}")
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
        name: "Documents",
        root_path: root,
        git_common_dir: Path.join(root, ".git"),
        specs_path: root,
        base_branch: "main"
      })

    {:ok, %{task: task, spec: spec}} =
      Projects.record_spec(project.id, %{
        relative_path: "AGENTS.md",
        explicit_id: "one",
        title: "Instructions",
        original_text: "# Instructions"
      })

    %{project: project, task: task, spec: spec, repo: repo, opts: opts}
  end

  test "conversion preserves complete historical rows, task pins and missing flags across restart",
       c do
    {:ok, %{revision: latest}} =
      Projects.record_spec(c.project.id, %{
        relative_path: "AGENTS.md",
        explicit_id: "one",
        title: "New source",
        original_text: "# Revised instructions"
      })

    {:ok, {:new, d}} = Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true")
    assert {:ok, _} = Deliveries.complete(d.id, "failed", "Historical failure")
    Repo.update!(Ecto.Changeset.change(c.spec, missing: true))
    before = history()
    command = Ecto.UUID.generate()
    assert {:ok, saved} = Documentation.admit(c.project.id, command, false)
    assert saved.source_count == 1
    assert history() == before

    assert Map.take(Projects.get_project!(c.project.id), [
             :root_path,
             :git_common_dir,
             :specs_path,
             :base_branch
           ]) == Map.take(c.project, [:root_path, :git_common_dir, :specs_path, :base_branch])

    assert Projects.get_project!(c.project.id).intake_mode == "documentation"

    assert [[c.task.spec_revision_id, latest.id, 2, "failed", 1]] ==
             Repo.query!(
               "SELECT spec_revision_id,latest_revision_id,state_version,state,missing FROM project_documentation_sources"
             ).rows

    assert [%{reference_only: true, missing: true}] = Projects.list_spec_entries(c.project.id)

    assert {:ok, %{reference_only: true, task: task, adoption: %{available?: false}}} =
             Tasks.get_details(c.project.id, c.task.id, latest.number)

    assert task.spec_revision_id == c.task.spec_revision_id
    stop_supervised!(Repo)
    Repo.put_dynamic_repo(start_supervised!({Repo, c.opts}))
    assert Documentation.get(c.project.id, command) == saved
    assert {:ok, ^saved} = Documentation.admit(c.project.id, command, true)

    assert {:error, :already_documentation} =
             Documentation.admit(c.project.id, Ecto.UUID.generate(), false)

    assert history() == before
  end

  test "new task effects refuse references while historical delivery, request and run UUIDs replay",
       c do
    run_command = Ecto.UUID.generate()
    {:ok, {:new, run}} = Runs.admit(c.project.id, c.task.id, run_command)
    {:ok, run} = Runs.update(run.id, status: "failed", cleanup: "group_empty")
    queue_command = Ecto.UUID.generate()
    {:ok, request} = Queue.admit(c.project.id, c.task.id, queue_command, "true", "codex")
    {:ok, request} = Queue.cancel(c.project.id, request.id)
    delivery_command = Ecto.UUID.generate()
    {:ok, {:new, d}} = Deliveries.admit(c.project.id, c.task.id, delivery_command, "true")
    {:ok, d} = Deliveries.complete(d.id, "failed")
    {:ok, _} = Documentation.admit(c.project.id, Ecto.UUID.generate(), false)
    assert {:ok, {:existing, ^run}} = Runs.admit(c.project.id, c.task.id, run_command)
    assert {:ok, ^request} = Queue.admit(c.project.id, c.task.id, queue_command, "true", "codex")

    assert {:ok, {:existing, ^d}} =
             Deliveries.admit(c.project.id, c.task.id, delivery_command, "true")

    assert {:error, :reference_only} = Runs.admit(c.project.id, c.task.id, Ecto.UUID.generate())

    assert {:error, :reference_only} =
             Runs.admit_check(c.project.id, run.id, Ecto.UUID.generate(), "true")

    assert {:error, :reference_only} =
             Runs.admit_review(c.project.id, run.id, Ecto.UUID.generate())

    assert {:error, :reference_only} =
             Queue.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true", "codex")

    assert {:error, :reference_only} =
             Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true")

    assert {:error, :reference_only} =
             Deliveries.admit_retry(c.project.id, d.id, Ecto.UUID.generate())

    assert {:error, :reference_only} =
             Deliveries.admit_integration(c.project.id, d.id, Ecto.UUID.generate())

    assert {:error, :reference_only} =
             Tasks.transition(c.task.id, %{
               command_id: "new",
               expected_version: 2,
               action: "cancel",
               reason: "Do not change source history"
             })

    assert [] == Queue.autopilot_candidates(c.project.id, 1)
    assert [] == Queue.autopilot_candidates(c.project.id, 2)
  end

  test "forged SQL cannot add execution, mutate membership or rewrite source history", c do
    {:ok, _} = Documentation.admit(c.project.id, Ecto.UUID.generate(), false)

    for sql <- [
          "UPDATE project_documentation_conversions SET source_count=0",
          "DELETE FROM project_documentation_conversions",
          "UPDATE project_documentation_sources SET state_version=99",
          "DELETE FROM project_documentation_sources",
          "UPDATE projects SET intake_mode='specs'",
          "UPDATE projects SET base_branch='other'",
          "UPDATE tasks SET state='failed'",
          "UPDATE specs SET missing=1",
          "INSERT INTO project_documentation_sources SELECT * FROM project_documentation_sources",
          "INSERT INTO spec_revisions (spec_id,number,relative_path,content_hash,original_text,inserted_at) SELECT spec_id,number+1,relative_path,content_hash,original_text,inserted_at FROM spec_revisions"
        ],
        do: assert({:error, _} = Repo.query(sql))

    for table <- ["deliveries", "delivery_requests", "agent_runs"] do
      assert {:error, %Exqlite.Error{message: message}} =
               Repo.query("INSERT INTO #{table}(id,project_id,task_id) VALUES (?,?,?)", [
                 Ecto.UUID.generate(),
                 c.project.id,
                 c.task.id
               ])

      assert message =~ "documentation references"
    end
  end

  test "conversion refuses live ownership, pending requests, active and unknown runs", c do
    command = Ecto.UUID.generate()
    assert {:error, :busy} = Documentation.admit(c.project.id, command, true)
    {:ok, queued} = Queue.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true", "codex")
    assert {:error, :busy} = Documentation.admit(c.project.id, command, false)
    assert {:ok, _} = Queue.pause()
    assert {:error, :busy} = Documentation.admit(c.project.id, command, false)
    {:ok, _} = Queue.cancel(c.project.id, queued.id)
    {:ok, {:new, run}} = Runs.admit(c.project.id, c.task.id, Ecto.UUID.generate())
    assert {:error, :busy} = Documentation.admit(c.project.id, command, false)
    {:ok, _} = Runs.update(run.id, status: "interrupted", cleanup: "unknown")
    assert {:error, :busy} = Documentation.admit(c.project.id, command, false)
    assert Documentation.latest(c.project.id) == nil
    assert Projects.get_project!(c.project.id).intake_mode == "specs"
  end

  test "conversion refuses active delivery and does not reinterpret its saved receipt", c do
    {:ok, {:new, d}} = Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true")
    before = history()
    assert {:error, :busy} = Documentation.admit(c.project.id, Ecto.UUID.generate(), false)
    assert history() == before
    assert {:ok, _} = Deliveries.complete(d.id, "failed")
    assert {:ok, _} = Documentation.admit(c.project.id, Ecto.UUID.generate(), false)
  end

  test "conversion requires the complete source snapshot and is atomic on invalid direct input",
       c do
    now = DateTime.utc_now()

    invalid = %Documentation.Conversion{
      id: Ecto.UUID.generate(),
      project_id: c.project.id,
      command_id: Ecto.UUID.generate(),
      source_count: 0,
      root_path: c.project.root_path,
      git_common_dir: c.project.git_common_dir,
      specs_path: c.project.specs_path,
      base_branch: c.project.base_branch,
      inserted_at: now
    }

    assert_raise Exqlite.Error, fn -> Repo.insert!(invalid) end
    assert Documentation.latest(c.project.id) == nil
    assert Repo.query!("SELECT count(*) FROM project_documentation_sources").rows == [[0]]
    assert Projects.get_project!(c.project.id).intake_mode == "specs"

    assert {:error, _} =
             Repo.query("UPDATE projects SET intake_mode='documentation' WHERE id=?", [
               c.project.id
             ])
  end

  test "converted references allow one fresh intake and are excluded from both SQL selection policies",
       c do
    {:ok, _} = Documentation.admit(c.project.id, Ecto.UUID.generate(), false)

    {:ok, {:new, intake}} =
      Intake.admit(c.project.id, Ecto.UUID.generate(), "true", "codex", false)

    assert intake.project_id == c.project.id

    assert {:ok, {:existing, ^intake}} =
             Intake.admit(c.project.id, intake.command_id, "true", "codex", true)

    assert Repo.query!("SELECT task_id FROM autopilot_recovery_candidates WHERE project_id=?", [
             c.project.id
           ]).rows == []

    assert {:error, _} =
             Repo.query(
               "INSERT INTO autopilots(id,project_id,command_id,task_ids,check_config,config_hash,reviewer,status,version,inserted_at,updated_at,autonomy_version,routing_version) VALUES (?,?,?,'[#{c.task.id}]','[]',?,'codex','running',0,?,?,1,1)",
               [
                 Ecto.UUID.generate(),
                 c.project.id,
                 Ecto.UUID.generate(),
                 String.duplicate("a", 64),
                 DateTime.utc_now(),
                 DateTime.utc_now()
               ]
             )
  end

  test "documentation projects with unclassified imported tasks still refuse intake", c do
    other =
      Repo.insert!(%Projects.Project{
        name: "Already docs",
        root_path: c.project.root_path <> "/other",
        git_common_dir: c.project.git_common_dir <> "/other",
        specs_path: c.project.specs_path,
        base_branch: "main",
        intake_mode: "documentation"
      })

    {:ok, _} =
      Projects.record_spec(other.id, %{
        relative_path: "one.md",
        title: "One",
        original_text: "# One"
      })

    assert {:error, :already_planned} =
             Intake.admit(other.id, Ecto.UUID.generate(), "true", "codex", false)
  end

  test "manager conversion has no worker effects and broadcasts only committed conversion", c do
    Phoenix.PubSub.subscribe(Boss.PubSub, Documentation.topic(c.project.id))
    caller = self()
    worker = fn _, _, _ -> send(caller, :unexpected_worker) end

    manager =
      start_supervised!(
        {Runs.Manager,
         name: nil,
         repo: c.repo,
         registry: Boss.DocumentationConversionRegistry,
         worker: worker,
         delivery_worker: worker}
      )

    command = Ecto.UUID.generate()
    assert {:ok, receipt} = Documentation.convert(c.project.id, command, manager)
    assert_receive {:project_documentation, project}, 2_000
    assert project == c.project.id
    assert {:ok, ^receipt} = Documentation.convert(c.project.id, command, manager)
    refute_receive {:project_documentation, _}, 50
    refute_receive :unexpected_worker, 50
  end

  test "ready approvals and stopped integration intents prevent conversion", c do
    d = ready_delivery(c)
    before = history()
    assert {:error, :busy} = Documentation.admit(c.project.id, Ecto.UUID.generate(), false)
    assert history() == before
    {:ok, {:new, d}} = Deliveries.admit_integration(c.project.id, d.id, Ecto.UUID.generate())
    candidate = Enum.find(Deliveries.steps(d.id), &(&1.kind == "check")).input["workspace"]

    {:ok, _} =
      Deliveries.set_integration_intent(d.id, %{
        "delivery_id" => d.id,
        "candidate" => candidate,
        "base_commit" => String.duplicate("a", 40),
        "candidate_commit" => String.duplicate("b", 40),
        "repo_path" => c.project.root_path,
        "base_branch" => c.project.base_branch
      })

    {:ok, _} = Deliveries.complete(d.id, "cancelled", "Stopped at publication boundary")
    before = history()
    assert {:error, :busy} = Documentation.admit(c.project.id, Ecto.UUID.generate(), false)
    assert history() == before
  end

  test "concurrent identical conversion commands commit one complete snapshot", c do
    command = Ecto.UUID.generate()

    results =
      for _ <- 1..2 do
        Task.async(fn ->
          Repo.put_dynamic_repo(c.repo)
          Documentation.admit(c.project.id, command, false)
        end)
      end
      |> Task.await_many(2_000)

    assert [{:ok, first}, {:ok, second}] = results
    assert first == second
    assert Repo.query!("SELECT count(*) FROM project_documentation_conversions").rows == [[1]]
    assert Repo.query!("SELECT count(*) FROM project_documentation_sources").rows == [[1]]
  end

  test "source count is bounded before any conversion effect", c do
    for n <- 1..256 do
      {:ok, _} =
        Projects.record_spec(c.project.id, %{
          relative_path: "document-#{n}.md",
          title: "Document",
          original_text: "# Document"
        })
    end

    before = history()

    assert {:error, :too_many_sources} =
             Documentation.admit(c.project.id, Ecto.UUID.generate(), false)

    assert Documentation.latest(c.project.id) == nil
    assert Projects.get_project!(c.project.id).intake_mode == "specs"
    assert history() == before
  end

  test "empty metadata migration is independent and new conversion history refuses downgrade",
       c do
    assert [%{reference_only: false}] = Projects.list_spec_entries(c.project.id)

    assert :ok = Ecto.Migrator.down(Repo, 20_261_106_160_000, Boss.Repo.Migrations.AddProviderRecovery, log: false)

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
             Ecto.Migrator.down(
               Repo,
               20_261_106_120_000,
               Boss.Repo.Migrations.ConvertProjectDocumentation,
               log: false
             )

    assert :ok =
             Ecto.Migrator.up(
               Repo,
               20_261_106_120_000,
               Boss.Repo.Migrations.DocumentationConversionSchema,
               log: false
             )

    assert [%{reference_only: false}] = Projects.list_spec_entries(c.project.id)

    assert :ok =
             Ecto.Migrator.down(
               Repo,
               20_261_106_120_000,
               Boss.Repo.Migrations.DocumentationConversionSchema,
               log: false
             )

    assert :ok =
             Ecto.Migrator.up(
               Repo,
               20_261_106_120_000,
               Boss.Repo.Migrations.ConvertProjectDocumentation,
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

    assert :ok =
             Ecto.Migrator.up(
               Repo,
               20_261_106_150_000,
               Boss.Repo.Migrations.AddCheckpointRecovery,
               log: false
             )

    assert :ok = Ecto.Migrator.up(Repo, 20_261_106_160_000, Boss.Repo.Migrations.AddProviderRecovery, log: false)

    {:ok, _} = Documentation.admit(c.project.id, Ecto.UUID.generate(), false)

    assert_raise RuntimeError, ~r/Refusing to discard documentation conversion history/, fn ->
      Ecto.Migrator.down(
        Repo,
        20_261_106_120_000,
        Boss.Repo.Migrations.ConvertProjectDocumentation,
        log: false
      )
    end

    assert Projects.get_project!(c.project.id).intake_mode == "documentation"
    assert [%{reference_only: true}] = Projects.list_spec_entries(c.project.id)
  end

  test "membership capture closes before generated tasks can be added", c do
    {:ok, conversion} = Documentation.admit(c.project.id, Ecto.UUID.generate(), false)

    {:ok, %{task: task, spec: spec}} =
      Projects.record_spec(c.project.id, %{
        relative_path: "autopilot/intake-new.md",
        explicit_id: "intake-new",
        title: "Generated",
        original_text: "# New implementation"
      })

    assert [%{reference_only: true}, %{reference_only: false}] =
             Projects.list_spec_entries(c.project.id)

    assert {:error, _} =
             Repo.query(
               """
               INSERT INTO project_documentation_sources
                 (conversion_id,spec_id,task_id,spec_revision_id,latest_revision_id,state_version,state,identity_key,relative_path,missing)
               VALUES(?,?,?,?,?,0,'new',?,?,0)
               """,
               [
                 conversion.id,
                 spec.id,
                 task.id,
                 task.spec_revision_id,
                 task.spec_revision_id,
                 spec.identity_key,
                 spec.relative_path
               ]
             )

    assert Documentation.reference_only?(c.task.id)
    refute Documentation.reference_only?(task.id)

    assert {:error, :already_planned} =
             Intake.admit(c.project.id, Ecto.UUID.generate(), "true", "codex", false)
  end

  test "historical schema can add empty reference metadata without later execution tables", c do
    opts = Keyword.put(c.opts, :database, Path.join(c.project.root_path, "historical.db"))

    repo =
      start_supervised!(%{id: :historical_documentation_repo, start: {Repo, :start_link, [opts]}})

    Repo.put_dynamic_repo(repo)

    migrations =
      Enum.take(@migrations, 4) ++
        [
          {20_261_027_010_000, Boss.Repo.Migrations.AddTaskRevisionAdoption},
          {20_261_103_120_000, Boss.Repo.Migrations.AddProjectIntake},
          {20_261_106_120_000, Boss.Repo.Migrations.DocumentationConversionSchema}
        ]

    Ecto.Migrator.run(Repo, migrations, :up, all: true, log: false)

    project =
      Repo.insert!(%Projects.Project{
        name: "Historical",
        root_path: c.project.root_path,
        git_common_dir: c.project.git_common_dir,
        specs_path: c.project.specs_path,
        base_branch: "main"
      })

    {:ok, %{task: task}} =
      Projects.record_spec(project.id, %{
        relative_path: "one.md",
        title: "One",
        original_text: "# One"
      })

    assert [%{reference_only: false}] = Projects.list_spec_entries(project.id)
    assert {:ok, %{reference_only: false}} = Tasks.get_details(project.id, task.id)

    assert {:ok, _} =
             Tasks.transition(task.id, %{
               command_id: "cancel",
               expected_version: 0,
               action: "cancel",
               reason: "Historical transition"
             })

    assert Repo.query!("SELECT name FROM sqlite_master WHERE type='table' AND name='deliveries'").rows ==
             []

    Repo.put_dynamic_repo(c.repo)
  end

  defp ready_delivery(c) do
    base = String.duplicate("a", 40)
    sha = String.duplicate("b", 40)
    hash = String.duplicate("c", 64)

    {:ok, {:new, d}} =
      Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true", "codex", false, 0)

    intent = %{
      "run_id" => d.id,
      "project_id" => to_string(c.project.id),
      "repo_path" => c.project.root_path,
      "git_common_dir" => c.project.git_common_dir,
      "base_branch" => c.project.base_branch,
      "base_commit" => base
    }

    {:ok, d} = Deliveries.set_intent(d.id, intent)

    plan =
      stage(d, "plan", 0, %{"workspace" => intent}, %{
        "report" => %{
          "summary" => "Plan",
          "steps" => ["Implement"],
          "acceptance" => ["Criterion"]
        }
      })

    implement =
      stage(d, "implement", 1, %{"plan_step_id" => plan.id}, %{
        "workspace" => intent,
        "head_commit" => base
      })

    id = Ecto.UUID.generate()

    workspace = %{
      "check_id" => id,
      "path" => "/checks/" <> id,
      "ref" => "refs/boss/checks/" <> id,
      "run_workspace" => intent
    }

    snapshot =
      stage(d, "snapshot", 1, %{"implementation_step_id" => implement.id}, %{
        "workspace" => workspace,
        "candidate_commit" => sha
      })

    check =
      stage(
        d,
        "check",
        1,
        %{"snapshot_step_id" => snapshot.id, "workspace" => workspace, "candidate_commit" => sha},
        %{"output_complete" => true, "output_hash" => hash}
      )

    stage(
      d,
      "review",
      1,
      %{
        "plan_step_id" => plan.id,
        "check_step_id" => check.id,
        "candidate_commit" => sha,
        "original_base" => base,
        "input_hash" => hash
      },
      %{
        "report" => %{
          "verdict" => "approved",
          "summary" => "Verified",
          "acceptance" => [
            %{"criterion" => "Criterion", "status" => "passed", "evidence" => "Checked"}
          ],
          "issues" => []
        }
      }
    )

    {:ok, d} = Deliveries.complete(d.id, "ready_to_merge")
    d
  end

  defp stage(d, kind, cycle, input, receipt) do
    {:ok, step} =
      Deliveries.begin_step(
        d.id,
        kind,
        cycle,
        Map.merge(
          %{"spec_revision_id" => d.spec_revision_id, "config_hash" => d.config_hash},
          input
        )
      )

    {:ok, step} =
      Deliveries.finish_step(
        step.id,
        Map.merge(
          %{
            "status" => "finished",
            "cleanup" => "group_empty",
            "exit_kind" => "exit",
            "exit_code" => 0,
            "eof" => %{"stdout" => true, "stderr" => true}
          },
          receipt
        )
      )

    step
  end

  defp history do
    for table <-
          ~w(specs spec_revisions tasks task_events agent_runs deliveries delivery_steps delivery_requests autopilots autopilot_items),
        into: %{},
        do: {table, Repo.query!("SELECT * FROM #{table} ORDER BY 1").rows}
  end
end
