defmodule BossWeb.SpecSyncLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  require Phoenix.LiveView
  alias Boss.Projects
  alias Boss.Projects.{SpecImporter, SpecWatcher}
  alias BossWeb.ProjectLive

  setup %{conn: conn} do
    root =
      Path.join(System.tmp_dir!(), "boss-sync-ui-#{Base.encode16(:crypto.strong_rand_bytes(16))}")

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    specs = Path.join(root, "specs")
    File.mkdir!(specs)
    git!(root, ["init", "-b", "main"])
    git!(root, ["commit", "--allow-empty", "-m", "base"])
    {:ok, project} = Projects.create_project(%{root_path: root, name: "Sync project"})
    {:ok, session} = Boss.LocalAccess.exchange(Boss.LocalAccess.new_token())
    conn = %{conn | host: "127.0.0.1", port: 4002} |> init_test_session(local_session: session)
    %{conn: conn, project: project, specs: specs}
  end

  test "project links open protected pages and invalid IDs are explained", %{
    conn: conn,
    project: project
  } do
    path = "/projects/#{project.id}"
    anonymous = %{build_conn() | host: "127.0.0.1", port: 4002}
    assert redirected_to(get(anonymous, path)) == "/unlock"
    {:ok, home, _} = live(conn, "/")
    assert has_element?(home, "#project-#{project.id} a[href='#{path}']", project.name)

    for id <- ["invalid", "0", "-1", "999999999999999999999999999", "#{project.id + 1}"] do
      {:ok, view, _} = live(conn, "/projects/#{id}")
      assert has_element?(view, "h1", "Project not found")
      refute has_element?(view, "#sync-specs")
      assert has_element?(view, "a[href='/']", "Projects")
    end
  end

  test "manual Sync imports three tasks without duplication and survives reopening", %{
    conn: conn,
    project: project,
    specs: specs
  } do
    write_specs(specs)
    {:ok, view, _} = live(conn, "/projects/#{project.id}")
    assert render(view) =~ "No specs imported yet"
    assert sync(view) =~ "3 created"
    assert length(Projects.list_spec_entries(project.id)) == 3
    assert has_element?(view, "#spec-entries li h3", "Alpha")
    assert has_element?(view, "#spec-entries li", "alpha.md")
    assert has_element?(view, "#spec-entries li", "New")
    assert has_element?(view, "#spec-entries li", "Source revision 1")
    assert has_element?(view, "#spec-entries li", "Task snapshot 1")
    refute has_element?(view, "#sync-specs[disabled]")
    assert sync(view) =~ "3 unchanged"
    assert length(Projects.list_spec_entries(project.id)) == 3
    {:ok, reopened, _} = live(conn, "/projects/#{project.id}")
    assert has_element?(reopened, "#spec-entries li h3", "Alpha")
    refute has_element?(reopened, "button", "Start")
  end

  test "source changes and missing files keep their task snapshot visible", %{
    conn: conn,
    project: project,
    specs: specs
  } do
    write_specs(specs)
    {:ok, view, _} = live(conn, "/projects/#{project.id}")
    sync(view)
    entries = Projects.list_spec_entries(project.id)
    alpha = Enum.find(entries, &(&1.relative_path == "alpha.md"))
    beta = Enum.find(entries, &(&1.relative_path == "beta.md"))
    File.write!(Path.join(specs, "alpha.md"), "# Changed title\nChanged source.\n")
    File.rm!(Path.join(specs, "beta.md"))
    sync(view)

    assert has_element?(view, "#spec-#{alpha.id} h3", "Alpha")
    assert has_element?(view, "#spec-#{alpha.id}", "Source revision 2")
    assert has_element?(view, "#spec-#{alpha.id}", "Task snapshot 1")

    assert has_element?(
             view,
             "#spec-#{alpha.id}",
             "Source changed; the task keeps its saved snapshot"
           )

    assert has_element?(view, "#spec-#{beta.id}", "File missing")
    assert length(Projects.list_spec_entries(project.id)) == 3
  end

  test "scan errors preserve the list and expose no source text; retry can succeed", %{
    conn: conn,
    project: project,
    specs: specs
  } do
    write_specs(specs)
    {:ok, view, _} = live(conn, "/projects/#{project.id}")
    sync(view)
    File.rm!(Path.join(specs, "alpha.md"))
    File.write!(Path.join(specs, "broken.md"), "---\nid: [\n---\nPRIVATE_SOURCE_CONTENT\n")
    html = sync(view)
    assert has_element?(view, "#sync-errors[role='alert']", "broken.md")
    assert has_element?(view, "#spec-entries li h3", "Alpha")
    refute has_element?(view, "#spec-entries li", "File missing")
    refute html =~ "PRIVATE_SOURCE_CONTENT"
    refute has_element?(view, "#sync-specs[disabled]")
    File.rm!(Path.join(specs, "broken.md"))
    assert sync(view) =~ "Sync complete"
    refute has_element?(view, "#sync-errors")
    assert has_element?(view, "#spec-entries li", "File missing")
  end

  test "background notifications refresh entries and recover from errors", %{
    conn: conn,
    project: project,
    specs: specs
  } do
    start_watcher(project)
    {:ok, view, _} = live(conn, "/projects/#{project.id}")
    refute render(view) =~ "refresh automatically"
    write_specs(specs)
    assert {:ok, %{created: 3}} = SpecImporter.sync(project.id)
    assert refresh(view) =~ "3 created"
    assert has_element?(view, "#spec-entries li h3", "Alpha")

    File.write!(Path.join(specs, "broken.md"), "---\nid: [\n---\nPRIVATE_SOURCE_CONTENT\n")
    assert {:error, _} = SpecImporter.sync(project.id)
    html = refresh(view)
    assert has_element?(view, "#sync-errors", "broken.md")
    assert has_element?(view, "#spec-entries li h3", "Alpha")
    refute html =~ "PRIVATE_SOURCE_CONTENT"

    File.rm!(Path.join(specs, "broken.md"))
    assert {:ok, _} = SpecImporter.sync(project.id)
    assert refresh(view) =~ "3 unchanged"
    refute has_element?(view, "#sync-errors")
  end

  test "opening after a background failure displays its status and enabled copy", %{
    conn: conn,
    project: project,
    specs: specs
  } do
    previous = Application.fetch_env!(:boss, :spec_auto_sync)
    Application.put_env(:boss, :spec_auto_sync, true)
    on_exit(fn -> Application.put_env(:boss, :spec_auto_sync, previous) end)
    File.write!(Path.join(specs, "broken.md"), "---\nid: [\n---\n")
    assert {:error, _} = start_watcher(project)
    {:ok, view, _} = live(conn, "/projects/#{project.id}")
    assert has_element?(view, "#sync-help", "refresh automatically")
    assert has_element?(view, "#sync-errors", "broken.md")
  end

  test "notifications coalesce without cancelling a slow read and load the latest entries", %{
    conn: conn,
    project: project,
    specs: specs
  } do
    start_watcher(project)
    {:ok, view, _} = live(conn, "/projects/#{project.id}")
    old_result = {[], {:error, [%{path: "old.md", message: "Obsolete error"}]}}
    {old_task, monitor} = hold_async(view, :refresh, old_result)
    write_specs(specs)

    for _ <- 1..3, do: assert({:ok, _} = SpecImporter.sync(project.id))

    render(view)
    assert {_, ^old_task, _} = :sys.get_state(view.pid).socket.private.live_async.refresh
    send(old_task, :release)
    assert_receive {:DOWN, ^monitor, :process, ^old_task, :normal}
    assert refresh(view) =~ "3 unchanged"
    assert has_element?(view, "#spec-entries li h3", "Alpha")
    refute render(view) =~ "Obsolete error"
  end

  test "a killed manual sync cannot display a cached successful result", %{
    conn: conn,
    project: project
  } do
    assert {:ok, _} = start_watcher(project)
    {:ok, view, _} = live(conn, "/projects/#{project.id}")
    assert has_element?(view, "#sync-status", "Sync complete")
    {manual_task, monitor} = hold_async(view, :sync, {:ok, %{}})

    :sys.replace_state(view.pid, fn state ->
      %{state | socket: Phoenix.LiveView.cancel_async(state.socket, :sync, :kill)}
    end)

    assert_receive {:DOWN, ^monitor, :process, ^manual_task, :killed}
    refresh(view)
    assert has_element?(view, "#sync-status", "Sync was interrupted")
    refute has_element?(view, "#sync-status", "Sync complete")
    refute has_element?(view, "#sync-specs[disabled]")
  end

  test "automatic refresh does not release manual busy state or restore its older summary", %{
    conn: conn,
    project: project,
    specs: specs
  } do
    start_watcher(project)
    {:ok, view, _} = live(conn, "/projects/#{project.id}")
    old_result = {:ok, %{created: 99, revised: 0, unchanged: 0, missing: 0}}
    {manual_task, monitor} = hold_async(view, :sync, old_result)
    write_specs(specs)
    assert {:ok, _} = SpecImporter.sync(project.id)
    assert refresh_while_syncing(view) =~ "3 created"
    assert has_element?(view, "#sync-specs[disabled]")
    send(manual_task, :release)
    assert_receive {:DOWN, ^monitor, :process, ^manual_task, :normal}
    refresh(view)
    assert has_element?(view, "#sync-status", "3 created")
    refute has_element?(view, "#sync-status", "99 created")
    refute has_element?(view, "#sync-specs[disabled]")
    assert has_element?(view, "#spec-entries li h3", "Alpha")
  end

  test "a repeated event cannot replace an active sync or hide its errors", %{project: project} do
    socket = busy_socket(project)
    assert {:noreply, ^socket} = ProjectLive.handle_event("sync", %{}, socket)
    html = render_component(&ProjectLive.render/1, socket.assigns)
    assert html =~ "disabled"
    assert html =~ "broken.md"
  end

  test "an async exit refreshes saved entries before offering a safe retry", %{project: project} do
    {:ok, saved} =
      Projects.record_spec(project.id, %{
        relative_path: "saved.md",
        title: "Saved task",
        original_text: "# Saved task\n"
      })

    socket = %{busy_socket(project) | transport_pid: nil}

    assert {:noreply, reloading} =
             ProjectLive.handle_async(:sync, {:exit, "PRIVATE_CRASH_DETAILS"}, socket)

    refute reloading.assigns.syncing
    refute reloading.assigns.status =~ "PRIVATE_CRASH_DETAILS"

    assert {:noreply, socket} =
             ProjectLive.handle_async(
               :refresh,
               {:ok, {Projects.list_spec_entries(project.id), :interrupted}},
               reloading
             )

    refute socket.assigns.syncing
    assert socket.assigns.status =~ "Try Sync again"
    assert [%{id: id}] = socket.assigns.entries
    assert id == saved.spec.id
  end

  test "failed reload preserves the last visible entries and errors", %{project: project} do
    socket = busy_socket(project)
    entries = [%{id: 123, title: "Last loaded task"}]
    socket = Phoenix.Component.assign(socket, entries: entries, syncing: false)

    assert {:noreply, failed} =
             ProjectLive.handle_async(:refresh, {:exit, "PRIVATE_DATABASE_DETAILS"}, socket)

    refute failed.assigns.syncing
    assert failed.assigns.entries == entries
    assert failed.assigns.errors == socket.assigns.errors
    assert failed.assigns.status =~ "Showing the last loaded entries"
    refute failed.assigns.status =~ "PRIVATE_DATABASE_DETAILS"
  end

  defp busy_socket(project) do
    %Phoenix.LiveView.Socket{
      transport_pid: self(),
      assigns: %{
        __changed__: %{},
        project: project,
        syncing: true,
        refreshing: false,
        refresh_pending: nil,
        status: "Syncing specs…",
        entries: [],
        auto_sync: false,
        errors: [%{path: "broken.md", message: "Invalid frontmatter"}]
      }
    }
  end

  defp write_specs(specs) do
    for {file, title} <- [{"alpha.md", "Alpha"}, {"beta.md", "Beta"}, {"gamma.md", "Gamma"}] do
      File.write!(Path.join(specs, file), "# #{title}\nSource text.\n")
    end
  end

  defp sync(view) do
    view |> element("#sync-specs") |> render_click()
    render_async(view)
    render_async(view)
  end

  defp refresh(view) do
    render(view)
    render_async(view)
    render_async(view)
  end

  defp refresh_while_syncing(view) do
    render(view)

    case :sys.get_state(view.pid).socket.private[:live_async][:refresh] do
      {_, pid, _} ->
        monitor = Process.monitor(pid)
        assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000

      nil ->
        :ok
    end

    render(view)
  end

  defp start_watcher(project) do
    SpecWatcher.subscribe(project.id)
    start_supervised!({SpecWatcher, interval_ms: 60_000, settle_ms: 0})
    id = project.id
    assert_receive {:spec_sync, ^id, result}, 2_000
    result
  end

  # Control task completion order without adding timing hooks to production code.
  defp hold_async(view, key, result) do
    test_pid = self()

    :sys.replace_state(view.pid, fn state ->
      socket =
        state.socket
        |> Phoenix.Component.assign(syncing: key == :sync, refreshing: key == :refresh)
        |> Phoenix.LiveView.start_async(key, fn ->
          Process.flag(:trap_exit, true)
          send(test_pid, {:held_task, self()})

          receive do
            :release -> result
          end
        end)

      %{state | socket: socket}
    end)

    assert_receive {:held_task, pid}
    on_exit(fn -> Process.exit(pid, :kill) end)
    {pid, Process.monitor(pid)}
  end

  defp git!(root, args) do
    env = for {key, _} <- System.get_env(), String.starts_with?(key, "GIT_"), do: {key, nil}
    env = env ++ [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"}]

    {_, 0} =
      System.cmd(
        "git",
        [
          "-C",
          root,
          "-c",
          "user.name=Test",
          "-c",
          "user.email=test@example.invalid",
          "-c",
          "commit.gpgSign=false" | args
        ],
        env: env,
        stderr_to_stdout: true
      )
  end
end
