defmodule BossWeb.TaskBoardLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query
  require Phoenix.LiveView
  alias Boss.{Projects, Repo, Tasks}

  setup %{conn: conn} do
    project = project("board")
    {:ok, session} = Boss.LocalAccess.exchange(Boss.LocalAccess.new_token())
    conn = %{conn | host: "127.0.0.1", port: 4002} |> init_test_session(local_session: session)
    %{conn: conn, project: project}
  end

  test "every task appears once in its product column, including unknown states", %{
    conn: conn,
    project: project
  } do
    groups = [
      {"backlog", ~w(new planning ready)},
      {"in-progress", ~w(implementing testing integrating)},
      {"review", ~w(reviewing approved)},
      {"needs-attention",
       ~w(ready_to_merge blocked needs_input failed interrupted cancelled future)},
      {"done", ~w(done)}
    ]

    tasks =
      for {column, states} <- groups, state <- states do
        saved = spec(project, state)

        Repo.update_all(from(t in Boss.Tasks.Task, where: t.id == ^saved.task.id),
          set: [state: state]
        )

        {column, saved}
      end

    {:ok, view, html} = live(conn, "/projects/#{project.id}")
    assert length(Regex.scan(~r/data-task-card="/, html)) == length(tasks)

    for {column, saved} <- tasks do
      assert has_element?(view, "#column-#{column} #spec-#{saved.spec.id} h4", saved.task.title)

      assert has_element?(
               view,
               "#task-#{saved.task.id}[href='/projects/#{project.id}/tasks/#{saved.task.id}']"
             )
    end

    refute has_element?(view, "button", "Start")
    refute has_element?(view, "button", "Approve")
  end

  test "drawer shows the pinned source, real events and a URL-selected revision", %{
    conn: conn,
    project: project
  } do
    source = "# Original\n<script>PRIVATE_SCRIPT()</script>\n**Plain Markdown**"
    saved = spec(project, "original", source)
    spec(project, "original", "# Updated source")

    {:ok, _} =
      Tasks.transition(saved.task.id, %{
        command_id: "block",
        expected_version: 0,
        action: "block",
        reason: "Choose an approach"
      })

    {:ok, view, _} = live(conn, "/projects/#{project.id}")
    view |> element("#task-#{saved.task.id}") |> render_click()
    assert_patch(view, "/projects/#{project.id}/tasks/#{saved.task.id}")
    settle(view)

    assert has_element?(
             view,
             "#task-drawer[phx-hook='TaskDrawer'][aria-labelledby='task-drawer-title']"
           )

    assert render(element(view, "#task-source")) =~
             Phoenix.HTML.safe_to_string(Phoenix.HTML.html_escape(source))

    refute has_element?(view, "#task-source script")
    refute has_element?(view, "#task-source h1")
    assert has_element?(view, "#task-snapshot", "1")
    assert has_element?(view, "#task-latest-revision", "2")
    assert has_element?(view, "#task-attention", "Choose an approach")
    assert has_element?(view, "#task-events li", "New → Blocked")

    view |> form("#task-revision-form", %{revision: "2"}) |> render_change()
    path = "/projects/#{project.id}/tasks/#{saved.task.id}?revision=2"
    assert_patch(view, path)
    settle(view)
    assert has_element?(view, "#task-source", "# Updated source")
    assert has_element?(view, "#task-drawer[data-revision='2']")
    assert has_element?(view, "#task-revision option[value='2'][selected]")
    {:ok, reopened, _} = live(conn, path)
    settle(reopened)
    assert has_element?(reopened, "#task-source", "# Updated source")
    reopened |> element("#task-drawer-close") |> render_click()
    assert_patch(reopened, "/projects/#{project.id}")
    refute has_element?(reopened, "#task-drawer")
  end

  test "background refresh preserves the open revision while updating latest metadata", %{
    conn: conn,
    project: project
  } do
    saved = spec(project, "one", "# First")
    spec(project, "one", "# Second")
    path = "/projects/#{project.id}/tasks/#{saved.task.id}?revision=2"
    {:ok, view, _} = live(conn, path)
    settle(view)
    spec(project, "one", "# Third")
    saved.spec |> Ecto.Changeset.change(missing: true) |> Repo.update!()
    notify(project)
    settle(view)
    assert has_element?(view, "#task-source", "# Second")
    assert has_element?(view, "#task-latest-revision", "3")
    assert has_element?(view, "#task-snapshot", "1")
    assert has_element?(view, "#task-revision option[value='2'][selected]")
    assert has_element?(view, "#task-drawer", "File missing")
  end

  test "malformed and cross-project selections never reveal another task", %{
    conn: conn,
    project: project
  } do
    own = spec(project, "own")
    foreign = spec(project("foreign"), "secret", "PRIVATE_FOREIGN_SOURCE")
    anonymous = %{build_conn() | host: "127.0.0.1", port: 4002}

    assert redirected_to(get(anonymous, "/projects/#{project.id}/tasks/#{own.task.id}")) ==
             "/unlock"

    paths = [
      "/projects/#{project.id}/tasks/#{foreign.task.id}",
      "/projects/#{project.id}/tasks/bad",
      "/projects/#{project.id}/tasks/99999999999999999999999",
      "/projects/#{project.id}/tasks/#{own.task.id}?revision=bad",
      "/projects/#{project.id}/tasks/#{own.task.id}?revision=0",
      "/projects/#{project.id}/tasks/#{own.task.id}?revision=999"
    ]

    for path <- paths do
      {:ok, view, _} = live(conn, path)
      settle(view)
      assert has_element?(view, "#task-drawer-error", "Task or revision not found")
      refute has_element?(view, "#task-source")
      refute render(view) =~ "PRIVATE_FOREIGN_SOURCE"
    end
  end

  test "late details from a previous selection cannot replace the new task or reopen a closed drawer",
       %{
         conn: conn,
         project: project
       } do
    first = spec(project, "first", "FIRST_SOURCE")
    second = spec(project, "second", "SECOND_SOURCE")
    {:ok, view, _} = live(conn, "/projects/#{project.id}/tasks/#{first.task.id}")
    settle(view)
    {:ok, first_details} = Tasks.get_details(project.id, first.task.id)
    {old, monitor} = hold_details(view, {{first.task.id, nil}, {:ok, first_details}})
    render_patch(view, "/projects/#{project.id}/tasks/#{second.task.id}")
    settle(view)
    send(old, :release)
    assert_receive {:DOWN, ^monitor, :process, ^old, :normal}
    assert has_element?(view, "#task-source", "SECOND_SOURCE")
    refute has_element?(view, "#task-source", "FIRST_SOURCE")

    {old, monitor} = hold_details(view, {{first.task.id, nil}, {:ok, first_details}})
    render_patch(view, "/projects/#{project.id}")
    send(old, :release)
    assert_receive {:DOWN, ^monitor, :process, ^old, :normal}
    refute has_element?(view, "#task-drawer")
  end

  test "patching to another project remounts before reading that project's task", %{
    conn: conn,
    project: first_project
  } do
    first = spec(first_project, "first", "FIRST_PROJECT_SOURCE")
    second_project = project("second-project")
    second = spec(second_project, "second", "SECOND_PROJECT_SOURCE")
    {:ok, view, _} = live(conn, "/projects/#{first_project.id}/tasks/#{first.task.id}")
    settle(view)
    path = "/projects/#{second_project.id}/tasks/#{second.task.id}?revision=1"
    assert {:error, {:live_redirect, %{to: ^path}}} = redirected = render_patch(view, path)
    {:ok, next, _} = follow_redirect(redirected, conn)
    settle(next)
    assert has_element?(next, "h1", second_project.name)
    assert has_element?(next, "#task-source", "SECOND_PROJECT_SOURCE")
    refute has_element?(next, "#task-source", "FIRST_PROJECT_SOURCE")
  end

  test "repeated board refreshes coalesce behind a slow drawer read", %{
    conn: conn,
    project: project
  } do
    saved = spec(project, "slow", "PINNED_SOURCE")
    {:ok, view, _} = live(conn, "/projects/#{project.id}/tasks/#{saved.task.id}")
    settle(view)
    {:ok, details} = Tasks.get_details(project.id, saved.task.id)
    {old, monitor} = hold_details(view, {{saved.task.id, nil}, {:ok, details}})

    for source <- ["SECOND_SOURCE", "THIRD_SOURCE"] do
      spec(project, "slow", source)
      notify(project)
      await_task(view, :refresh)
    end

    assert {_, ^old, _} = :sys.get_state(view.pid).socket.private.live_async.details
    assert has_element?(view, "#task-source", "PINNED_SOURCE")
    send(old, :release)
    assert_receive {:DOWN, ^monitor, :process, ^old, :normal}
    settle(view)
    assert has_element?(view, "#task-source", "PINNED_SOURCE")
    assert has_element?(view, "#task-latest-revision", "3")
  end

  test "failed detail refresh keeps the loaded task and offers a safe retry", %{
    conn: conn,
    project: project
  } do
    saved = spec(project, "retained", "RETAINED_SOURCE")
    {:ok, view, _} = live(conn, "/projects/#{project.id}/tasks/#{saved.task.id}")
    settle(view)
    {old, monitor} = hold_details(view, :unused)

    :sys.replace_state(view.pid, fn state ->
      %{state | socket: Phoenix.LiveView.cancel_async(state.socket, :details, :kill)}
    end)

    assert_receive {:DOWN, ^monitor, :process, ^old, :killed}
    settle(view)
    assert has_element?(view, "#task-source", "RETAINED_SOURCE")
    assert has_element?(view, "#task-drawer-error", "could not be refreshed")
    assert has_element?(view, "#task-drawer-title", "retained")
  end

  @tag capture_log: true
  test "returning to the pinned revision hides a later source while loading and after failure", %{
    conn: conn,
    project: project
  } do
    saved = spec(project, "revision", "PINNED_SOURCE")
    spec(project, "revision", "LATER_SOURCE")
    path = "/projects/#{project.id}/tasks/#{saved.task.id}"
    {:ok, view, _} = live(conn, path <> "?revision=2")
    settle(view)
    assert has_element?(view, "#task-source", "LATER_SOURCE")
    gate = make_ref()
    :ok = :telemetry.attach(gate, [:boss, :repo, :query], &__MODULE__.hold_query/4, self())
    on_exit(fn -> :telemetry.detach(gate) end)

    render_patch(view, path)
    assert_receive {:held_query, pid}
    monitor = Process.monitor(pid)
    on_exit(fn -> Process.exit(pid, :kill) end)
    refute has_element?(view, "#task-source")
    assert has_element?(view, "#task-drawer[data-revision='1']")
    assert has_element?(view, "#task-revision option[value='1'][selected]")

    :sys.replace_state(view.pid, fn state ->
      %{state | socket: Phoenix.LiveView.cancel_async(state.socket, :details, :kill)}
    end)

    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    settle(view)
    refute has_element?(view, "#task-source")
    assert has_element?(view, "#task-drawer[data-revision='1']")
    assert has_element?(view, "#task-revision option[value='1'][selected]")
    assert has_element?(view, "#task-drawer-error", "could not be refreshed")
  end

  @tag capture_log: true
  test "a cancelled read cannot overwrite an invalid selection or a closed drawer", %{
    conn: conn,
    project: project
  } do
    saved = spec(project, "cancelled")
    path = "/projects/#{project.id}"

    for {target, expected_error} <- [{path <> "/tasks/bad", :not_found}, {path, nil}] do
      {:ok, view, _} = live(conn, path <> "/tasks/#{saved.task.id}")
      settle(view)
      {old, monitor} = hold_details(view, :unused)
      render_patch(view, target)
      send(old, :fail)
      assert_receive {:DOWN, ^monitor, :process, ^old, :simulated_failure}
      settle(view)
      assert :sys.get_state(view.pid).socket.assigns.detail_error == expected_error
      refute has_element?(view, "#task-source")
    end
  end

  def hold_query(_, _, %{query: query}, owner) do
    if String.starts_with?(query, "SELECT") and String.contains?(query, ~s(FROM "tasks")) do
      send(owner, {:held_query, self()})
      receive do: (:release_query -> :ok)
    end
  end

  defp project(name) do
    Repo.insert!(%Boss.Projects.Project{
      name: name,
      root_path: "/#{name}",
      git_common_dir: "/#{name}/.git",
      specs_path: "/#{name}/specs",
      base_branch: "main"
    })
  end

  defp spec(project, name, source \\ "# Source") do
    {:ok, saved} =
      Projects.record_spec(project.id, %{
        relative_path: "#{name}.md",
        title: name,
        original_text: source
      })

    saved
  end

  defp notify(project) do
    Phoenix.PubSub.broadcast(
      Boss.PubSub,
      "specs:#{project.id}",
      {:spec_sync, project.id, {:ok, %{created: 0, revised: 1, unchanged: 0, missing: 0}}}
    )
  end

  defp settle(view) do
    render(view)
    render_async(view)
    render_async(view)
    render_async(view)
  end

  defp hold_details(view, result) do
    test_pid = self()

    :sys.replace_state(view.pid, fn state ->
      socket =
        state.socket
        |> Phoenix.Component.assign(detail_loading: true)
        |> Phoenix.LiveView.start_async(:details, fn ->
          Process.flag(:trap_exit, true)
          send(test_pid, {:held_details, self()})

          receive do
            :release -> result
            :fail -> exit(:simulated_failure)
          end
        end)

      %{state | socket: socket}
    end)

    assert_receive {:held_details, pid}
    on_exit(fn -> Process.exit(pid, :kill) end)
    {pid, Process.monitor(pid)}
  end

  defp await_task(view, key) do
    render(view)

    case :sys.get_state(view.pid).socket.private[:live_async][key] do
      {_, pid, _} ->
        monitor = Process.monitor(pid)
        assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000

      nil ->
        :ok
    end

    render(view)
  end
end
