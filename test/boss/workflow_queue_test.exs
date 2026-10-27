defmodule Boss.WorkflowQueueTest do
  use Boss.DataCase
  alias Boss.{Deliveries, Projects, Runs, Tasks}
  alias Boss.Deliveries.{Queue, Request}

  setup do
    project =
      Repo.insert!(%Projects.Project{
        name: "Queue",
        root_path: "/queue",
        git_common_dir: "/queue/.git",
        specs_path: "/queue/specs",
        base_branch: "main"
      })

    tasks = for n <- 1..4, do: task(project.id, "task#{n}")
    %{project: project, tasks: tasks}
  end

  test "queue pins input without changing task; replay precedes readiness and ownership", %{
    project: p,
    tasks: [task | _]
  } do
    command = Ecto.UUID.generate()
    assert {:ok, request} = Queue.admit(p.id, task.id, command, "true", "claude")
    assert request.spec_revision_id == task.spec_revision_id
    assert request.admitted_version == task.state_version
    assert Tasks.get_task!(task.id) == task
    assert {:ok, ^request} = Queue.admit(p.id, task.id, command, "true", "claude")

    assert {:error, :idempotency_conflict} =
             Queue.admit(p.id, task.id, command, "false", "claude")

    assert {:error, :idempotency_conflict} = Queue.admit(p.id, task.id, command, "true", "codex")

    assert {:error, :task_queued} =
             Queue.admit(p.id, task.id, Ecto.UUID.generate(), "true", "codex")

    assert {:error, :idempotency_conflict} =
             Deliveries.admit(p.id, task.id, command, "true", "claude", false)

    assert {:error, :task_queued} = Runs.admit(p.id, task.id, Ecto.UUID.generate())

    assert {:error, _} =
             Repo.query("UPDATE delivery_requests SET reviewer='codex' WHERE id=?", [request.id])

    assert {:error, _} = Repo.query("DELETE FROM delivery_requests WHERE id=?", [request.id])
    assert Queue.list(p.id + 1, task.id) == []
    assert {:error, :not_found} = Queue.cancel(p.id + 1, request.id)
  end

  test "claim atomically owns two independent tasks and does not double launch", %{
    project: p,
    tasks: tasks
  } do
    [a, b, c, _] = Enum.map(tasks, &enqueue(p, &1))
    assert {:ok, {:started, started, first}} = Queue.claim(a.id)
    assert started.delivery_id == first.id
    assert {:ok, {:existing, ^started, ^first}} = Queue.claim(a.id)
    assert {:ok, {:started, _, second}} = Queue.claim(b.id)
    assert {:error, :busy} = Queue.claim(c.id)
    assert Repo.get!(Request, c.id).status == "queued"
    assert {:error, :task_queued} = Runs.admit(p.id, c.task_id, Ecto.UUID.generate())
    assert {:error, _} = raw_delivery(p, Enum.at(tasks, 3))
    assert {:ok, _} = Deliveries.complete(first.id, "cancelled")
    assert {:ok, {:started, _, third}} = Queue.claim(c.id)
    assert second.id != third.id
    assert {:error, :already_started} = Queue.cancel(p.id, a.id)
  end

  test "active unknown receipt persists alongside peer and blocks new acquisitions", %{
    project: p,
    tasks: [a, b, c | _]
  } do
    {:ok, {:new, first}} = Deliveries.admit(p.id, a.id, Ecto.UUID.generate(), "true")
    {:ok, {:new, second}} = Deliveries.admit(p.id, b.id, Ecto.UUID.generate(), "true")
    assert {:ok, unknown} = Deliveries.interrupt(first.id)
    assert unknown.cleanup == "unknown"
    assert Deliveries.get(p.id, second.id).status == "planning"
    assert {:error, :busy} = Deliveries.admit(p.id, c.id, Ecto.UUID.generate(), "true")
    assert {:error, _} = raw_delivery(p, c)
    assert {:ok, _} = Deliveries.complete(second.id, "cancelled")
    assert {:error, :busy} = Deliveries.admit(p.id, c.id, Ecto.UUID.generate(), "true")
  end

  test "manual execution owns all capacity even with queued requests", %{
    project: p,
    tasks: [a, b | _]
  } do
    {:ok, {:new, run}} = Runs.admit(p.id, a.id, Ecto.UUID.generate())
    request = enqueue(p, b)
    assert {:error, :busy} = Queue.claim(request.id)
    assert {:error, _} = raw_delivery(p, b)
    assert Runs.get(p.id, run.id).status == "preparing"
  end

  test "task drift retires the request and old UUID cannot resurrect it", %{
    project: p,
    tasks: [a | _]
  } do
    request = enqueue(p, a)
    Repo.update_all(from(t in Tasks.Task, where: t.id == ^a.id), inc: [state_version: 1])
    assert {:ok, {:stale, saved}} = Queue.claim(request.id)
    assert saved.status == "stale"
    assert saved.reason == "Task changed after this request was queued."
    assert {:error, :request_finished} = Queue.resume_saved(p.id, saved.id)

    assert {:error, :idempotency_conflict} =
             Deliveries.admit(p.id, a.id, saved.command_id, "true")

    assert {:ok, ^saved} = Queue.admit(p.id, a.id, request.command_id, "true", "codex")
    assert Deliveries.list(p.id, a.id) == []
  end

  test "cancel and restart pause are idempotent and resume preserves all authorization", %{
    project: p,
    tasks: [a | _]
  } do
    request = enqueue(p, a)
    assert {:ok, [paused]} = Queue.pause()
    assert paused.status == "paused"
    assert {:error, :request_unavailable} = Queue.claim(request.id)
    assert {:ok, resumed} = Queue.resume_saved(p.id, request.id)
    assert resumed.command_id == request.command_id
    assert resumed.check_config == request.check_config
    assert {:ok, cancelled} = Queue.cancel(p.id, request.id)
    assert {:ok, ^cancelled} = Queue.cancel(p.id, request.id)
    assert {:error, :request_finished} = Queue.resume_saved(p.id, request.id)

    assert {:error, :idempotency_conflict} =
             Deliveries.admit(p.id, a.id, request.command_id, "true")

    assert Tasks.get_task!(a.id).state == "new"
  end

  test "dependency waiting has no writes and queue cannot impersonate direct start", %{
    project: p,
    tasks: [a | _]
  } do
    dependent =
      task(p.id, "dependent", "---\nid: dependent\ndepends_on: [missing]\n---\n# Dependent")

    request = enqueue(p, dependent)
    assert {:error, {:dependencies_blocked, _}} = Queue.claim(request.id)
    assert Repo.get!(Request, request.id) == request
    command = Ecto.UUID.generate()
    assert {:ok, {:new, _}} = Deliveries.admit(p.id, a.id, command, "true")
    assert {:error, :idempotency_conflict} = Queue.admit(p.id, a.id, command, "true", "codex")
  end

  test "history is bounded and pending global limit includes paused requests", %{
    project: p,
    tasks: [a | _]
  } do
    for _ <- 1..4 do
      request = enqueue(p, a)
      assert {:ok, _} = Queue.cancel(p.id, request.id)
    end

    assert length(Queue.list(p.id, a.id)) == 3
    for n <- 1..32, do: enqueue(p, task(p.id, "limit#{n}"))
    assert {:ok, paused} = Queue.pause()
    assert length(paused) == 32
    assert {:error, :queue_full} = Queue.admit(p.id, a.id, Ecto.UUID.generate(), "true", "codex")
  end

  defp enqueue(project, task) do
    {:ok, request} = Queue.admit(project.id, task.id, Ecto.UUID.generate(), "true", "codex")
    request
  end

  defp task(project, name, source \\ nil) do
    {:ok, %{task: task}} =
      Projects.record_spec(project, %{
        relative_path: name <> ".md",
        title: name,
        original_text: source || "# " <> name
      })

    task
  end

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
