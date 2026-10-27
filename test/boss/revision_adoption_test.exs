defmodule Boss.RevisionAdoptionTest do
  use Boss.DataCase
  alias Boss.{Projects, Runs, Tasks}

  setup do
    project =
      Repo.insert!(%Projects.Project{
        name: "Adoption",
        root_path: "/adoption",
        git_common_dir: "/adoption/.git",
        specs_path: "/adoption/specs",
        base_branch: "main"
      })

    first = record(project.id, "# Original")
    second = record(project.id, "---\ndepends_on: [missing]\n---\n# Revised")
    %{project: project, first: first, second: second}
  end

  test "explicit adoption atomically changes title and source but retains originals and unmet dependencies",
       c do
    {:ok, _} =
      Tasks.transition(c.first.task.id, %{
        command_id: "block",
        expected_version: 0,
        action: "block",
        reason: "Question"
      })

    cmd = command(c, c.second.revision.id, 1)
    assert {:ok, event} = Tasks.transition(c.first.task.id, cmd)
    task = Tasks.get_task!(c.first.task.id)

    assert {task.title, task.spec_revision_id, task.state, task.state_version} ==
             {"Revised", c.second.revision.id, "new", 2}

    assert task.attention_reason == nil and task.recovery_state == nil
    assert event.spec_revision_id == c.first.revision.id
    assert event.target_spec_revision_id == c.second.revision.id
    assert event.from_state == "blocked" and event.to_state == "new"
    assert Repo.get!(Projects.SpecRevision, c.first.revision.id) == c.first.revision
    assert {:ok, details} = Tasks.get_details(c.project.id, task.id)
    refute details.dependencies.ready?
    assert details.adoption == %{available?: false, reason: :revision_unavailable}

    assert {:error, {:dependencies_blocked, _}} =
             Runs.admit(c.project.id, task.id, Ecto.UUID.generate())
  end

  test "viewing source is read-only and chosen newer revision need not be latest", c do
    third = record(c.project.id, "# Latest")
    assert {:ok, details} = Tasks.get_details(c.project.id, c.first.task.id, 2)
    assert details.adoption == %{available?: true, reason: nil}
    assert details.task == c.first.task
    assert details.latest_revision == third.revision
    assert {:ok, _} = Tasks.transition(c.first.task.id, command(c, c.second.revision.id))
    assert Tasks.get_task!(c.first.task.id).spec_revision_id == c.second.revision.id
  end

  test "original command replays after another adoption but changed target conflicts", c do
    third = record(c.project.id, "# Latest")
    cmd = command(c, c.second.revision.id)
    assert {:ok, event} = Tasks.transition(c.first.task.id, cmd)
    assert {:ok, _} = Tasks.transition(c.first.task.id, command(c, third.revision.id, 1))
    assert {:ok, ^event} = Tasks.transition(c.first.task.id, cmd)

    assert {:error, :idempotency_conflict} =
             Tasks.transition(c.first.task.id, %{cmd | spec_revision_id: third.revision.id})

    assert {:error, :stale_state} =
             Tasks.transition(c.first.task.id, %{cmd | command_id: Ecto.UUID.generate()})

    assert {:error, :revision_unavailable} =
             Tasks.transition(c.first.task.id, command(c, c.second.revision.id, 2))

    assert length(Tasks.list_events(c.first.task.id)) == 2
  end

  test "foreign project, foreign/current revision and malformed commands cannot change the pin",
       c do
    {:ok, other} =
      Projects.record_spec(c.project.id, %{
        relative_path: "other.md",
        original_text: "# Other",
        title: "Other"
      })

    cmd = command(c, c.second.revision.id)

    for id <- [other.revision.id, c.first.revision.id, 99_999] do
      assert {:error, :revision_unavailable} =
               Tasks.transition(c.first.task.id, %{cmd | spec_revision_id: id})
    end

    assert {:error, :not_found} =
             Tasks.transition(c.first.task.id, %{cmd | project_id: c.project.id + 100})

    for invalid <- [
          Map.put(cmd, :reason, "Please"),
          Map.put(cmd, :delivery_id, Ecto.UUID.generate()),
          Map.delete(cmd, :project_id),
          Map.delete(cmd, :spec_revision_id),
          Map.put(cmd, :spec_revision_id, "2")
        ] do
      assert {:error, :invalid_command} = Tasks.transition(c.first.task.id, invalid)
    end

    assert Tasks.get_task!(c.first.task.id) == c.first.task
    assert Tasks.list_events(c.first.task.id) == []
  end

  test "legacy malformed sources and identity changes cannot be adopted", c do
    for source <- ["---\ndepends_on: {}\n---\n# Bad", "---\nid: different\n---\n# Identity"] do
      bad = record(c.project.id, source)

      assert {:error, :source_unavailable} =
               Tasks.transition(c.first.task.id, command(c, bad.revision.id))

      assert {:ok, %{adoption: %{available?: false, reason: :source_unavailable}}} =
               Tasks.get_details(c.project.id, c.first.task.id, bad.revision.number)
    end

    assert Tasks.get_task!(c.first.task.id) == c.first.task
  end

  test "Done and active task states cannot be reopened by adoption", c do
    for state <- ~w(done planning implementing testing reviewing integrating approved) do
      Repo.update_all(from(t in Tasks.Task, where: t.id == ^c.first.task.id), set: [state: state])

      assert {:error, :task_unavailable} =
               Tasks.transition(c.first.task.id, command(c, c.second.revision.id))
    end

    assert Tasks.list_events(c.first.task.id) == []
  end

  test "a manual active or unknown attempt blocks adoption even while task remains New", c do
    {:ok, {:new, run}} = Runs.admit(c.project.id, c.first.task.id, Ecto.UUID.generate())
    cmd = command(c, c.second.revision.id)
    assert {:error, :busy} = Tasks.transition(c.first.task.id, cmd)
    {:ok, _} = Runs.update(run.id, status: "interrupted", cleanup: "unknown")
    assert {:error, :busy} = Tasks.transition(c.first.task.id, cmd)
    assert Tasks.get_task!(c.first.task.id) == c.first.task
  end

  test "failed event insertion rolls back task and same command can reconcile", c do
    Repo.query!(
      "CREATE TRIGGER reject_adoption BEFORE INSERT ON task_events BEGIN SELECT RAISE(ABORT, 'fixture'); END"
    )

    cmd = command(c, c.second.revision.id)
    assert {:error, :storage_error} = Tasks.transition(c.first.task.id, cmd)
    assert Tasks.get_task!(c.first.task.id) == c.first.task
    Repo.query!("DROP TRIGGER reject_adoption")
    assert {:ok, event} = Tasks.transition(c.first.task.id, cmd)

    assert {:error, _} =
             Repo.query("UPDATE task_events SET target_spec_revision_id = ? WHERE id = ?", [
               c.first.revision.id,
               event.id
             ])

    assert {:error, _} = Repo.query("DELETE FROM task_events WHERE id = ?", [event.id])
  end

  test "nested provisional adoption does not publish before outer transaction commits", c do
    Tasks.subscribe(c.project.id)

    assert {:error, :rollback} =
             Repo.transaction(fn ->
               assert {:ok, _} =
                        Tasks.transition(c.first.task.id, command(c, c.second.revision.id))

               refute_receive {:task_changed, _}, 20
               Repo.rollback(:rollback)
             end)

    assert Tasks.get_task!(c.first.task.id) == c.first.task
  end

  defp record(project, source) do
    {:ok, result} =
      Projects.record_spec(project, %{
        relative_path: "one.md",
        title: "Persisted title is not authoritative",
        original_text: source
      })

    result
  end

  defp command(c, revision, version \\ 0),
    do: %{
      command_id: Ecto.UUID.generate(),
      expected_version: version,
      action: "adopt_revision",
      project_id: c.project.id,
      spec_revision_id: revision
    }
end
