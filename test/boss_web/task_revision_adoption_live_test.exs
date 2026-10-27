defmodule BossWeb.TaskRevisionAdoptionLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  require Phoenix.LiveView
  import Ecto.Query
  alias Boss.{LocalAccess, Projects, Repo, Runs, Tasks}

  setup %{conn: conn} do
    project =
      Repo.insert!(%Projects.Project{
        name: "Revision UI",
        root_path: "/revision-ui",
        git_common_dir: "/revision-ui/.git",
        specs_path: "/revision-ui/specs",
        base_branch: "main"
      })

    first = spec(project, "Original", ["missing"])
    second = spec(project, "Updated", [])
    {:ok, session} = LocalAccess.exchange(LocalAccess.new_token())
    conn = %{conn | host: "127.0.0.1", port: 4002} |> init_test_session(local_session: session)
    %{conn: conn, project: project, first: first, second: second}
  end

  test "viewing source stays read-only; explicit adoption updates title, snapshot and dependencies",
       c do
    {:ok, view, _} = live(c.conn, path(c) <> "?revision=2")
    settle(view)
    assert has_element?(view, "#task-drawer-title", "Original")
    assert has_element?(view, "#task-source", "Updated")
    assert has_element?(view, "#task-dependencies code", "missing")
    assert has_element?(view, "#adopt-revision", "Use revision 2")
    assert Tasks.get_task!(c.first.task.id).spec_revision_id == c.first.revision.id
    assert Tasks.list_events(c.first.task.id) == []

    adopt(view)
    settle(view)
    assert has_element?(view, "#task-drawer-title", "Updated")
    assert has_element?(view, "#task-snapshot", "Revision 2")
    assert has_element?(view, "#task-dependencies-status", "No dependencies")
    assert has_element?(view, "#task-events", "Source revision 1 →")
    assert has_element?(view, "#task-events", "2 adopted.")
    task = Tasks.get_task!(c.first.task.id)

    assert {task.state, task.state_version, task.spec_revision_id} ==
             {"new", 1, c.second.revision.id}

    render_patch(view, path(c) <> "?revision=1")
    settle(view)
    assert has_element?(view, "#task-source", "Original")
    assert has_element?(view, "#task-snapshot", "Revision 2")
    refute has_element?(view, "#adopt-revision")
    assert Tasks.get_task!(task.id).spec_revision_id == c.second.revision.id
  end

  test "committed adoption refreshes another connected drawer and board", c do
    {:ok, first, _} = live(c.conn, path(c) <> "?revision=2")
    {:ok, other, _} = live(c.conn, path(c))
    settle(first)
    settle(other)
    adopt(first)
    settle(first)
    settle(other)
    assert has_element?(other, "#task-drawer-title", "Updated")
    assert has_element?(other, "#task-snapshot", "Revision 2")
    assert has_element?(other, "#task-source", "Updated")
    assert has_element?(other, "#task-#{c.first.task.id}", "Updated")
  end

  test "active, Done and unknown cleanup prevent adoption and forged events have no effect", c do
    for state <- ["implementing", "done"] do
      set_state(c.first.task.id, state)
      {:ok, view, _} = live(c.conn, path(c) <> "?revision=2")
      settle(view)
      assert has_element?(view, "#adopt-revision[disabled]")
      adopt(view)
      settle(view)
      assert Tasks.get_task!(c.first.task.id).spec_revision_id == c.first.revision.id
    end

    set_state(c.first.task.id, "new")

    {:ok, prerequisite} =
      Projects.record_spec(c.project.id, %{
        explicit_id: "missing",
        relative_path: "missing.md",
        title: "Prerequisite",
        original_text: "---\nid: missing\n---\n# Prerequisite"
      })

    set_state(prerequisite.task.id, "done")
    {:ok, {:new, run}} = Runs.admit(c.project.id, c.first.task.id, Ecto.UUID.generate())
    {:ok, _} = Runs.update(run.id, status: "interrupted", cleanup: "unknown")
    {:ok, view, _} = live(c.conn, path(c) <> "?revision=2")
    settle(view)
    assert has_element?(view, "#task-revision-adoption", "cleanup that needs attention")
    assert has_element?(view, "#adopt-revision[disabled]")
    adopt(view)
    settle(view)
    assert Tasks.list_events(c.first.task.id) == []
  end

  test "admission rejects stale version and refreshes before a new request", c do
    {:ok, view, _} = live(c.conn, path(c) <> "?revision=2")
    settle(view)
    original = command(view)

    {:ok, _} =
      Tasks.transition(c.first.task.id, %{
        command_id: Ecto.UUID.generate(),
        expected_version: 0,
        action: "block",
        reason: "Check source"
      })

    adopt(view)
    settle(view)
    assert has_element?(view, "#adopt-revision-error", "The task changed")
    refute command(view) == original
    refute :sys.get_state(view.pid).socket.assigns.adoption_requests[c.first.task.id].locked
    assert Tasks.get_task!(c.first.task.id).spec_revision_id == c.first.revision.id
    adopt(view)
    settle(view)
    task = Tasks.get_task!(c.first.task.id)
    assert {task.state, task.attention_reason, task.recovery_state} == {"new", nil, nil}
  end

  test "stale selected source and foreign command IDs cannot choose another target", c do
    third = spec(c.project, "Third", [])
    {:ok, view, _} = live(c.conn, path(c) <> "?revision=2")
    settle(view)
    original = command(view)

    render_click(view, "adopt_revision", %{
      "command-id" => Ecto.UUID.generate(),
      "spec_revision_id" => third.revision.id
    })

    settle(view)
    assert Tasks.list_events(c.first.task.id) == []
    render_patch(view, path(c) <> "?revision=3")
    settle(view)
    render_click(view, "adopt_revision", %{"command-id" => original})
    settle(view)
    assert Tasks.list_events(c.first.task.id) == []
    assert has_element?(view, "#adopt-revision", "Use revision 3")
    assert Tasks.get_task!(c.first.task.id).spec_revision_id == c.first.revision.id
  end

  test "unknown update retries original UUID, target and version across source navigation", c do
    third = spec(c.project, "Third", [])
    {:ok, view, _} = live(c.conn, path(c) <> "?revision=2")
    settle(view)
    id = command(view)
    hold_adoption(view, id)

    :sys.replace_state(view.pid, fn state ->
      key = state.socket.assigns.adoption_starting
      %{state | socket: Phoenix.LiveView.cancel_async(state.socket, key, :kill)}
    end)

    settle(view)
    assert has_element?(view, "#adopt-revision-pending", "revision 2")
    assert has_element?(view, "#start-codex[disabled]")
    assert has_element?(view, "#start-delivery[disabled]")
    render_patch(view, path(c) <> "?revision=3")
    settle(view)
    assert has_element?(view, "#task-source", "Third")
    assert has_element?(view, "#adopt-revision", "Retry revision 2")
    assert command(view) == id
    saved = :sys.get_state(view.pid).socket.assigns.adoption_requests[c.first.task.id]
    assert saved.command.spec_revision_id == c.second.revision.id
    assert saved.command.expected_version == 0
    refute saved.command.spec_revision_id == third.revision.id
    adopt(view)
    settle(view)
    assert Tasks.get_task!(c.first.task.id).spec_revision_id == c.second.revision.id
    assert [event] = Tasks.list_events(c.first.task.id)
    assert event.command_id == id
    assert has_element?(view, "#task-source", "Third")
    assert has_element?(view, "#task-snapshot", "Revision 2")
    refute has_element?(view, "#adopt-revision-pending")
  end

  test "historical manual results keep their source label and check controls", c do
    set_state(c.first.task.id, "new")
    {:ok, clean} = Tasks.transition(c.first.task.id, adoption(c, c.second.revision.id, 0))
    {:ok, {:new, run}} = Runs.admit(c.project.id, c.first.task.id, Ecto.UUID.generate())

    {:ok, _} =
      Runs.update(run.id,
        status: "finished",
        cleanup: "group_empty",
        workspace: %{"path" => "/retained/source"}
      )

    third = spec(c.project, "Third", [])
    {:ok, view, _} = live(c.conn, path(c) <> "?revision=3")
    settle(view)
    adopt(view)
    settle(view)
    assert has_element?(view, "#run-#{run.id}", "Source revision 2")
    assert has_element?(view, "#run-#{run.id}", "historical snapshot")
    assert has_element?(view, "#task-snapshot", "Revision 3")

    if :os.type() == {:unix, :darwin},
      do: refute(has_element?(view, "#check-form-#{run.id} button[disabled]"))

    assert Repo.get!(Runs.Run, run.id).spec_revision_id == c.second.revision.id
    assert clean.target_spec_revision_id == c.second.revision.id
    assert Tasks.get_task!(c.first.task.id).spec_revision_id == third.revision.id
  end

  defp spec(project, title, deps) do
    text =
      "---\nid: source\ntitle: #{title}\ndepends_on: #{JSON.encode!(deps)}\n---\n# #{title}\n"

    {:ok, attrs} = Projects.SpecDocument.parse("source.md", text)
    {:ok, saved} = Projects.record_spec(project.id, attrs)
    saved
  end

  defp adoption(c, revision, version),
    do: %{
      action: "adopt_revision",
      project_id: c.project.id,
      spec_revision_id: revision,
      expected_version: version,
      command_id: Ecto.UUID.generate()
    }

  defp set_state(task, state),
    do: Repo.update_all(from(t in Tasks.Task, where: t.id == ^task), set: [state: state])

  defp path(c), do: "/projects/#{c.project.id}/tasks/#{c.first.task.id}"
  defp adopt(view), do: render_click(view, "adopt_revision", %{"command-id" => command(view)})

  defp command(view),
    do:
      view
      |> element("#adopt-revision")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("phx-value-command-id")
      |> hd()

  defp settle(view) do
    render(view)
    for _ <- 1..5, do: render_async(view)
  end

  defp hold_adoption(view, id) do
    owner = self()

    :sys.replace_state(view.pid, fn state ->
      # Drop dispatch before storage receives it; the real handler still pins the request.
      {:noreply, socket} =
        BossWeb.ProjectLive.handle_event(
          "adopt_revision",
          %{"command-id" => id},
          %{state.socket | transport_pid: nil}
        )

      socket = %{socket | transport_pid: state.socket.transport_pid}
      key = socket.assigns.adoption_starting

      socket =
        Phoenix.LiveView.start_async(socket, key, fn ->
          send(owner, :adoption_held)

          receive do
            :release -> :unknown
          end
        end)

      %{state | socket: socket}
    end)

    assert_receive :adoption_held, 1000
  end
end
