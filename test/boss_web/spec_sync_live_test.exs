defmodule BossWeb.SpecSyncLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Boss.Projects
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

    assert reloading.assigns.syncing
    refute reloading.assigns.status =~ "PRIVATE_CRASH_DETAILS"

    assert {:noreply, socket} =
             ProjectLive.handle_async(
               :reload,
               {:ok, Projects.list_spec_entries(project.id)},
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
    socket = %{socket | assigns: Map.put(socket.assigns, :entries, entries)}

    assert {:noreply, failed} =
             ProjectLive.handle_async(:reload, {:exit, "PRIVATE_DATABASE_DETAILS"}, socket)

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
        status: "Syncing specs…",
        entries: [],
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
