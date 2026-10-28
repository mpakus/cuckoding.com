defmodule Boss.MergeIntegrationPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo, Tasks}
  @moduletag capture_log: true
  @version 20_261_027_050_000
  @base String.duplicate("a", 40)
  @approved String.duplicate("b", 40)
  @target String.duplicate("d", 40)
  @hash String.duplicate("c", 64)
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
    {20_261_027_070_000, Boss.Repo.Migrations.AddAutopilot}
  ]

  test "upgrade preserves legacy approval and publication; durable merge intent forbids downgrade and restart replay" do
    {root, opts, project} = fresh_database(@version - 10_000)

    {legacy, original} = ready(project, "legacy")
    saved_steps = Deliveries.steps(legacy.id)
    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)
    assert Deliveries.get(project.id, legacy.id) == legacy
    assert Deliveries.steps(legacy.id) == saved_steps
    Ecto.Migrator.run(Repo, @migrations, :down, to: @version, log: false)
    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)
    assert Deliveries.steps(legacy.id) == saved_steps

    command = Ecto.UUID.generate()
    assert {:ok, {:new, legacy}} = Deliveries.admit_integration(project.id, legacy.id, command)
    original_check = Enum.find(saved_steps, &(&1.id == original.input["check_step_id"]))

    intent = %{
      "delivery_id" => legacy.id,
      "candidate" => original_check.input["workspace"],
      "candidate_commit" => @approved,
      "base_commit" => @base,
      "repo_path" => root,
      "base_branch" => "main"
    }

    assert {:ok, _} = Deliveries.set_integration_intent(legacy.id, intent)

    {:ok, publish} =
      Deliveries.begin_step(legacy.id, "publish", 1, %{
        "intent" => intent,
        "review_step_id" => original.id
      })

    assert :ok = Deliveries.authorize_publication(legacy.id)

    {:ok, publish} =
      Deliveries.finish_step(publish.id, receipt(%{"candidate_commit" => @approved}))

    stage(
      legacy,
      "post_check",
      1,
      %{"intent" => intent, "publish_step_id" => publish.id, "config_hash" => legacy.config_hash},
      %{"candidate_commit" => @approved, "output_complete" => true, "output_hash" => @hash}
    )

    assert {:ok, done} = Deliveries.complete(legacy.id, "done")
    assert done.status == "done"

    {delivery, review} = ready(project, "merge")
    command = Ecto.UUID.generate()

    assert {:ok, {:new, delivery}} =
             Deliveries.admit_integration(project.id, delivery.id, command)

    all = Deliveries.steps(delivery.id)
    check = Enum.find(all, &(&1.id == review.input["check_step_id"]))
    plan = Enum.find(all, &(&1.id == review.input["plan_step_id"]))
    candidate = workspace(check.input["workspace"]["run_workspace"])

    input = %{
      "original_review_step_id" => review.id,
      "original_check_step_id" => check.id,
      "plan_step_id" => plan.id,
      "original_candidate" => @approved,
      "original_base" => @base,
      "target_commit" => @target,
      "workspace" => candidate,
      "config_hash" => delivery.config_hash,
      "spec_revision_id" => delivery.spec_revision_id
    }

    assert {:ok, merge} = Deliveries.begin_step(delivery.id, "merge", 1, input)
    before_restart = Repo.get!(Deliveries.Step, merge.id)
    :ok = stop_supervised(Repo)
    repo = start_supervised!({Repo, opts})
    Repo.put_dynamic_repo(repo)
    assert Repo.get!(Deliveries.Step, merge.id) == before_restart
    assert Deliveries.get(project.id, legacy.id) == done
    assert {:ok, [interrupted]} = Deliveries.reconcile()
    assert interrupted.id == delivery.id
    assert interrupted.status == "interrupted" and interrupted.cleanup == "unknown"
    merge = Repo.get!(Deliveries.Step, merge.id)
    assert merge.input == input and merge.status == "interrupted"
    assert merge.receipt["cleanup"] == "unknown"
    assert Deliveries.get(project.id, delivery.id).integration_intent == %{}

    assert {:ok, {:existing, ^interrupted}} =
             Deliveries.admit_integration(project.id, delivery.id, command)

    assert length(Deliveries.steps(delivery.id)) == 6
    refute Tasks.get_task!(delivery.task_id).state == "done"

    assert_raise RuntimeError, "Refusing to discard merge integration evidence", fn ->
      Ecto.Migrator.run(Repo, @migrations, :down, to: @version, log: false)
    end
  end

  test "real pooled SQL refuses false merge approval and keeps refusal durable across restart" do
    {root, opts, project} = fresh_database(@version)
    {d, original} = ready(project, "invalid-merge-report")
    {:ok, {:new, d}} = Deliveries.admit_integration(project.id, d.id, Ecto.UUID.generate())
    all = Deliveries.steps(d.id)
    original_check = Enum.find(all, &(&1.id == original.input["check_step_id"]))
    plan = Enum.find(all, &(&1.id == original.input["plan_step_id"]))
    candidate = workspace(original_check.input["workspace"]["run_workspace"])

    merge =
      stage(
        d,
        "merge",
        1,
        %{
          "original_review_step_id" => original.id,
          "original_check_step_id" => original_check.id,
          "plan_step_id" => plan.id,
          "original_candidate" => @approved,
          "original_base" => @base,
          "target_commit" => @target,
          "workspace" => candidate,
          "config_hash" => d.config_hash,
          "spec_revision_id" => d.spec_revision_id
        },
        %{"candidate_commit" => String.duplicate("e", 40), "workspace" => candidate}
      )

    merged = merge.receipt["candidate_commit"]

    check =
      stage(
        d,
        "merge_check",
        1,
        %{
          "merge_step_id" => merge.id,
          "candidate_commit" => merged,
          "target_commit" => @target,
          "workspace" => candidate,
          "config_hash" => d.config_hash,
          "spec_revision_id" => d.spec_revision_id
        },
        %{"candidate_commit" => merged, "output_complete" => true, "output_hash" => @hash}
      )

    {:ok, review} =
      Deliveries.begin_step(d.id, "merge_review", 1, %{
        "merge_step_id" => merge.id,
        "merge_check_step_id" => check.id,
        "original_review_step_id" => original.id,
        "plan_step_id" => plan.id,
        "candidate_commit" => merged,
        "target_commit" => @target,
        "original_base" => @base,
        "config_hash" => d.config_hash,
        "spec_revision_id" => d.spec_revision_id,
        "input_hash" => @hash,
        "output_hash" => @hash
      })

    valid = original.receipt["report"]

    invalid =
      for issues <- [[%{"criterion" => "Criterion", "message" => "Unfixed issue"}], nil, %{}],
          do: Map.put(valid, "issues", issues)

    for report <- [Map.delete(valid, "issues") | invalid] do
      invalid_receipt = receipt(%{"candidate_commit" => merged, "report" => report})

      assert {:error, %Exqlite.Error{}} =
               Repo.query("UPDATE delivery_steps SET status='finished', receipt=? WHERE id=?", [
                 JSON.encode!(invalid_receipt),
                 review.id
               ])

      assert Repo.get!(Deliveries.Step, review.id).status == "running"
    end

    intent = %{
      "delivery_id" => d.id,
      "candidate" => candidate,
      "candidate_commit" => merged,
      "base_commit" => @target,
      "repo_path" => root,
      "base_branch" => "main"
    }

    assert {:error, :missing_evidence} = Deliveries.set_integration_intent(d.id, intent)

    assert {:error, %Exqlite.Error{}} =
             Repo.query("UPDATE deliveries SET integration_intent=? WHERE id=?", [
               JSON.encode!(intent),
               d.id
             ])

    assert {:error, :missing_evidence} = Deliveries.authorize_publication(d.id)
    :ok = stop_supervised(Repo)
    repo = start_supervised!({Repo, opts})
    Repo.put_dynamic_repo(repo)
    assert Repo.get!(Deliveries.Step, review.id).receipt == %{}
    assert Deliveries.get(project.id, d.id).integration_intent == %{}
    assert {:error, :missing_evidence} = Deliveries.set_integration_intent(d.id, intent)
    assert {:ok, [%{status: "interrupted", cleanup: "unknown"}]} = Deliveries.reconcile()
    refute Tasks.get_task!(d.task_id).state == "done"
  end

  defp fresh_database(version) do
    root = Path.join(System.tmp_dir!(), "boss-merge-upgrade-#{Ecto.UUID.generate()}")
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
    Ecto.Migrator.run(Repo, @migrations, :up, to: version, log: false)
    # Current admission reads scheduling and Autopilot; install those independent
    # migrations while retaining the old merge schema exercised by this fixture.
    for {version, module} <- [
          {20_261_027_060_000, Boss.Repo.Migrations.AddDeliveryScheduling},
          {20_261_027_070_000, Boss.Repo.Migrations.AddAutopilot}
        ],
        do: Ecto.Migrator.up(Repo, version, module, log: false)

    project =
      Repo.insert!(%Projects.Project{
        name: "Merge upgrade",
        root_path: root,
        git_common_dir: Path.join(root, ".git"),
        specs_path: root,
        base_branch: "main"
      })

    {root, opts, project}
  end

  defp ready(project, name) do
    {:ok, %{task: task}} =
      Projects.record_spec(project.id, %{
        relative_path: name <> ".md",
        title: name,
        original_text: "# " <> name
      })

    {:ok, {:new, d}} = Deliveries.admit(project.id, task.id, Ecto.UUID.generate(), "true")

    intent = %{
      "run_id" => d.id,
      "project_id" => to_string(project.id),
      "repo_path" => project.root_path,
      "git_common_dir" => project.git_common_dir,
      "base_branch" => "main",
      "base_commit" => @base
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

    implementation =
      stage(d, "implement", 1, %{"plan_step_id" => plan.id}, %{
        "workspace" => intent,
        "head_commit" => @base
      })

    candidate = workspace(intent)

    snapshot =
      stage(d, "snapshot", 1, %{"implementation_step_id" => implementation.id}, %{
        "workspace" => candidate,
        "candidate_commit" => @approved
      })

    check =
      stage(
        d,
        "check",
        1,
        %{
          "snapshot_step_id" => snapshot.id,
          "workspace" => candidate,
          "candidate_commit" => @approved,
          "config_hash" => d.config_hash
        },
        %{"output_complete" => true, "output_hash" => @hash}
      )

    review =
      stage(
        d,
        "review",
        1,
        %{
          "plan_step_id" => plan.id,
          "check_step_id" => check.id,
          "candidate_commit" => @approved,
          "original_base" => @base,
          "config_hash" => d.config_hash,
          "input_hash" => @hash
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

    {:ok, ready} = Deliveries.complete(d.id, "ready_to_merge")
    {ready, review}
  end

  defp workspace(run) do
    id = Ecto.UUID.generate()

    %{
      "run_workspace" => run,
      "check_id" => id,
      "path" => "/checks/" <> id,
      "ref" => "refs/boss/checks/" <> id
    }
  end

  defp stage(d, kind, cycle, input, attrs) do
    {:ok, step} = Deliveries.begin_step(d.id, kind, cycle, input)
    {:ok, saved} = Deliveries.finish_step(step.id, receipt(attrs))
    saved
  end

  defp receipt(attrs),
    do:
      Map.merge(
        %{
          "status" => "finished",
          "cleanup" => "group_empty",
          "exit_kind" => "exit",
          "exit_code" => 0,
          "eof" => %{"stdout" => true, "stderr" => true}
        },
        attrs
      )
end
