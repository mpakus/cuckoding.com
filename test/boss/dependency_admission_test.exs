defmodule Boss.DependencyAdmissionTest do
  use Boss.DataCase
  alias Boss.{Deliveries, Projects, Runs, Tasks}

  setup do
    project =
      Repo.insert!(%Projects.Project{
        name: "Dependencies",
        root_path: "/dependencies",
        git_common_dir: "/dependencies/.git",
        specs_path: "/dependencies/specs",
        base_branch: "main"
      })

    %{project: project}
  end

  test "new manual and managed starts refuse a pending dependency before effects", c do
    prerequisite = spec(c.project, "first", [])
    task = spec(c.project, "second", ["first"])

    for state <- ["new", "ready_to_merge", "blocked", "failed", "cancelled", "interrupted"] do
      state(prerequisite.task, state)

      for start <- [&Runs.admit/3, fn p, t, id -> Deliveries.admit(p, t, id, "true") end] do
        assert {:error, {:dependencies_blocked, %{ready?: false}}} =
                 start.(c.project.id, task.task.id, Ecto.UUID.generate())
      end
    end

    assert Repo.aggregate(Runs.Run, :count) == 0
    assert Repo.aggregate(Deliveries.Delivery, :count) == 0
    assert Tasks.list_events(task.task.id) == []
    assert Tasks.get_task!(task.task.id).state == "new"
  end

  test "Done unlocks managed admission, while command replay survives later invalid readiness",
       c do
    prerequisite = spec(c.project, "first", [])
    task = spec(c.project, "second", ["first"])
    state(prerequisite.task, "done")
    command = Ecto.UUID.generate()
    assert {:ok, {:new, delivery}} = Deliveries.admit(c.project.id, task.task.id, command, "true")
    assert delivery.spec_revision_id == task.revision.id
    state(prerequisite.task, "failed")
    assert {:ok, %{ready?: false}} = Tasks.Dependencies.snapshot(c.project.id, task.task.id)

    assert {:ok, {:existing, ^delivery}} =
             Deliveries.admit(c.project.id, task.task.id, command, "true")

    assert length(Tasks.list_events(task.task.id)) == 1
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
  end

  test "Done unlocks manual admission and saved command replay never creates another run", c do
    prerequisite = spec(c.project, "first", [])
    task = spec(c.project, "second", ["first"])
    state(prerequisite.task, "done")
    command = Ecto.UUID.generate()
    assert {:ok, {:new, run}} = Runs.admit(c.project.id, task.task.id, command)
    state(prerequisite.task, "cancelled")
    assert {:ok, {:existing, ^run}} = Runs.admit(c.project.id, task.task.id, command)
    assert Repo.aggregate(Runs.Run, :count) == 1
    assert Tasks.list_events(task.task.id) == []
  end

  test "selected and latest revisions cannot silently remove the task's pinned dependencies", c do
    task = spec(c.project, "second", ["missing"])
    latest = spec(c.project, "second", [])
    assert latest.revision.number == 2
    assert {:ok, details} = Tasks.get_details(c.project.id, task.task.id, 2)
    assert details.selected_revision.id == latest.revision.id
    assert details.pinned_revision.id == task.revision.id
    refute details.dependencies.ready?
    assert [%{reference: "missing", task_id: nil}] = details.dependencies.dependencies

    assert {:error, {:dependencies_blocked, _}} =
             Deliveries.admit(c.project.id, task.task.id, Ecto.UUID.generate(), "true")

    prerequisite = spec(c.project, "missing", [])
    state(prerequisite.task, "done")

    assert {:ok, {:new, delivery}} =
             Deliveries.admit(c.project.id, task.task.id, Ecto.UUID.generate(), "true")

    assert delivery.spec_revision_id == task.revision.id
  end

  test "a legacy malformed declaration fails closed rather than behaving like no dependencies",
       c do
    {:ok, task} =
      Projects.record_spec(c.project.id, %{
        relative_path: "legacy.md",
        title: "Legacy",
        explicit_id: "legacy",
        original_text: "---\ndepends_on: false\n---\n# Legacy\n"
      })

    assert {:error, {:dependencies_blocked, %{ready?: false}}} =
             Runs.admit(c.project.id, task.task.id, Ecto.UUID.generate())

    assert {:error, {:dependencies_blocked, %{ready?: false}}} =
             Deliveries.admit(c.project.id, task.task.id, Ecto.UUID.generate(), "true")

    assert Repo.aggregate(Runs.Run, :count) == 0
    assert Repo.aggregate(Deliveries.Delivery, :count) == 0
  end

  defp spec(project, id, dependencies) do
    {:ok, saved} =
      Projects.record_spec(project.id, %{
        relative_path: id <> ".md",
        explicit_id: id,
        title: id,
        original_text: "---\nid: #{id}\ndepends_on: #{JSON.encode!(dependencies)}\n---\n# #{id}\n"
      })

    saved
  end

  defp state(task, state), do: task |> Ecto.Changeset.change(state: state) |> Repo.update!()
end
