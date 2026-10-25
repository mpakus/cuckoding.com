defmodule BossWeb.ProjectLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  defmodule Picker do
    use GenServer
    def start_link(result), do: GenServer.start_link(__MODULE__, result)
    def init(result), do: {:ok, {result, nil}}

    def handle_call({:choose, kind, initial}, _, {result, _}),
      do: {:reply, result, {result, {kind, initial}}}

    def handle_call({:result, result}, _, {_, request}), do: {:reply, :ok, {result, request}}
    def handle_call(:request, _, {_, request} = state), do: {:reply, request, state}
  end

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
    picker = start_supervised!({Picker, {:ok, root}})
    Application.put_env(:boss, :folder_picker_server, picker)
    on_exit(fn -> Application.delete_env(:boss, :folder_picker_server) end)
    %{conn: conn, root: root, picker: picker}
  end

  test "chooses a repository, rejects duplicates and restores it when reopened", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")
    assert html =~ "No projects yet"
    assert has_element?(view, "#project_root_path[readonly]")
    refute has_element?(view, "input[name='project[root_path]']")
    choose(view, "repository")

    view |> form("#project-form", project: %{name: "Local project"}) |> render_change()
    view |> form("#project-form", project: %{name: "Local project"}) |> render_submit()
    assert has_element?(view, "#projects li", "Local project")
    assert render(view) =~ "Project added"
    refute has_element?(view, "#project_name[value='Local project']")
    assert has_element?(view, "#add-project[disabled]")

    choose(view, "repository")
    view |> form("#project-form") |> render_submit()
    assert render(view) =~ "already registered"
    assert length(Boss.Projects.list_projects()) == 1
    {:ok, reopened, _html} = live(conn, "/")
    assert has_element?(reopened, "#projects li", "Local project")
  end

  test "cancel or unavailable picker keeps the selected folder and other inputs", %{
    conn: conn,
    picker: picker,
    root: root
  } do
    {:ok, view, _} = live(conn, "/")
    choose(view, "repository")
    view |> form("#project-form", project: %{name: "Keep me"}) |> render_change()

    for result <- [:cancelled, {:error, :unavailable}] do
      :ok = GenServer.call(picker, {:result, result})
      choose(view, "repository")
      assert has_element?(view, "#project_root_path[value='#{root}']")
      assert has_element?(view, "#project_name[value='Keep me']")
    end

    assert render(view) =~ "Folder selection is unavailable"
  end

  test "selects specs with the OS picker and still enforces the repository boundary", %{
    conn: conn,
    picker: picker
  } do
    {:ok, view, _} = live(conn, "/")
    choose(view, "repository")
    :ok = GenServer.call(picker, {:result, {:ok, System.tmp_dir!()}})
    choose(view, "specs")
    view |> form("#project-form") |> render_submit()
    assert render(view) =~ "specs directory must be inside the project"
    assert Boss.Projects.list_projects() == []
  end

  test "forged form paths cannot replace the OS selection", %{conn: conn, root: root} do
    {:ok, view, _} = live(conn, "/")
    render_submit(view, "create", %{"project" => %{"root_path" => root, "specs_path" => "specs"}})
    assert Boss.Projects.list_projects() == []
    choose(view, "repository")

    render_change(view, "validate", %{
      "project" => %{"root_path" => "/forged", "specs_path" => "/forged"}
    })

    render_submit(view, "create", %{
      "project" => %{"root_path" => "/forged", "specs_path" => "/forged"}
    })

    assert [project] = Boss.Projects.list_projects()
    assert project.root_path != "/forged"
    assert project.specs_path == Path.join(project.root_path, "specs")
  end

  test "reopens specs selection inside the chosen repository", %{
    conn: conn,
    root: root,
    picker: picker
  } do
    chosen_specs = Path.join(root, "requirements")
    File.mkdir!(chosen_specs)
    {:ok, view, _} = live(conn, "/")
    choose(view, "repository")
    :ok = GenServer.call(picker, {:result, {:ok, chosen_specs}})
    choose(view, "specs")
    assert {:specs, initial} = GenServer.call(picker, :request)
    assert initial == Path.join(root, "specs")
    choose(view, "specs")
    assert {:specs, ^chosen_specs} = GenServer.call(picker, :request)
    view |> form("#project-form") |> render_submit()
    assert [project] = Boss.Projects.list_projects()
    assert project.specs_path == Path.join(project.root_path, "requirements")
  end

  defp choose(view, kind) do
    view |> element("#choose-#{kind}") |> render_click()
    render_async(view)
  end
end
