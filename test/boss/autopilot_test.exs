defmodule Boss.AutopilotTest do
  use Boss.DataCase
  alias Boss.{Deliveries, Projects, Runs, Tasks}
  alias Boss.Deliveries.{Autopilot, AutopilotBatch, AutopilotItem, Queue, Request}

  setup do
    project =
      Repo.insert!(%Projects.Project{
        name: "Autopilot",
        root_path: "/autopilot",
        git_common_dir: "/autopilot/.git",
        specs_path: "/autopilot/specs",
        base_branch: "main"
      })

    tasks = for n <- 1..3, do: task(project.id, "task#{n}")
    %{project: project, tasks: tasks}
  end

  test "whole current Backlog is frozen; replay precedes later imports and admission", c do
    command = Ecto.UUID.generate()
    ids = Enum.map(c.tasks, & &1.id)
    assert {:ok, batch} = Autopilot.admit(c.project.id, command, ids, "true", "claude")
    assert batch.status == "running" and batch.version == 0
    assert Enum.map(batch.items, & &1.task_id) == ids

    assert Enum.map(batch.items, & &1.spec_revision_id) ==
             Enum.map(c.tasks, & &1.spec_revision_id)

    assert Enum.all?(c.tasks, &(Tasks.get_task!(&1.id).state == "new"))
    task(c.project.id, "later")
    assert {:ok, ^batch} = Autopilot.admit(c.project.id, command, ids, "true", "claude", true)

    assert {:error, :idempotency_conflict} =
             Autopilot.admit(c.project.id, command, Enum.reverse(ids), "true", "claude")

    assert {:error, :idempotency_conflict} =
             Autopilot.admit(c.project.id, command, ids, "false", "claude")

    assert {:error, :idempotency_conflict} =
             Autopilot.admit(c.project.id, command, ids, "true", "codex")

    assert {:ok, nil} = Autopilot.current(c.project.id + 1)
  end

  test "partial or stale selection is rejected atomically and does not include Failed", c do
    [first | rest] = c.tasks
    assert {:error, :backlog_changed} = admit(c, rest)
    assert Repo.aggregate(Request, :count) == 0
    Repo.update_all(from(t in Tasks.Task, where: t.id == ^first.id), set: [state: "failed"])
    assert {:error, :backlog_changed} = admit(c, c.tasks)
    assert {:ok, batch} = admit(c, rest)
    assert length(batch.items) == 2
    assert Enum.all?(batch.items, &(&1.task_id != first.id))
  end

  test "more than 32 frozen tasks keep ordinary queue capacity separate", c do
    tasks = c.tasks ++ for(n <- 4..46, do: task(c.project.id, "task#{n}"))
    assert {:ok, batch} = admit(c, tasks)
    assert length(batch.items) == 46
    assert Queue.queued() == []

    for n <- 1..32 do
      extra = task(c.project.id, "extra#{n}")
      assert {:ok, _} = Queue.admit(c.project.id, extra.id, Ecto.UUID.generate(), "true", "codex")
    end

    extra = task(c.project.id, "overflow")

    assert {:error, :queue_full} =
             Queue.admit(c.project.id, extra.id, Ecto.UUID.generate(), "true", "codex")
  end

  test "a full ordinary queue in another project does not consume frozen batch capacity", c do
    other =
      Repo.insert!(%Projects.Project{
        name: "Other",
        root_path: "/other",
        git_common_dir: "/other/.git",
        specs_path: "/other/specs",
        base_branch: "main"
      })

    for n <- 1..32 do
      task = task(other.id, "queued#{n}")
      assert {:ok, _} = Queue.admit(other.id, task.id, Ecto.UUID.generate(), "true", "codex")
    end

    assert {:ok, batch} = admit(c, c.tasks)
    assert length(batch.items) == 3
    assert length(Queue.queued()) == 32
  end

  test "pause and resume use version CAS; Stop is terminal for the selected batch", c do
    {:ok, batch} = admit(c, c.tasks)
    assert {:ok, paused} = Autopilot.pause(c.project.id, batch.id, 0)
    assert paused.status == "paused" and paused.version == 1
    assert {:ok, ^paused} = Autopilot.pause(c.project.id, batch.id, 0)
    assert {:ok, resumed} = Autopilot.resume_saved(c.project.id, batch.id, 1)
    assert resumed.version == 2
    assert {:error, :stale_version} = Autopilot.pause(c.project.id, batch.id, 0)
    assert {:error, :stale_version} = Autopilot.resume_saved(c.project.id, batch.id, 0)
    assert {:ok, stopped} = Autopilot.cancel(c.project.id, batch.id, 0)
    assert stopped.status == "cancelled"
    assert Enum.all?(stopped.items, &(&1.request_status == "cancelled"))
    assert {:ok, ^stopped} = Autopilot.cancel(c.project.id, batch.id, 0)

    assert {:error, :request_finished} =
             Autopilot.resume_saved(c.project.id, batch.id, stopped.version)

    assert {:ok, ^stopped} =
             Autopilot.admit(c.project.id, batch.command_id, batch.task_ids, "true", "codex")
  end

  test "queue controls cannot resume one member or bypass sequential admission", c do
    {:ok, batch} = admit(c, c.tasks)
    [a, b | _] = batch.items
    assert {:error, :autopilot_owned} = Queue.cancel(c.project.id, a.request_id)
    assert {:error, :autopilot_owned} = Queue.resume_saved(c.project.id, a.request_id)
    assert {:ok, {:started, _, first}} = Queue.claim(a.request_id)
    assert {:ok, {:existing, _, ^first}} = Queue.claim(a.request_id)
    assert {:error, :busy} = Queue.claim(b.request_id)

    assert {:error, :task_queued} =
             Deliveries.admit(c.project.id, b.task_id, Ecto.UUID.generate(), "true")

    extra = task(c.project.id, "extra")
    assert {:error, :busy} = Runs.admit(c.project.id, extra.id, Ecto.UUID.generate())

    assert {:error, :busy} =
             Deliveries.admit(c.project.id, extra.id, Ecto.UUID.generate(), "true")

    assert {:ok, _} = Deliveries.complete(first.id, "failed", "Fixture failure")
    assert {:ok, {:changed, blocked}} = Autopilot.advance()
    assert blocked.status == "blocked"
    assert Enum.count(blocked.items, &(&1.request_status == "cancelled")) == 2
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
  end

  test "raw SQL cannot replace authorization, change pins, erase items or fabricate completion",
       c do
    {:ok, batch} = admit(c, c.tasks)
    item = hd(batch.items)

    for sql <- [
          "UPDATE autopilots SET reviewer='claude',version=version+1 WHERE id=?",
          "UPDATE autopilots SET status='completed',version=version+1 WHERE id=?",
          "DELETE FROM autopilots WHERE id=?",
          "INSERT OR REPLACE INTO autopilots SELECT * FROM autopilots WHERE id=?"
        ] do
      assert {:error, error} = Repo.query(sql, [batch.id])
      assert Exception.message(error) =~ "autopilot"
    end

    for sql <- [
          "UPDATE autopilot_items SET integration_command_id='00000000-0000-0000-0000-000000000000' WHERE request_id=?",
          "DELETE FROM autopilot_items WHERE request_id=?",
          "INSERT OR REPLACE INTO autopilot_items SELECT * FROM autopilot_items WHERE request_id=?",
          "INSERT OR REPLACE INTO delivery_requests SELECT * FROM delivery_requests WHERE id=?"
        ] do
      assert {:error, _} = Repo.query(sql, [item.request_id])
    end
  end

  test "a partially inserted authorization cannot acquire a delivery even through SQL", c do
    {:ok, config, hash} = Boss.Checks.Command.parse("true")

    batch =
      Repo.insert!(%AutopilotBatch{
        id: Ecto.UUID.generate(),
        project_id: c.project.id,
        command_id: Ecto.UUID.generate(),
        task_ids: Enum.map(c.tasks, & &1.id),
        check_config: config,
        config_hash: hash,
        reviewer: "codex"
      })

    first = hd(c.tasks)
    {:ok, request} = Queue.admit(c.project.id, first.id, Ecto.UUID.generate(), "true", "codex")

    Repo.insert!(%AutopilotItem{
      request_id: request.id,
      autopilot_id: batch.id,
      position: 0,
      integration_command_id: Ecto.UUID.generate()
    })

    assert {:error, :busy} = Queue.claim(request.id)

    assert {:error, error} =
             Repo.query(
               """
               INSERT INTO deliveries(id,project_id,task_id,spec_revision_id,command_id,admitted_version,task_version,check_config,config_hash,reviewer,inserted_at,updated_at)
               VALUES(?,?,?,?,?,?,?,?,?,?,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)
               """,
               [
                 Ecto.UUID.generate(),
                 c.project.id,
                 first.id,
                 first.spec_revision_id,
                 request.command_id,
                 first.state_version,
                 first.state_version,
                 JSON.encode!(config),
                 hash,
                 "codex"
               ]
             )

    assert Exception.message(error) =~ "autopilot sequence unavailable"
    assert Repo.aggregate(Deliveries.Delivery, :count) == 0
  end

  test "Restart pauses authorization and retained requests without resetting inputs", c do
    {:ok, batch} = admit(c, c.tasks)
    assert {:ok, _} = Queue.pause()
    assert {:ok, [_]} = Autopilot.pause_on_restart()
    {:ok, paused} = Autopilot.current(c.project.id)
    assert paused.status == "paused" and paused.version == 1
    assert Enum.all?(paused.items, &(&1.request_status == "paused"))
    assert {:error, :request_unavailable} = Queue.claim(hd(paused.items).request_id)
    assert {:ok, resumed} = Autopilot.resume_saved(c.project.id, batch.id, paused.version)
    assert resumed.task_ids == batch.task_ids
    assert resumed.check_config == batch.check_config
    assert Enum.all?(resumed.items, &(&1.request_status == "queued"))
  end

  defp admit(c, tasks),
    do:
      Autopilot.admit(
        c.project.id,
        Ecto.UUID.generate(),
        Enum.map(tasks, & &1.id),
        "true",
        "codex"
      )

  defp task(project, name) do
    {:ok, %{task: task}} =
      Projects.record_spec(project, %{
        relative_path: name <> ".md",
        title: name,
        original_text: "# " <> name
      })

    task
  end

end
