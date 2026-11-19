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
    {20_261_110_280_000, Boss.Repo.Migrations.AllowOpenCodeRunner},
    {20_261_114_120_000, Boss.Repo.Migrations.ReleaseUnknownCleanup},
    {20_261_118_120_000, Boss.Repo.Migrations.HardenMultiAgentRetriesAndAnalyticRouting}
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
    plan_step = finish_plan!(parent, nil)

    impl_step =
      finish(
        parent,
        "implement",
        1,
        %{
          "parent_step_id" => plan_step.id,
          "plan_step_id" => plan_step.id,
          "workspace" => fresh(w),
          "model_profile" => nil
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

    assert_raise Exqlite.Error, ~r/exact terminal rate-limit source/, fn ->
      Repo.query!(
        """
        INSERT INTO deliveries (
          id, project_id, task_id, spec_revision_id, command_id, admitted_version, task_version,
          status, cleanup, cycle, check_config, config_hash, reviewer, implementer, analytic,
          autonomy_version, routing_version, model_catalog,
          execution_recovery_version, checkpoint_recovery_version, provider_recovery_version,
          implementation_network_version, retry_implementation_id,
          inserted_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 'planning', 'not_started', 0, ?, ?, ?, 'claude', ?, 1, 2, '{}', 1, 1, 1, 1, ?, ?, ?)
        """,
        [
          Ecto.UUID.generate(),
          c.project.id,
          rate_task.id,
          parent.spec_revision_id,
          Ecto.UUID.generate(),
          parent.task_version + 1,
          parent.task_version + 1,
          Jason.encode!(parent.check_config),
          parent.config_hash,
          parent.reviewer,
          parent.analytic,
          impl_step.id,
          "2026-11-18T00:00:00Z",
          "2026-11-18T00:00:00Z"
        ]
      )
    end

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

    assert_raise RuntimeError, ~r/Refusing to discard non-Codex execution recovery history/, fn ->
      Ecto.Migrator.down(
        Repo,
        20_261_118_120_000,
        Boss.Repo.Migrations.HardenMultiAgentRetriesAndAnalyticRouting,
        log: false
      )
    end

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
    t_plan = finish_plan!(t_parent, nil)

    _t_impl =
      finish(
        t_parent,
        "implement",
        1,
        %{
          "parent_step_id" => t_plan.id,
          "plan_step_id" => t_plan.id,
          "workspace" => fresh(tw),
          "model_profile" => nil
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

    {:ok, %{task: chk_task}} =
      Projects.record_spec(c.project.id, %{
        relative_path: "checkpoint.md",
        title: "Checkpoint recovery",
        original_text: "# Checkpoint recovery"
      })

    {:ok, {:new, c_parent}} =
      Deliveries.admit(
        c.project.id,
        chk_task.id,
        Ecto.UUID.generate(),
        "mix test",
        "opencode",
        false,
        1,
        2
      )

    cw = workspace(c, c_parent.id)
    {:ok, c_parent} = Deliveries.set_intent(c_parent.id, cw)
    c_plan = finish_plan!(c_parent, nil)
    c_impl_ws = fresh(cw)

    c_impl =
      finish(
        c_parent,
        "implement",
        1,
        %{
          "parent_step_id" => c_plan.id,
          "plan_step_id" => c_plan.id,
          "workspace" => c_impl_ws,
          "model_profile" => nil
        },
        %{"workspace" => c_impl_ws, "head_commit" => @sha}
      )

    c_chk_id = Ecto.UUID.generate()

    c_chk_ws = %{
      "check_id" => c_chk_id,
      "run_workspace" => c_impl_ws,
      "path" => Path.join(c.root, "chk-" <> c_chk_id),
      "ref" => "refs/boss/checks/" <> c_chk_id
    }

    c_snap =
      finish(
        c_parent,
        "snapshot",
        1,
        %{"implementation_step_id" => c_impl.id, "plan_step_id" => c_plan.id},
        %{"workspace" => c_chk_ws, "candidate_commit" => @sha}
      )

    c_check =
      finish(
        c_parent,
        "check",
        1,
        %{
          "snapshot_step_id" => c_snap.id,
          "plan_step_id" => c_plan.id,
          "workspace" => c_chk_ws,
          "candidate_commit" => @sha
        },
        %{
          "status" => "failed",
          "outcome" => "checks_failed",
          "exit_code" => 1,
          "output_complete" => true,
          "output_hash" => @hash
        }
      )

    {:ok, c_parent} = Deliveries.complete(c_parent.id, "failed", "Checks failed.")

    {:ok, {:new, c_child}} =
      Deliveries.admit_checkpoint_retry(c.project.id, c_parent.id, Ecto.UUID.generate())

    assert c_child.checkpoint_recovery_version == 1
    assert c_child.provider_recovery_version == 0
    assert c_child.implementer == "claude"
    assert c_child.analytic == "cursor"
    assert c_child.retry_source_check_id == c_check.id
    assert {:ok, %{parent: ^c_parent, check: %_{id: chk_id}}} = ExecutionRetry.source(c_child)
    assert chk_id == c_check.id
    {:ok, _} = Deliveries.complete(c_child.id, "cancelled", "Stopped for next test.")

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
    r_plan = finish_plan!(r_parent, nil)

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
          "model_profile" => nil
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

    r_review =
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
          "model_profile" => nil
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

    assert_raise Exqlite.Error, ~r/invalid rejected review source/, fn ->
      Repo.query!(
        """
        INSERT INTO deliveries (
          id, project_id, task_id, spec_revision_id, command_id, admitted_version, task_version,
          status, cleanup, cycle, check_config, config_hash, reviewer, implementer, analytic,
          autonomy_version, routing_version, model_catalog, retry_review_id,
          inserted_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 'planning', 'not_started', 0, ?, ?, ?, 'cursor', ?, 1, 2, '{}', ?, ?, ?)
        """,
        [
          Ecto.UUID.generate(),
          c.project.id,
          review_task.id,
          r_parent.spec_revision_id,
          Ecto.UUID.generate(),
          r_parent.task_version + 1,
          r_parent.task_version + 1,
          Jason.encode!(r_parent.check_config),
          r_parent.config_hash,
          r_parent.reviewer,
          r_parent.analytic,
          r_review.id,
          "2026-11-18T00:00:00Z",
          "2026-11-18T00:00:00Z"
        ]
      )
    end

    {:ok, {:new, r_child}} =
      Deliveries.admit_retry(c.project.id, r_parent.id, Ecto.UUID.generate())

    assert r_child.implementer == "claude"
    assert r_child.analytic == "cursor"
    assert r_child.reviewer == "opencode"
    assert {:ok, %{parent: ^r_parent}} = Retry.source(r_child)
  end

  test "mixed non-Codex implementer with Codex analytic routes resolve through the pinned Codex catalog",
       c do
    authorize_agents!(~w(cursor codex))
    wire_role!("implementer", "cursor", "auto", nil)
    wire_role!("analytic", "codex", "gpt-5.6-sol", "high")
    wire_role!("reviewer", "cursor", "auto", nil)

    {:ok, %{task: task}} =
      Projects.record_spec(c.project.id, %{
        relative_path: "mixed-analytic.md",
        title: "Mixed analytic",
        original_text: "# Mixed analytic"
      })

    {:ok, {:new, delivery}} =
      Deliveries.admit(
        c.project.id,
        task.id,
        Ecto.UUID.generate(),
        "mix test",
        "cursor",
        false,
        1,
        2
      )

    assert delivery.implementer == "cursor"
    assert delivery.analytic == "codex"

    catalog = %{
      "version" => 2,
      "primary" => %{"model" => "gpt-5.6-sol", "reasoning_effort" => "high"},
      "resolver" => %{"model" => "gpt-5.6-terra", "reasoning_effort" => "xhigh"},
      "small" => %{"model" => "gpt-5.6-luna", "reasoning_effort" => "medium"},
      "fallbacks" => [
        %{"model" => "gpt-5.6-sol", "reasoning_effort" => "xhigh"},
        %{"model" => "gpt-5.6-terra", "reasoning_effort" => "xhigh"}
      ]
    }

    {:ok, delivery} = Deliveries.set_model_catalog(delivery.id, catalog)
    w = workspace(c, delivery.id)
    {:ok, delivery} = Deliveries.set_intent(delivery.id, w)

    assert {:ok, nil} = Deliveries.model_profile(delivery, :plan, 0)
    plan_step = finish_plan!(delivery, nil)
    assert {:ok, nil} = Deliveries.model_profile(delivery, :implement, 1, plan_step.id)

    assert {:ok, %{"model" => "gpt-5.6-terra", "reasoning_effort" => "xhigh"}} =
             Deliveries.model_profile(delivery, :resolve, 1, plan_step.id)

    failed_impl =
      finish(
        delivery,
        "implement",
        1,
        %{
          "parent_step_id" => plan_step.id,
          "plan_step_id" => plan_step.id,
          "workspace" => fresh(w),
          "model_profile" => nil
        },
        %{
          "status" => "failed",
          "outcome" => "exited",
          "exit_code" => 1
        }
      )

    resolve_ws = fresh(w)

    assert {:error, :invalid_step} =
             Deliveries.begin_step(
               delivery.id,
               "resolve",
               1,
               pins(delivery, %{
                 "parent_step_id" => failed_impl.id,
                 "source_step_id" => failed_impl.id,
                 "plan_step_id" => plan_step.id,
                 "workspace" => resolve_ws,
                 "candidate_commit" => @sha,
                 "feedback_hash" => @hash,
                 "input_hash" => @hash,
                 "model_profile" => nil,
                 "resolution_attempt" => 1
               })
             )

    assert {:ok, resolve_step} =
             Deliveries.begin_step(
               delivery.id,
               "resolve",
               1,
               pins(delivery, %{
                 "parent_step_id" => failed_impl.id,
                 "source_step_id" => failed_impl.id,
                 "plan_step_id" => plan_step.id,
                 "workspace" => resolve_ws,
                 "candidate_commit" => @sha,
                 "feedback_hash" => @hash,
                 "input_hash" => @hash,
                 "model_profile" => %{"model" => "gpt-5.6-terra", "reasoning_effort" => "xhigh"},
                 "resolution_attempt" => 1
               })
             )

    assert resolve_step.input["model_profile"] == %{
             "model" => "gpt-5.6-terra",
             "reasoning_effort" => "xhigh"
           }
  end

  # Compile-time atoms so authorize_agents! does not depend on module load order.
  @agent_atoms %{
    "cursor" => :cursor,
    "opencode" => :opencode,
    "claude" => :claude,
    "codex" => :codex
  }

  defp authorize_agents!(ids) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      for id <- ids do
        atom = Map.fetch!(@agent_atoms, id)

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
    profile =
      if is_nil(model_name), do: nil, else: %{"model" => model_name, "reasoning_effort" => "high"}

    finish(
      d,
      "plan",
      0,
      %{
        "workspace" => d.intent,
        "input_hash" => @hash,
        "model_profile" => profile
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
