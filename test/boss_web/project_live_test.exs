defmodule BossWeb.ProjectLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-ui-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    File.mkdir!(Path.join(root, "specs"))
    {_, 0} = System.cmd("git", ["-C", root, "init", "-b", "main"])

    {_, 0} =
      System.cmd("git", [
        "-C",
        root,
        "-c",
        "user.name=Test",
        "-c",
        "user.email=test@example.invalid",
        "commit",
        "--allow-empty",
        "-m",
        "base"
      ])

    {:ok, session} = Boss.LocalAccess.exchange(Boss.LocalAccess.new_token())
    conn = %{conn | host: "127.0.0.1", port: 4002} |> init_test_session(local_session: session)
    %{conn: conn, root: root}
  end

  test "registers a project, rejects duplicates and restores it when reopened", %{
    conn: conn,
    root: root
  } do
    {:ok, view, html} = live(conn, "/")
    assert html =~ "No projects yet"

    view
    |> form("#project-form",
      project: %{root_path: root, specs_path: "specs", name: "Local project"}
    )
    |> render_change()

    view
    |> form("#project-form",
      project: %{root_path: root, specs_path: "specs", name: "Local project"}
    )
    |> render_submit()

    assert has_element?(view, "#projects li", "Local project")
    assert render(view) =~ "Project added"
    refute has_element?(view, "#project_name[value='Local project']")

    view
    |> form("#project-form", project: %{root_path: root, specs_path: "specs"})
    |> render_submit()

    assert render(view) =~ "already registered"
    assert length(Boss.Projects.list_projects()) == 1
    {:ok, reopened, _html} = live(conn, "/")
    assert has_element?(reopened, "#projects li", "Local project")
  end

  test "invalid path is explained without registering a project", %{conn: conn, root: root} do
    {:ok, view, _html} = live(conn, "/")

    view
    |> form("#project-form", project: %{root_path: root, specs_path: "../outside"})
    |> render_submit()

    assert render(view) =~ "specs directory must be inside the project"
    assert Boss.Projects.list_projects() == []
  end
end
