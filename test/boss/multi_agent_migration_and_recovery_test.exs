defmodule Boss.MultiAgentMigrationAndRecoveryTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo}
  alias Boss.Agents.{Detections, Roles}
  alias Boss.Deliveries.{ExecutionRetry, Retry}
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
    {20_261_106_160_000, Boss.Repo.Migrations.AddProviderRecovery},
    {20_261_110_120_000, Boss.Repo.Migrations.RepairMergeConflicts},
    {20_261_110_140_000, Boss.Repo.Migrations.RepairRejectedMergeReview},
    {20_261_110_160_000, Boss.Repo.Migrations.RetargetMergeAfterDrift},
    {20_261_110_180_000, Boss.Repo.Migrations.RepairFailedPostcheck},
    {20_261_110_210_000, Boss.Repo.Migrations.CreateAgentRoles},
    {20_261_110_220_000, Boss.Repo.Migrations.AddStandardAgentRoles},
    {20_261_110_230_000, Boss.Repo.Migrations.AllowCursorReviewer},
    {20_261_110_240_000, Boss.Repo.Migrations.PinCursorImplementer},
    {20_261_110_250_000, Boss.Repo.Migrations.PinCursorAnalytic},
    {20_261_110_260_000, Boss.Repo.Migrations.AllowClaudeAndIntakePlanner},
    {20_261_110_270_000, Boss.Repo.Migrations.PersistAgentDetectionsAndRoleModels},
    {20_261_110_280_000, Boss.Repo.Migrations.AllowOpenCodeRunner}
  ]

  setup do
    root = Path.join(System.tmp_dir!(), "boss-multi-agent-storage-#{Ecto.UUID.generate()}")
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
        name: "BetaMultiAgent",
        root_path: root,
        git_common_dir: Path.join(root, ".git"),
        specs_path: root,
        base_branch: "main"
      })

    %{project: project, root: root, repo: repo, opts: opts}
  end

  test "agent role, detection, and OpenCode runner migrations roundtrip cleanly and guard OpenCode history",
       c do
    for {version, mod} <-
          @migrations
          |> Enum.filter(fn {v, _} -> v >= 20_261_110_210_000 end)
          |> Enum.reverse() do
      assert :ok = Ecto.Migrator.down(Repo, version, mod, log: false)
    end

    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)

    authorize_agents!(~w(cursor opencode claude codex))
    wire_role!("implementer", "opencode", "opencode/beam-free", "high")
    wire_role!("analytic", "cursor", "auto", nil)
    wire_role!("reviewer", "opencode", "opencode/beam-free", "high")

    {:ok, %{task: task}} =
      Projects.record_spec(c.project.id, %{
        relative_path: "guard.md",
        title: "Guard",
        original_text: "# Guard"
      })

    {:ok, {:new, delivery}} =
      Deliveries.admit(
        c.project.id,
        task.id,
        Ecto.UUID.generate(),
        "mix test",
        "opencode",
        false,
        1,
        2
      )

    assert delivery.implementer == "opencode"
    assert delivery.analytic == "cursor"
    assert delivery.reviewer == "opencode"

    assert_raise RuntimeError, ~r/Refusing to discard OpenCode delivery history/, fn ->
      Ecto.Migrator.down(
        Repo,
        20_261_110_280_000,
        Boss.Repo.Migrations.AllowOpenCodeRunner,
        log: false
      )
    end
  end

  test "non-Codex provider rate-limit, timeout, and review retries preserve pinned roles with empty Codex catalog",
       c do
    authorize_agents!(~w(cursor opencode claude codex))
    wire_role!("implementer", "cursor", "auto", nil)
    wire_role!("analytic", "opencode", "opencode/beam-free", "high")
    wire_role!("reviewer", "cursor", "auto", nil)

    {:ok, %{task: rate_task}} =
      Projects.record_spec(c.project.id, %{
        relative_path: "rate-limit.md",
        title: "Rate limit recovery",
        original_text: "# Rate limit recovery"
      })

    {:ok, {:new, parent}} =
      Deliveries.admit(
        c.project.id,
        rate_task.id,
        Ecto.UUID.generate(),
        "mix test",
        "cursor",
        false,
        1,
        2
      )

    assert parent.model_catalog == %{}
    assert parent.implementer == "cursor"
    assert parent.analytic == "opencode"

    w = workspace(c, parent.id)
    {:ok, parent} = Deliveries.set_intent(parent.id, w)
    plan_step = finish_plan!(parent, "cursor")

    impl_step =
      finish(
        parent,
        "implement",
        1,
        %{
          "parent_step_id" => plan_step.id,
          "plan_step_id" => plan_step.id,
          "workspace" => fresh(w),
          "model_profile" => %{"model" => "cursor", "reasoning_effort" => "high"}
        },
        %{
          "status" => "failed",
          "outcome" => "exited",
          "exit_code" => 1,
          "summary" => %{"error_class" => "rate_limit"}
        }
      )

    {:ok, parent} =
      Deliveries.complete(
        parent.id,
        "failed",
        "Cursor Agent reported a quota, usage, or credit limit.",
        "provider_rate_limit"
      )

    wire_role!("implementer", "claude", "sonnet", "high")
    wire_role!("analytic", "claude", "sonnet", "high")

    {:ok, {:new, child}} =
      Deliveries.admit_checkpoint_retry(c.project.id, parent.id, Ecto.UUID.generate())

    assert child.provider_recovery_version == 1
    assert child.checkpoint_recovery_version == 1
    assert child.execution_recovery_version == 1
    assert child.model_catalog == %{}
    assert child.implementer == "cursor"
    assert child.analytic == "opencode"
    assert child.reviewer == "cursor"
    assert child.retry_implementation_id == impl_step.id
    assert {:ok, %{source_kind: :rate_limit, parent: ^parent}} = ExecutionRetry.source(child)
    {:ok, _} = Deliveries.complete(child.id, "cancelled", "Stopped for next test.")

    {:ok, %{task: timeout_task}} =
      Projects.record_spec(c.project.id, %{
        relative_path: "timeout.md",
        title: "Timeout recovery",
        original_text: "# Timeout recovery"
      })

    wire_role!("implementer", "opencode", "opencode/beam-free", "high")
    wire_role!("analytic", "cursor", "auto", nil)

    {:ok, {:new, t_parent}} =
      Deliveries.admit(
        c.project.id,
        timeout_task.id,
        Ecto.UUID.generate(),
        "mix test",
        "opencode",
        false,
        1,
        2
      )

    tw = workspace(c, t_parent.id)
    {:ok, t_parent} = Deliveries.set_intent(t_parent.id, tw)
    t_plan = finish_plan!(t_parent, "opencode")

    _t_impl =
      finish(
        t_parent,
        "implement",
        1,
        %{
          "parent_step_id" => t_plan.id,
          "plan_step_id" => t_plan.id,
          "workspace" => fresh(tw),
          "model_profile" => %{"model" => "opencode", "reasoning_effort" => "high"}
        },
        %{
          "status" => "failed",
          "outcome" => "timeout",
          "exit_kind" => "signal",
          "exit_code" => nil,
          "signal" => 15
        }
      )

    {:ok, t_parent} = Deliveries.complete(t_parent.id, "failed", "Implementation timed out.")

    wire_role!("implementer", "claude", "sonnet", "high")

    {:ok, {:new, t_child}} =
      Deliveries.admit_timeout_retry(c.project.id, t_parent.id, Ecto.UUID.generate())

    assert t_child.implementer == "opencode"
    assert t_child.analytic == "cursor"
    assert t_child.reviewer == "opencode"
    assert t_child.model_catalog == %{}
    assert {:ok, %{parent: ^t_parent}} = ExecutionRetry.source(t_child)
    {:ok, _} = Deliveries.complete(t_child.id, "cancelled", "Stopped for next test.")

    {:ok, %{task: review_task}} =
      Projects.record_spec(c.project.id, %{
        relative_path: "review-retry.md",
        title: "Review retry",
        original_text: "# Review retry"
      })

    {:ok, {:new, r_parent}} =
      Deliveries.admit(
        c.project.id,
        review_task.id,
        Ecto.UUID.generate(),
        "mix test",
        "opencode",
        false,
        1,
        2
      )

    rw = workspace(c, r_parent.id)
    {:ok, r_parent} = Deliveries.set_intent(r_parent.id, rw)
    r_plan = finish_plan!(r_parent, "claude")

    r_impl_ws = fresh(rw)

    r_impl =
      finish(
        r_parent,
        "implement",
        1,
        %{
          "parent_step_id" => r_plan.id,
          "plan_step_id" => r_plan.id,
          "workspace" => r_impl_ws,
          "model_profile" => %{"model" => "claude", "reasoning_effort" => "high"}
        },
        %{"workspace" => r_impl_ws, "head_commit" => @sha}
      )

    check_ws = %{
      "check_id" => Ecto.UUID.generate(),
      "run_workspace" => r_impl.input["workspace"],
      "path" => Path.join(c.root, "chk-" <> Ecto.UUID.generate()),
      "ref" => "refs/boss/checks/" <> Ecto.UUID.generate()
    }

    r_snap =
      finish(
        r_parent,
        "snapshot",
        1,
        %{"implementation_step_id" => r_impl.id, "plan_step_id" => r_plan.id},
        %{"workspace" => check_ws, "candidate_commit" => @sha}
      )

    r_check =
      finish(
        r_parent,
        "check",
        1,
        %{
          "snapshot_step_id" => r_snap.id,
          "plan_step_id" => r_plan.id,
          "workspace" => check_ws,
          "candidate_commit" => @sha
        },
        %{"output_complete" => true, "output_hash" => @hash}
      )

    _r_review =
      finish(
        r_parent,
        "review",
        1,
        %{
          "check_step_id" => r_check.id,
          "plan_step_id" => r_plan.id,
          "workspace" => check_ws,
          "candidate_commit" => @sha,
          "original_base" => @sha,
          "input_hash" => @hash,
          "model_profile" => %{"model" => "opencode", "reasoning_effort" => "high"}
        },
        %{
          "report" => %{
            "verdict" => "changes_requested",
            "summary" => "Needs adjustment",
            "acceptance" => [
              %{
                "criterion" => "Saved criterion",
                "status" => "failed",
                "evidence" => "Missing check"
              }
            ],
            "issues" => [%{"criterion" => "Saved criterion", "message" => "Fix it"}]
          }
        }
      )

    {:ok, r_parent} = Deliveries.complete(r_parent.id, "blocked", "Reviewer requested changes.")

    wire_role!("implementer", "cursor", "auto", nil)

    {:ok, {:new, r_child}} =
      Deliveries.admit_retry(c.project.id, r_parent.id, Ecto.UUID.generate())

    assert r_child.implementer == "claude"
    assert r_child.analytic == "cursor"
    assert r_child.reviewer == "opencode"
    assert {:ok, %{parent: ^r_parent}} = Retry.source(r_child)
  end

  defp authorize_agents!(ids) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      for id <- ids do
        atom = String.to_existing_atom(id)

        %{
          id: atom,
          name: String.capitalize(id),
          probe_status: :ok,
          path: "/usr/local/bin/#{id}",
          version: "1.0.0",
          auth_status: :configured,
          capabilities: %{
            headless: :advertised,
            streaming: :advertised,
            session_resume: :advertised,
            structured_output: :advertised,
            approval_support: :advertised,
            usage_reporting: :advertised
          },
          errors: []
        }
      end

    _ = Detections.save_scan(entries, ts)

    for id <- ids do
      models =
        case id do
          "cursor" ->
            [%{"id" => "auto", "label" => "Auto", "reasoning_efforts" => []}]

          "opencode" ->
            [
              %{
                "id" => "opencode/beam-free",
                "label" => "Beam Free",
                "reasoning_efforts" => ["high"]
              }
            ]

          "claude" ->
            [%{"id" => "sonnet", "label" => "Sonnet", "reasoning_efforts" => ["high"]}]

          "codex" ->
            [%{"id" => "gpt-5.6-sol", "label" => "Sol", "reasoning_efforts" => ["high"]}]
        end

      Detections.save_models(id, models, ts)
    end
  end

  defp wire_role!(kind, agent_id, model_id, effort) do
    role = Enum.find(Roles.list(), &(&1.kind == kind))

    assert {:ok, _} =
             Roles.assign(role.id, [agent_id], %{
               agent_id => %{model_id: model_id, reasoning_effort: effort}
             })
  end

  defp finish_plan!(d, model_name) do
    finish(
      d,
      "plan",
      0,
      %{
        "workspace" => d.intent,
        "input_hash" => @hash,
        "model_profile" => %{"model" => model_name, "reasoning_effort" => "high"}
      },
      %{
        "report" => %{
          "summary" => "Implement saved requirement",
          "steps" => ["Use existing convention"],
          "acceptance" => ["Saved criterion"],
          "clarification" => nil
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
end
