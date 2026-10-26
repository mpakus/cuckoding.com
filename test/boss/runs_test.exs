defmodule Boss.RunsTest do
  use Boss.DataCase
  alias Boss.{Projects, Runs, Tasks}

  setup do
    project =
      Repo.insert!(%Projects.Project{
        name: "Runs",
        root_path: "/test/runs",
        git_common_dir: "/test/runs/.git",
        specs_path: "/test/runs/specs",
        base_branch: "main"
      })

    {:ok, record} =
      Projects.record_spec(project.id, %{
        relative_path: "one.md",
        original_text: "# Pinned",
        title: "Pinned"
      })

    %{project: project, task: record.task}
  end

  test "intent pins saved task revision, replays and leaves task workflow unchanged", %{
    project: p,
    task: t
  } do
    {:ok, _} =
      Projects.record_spec(p.id, %{
        relative_path: "one.md",
        original_text: "# Newer",
        title: "Newer"
      })

    id = Ecto.UUID.generate()
    assert {:ok, {:new, run}} = Runs.admit(p.id, t.id, id)
    assert run.spec_revision_id == t.spec_revision_id
    assert run.status == "preparing"
    assert {:ok, {:existing, ^run}} = Runs.admit(p.id, t.id, id)
    assert Tasks.get_task!(t.id) == t
    assert Tasks.list_events(t.id) == []
    assert {:error, :busy} = Runs.admit(p.id, t.id, Ecto.UUID.generate())
    assert {:error, :not_found} = Runs.admit(p.id + 1, t.id, id)
  end

  test "workspace pin and completed receipts cannot be changed", %{project: p, task: t} do
    {:ok, {:new, run}} = Runs.admit(p.id, t.id, Ecto.UUID.generate())
    assert {:ok, _} = Runs.update(run.id, workspace: %{"base_commit" => "immutable"})

    assert {:error, :storage_error} =
             Runs.update(run.id, workspace: %{"base_commit" => "changed"})

    assert {:ok, _} = Runs.update(run.id, status: "finished", cleanup: "group_empty")
    assert {:error, :already_finished} = Runs.update(run.id, status: "running")
    assert {:ok, {:new, _}} = Runs.admit(p.id, t.id, Ecto.UUID.generate())
  end

  test "recovery quarantines unresolved intent without changing snapshot or launching", %{
    project: p,
    task: t
  } do
    {:ok, {:new, run}} = Runs.admit(p.id, t.id, Ecto.UUID.generate())
    assert {:ok, {1, _}} = Runs.reconcile()
    saved = Runs.get(p.id, run.id)
    assert saved.status == "interrupted"
    assert saved.cleanup == "unknown"
    assert {:error, :busy} = Runs.admit(p.id, t.id, Ecto.UUID.generate())
    assert {:ok, {0, _}} = Runs.reconcile()
    assert saved == Runs.get(p.id, run.id)
  end
end
