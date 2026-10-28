defmodule Boss.DeliverySchedulingTest do
  use Boss.DataCase
  alias Boss.{Deliveries, Projects, Tasks}
  alias Boss.Deliveries.Scheduling
  @base String.duplicate("a", 40)

  setup do
    project =
      Repo.insert!(%Projects.Project{
        name: "Scheduling",
        root_path: "/schedule",
        git_common_dir: "/schedule/.git",
        specs_path: "/schedule/specs",
        base_branch: "main"
      })

    %{project: project}
  end

  test "capacity is explicit, versioned, bounded and mirrored by SQLite admission", c do
    assert {:ok, %{max_parallel_tasks: 2, version: 0}} = Scheduling.get()
    assert {:ok, %{max_parallel_tasks: 1, version: 1}} = Scheduling.update(0, 1, 0)
    first = planned(c.project, "one", nil)
    assert {:error, :busy} = admit(c.project, task(c.project, "two"))
    assert {:error, _} = raw_delivery(c.project, task(c.project, "raw"))
    assert {:error, :stale_settings} = Scheduling.update(0, 3, 0)

    for invalid <- [0, 4, "2", nil, 1.0],
        do: assert({:error, :invalid_capacity} = Scheduling.update(1, invalid, 0))

    assert {:ok, %{max_parallel_tasks: 3, version: 2}} = Scheduling.update(1, 3, 0)
    second = planned(c.project, "three", nil)
    _third = planned(c.project, "four", nil)
    assert {:error, :workers_active} = Scheduling.update(2, 2, 0)

    assert {:error, _} =
             Repo.query("UPDATE delivery_settings SET max_parallel_tasks=2,version=version+1")

    assert {:error, _} = Repo.query("DELETE FROM delivery_settings")
    assert {:error, _} = Repo.query("INSERT OR REPLACE INTO delivery_settings VALUES(1,1,0)")

    assert {:error, _} =
             Repo.query("UPDATE delivery_settings SET max_parallel_tasks=4,version=version+1")

    assert {:error, _} = Repo.query("UPDATE delivery_settings SET version=version+2")
    assert {:ok, _} = cancel(first.delivery.id)
    assert {:error, :workers_active} = Scheduling.update(2, 2, 3)
    assert {:ok, %{max_parallel_tasks: 2, version: 3}} = Scheduling.update(2, 2, 2)
    assert {:ok, _} = Deliveries.interrupt(second.delivery.id)
    assert {:error, :busy} = admit(c.project, task(c.project, "unknown"))
  end

  test "only acquired scopes serialize, with stable waiting state and terminal release", c do
    first = planned(c.project, "one", scope("lib", "directory"))
    second = planned(c.project, "two", scope("lib/tasks.ex"))
    assert Scheduling.blockers(first.delivery) == []
    assert Scheduling.blockers(second.delivery) == []
    assert {:ok, implementation} = implement(first)

    for step <- [first.plan, implementation] do
      assert {:error, error} =
               Repo.query(
                 "INSERT OR REPLACE INTO delivery_steps(id,delivery_id,number,kind,cycle,input,receipt,status,inserted_at,updated_at) SELECT id,delivery_id,number,kind,cycle,input,'{}','running',inserted_at,updated_at FROM delivery_steps WHERE id=?",
                 [step.id]
               )

      assert Exception.message(error) =~ "delivery evidence cannot be replaced"
    end

    assert {:error, error} =
             Repo.query(
               "INSERT OR REPLACE INTO delivery_steps(id,delivery_id,number,kind,cycle,input,receipt,status,inserted_at,updated_at) SELECT ?,delivery_id,99,'review',1,'{}','{}','running',inserted_at,updated_at FROM delivery_steps WHERE id=?",
               [Ecto.UUID.generate(), implementation.id]
             )

    assert Exception.message(error) =~ "delivery evidence cannot be replaced"
    assert Scheduling.blockers(second.delivery) == [first.delivery.id]
    saved = Deliveries.get(c.project.id, second.delivery.id)
    task = Tasks.get_task!(second.delivery.task_id)
    for _ <- 1..3, do: assert({:error, :scope_conflict} = implement(second))
    assert Deliveries.get(c.project.id, second.delivery.id) == saved
    assert Tasks.get_task!(second.delivery.task_id) == task
    assert length(Deliveries.steps(second.delivery.id)) == 1
    assert_raw_scope_refusal(second)

    assert {:ok, _} =
             Deliveries.finish_step(
               implementation.id,
               receipt(%{"workspace" => first.delivery.intent, "head_commit" => @base})
             )

    assert {:error, :scope_conflict} = implement(second)
    assert {:ok, _} = cancel(first.delivery.id)
    assert Scheduling.blockers(second.delivery) == []
    assert {:ok, _} = implement(second)
  end

  test "SQLite overlap respects segment boundaries, case, Unicode, unknown and repositories", c do
    pairs = [
      {scope("src/a.ex"), scope("src/a.ex"), true},
      {scope("src/a.ex"), scope("SRC/A.ex"), true},
      {scope("src", "directory"), scope("src/a.ex"), true},
      {scope("src"), scope("src/child"), true},
      {scope("src"), scope("src2/a.ex"), false},
      {scope("lib/é.ex"), scope("other.ex"), true},
      {scope("lib/é.ex"), nil, false},
      {nil, scope("lib/a.ex"), false}
    ]

    for {{left, right, blocked}, n} <- Enum.with_index(pairs) do
      first = planned(c.project, "left#{n}", left)
      second = planned(c.project, "right#{n}", right)
      assert {:ok, _} = implement(first)
      assert Scheduling.blockers(second.delivery) != [] == blocked

      if blocked do
        assert {:error, :scope_conflict} = implement(second)
        assert_raw_scope_refusal(second)
      else
        assert {:ok, _} = implement(second)
      end

      assert {:ok, _} = cancel(first.delivery.id)
      assert {:ok, _} = cancel(second.delivery.id)
    end

    other =
      Repo.insert!(%Projects.Project{
        name: "Other",
        root_path: "/other",
        git_common_dir: "/other/.git",
        specs_path: "/other/specs",
        base_branch: "main"
      })

    first = planned(c.project, "own", scope("lib"))
    second = planned(other, "other", scope("lib"))
    assert {:ok, _} = implement(first)
    assert {:ok, _} = implement(second)
  end

  test "unknown cleanup blocks a first write even with unknown or disjoint predicted scopes", c do
    first = planned(c.project, "one", nil)
    second = planned(c.project, "two", scope("lib/file"))
    assert {:ok, _} = implement(first)
    assert {:ok, _} = Deliveries.interrupt(first.delivery.id)
    assert Scheduling.blockers(second.delivery) == []
    assert {:error, :execution_quarantined} = implement(second)
    assert_raw_scope_refusal(second)
  end

  test "quarantine also blocks disjoint predictions in another repository", c do
    other =
      Repo.insert!(%Projects.Project{
        name: "Other",
        root_path: "/other",
        git_common_dir: "/other/.git",
        specs_path: "/other/specs",
        base_branch: "main"
      })

    first = planned(c.project, "one", scope("lib"))
    second = planned(other, "two", scope("different/file"))
    assert {:ok, _} = implement(first)
    assert {:ok, _} = Deliveries.interrupt(first.delivery.id)
    assert Scheduling.blockers(second.delivery) == []
    assert {:error, :execution_quarantined} = implement(second)
    assert_raw_scope_refusal(second)
  end

  test "duplicate JSON keys cannot hide a predicted scope from SQL admission", c do
    data = planned_start(c.project, "duplicates")
    suffix = ~s(,"summary":"Plan","steps":["Implement"],"acceptance":["Pass"]})
    report = ~s({"file_scopes":null,"file_scopes":[{"path":"lib","kind":"directory"}]) <> suffix
    received = JSON.encode!(receipt(%{"report" => nil}))

    for ambiguous <- [
          String.replace(received, ~s("report":null), ~s("report":) <> report),
          String.replace(
            received,
            ~s("report":null),
            ~s("report":null,"report":) <> JSON.encode!(plan())
          )
        ] do
      assert {:error, _} =
               Repo.query("UPDATE delivery_steps SET status='finished',receipt=? WHERE id=?", [
                 ambiguous,
                 data.plan.id
               ])
    end

    assert Repo.get!(Boss.Deliveries.Step, data.plan.id).status == "running"
  end

  test "invalid typed predictions cannot be persisted through context or raw SQL", c do
    for {scopes, n} <-
          Enum.with_index([
            [],
            %{},
            "lib",
            [%{"path" => "lib"}],
            scope("../lib"),
            scope("/tmp/file"),
            scope("lib//a"),
            scope(".GIT/config"),
            scope("lib/*"),
            scope("a\\b"),
            scope("a" <> <<0>>),
            scope("a" <> <<31>>),
            scope("a" <> <<127>>),
            scope("a") ++ scope("a")
          ]) do
      data = planned_start(c.project, "invalid#{n}")
      report = Map.put(plan(), "file_scopes", scopes)
      received = receipt(%{"report" => report})
      assert {:error, :invalid_receipt} = Deliveries.finish_step(data.plan.id, received)

      assert {:error, _} =
               Repo.query("UPDATE delivery_steps SET status='finished',receipt=? WHERE id=?", [
                 JSON.encode!(received),
                 data.plan.id
               ])

      assert {:ok, _} = cancel(data.delivery.id)
    end

    legacy = planned_start(c.project, "legacy")
    assert {:ok, _} = Deliveries.finish_step(legacy.plan.id, receipt(%{"report" => plan()}))
    assert {:ok, _} = implement(legacy)
  end

  defp cancel(id) do
    for step <- Deliveries.steps(id), step.status == "running" do
      assert {:ok, _} =
               Deliveries.finish_step(step.id, %{
                 "status" => "cancelled",
                 "cleanup" => "not_started"
               })
    end

    Deliveries.complete(id, "cancelled")
  end

  defp task(project, name) do
    {:ok, %{task: task}} =
      Projects.record_spec(project.id, %{
        relative_path: name <> ".md",
        title: name,
        original_text: "# " <> name
      })

    task
  end

  defp admit(project, task),
    do: Deliveries.admit(project.id, task.id, Ecto.UUID.generate(), "true")

  defp planned_start(project, name) do
    {:ok, {:new, d}} = admit(project, task(project, name))

    intent = %{
      "run_id" => d.id,
      "project_id" => to_string(project.id),
      "repo_path" => project.root_path,
      "git_common_dir" => project.git_common_dir,
      "base_branch" => "main",
      "base_commit" => @base
    }

    {:ok, d} = Deliveries.set_intent(d.id, intent)
    {:ok, p} = Deliveries.begin_step(d.id, "plan", 0, %{"workspace" => intent})
    %{delivery: d, plan: p}
  end

  defp planned(project, name, scopes) do
    data = planned_start(project, name)

    {:ok, p} =
      Deliveries.finish_step(
        data.plan.id,
        receipt(%{"report" => Map.put(plan(), "file_scopes", scopes)})
      )

    %{data | plan: p}
  end

  defp plan, do: %{"summary" => "Plan", "steps" => ["Implement"], "acceptance" => ["Pass"]}
  defp scope(path, kind \\ "file"), do: [%{"path" => path, "kind" => kind}]

  defp implement(data),
    do: Deliveries.begin_step(data.delivery.id, "implement", 1, %{"plan_step_id" => data.plan.id})

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

  defp assert_raw_scope_refusal(data) do
    assert {:error, error} = raw_implement(data)
    assert Exception.message(error) =~ "predicted file scope is held"
  end

  defp raw_implement(data),
    do:
      Repo.query(
        "INSERT INTO delivery_steps(id,delivery_id,number,kind,cycle,input,receipt,status,inserted_at,updated_at) VALUES(?,?,2,'implement',1,?,'{}','running',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",
        [
          Ecto.UUID.generate(),
          data.delivery.id,
          JSON.encode!(%{"plan_step_id" => data.plan.id})
        ]
      )

  defp raw_delivery(project, task) do
    {:ok, config, hash} = Boss.Checks.Command.parse("true")

    Repo.query(
      "INSERT INTO deliveries(id,project_id,task_id,spec_revision_id,command_id,admitted_version,task_version,check_config,config_hash,inserted_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)",
      [
        Ecto.UUID.generate(),
        project.id,
        task.id,
        task.spec_revision_id,
        Ecto.UUID.generate(),
        task.state_version,
        task.state_version,
        JSON.encode!(config),
        hash
      ]
    )
  end
end
