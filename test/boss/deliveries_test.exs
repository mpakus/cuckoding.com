defmodule Boss.DeliveriesTest do
  use Boss.DataCase
  alias Boss.{Deliveries, Projects, Runs, Tasks}
  @base String.duplicate("a", 40)
  @candidate String.duplicate("b", 40)
  @hash String.duplicate("c", 64)

  setup do
    project =
      Repo.insert!(%Projects.Project{
        name: "Delivery",
        root_path: "/delivery",
        git_common_dir: "/delivery/.git",
        specs_path: "/delivery/specs",
        base_branch: "main"
      })

    {:ok, record} =
      Projects.record_spec(project.id, %{
        relative_path: "one.md",
        title: "One",
        original_text: "# One"
      })

    %{project: project, task: record.task}
  end

  test "admission pins revision and command, owns gaps and replays without advancing task", c do
    id = Ecto.UUID.generate()
    assert {:ok, {:new, d}} = Deliveries.admit(c.project.id, c.task.id, id, "mix test")
    assert d.spec_revision_id == c.task.spec_revision_id
    assert Tasks.get_task!(c.task.id).state == "planning"

    assert {:ok, {:existing, ^d}} =
             Deliveries.admit(c.project.id, c.task.id, id, "mix test", true)

    assert {:error, :idempotency_conflict} =
             Deliveries.admit(c.project.id, c.task.id, id, "mix test other")

    assert {:error, :task_unavailable} = Runs.admit(c.project.id, c.task.id, Ecto.UUID.generate())
    assert {:error, :missing_evidence} = Deliveries.complete(d.id, "done")
    assert {:ok, cancelled} = Deliveries.complete(d.id, "cancelled", "Stopped")
    assert cancelled.status == "cancelled"
    assert Tasks.get_task!(c.task.id).state == "cancelled"

    assert {:ok, {:existing, ^cancelled}} =
             Deliveries.admit(c.project.id, c.task.id, id, "mix test")
  end

  test "manual runs block managed admission and foreign projects cannot borrow task", c do
    assert {:error, :not_found} =
             Deliveries.admit(c.project.id + 1, c.task.id, Ecto.UUID.generate(), "true")

    assert {:ok, {:new, _}} = Runs.admit(c.project.id, c.task.id, Ecto.UUID.generate())

    assert {:error, :busy} =
             Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true")

    assert Tasks.get_task!(c.task.id).state == "new"
  end

  test "workflow transitions cannot take caller-selected states or evidence", c do
    {:ok, {:new, d}} = Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true")

    assert {:error, :invalid_command} =
             Tasks.transition(c.task.id, %{
               command_id: "fake",
               expected_version: d.task_version,
               action: "delivery_progress",
               delivery_id: d.id
             })

    assert {:error, :invalid_command} =
             Tasks.transition(c.task.id, %{
               command_id: d.id <> ":fake",
               expected_version: d.task_version,
               action: "delivery_progress",
               delivery_id: d.id,
               state: "done"
             })

    assert {:error, :missing_evidence} = Deliveries.complete(d.id, "ready_to_merge")

    assert {:error, :busy} =
             Deliveries.admit_integration(c.project.id, d.id, Ecto.UUID.generate())
  end

  test "only the complete checked plan and explicit publication can produce Done", c do
    {d, plan, check} = checked(c)
    review(d, plan, check)
    assert {:ok, ready} = Deliveries.complete(d.id, "ready_to_merge")
    assert Tasks.get_task!(c.task.id).state == "ready_to_merge"
    assert {:error, :not_active} = Deliveries.complete(d.id, "done")
    command = Ecto.UUID.generate()
    assert {:ok, {:new, integrating}} = Deliveries.admit_integration(c.project.id, d.id, command)
    assert integrating.task_version > ready.task_version
    assert {:error, :missing_evidence} = Deliveries.complete(d.id, "done")

    intent = %{
      "delivery_id" => d.id,
      "base_commit" => @base,
      "candidate_commit" => @candidate,
      "repo_path" => c.project.root_path,
      "base_branch" => c.project.base_branch
    }

    assert {:error, :invalid_intent} =
             Deliveries.set_integration_intent(d.id, %{intent | "candidate_commit" => @base})

    assert {:ok, _} = Deliveries.set_integration_intent(d.id, intent)
    publish = stage(d, "publish", 1, %{"intent" => intent}, %{"candidate_commit" => @candidate})
    assert {:error, :missing_evidence} = Deliveries.complete(d.id, "done")

    input = %{
      "publish_step_id" => publish.id,
      "intent" => intent,
      "config_hash" => d.config_hash
    }

    assert {:error, :invalid_step} =
             Deliveries.begin_step(d.id, "post_check", 1, %{input | "config_hash" => @hash})

    stage(d, "post_check", 1, input, %{
      "candidate_commit" => @candidate,
      "output_complete" => true,
      "output_hash" => @hash
    })

    assert {:ok, done} = Deliveries.complete(d.id, "done")
    assert Tasks.get_task!(c.task.id).state == "done"
    assert {:ok, {:existing, ^done}} = Deliveries.admit_integration(c.project.id, d.id, command)

    assert {:ok, {:existing, ^done}} =
             Deliveries.admit(c.project.id, c.task.id, d.command_id, "true")

    assert {:error, :idempotency_conflict} =
             Deliveries.admit_integration(c.project.id, d.id, Ecto.UUID.generate())

    assert {:error, :not_active} = Deliveries.complete(d.id, "failed")
    events = Tasks.list_events(c.task.id)
    assert List.last(events).to_state == "done"
    assert Enum.count(events, &(&1.to_state == "ready_to_merge")) == 1
  end

  test "different candidate, configuration or plan criteria cannot borrow a passing check", c do
    {d, plan, check} = checked(c)
    input = review_input(d, plan, check)

    for invalid <- [
          %{input | "candidate_commit" => @base},
          %{input | "config_hash" => @hash},
          %{input | "original_base" => @candidate},
          %{input | "check_step_id" => Ecto.UUID.generate()}
        ] do
      assert {:error, :invalid_step} = Deliveries.begin_step(d.id, "review", 1, invalid)
    end

    review(d, plan, check, "Unrelated criterion")
    assert {:error, :missing_evidence} = Deliveries.complete(d.id, "ready_to_merge")
    refute Tasks.get_task!(c.task.id).state == "done"
  end

  test "task version drift blocks approval even with a matching review", c do
    {d, plan, check} = checked(c)
    review(d, plan, check)
    task = Tasks.get_task!(c.task.id)

    assert {:ok, _} =
             Tasks.transition(task.id, %{
               command_id: "external-cancel",
               expected_version: task.state_version,
               action: "cancel",
               reason: "User cancelled"
             })

    assert {:error, :stale_state} = Deliveries.complete(d.id, "ready_to_merge")
    assert {:ok, _} = Deliveries.complete(d.id, "cancelled")
    assert Tasks.get_task!(task.id).state == "cancelled"
  end

  test "fresh explicit start retires a stale approval without reusing its evidence", c do
    {d, plan, check} = checked(c)
    review(d, plan, check)
    {:ok, ready} = Deliveries.complete(d.id, "ready_to_merge")

    assert {:ok, _} =
             Tasks.transition(c.task.id, %{
               command_id: "cancel-approved",
               expected_version: ready.task_version,
               action: "cancel",
               reason: "Start again"
             })

    assert {:error, :stale_state} =
             Deliveries.admit_integration(c.project.id, d.id, Ecto.UUID.generate())

    assert {:ok, {:new, fresh}} =
             Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true")

    refute fresh.id == d.id
    assert Deliveries.get(c.project.id, d.id).status == "cancelled"
    assert Deliveries.steps(fresh.id) == []
    assert Tasks.get_task!(c.task.id).state == "planning"
    assert {:error, :missing_evidence} = Deliveries.complete(fresh.id, "done")
  end

  test "database refuses forged terminal state and immutable history updates", c do
    {d, _plan, check} = checked(c)

    for status <- ["ready_to_merge", "done"] do
      assert {:error, %Exqlite.Error{}} =
               Ecto.Adapters.SQL.query(
                 Repo,
                 "UPDATE deliveries SET status=?, cleanup='group_empty' WHERE id=?",
                 [status, d.id]
               )
    end

    assert {:error, %Exqlite.Error{}} =
             Ecto.Adapters.SQL.query(Repo, "UPDATE delivery_steps SET receipt='{}' WHERE id=?", [
               check.id
             ])

    assert {:error, %Exqlite.Error{}} =
             Ecto.Adapters.SQL.query(Repo, "DELETE FROM delivery_steps WHERE id=?", [check.id])

    assert {:error, %Exqlite.Error{}} =
             Ecto.Adapters.SQL.query(Repo, "UPDATE deliveries SET config_hash=? WHERE id=?", [
               @hash,
               d.id
             ])

    assert {:ok, _} = Deliveries.complete(d.id, "cancelled")

    assert {:error, %Exqlite.Error{}} =
             Ecto.Adapters.SQL.query(
               Repo,
               "UPDATE deliveries SET reason='overwritten' WHERE id=?",
               [d.id]
             )
  end

  test "inserted terminal deliveries and completed steps cannot bypass evidence producers", c do
    assert {:error, %Exqlite.Error{}} =
             Ecto.Adapters.SQL.query(
               Repo,
               """
               INSERT INTO deliveries(id, project_id, task_id, spec_revision_id, command_id,
                 admitted_version, task_version, check_config, config_hash, status, cleanup, inserted_at, updated_at)
               VALUES(?,?,?,?,?,0,0,'{}',?,'done','group_empty',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)
               """,
               [
                 Ecto.UUID.generate(),
                 c.project.id,
                 c.task.id,
                 c.task.spec_revision_id,
                 Ecto.UUID.generate(),
                 @hash
               ]
             )

    {:ok, {:new, d}} = Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true")

    assert {:error, %Exqlite.Error{}} =
             Ecto.Adapters.SQL.query(
               Repo,
               """
               INSERT INTO delivery_steps(id, delivery_id, number, kind, cycle, input, receipt, status, inserted_at, updated_at)
               VALUES(?,?,1,'plan',0,'{}','{"status":"finished","cleanup":"group_empty"}','finished',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)
               """,
               [Ecto.UUID.generate(), d.id]
             )

    assert Deliveries.steps(d.id) == []
    refute Tasks.get_task!(c.task.id).state == "done"
  end

  defp checked(c) do
    {:ok, {:new, d}} = Deliveries.admit(c.project.id, c.task.id, Ecto.UUID.generate(), "true")

    intent = %{
      "run_id" => d.id,
      "project_id" => to_string(c.project.id),
      "repo_path" => c.project.root_path,
      "git_common_dir" => c.project.git_common_dir,
      "base_branch" => c.project.base_branch,
      "base_commit" => @base
    }

    {:ok, d} = Deliveries.set_intent(d.id, intent)

    plan =
      stage(d, "plan", 0, %{"workspace" => intent}, %{
        "report" => %{
          "summary" => "Plan",
          "steps" => ["Implement"],
          "acceptance" => ["Saved criterion"]
        }
      })

    implementation =
      stage(d, "implement", 1, %{"plan_step_id" => plan.id}, %{
        "workspace" => intent,
        "head_commit" => @base
      })

    snapshot =
      stage(d, "snapshot", 1, %{"implementation_step_id" => implementation.id}, %{
        "workspace" => intent,
        "candidate_commit" => @candidate
      })

    check =
      stage(
        d,
        "check",
        1,
        %{
          "snapshot_step_id" => snapshot.id,
          "workspace" => intent,
          "candidate_commit" => @candidate,
          "config_hash" => d.config_hash
        },
        %{"output_complete" => true, "output_hash" => @hash}
      )

    {d, plan, check}
  end

  defp review_input(d, plan, check),
    do: %{
      "plan_step_id" => plan.id,
      "check_step_id" => check.id,
      "candidate_commit" => @candidate,
      "config_hash" => d.config_hash,
      "original_base" => @base,
      "input_hash" => @hash
    }

  defp review(d, plan, check, criterion \\ "Saved criterion") do
    stage(d, "review", 1, review_input(d, plan, check), %{
      "report" => %{
        "verdict" => "approved",
        "summary" => "Verified",
        "acceptance" => [
          %{"criterion" => criterion, "status" => "passed", "evidence" => "Checked"}
        ],
        "issues" => []
      }
    })
  end

  defp stage(d, kind, cycle, input, receipt) do
    assert {:ok, step} = Deliveries.begin_step(d.id, kind, cycle, input)

    assert {:ok, step} =
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
end
