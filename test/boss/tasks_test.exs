defmodule Boss.TasksTest do
  use Boss.DataCase
  alias Boss.{Projects, Tasks}
  alias Boss.Tasks.Event

  setup do
    project =
      Repo.insert!(%Projects.Project{
        name: "Transitions",
        root_path: "/test/transitions",
        git_common_dir: "/test/transitions/.git",
        specs_path: "/test/transitions/specs",
        base_branch: "main"
      })

    {:ok, record} =
      Projects.record_spec(project.id, %{
        relative_path: "one.md",
        original_text: "# One",
        title: "One"
      })

    %{project: project, task: record.task}
  end

  test "a transition persists its event, reason and original snapshot together", %{
    project: project,
    task: task
  } do
    {:ok, _} =
      Projects.record_spec(project.id, %{
        relative_path: "one.md",
        original_text: "# Changed",
        title: "Changed"
      })

    assert {:ok, %Event{} = event} =
             Tasks.transition(task.id, command("block", 0, "Missing decision"))

    saved = Tasks.get_task!(task.id)
    assert saved.state == "blocked"
    assert saved.state_version == 1
    assert saved.attention_reason == "Missing decision"
    assert saved.recovery_state == "new"
    assert saved.title == task.title
    assert saved.spec_revision_id == task.spec_revision_id
    assert event.from_state == "new"
    assert event.to_state == "blocked"
    assert event.version == 1
    assert event.spec_revision_id == task.spec_revision_id
    assert event.reason == saved.attention_reason
    assert Tasks.list_events(task.id) == [event]
  end

  test "identical replay returns its receipt after later commands without changing current state",
       %{task: task} do
    block = command("block", 0, "Question")
    assert {:ok, receipt} = Tasks.transition(task.id, block)
    assert {:ok, resumed} = Tasks.transition(task.id, command("resume", 1))
    saved = Tasks.get_task!(task.id)
    assert saved.state == "new"
    assert saved.attention_reason == nil
    assert saved.recovery_state == nil
    assert {:ok, ^receipt} = Tasks.transition(task.id, block)
    assert Tasks.get_task!(task.id) == saved
    assert Tasks.list_events(task.id) == [receipt, resumed]
    assert {:error, :stale_state} = Tasks.transition(task.id, %{block | command_id: "stale"})
    assert Tasks.get_task!(task.id) == saved
  end

  test "reusing a command ID with changed content conflicts even after state advancement", %{
    task: task
  } do
    block = command("block", 0, "Question")
    assert {:ok, _} = Tasks.transition(task.id, block)

    for changed <- [
          %{block | action: "cancel"},
          %{block | reason: "Different"},
          %{block | expected_version: 1}
        ] do
      assert {:error, :idempotency_conflict} = Tasks.transition(task.id, changed)
    end

    assert length(Tasks.list_events(task.id)) == 1
    assert Tasks.get_task!(task.id).state_version == 1
  end

  test "malformed commands and caller-supplied evidence cannot mutate tasks", %{task: task} do
    block = command("block", 0, "Question")

    for invalid <- [
          nil,
          %{},
          Map.delete(block, :expected_version),
          Map.put(block, :verified, true),
          Map.put(block, :evidence, %{approved: true}),
          Map.put(block, :to_state, "done"),
          %{block | expected_version: -1},
          %{block | expected_version: 9_223_372_036_854_775_807},
          %{block | command_id: " "},
          %{block | command_id: String.duplicate("x", 129)},
          %{block | command_id: <<255>>},
          %{block | reason: <<0>>},
          %{block | reason: String.duplicate("x", 1001)},
          %{block | reason: <<255>>},
          %{"command_id" => "a", "expected_version" => 0, "action" => "block"}
        ] do
      assert {:error, :invalid_command} = Tasks.transition(task.id, invalid)
    end

    assert {:error, :invalid_command} = Tasks.transition("1", block)
    assert {:error, :not_found} = Tasks.transition(task.id + 1000, block)
    assert Tasks.get_task!(task.id) == task
    assert Tasks.list_events(task.id) == []
  end

  test "unavailable or invalid workflow actions leave no history or partial state", %{task: task} do
    assert {:error, {:gate_unavailable, :runner}} =
             Tasks.transition(task.id, command("start_planning", 0))

    assert {:error, :invalid_transition} =
             Tasks.transition(task.id, command("finish_integration", 0))

    assert {:error, :invalid_reason} = Tasks.transition(task.id, command("block", 0))
    assert Tasks.get_task!(task.id) == task
    assert Tasks.list_events(task.id) == []
  end

  test "event insertion failure rolls back the task update and permits the same command to retry",
       %{task: task} do
    Repo.query!(
      "CREATE TRIGGER reject_task_event BEFORE INSERT ON task_events BEGIN SELECT RAISE(ABORT, 'test failure'); END"
    )

    block = command("block", 0, "Question")
    assert {:error, :storage_error} = Tasks.transition(task.id, block)
    assert Tasks.get_task!(task.id) == task
    assert Tasks.list_events(task.id) == []
    Repo.query!("DROP TRIGGER reject_task_event")
    assert {:ok, %{version: 1}} = Tasks.transition(task.id, block)
  end

  test "the database rejects rewriting or deleting event history", %{task: task} do
    assert {:ok, event} = Tasks.transition(task.id, command("cancel", 0, "Stopped by user"))

    assert {:error, _} =
             Repo.query("UPDATE task_events SET reason = 'changed' WHERE id = ?", [event.id])

    assert {:error, _} = Repo.query("DELETE FROM task_events WHERE id = ?", [event.id])
    assert Tasks.list_events(task.id) == [event]
    assert {:ok, %{to_state: "new"}} = Tasks.transition(task.id, command("retry", 1))
  end

  defp command(action, version, reason \\ nil),
    do: %{
      command_id: "#{action}-#{version}",
      expected_version: version,
      action: action,
      reason: reason
    }
end
