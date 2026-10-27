defmodule Boss.DeliveriesTest do
  use Boss.DataCase
  alias Boss.{Deliveries, Projects, Runs, Tasks}

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
end
