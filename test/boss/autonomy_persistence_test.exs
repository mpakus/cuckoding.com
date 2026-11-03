defmodule Boss.AutonomyPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Deliveries, Projects, Repo}
  alias Boss.Deliveries.{Autopilot, AutopilotBatch, Queue, Request}
  @moduletag capture_log: true
  @sha String.duplicate("a", 40)
  @hash String.duplicate("b", 64)

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

    Ecto.Migrator.run(Repo, Application.app_dir(:boss, "priv/repo/migrations"), :up,
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

  defp delivery(c, version \\ 1) do
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
      "base_commit" => @sha
    }

    {:ok, d} = Deliveries.set_intent(d.id, intent)
    d
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
