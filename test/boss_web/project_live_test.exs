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

  @tag skip: :os.type() != {:unix, :darwin}
  @tag timeout: 120_000
  test "adding a documentation repository opens Start and starts its first generated task", c do
    alias Boss.{Deliveries, Projects, Repo}
    alias Boss.Projects.Intake

    File.mkdir!(Path.join(c.root, "docs"))

    File.write!(
      Path.join(c.root, "docs/product.md"),
      "# Product\nAlready implemented: existing.txt.\n## Work\nWrite one, then two."
    )

    File.write!(
      Path.join(c.root, "docs/architecture.md"),
      "# Architecture\nresult.txt stores the output."
    )

    File.write!(Path.join(c.root, "existing.txt"), "implemented")
    File.write!(Path.join(c.root, "result.txt"), "base")
    File.cp!(Path.expand("../fixtures/delivery_check.py", __DIR__), Path.join(c.root, "check.py"))
    assert {_, 0} = System.cmd("git", ["-C", c.root, "add", "."])

    assert {_, 0} =
             System.cmd("git", [
               "-C",
               c.root,
               "-c",
               "user.name=Test",
               "-c",
               "user.email=test@example.invalid",
               "commit",
               "-m",
               "fixture"
             ])

    bin = Path.join(c.root, "fixture-bin")
    gates = Path.join(c.root, "fixture-gates")
    File.mkdir!(bin)
    File.mkdir!(gates)
    codex = Path.join(bin, "codex")
    File.cp!(Path.expand("../fixtures/codex_autopilot.py", __DIR__), codex)
    File.chmod!(codex, 0o700)

    env = %{
      "PATH" => bin <> ":" <> System.fetch_env!("PATH"),
      "BOSS_AUTOPILOT_GATES" => gates,
      "BOSS_DELIVERY_FIXTURE" => c.root,
      "BOSS_AUTOPILOT_MODE" => "approved"
    }

    previous = Map.take(System.get_env(), Map.keys(env))
    manager = :sys.get_state(Boss.Runs.Manager)
    assert manager.active == %{}
    System.put_env(env)

    on_exit(fn ->
      try do
        BossWeb.ManagerFixture.restore(manager, [])
      after
        Enum.each(Map.keys(env), fn key ->
          if Map.has_key?(previous, key),
            do: System.put_env(key, previous[key]),
            else: System.delete_env(key)
        end)
      end
    end)

    {:ok, home, _} = live(c.conn, "/")
    choose(home, "repository")
    assert has_element?(home, "#project_intake_mode[checked]")

    {:ok, view, _} = home |> form("#project-form") |> render_submit() |> follow_redirect(c.conn)
    [project] = Projects.list_projects()
    assert project.intake_mode == "documentation"
    assert Projects.list_spec_entries(project.id) == []
    assert Intake.latest(project.id) == nil
    render_async(view, 2_000)
    refute has_element?(view, "#autopilot-content[hidden]")

    view
    |> form("#autopilot-form", %{"command" => "python3 check.py", "reviewer" => "codex"})
    |> render_submit()

    await_intake(fn -> File.exists?(Path.join(gates, "one-1.waiting")) end)
    assert %{status: "finished", batch_id: batch} = Intake.latest(project.id)
    assert is_binary(batch)
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1

    assert Enum.sort(Enum.map(Projects.list_spec_entries(project.id), & &1.title)) == [
             "one",
             "two"
           ]

    refute File.exists?(Path.join(gates, "two-1.waiting"))

    {:ok, current} = Deliveries.Autopilot.current(project.id)
    {:ok, _} = Deliveries.Autopilot.cancel(project.id, current.id, current.version)
    await_intake(fn -> :sys.get_state(Boss.Runs.Manager).active == %{} end)
  end

  defp await_intake(predicate, remaining \\ 1_500)
  defp await_intake(_, 0), do: flunk("Documentation intake did not reach the expected stage")

  defp await_intake(predicate, remaining) do
    unless predicate.() do
      Process.sleep(20)
      await_intake(predicate, remaining - 1)
    end
  end

  defp choose(view, kind) do
    view |> element("#choose-#{kind}") |> render_click()
    render_async(view, 2_000)
  end
end
