defmodule Boss.AutopilotRecoveryTest do
  use Boss.DataCase
  alias Boss.{Deliveries, Projects, Tasks}
  alias Boss.Deliveries.{Autopilot, AutopilotBatch, AutopilotItem, Queue, Request}
  @hash String.duplicate("b", 64)

  setup do
    root = Path.join(System.tmp_dir!(), "boss-autopilot-recovery-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    File.mkdir!(Path.join(root, "specs"))

    for args <- [
          ["init", "-q", "-b", "main"],
          [
            "-c",
            "user.name=Fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-q",
            "--allow-empty",
            "-m",
            "base"
          ],
          ["switch", "-q", "-c", "observer"]
        ] do
      assert {_, 0} = System.cmd("git", ["-C", root | args], stderr_to_stdout: true)
    end

    {:ok, project} =
      Projects.create_project(%{root_path: root, specs_path: "specs", base_branch: "main"})

    tasks = for name <- ~w(one two three), do: task(project, name)
    %{project: project, tasks: tasks}
  end

  test "a fresh Start retries an all-Failed selection without changing earlier evidence", c do
    failures =
      for task <- c.tasks do
        {:ok, {:new, delivery}} =
          Deliveries.admit(c.project.id, task.id, Ecto.UUID.generate(), "true")

        {:ok, failed} = Deliveries.complete(delivery.id, "failed", "Fixture task failure")
        failed
      end

    tasks = Enum.map(c.tasks, &Tasks.get_task!(&1.id))
    assert Enum.all?(tasks, &(&1.state == "failed"))
    [first | _] = tasks

    {:ok, changed} =
      Projects.record_spec(c.project.id, %{
        relative_path: "one.md",
        explicit_id: "one",
        title: "Changed source",
        original_text: "# Changed source"
      })

    refute changed.revision.id == first.spec_revision_id

    assert {:ok, batch} =
             Autopilot.admit(
               c.project.id,
               Ecto.UUID.generate(),
               Enum.map(tasks, & &1.id),
               "true",
               "codex"
             )

    assert batch.routing_version == 2
    assert Enum.map(batch.items, & &1.task_id) == Enum.map(tasks, & &1.id)
    assert Enum.map(failures, &Repo.get!(Deliveries.Delivery, &1.id)) == failures
    assert Enum.map(tasks, &Tasks.get_task!(&1.id)) == tasks
    assert Repo.aggregate(Deliveries.Delivery, :count) == 3

    for item <- batch.items do
      request = Repo.get!(Request, item.request_id)
      task = Enum.find(tasks, &(&1.id == item.task_id))
      assert request.spec_revision_id == task.spec_revision_id
      assert request.admitted_version == task.state_version
    end
  end

  for code <-
        ~w(catalog_unavailable catalog_invalid catalog_insufficient_models codex_unavailable models_exhausted provider_auth provider_rate_limit provider_schema provider_transport) do
    test "shared #{code} failure leaves the other two tasks untouched", c do
      {:ok, batch} =
        Autopilot.admit(
          c.project.id,
          Ecto.UUID.generate(),
          Enum.map(c.tasks, & &1.id),
          "true",
          "codex"
        )

      [first, second | _] = batch.items
      {:ok, {:started, _, delivery}} = Queue.claim(first.request_id)

      {:ok, failed} =
        Deliveries.complete(delivery.id, "failed", "A saved structured failure", unquote(code))

      assert {:error, :busy} = Queue.claim(second.request_id)
      assert {:ok, {:changed, stopped}} = Autopilot.advance()
      assert stopped.status == "blocked"
      assert stopped.reason =~ "did not start another task"
      assert Enum.map(c.tasks, &Tasks.get_task!(&1.id).state) == ~w(failed new new)
      assert Enum.map(stopped.items, & &1.request_status) == ~w(started cancelled cancelled)
      assert Repo.aggregate(Deliveries.Delivery, :count) == 1
      assert Repo.get!(Deliveries.Delivery, delivery.id) == failed
    end
  end

  for {exit_code, error_class} <- [{1, nil}, {0, "unknown"}] do
    test "two strong startup failures (#{exit_code}/#{error_class}) stop before the next task",
         c do
      {delivery, second} =
        startup_failures(c, %{
          "exit_code" => unquote(exit_code),
          "summary" => %{"error_class" => unquote(error_class)}
        })

      assert {:error, :busy} = Queue.claim(second.request_id)
      assert {:ok, {:changed, stopped}} = Autopilot.advance()
      assert stopped.status == "blocked"
      assert stopped.reason =~ "Two catalogued models could not start"
      assert Enum.map(c.tasks, &Tasks.get_task!(&1.id).state) == ~w(failed new new)
      assert Repo.aggregate(Deliveries.Delivery, :count) == 1
      assert Repo.get!(Deliveries.Delivery, delivery.id) == delivery
    end
  end

  test "invalid task reports across two models do not trip the shared startup circuit", c do
    {delivery, second} = startup_failures(c, %{"exit_code" => 0, "outcome" => "invalid_report"})
    assert {:ok, {:launch, :deliver, next, _}} = Autopilot.advance()
    assert next.task_id == second.task_id
    assert Repo.get!(Deliveries.Delivery, delivery.id) == delivery
    assert Enum.map(c.tasks, &Tasks.get_task!(&1.id).state) == ~w(failed planning new)
  end

  test "task-specific failure continues independent work even when its prose names shared errors",
       c do
    {:ok, batch} =
      Autopilot.admit(
        c.project.id,
        Ecto.UUID.generate(),
        Enum.map(c.tasks, & &1.id),
        "true",
        "codex"
      )

    [first, second | _] = batch.items
    {:ok, {:started, _, delivery}} = Queue.claim(first.request_id)

    {:ok, failed} =
      Deliveries.complete(delivery.id, "failed", "models_exhausted provider_auth catalog_invalid")

    assert {:ok, {:launch, :deliver, next, batch_id}} = Autopilot.advance()
    assert batch_id == batch.id
    assert next.task_id == second.task_id
    assert Enum.map(c.tasks, &Tasks.get_task!(&1.id).state) == ~w(failed planning new)
    assert Repo.get!(Deliveries.Delivery, delivery.id) == failed
    assert Repo.aggregate(Deliveries.Delivery, :count) == 2
  end

  test "fresh recovery snapshots retain dependency gates and do not resume the old batch", c do
    old = legacy_batch(c)
    [first | _] = old.items
    {:ok, {:started, _, delivery}} = Queue.claim(first.request_id)
    {:ok, _} = Deliveries.complete(delivery.id, "failed", "Task-specific fixture failure")
    {:ok, stopped} = Autopilot.cancel(c.project.id, old.id, old.version)
    requests = for item <- stopped.items, do: Repo.get!(Request, item.request_id)

    dependent =
      task(c.project, "dependent", "---\nid: dependent\ndepends_on: [one]\n---\n# Dependent")

    {:ok, _} =
      Tasks.transition(dependent.id, %{
        action: "block",
        expected_version: 0,
        command_id: Ecto.UUID.generate(),
        reason: "Requires the first task"
      })

    ids = [dependent.id | Enum.map(c.tasks, & &1.id)]
    {:ok, fresh} = Autopilot.admit(c.project.id, Ecto.UUID.generate(), ids, "true", "codex")
    refute fresh.id == stopped.id
    assert fresh.routing_version == 2
    assert stopped.routing_version == 1
    refute Enum.any?(fresh.items, fn item -> Enum.any?(requests, &(&1.id == item.request_id)) end)
    [waiting | _] = fresh.items
    assert {:error, {:dependencies_blocked, _}} = Queue.claim(waiting.request_id)
    assert {:ok, {:launch, :deliver, retried, _}} = Autopilot.advance()
    assert retried.task_id == first.task_id
    assert Tasks.get_task!(dependent.id).state == "blocked"
    assert Repo.get!(Request, waiting.request_id).status == "queued"

    assert {:ok, ^stopped} =
             Autopilot.admit(c.project.id, old.command_id, old.task_ids, "true", "codex", true)

    assert Enum.map(requests, &Repo.get!(Request, &1.id)) == requests
  end

  test "cancelled and unknown-cleanup tasks are excluded without clearing the global gate", c do
    [cancelled, interrupted, remaining] = c.tasks

    {:ok, _} =
      Tasks.transition(cancelled.id, %{
        action: "cancel",
        expected_version: 0,
        command_id: Ecto.UUID.generate(),
        reason: "Owner stopped this task"
      })

    {:ok, {:new, delivery}} =
      Deliveries.admit(c.project.id, interrupted.id, Ecto.UUID.generate(), "true")

    {:ok, _} = Deliveries.interrupt(delivery.id)
    assert {:ok, [id]} = Autopilot.selection(c.project.id)
    assert id == remaining.id

    assert {:error, :busy} =
             Autopilot.admit(c.project.id, Ecto.UUID.generate(), [id], "true", "codex")

    assert Repo.aggregate(AutopilotBatch, :count) == 0
    assert Tasks.get_task!(cancelled.id).state == "cancelled"
    assert Repo.get!(Deliveries.Delivery, delivery.id).cleanup == "unknown"
  end

  test "legacy model-route exhaustion prevents another selected task from being claimed", c do
    batch = legacy_batch(c)
    [first, second | _] = batch.items
    {:ok, {:started, _, delivery}} = Queue.claim(first.request_id)
    {:ok, workspace} = Boss.Agents.Workspace.plan(c.project, delivery.id)
    workspace = Map.new(workspace, fn {key, value} -> {Atom.to_string(key), value} end)
    {:ok, delivery} = Deliveries.set_intent(delivery.id, workspace)

    plan = failed_step(delivery, "plan", %{"workspace" => delivery.intent})

    failed_step(delivery, "resolve", %{
      "parent_step_id" => plan.id,
      "source_step_id" => plan.id,
      "plan_step_id" => plan.id,
      "workspace" => delivery.intent,
      "candidate_commit" => delivery.intent["base_commit"],
      "config_hash" => delivery.config_hash,
      "spec_revision_id" => delivery.spec_revision_id,
      "input_hash" => @hash,
      "feedback_hash" => @hash,
      "resolution_attempt" => 1
    })

    {:ok, failed} = Deliveries.complete(delivery.id, "failed", "An unrelated human-readable note")
    assert {:error, :models_exhausted} = Deliveries.model_profile(failed, :plan, 0)
    assert {:error, :busy} = Queue.claim(second.request_id)
    assert {:ok, {:changed, stopped}} = Autopilot.advance()
    assert stopped.status == "blocked"
    assert stopped.reason =~ "model routes"
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
    assert Enum.map(c.tasks, &Tasks.get_task!(&1.id).state) == ~w(failed new new)
    assert Enum.map(stopped.items, & &1.request_status) == ~w(started cancelled cancelled)
    assert Repo.get!(Deliveries.Delivery, delivery.id) == failed
  end

  defp task(project, name, source \\ nil) do
    {:ok, saved} =
      Projects.record_spec(project.id, %{
        relative_path: name <> ".md",
        explicit_id: name,
        title: name,
        original_text: source || "# " <> name
      })

    saved.task
  end

  defp legacy_batch(c) do
    {:ok, config, hash} = Boss.Checks.Command.parse("true")

    batch =
      Repo.insert!(%AutopilotBatch{
        id: Ecto.UUID.generate(),
        project_id: c.project.id,
        command_id: Ecto.UUID.generate(),
        task_ids: Enum.map(c.tasks, & &1.id),
        check_config: config,
        config_hash: hash,
        reviewer: "codex",
        autonomy_version: 1
      })

    for {task, position} <- Enum.with_index(c.tasks) do
      {:ok, request} =
        Queue.admit(c.project.id, task.id, Ecto.UUID.generate(), "true", "codex", 1, 1)

      Repo.insert!(%AutopilotItem{
        request_id: request.id,
        autopilot_id: batch.id,
        position: position,
        integration_command_id: Ecto.UUID.generate()
      })
    end

    {:ok, saved} = Autopilot.current(c.project.id)
    saved
  end

  defp startup_failures(c, receipt) do
    {:ok, batch} =
      Autopilot.admit(
        c.project.id,
        Ecto.UUID.generate(),
        Enum.map(c.tasks, & &1.id),
        "true",
        "codex"
      )

    [first, second | _] = batch.items
    {:ok, {:started, _, delivery}} = Queue.claim(first.request_id)
    {:ok, delivery} = Deliveries.set_model_catalog(delivery.id, catalog())
    {:ok, workspace} = Boss.Agents.Workspace.plan(c.project, delivery.id)

    {:ok, delivery} =
      Deliveries.set_intent(
        delivery.id,
        Map.new(workspace, fn {k, v} -> {Atom.to_string(k), v} end)
      )

    plan = failed_step(delivery, "plan", %{"workspace" => delivery.intent}, receipt)

    resolution =
      failed_step(
        delivery,
        "resolve",
        %{
          "parent_step_id" => plan.id,
          "source_step_id" => plan.id,
          "plan_step_id" => plan.id,
          "workspace" => delivery.intent,
          "candidate_commit" => delivery.intent["base_commit"],
          "input_hash" => @hash,
          "feedback_hash" => @hash,
          "resolution_attempt" => 1
        },
        receipt
      )

    refute plan.input["model_profile"]["model"] == resolution.input["model_profile"]["model"]

    {:ok, failed} =
      Deliveries.complete(delivery.id, "failed", "Bounded startup attempts exhausted")

    {failed, second}
  end

  defp catalog do
    primary = %{"model" => "gpt-5.6-sol", "reasoning_effort" => "high"}
    resolver = %{"model" => "gpt-5.6-terra", "reasoning_effort" => "xhigh"}

    %{
      "version" => 2,
      "primary" => primary,
      "resolver" => resolver,
      "small" => nil,
      "fallbacks" => [%{primary | "reasoning_effort" => "xhigh"}, resolver]
    }
  end

  defp failed_step(delivery, kind, input, overrides \\ %{}) do
    input =
      Map.merge(
        %{"spec_revision_id" => delivery.spec_revision_id, "config_hash" => delivery.config_hash},
        input
      )

    {:ok, step} = Deliveries.begin_step(delivery.id, kind, 0, input)

    {:ok, saved} =
      Deliveries.finish_step(
        step.id,
        Map.merge(
          %{
            "status" => "failed",
            "cleanup" => "group_empty",
            "outcome" => "exited",
            "exit_kind" => "exit",
            "exit_code" => 1,
            "eof" => %{"stdout" => true, "stderr" => true},
            "candidate_commit" => delivery.intent["base_commit"]
          },
          overrides
        )
      )

    saved
  end
end
