defmodule BossWeb.TaskDependenciesLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Ecto.Query
  alias Boss.{LocalAccess, Projects, Repo, Runs, Deliveries}
  alias Boss.Runs.Manager
  alias BossWeb.ManagerFixture

  setup %{conn: conn} do
    owner = self()
    original = :sys.get_state(Manager)
    assert original.active == %{}

    :sys.replace_state(Manager, fn state ->
      %{
        state
        | worker: fn _, _, _ -> send(owner, :unexpected_worker) end,
          delivery_worker: fn _, _, _ -> send(owner, :unexpected_worker) end
      }
    end)

    on_exit(fn -> ManagerFixture.restore(original, [:worker, :delivery_worker]) end)

    project =
      Repo.insert!(%Projects.Project{
        name: "Dependency UI",
        root_path: "/dependency-ui",
        git_common_dir: "/dependency-ui/.git",
        specs_path: "/dependency-ui/specs",
        base_branch: "main"
      })

    dependency = spec(project, "first", [])
    saved = spec(project, "second", ["first"])
    {:ok, session} = LocalAccess.exchange(LocalAccess.new_token())
    conn = %{conn | host: "127.0.0.1", port: 4002} |> init_test_session(local_session: session)
    %{conn: conn, project: project, dependency: dependency, saved: saved}
  end

  test "waiting dependency links to its task, blocks forged starts, and refreshes only on Done",
       c do
    {:ok, view, _} = live(c.conn, path(c))
    settle(view)
    assert has_element?(view, "#task-dependencies", "Waiting · New")

    assert has_element?(
             view,
             "#task-dependencies a[href='/projects/#{c.project.id}/tasks/#{c.dependency.task.id}']",
             "first"
           )

    assert has_element?(view, "#start-codex[disabled]")
    assert has_element?(view, "#start-delivery[disabled]")
    start(view, :manual, command(view, :manual))
    start(view, :workflow, command(view, :workflow))
    settle(view)
    assert Runs.list(c.project.id, c.saved.task.id) == []
    assert Deliveries.list(c.project.id, c.saved.task.id) == []
    refute_receive :unexpected_worker, 20

    state(c.dependency, "ready_to_merge")
    refresh(view, c)
    assert has_element?(view, "#task-dependencies", "Waiting · Ready to merge")
    assert has_element?(view, "#start-codex[disabled]")
    state(c.dependency, "done")
    refresh(view, c)
    assert has_element?(view, "#task-dependencies-status", "All dependencies are Done")

    if :os.type() == {:unix, :darwin} do
      refute has_element?(view, "#start-codex[disabled]")
      refute has_element?(view, "#start-delivery[disabled]")
    end
  end

  test "URL source selection leaves pinned dependencies unchanged", c do
    spec(c.project, "second", ["different"])
    {:ok, view, _} = live(c.conn, path(c) <> "?revision=2")
    settle(view)
    assert has_element?(view, "#task-source", "different")
    assert has_element?(view, "#task-dependencies", "task snapshot revision 1")
    assert has_element?(view, "#task-dependencies code", "first")
    refute has_element?(view, "#task-dependencies code", "different")
    assert has_element?(view, "#start-codex[disabled]")
  end

  test "cycle and missing source reasons are visible and unknown identifiers are escaped", c do
    cyclic = spec(c.project, "cycle", ["cycle", "<script>alert(1)</script>"])
    {:ok, view, _} = live(c.conn, path(%{c | saved: cyclic}))
    settle(view)
    assert has_element?(view, "#task-dependency-issues")
    assert render(element(view, "#task-dependency-issues")) =~ "cycle"
    assert has_element?(view, "#task-dependencies code", "<script>alert(1)</script>")
    refute has_element?(view, "#task-dependencies script")
    assert has_element?(view, "#start-delivery[disabled]")

    c.dependency.spec |> Ecto.Changeset.change(missing: true) |> Repo.update!()
    render_patch(view, path(c))
    settle(view)
    assert has_element?(view, "#task-dependencies", "Source missing")
    assert has_element?(view, "#start-codex[disabled]")
    state(c.dependency, "done")
    refresh(view, c)
    assert has_element?(view, "#task-dependencies", "Done · source missing")
    assert has_element?(view, "#task-dependencies-status", "All dependencies are Done")
  end

  test "invalid declaration is shown as a blocker rather than no dependencies", c do
    invalid = spec(c.project, "invalid", nil)
    {:ok, view, _} = live(c.conn, path(%{c | saved: invalid}))
    settle(view)
    assert has_element?(view, "#task-dependency-issues", "depends_on")
    refute has_element?(view, "#task-dependencies-status", "No dependencies")
    assert has_element?(view, "#start-codex[disabled]")
    assert has_element?(view, "#start-delivery[disabled]")
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "dependency admission rejection refreshes stale details and clears request locks", c do
    for kind <- [:manual, :workflow] do
      state(c.dependency, "done")
      {:ok, view, _} = live(c.conn, path(c))
      settle(view)
      id = command(view, kind)
      state(c.dependency, "new")
      start(view, kind, id)
      settle(view)
      assert has_element?(view, error_selector(kind), "Dependencies are not ready")
      assert has_element?(view, "#task-dependencies", "Waiting · New")
      assert :sys.get_state(view.pid).socket.assigns.manual_pending == %{}
      refute :sys.get_state(view.pid).socket.assigns.delivery_requests[c.saved.task.id].locked
      refute has_element?(view, "#delivery-request-pending")
      refute_receive :unexpected_worker, 20
    end
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "unknown requests retry the same UUID and input after dependencies become blocked", c do
    for kind <- [:manual, :workflow] do
      state(c.dependency, "done")
      {:ok, view, _} = live(c.conn, path(c))
      settle(view)
      id = command(view, kind)
      :sys.suspend(Manager)
      start(view, kind, id)

      :sys.replace_state(view.pid, fn state ->
        key = if kind == :manual, do: :start_run, else: state.socket.assigns.delivery_starting
        %{state | socket: Phoenix.LiveView.cancel_async(state.socket, key, :kill)}
      end)

      settle(view)
      state(c.dependency, "new")
      refresh(view, c)
      assert command(view, kind) == id
      refute has_element?(view, start_selector(kind) <> "[disabled]")

      if kind == :workflow do
        assert has_element?(view, "#delivery-command[readonly][value='mix test']")
        start(view, kind, id, "changed input")
        assert has_element?(view, "#delivery-command[value='mix test']")
      end

      start(view, kind, id)
      :sys.resume(Manager)
      settle(view)
      assert has_element?(view, error_selector(kind), "Dependencies are not ready")
      assert :sys.get_state(view.pid).socket.assigns.manual_pending == %{}
      refute :sys.get_state(view.pid).socket.assigns.delivery_requests[c.saved.task.id].locked
      refute_receive :unexpected_worker, 20
    end
  end

  @tag skip: :os.type() != {:unix, :darwin}
  test "blocked new starts leave saved manual check and review controls available", c do
    state(c.dependency, "done")
    {:ok, {:new, run}} = Runs.admit(c.project.id, c.saved.task.id, Ecto.UUID.generate())

    workspace = %{
      "project_id" => to_string(c.project.id),
      "run_id" => run.id,
      "repo_path" => c.project.root_path,
      "git_common_dir" => c.project.git_common_dir,
      "base_branch" => "main",
      "base_commit" => String.duplicate("a", 40),
      "path" => "/retained/#{run.id}",
      "branch" => "codex/boss-run-#{run.id}"
    }

    {:ok, _} =
      Runs.update(run.id, status: "finished", cleanup: "group_empty", workspace: workspace)

    state(c.dependency, "new")

    {:ok, {:new, check}} =
      Runs.admit_check(c.project.id, run.id, Ecto.UUID.generate(), "mix test")

    {:ok, _} =
      Runs.update(check.id,
        status: "finished",
        cleanup: "group_empty",
        candidate_commit: String.duplicate("b", 40),
        exit_kind: "exit",
        exit_code: 0,
        workspace: %{
          "run_workspace" => workspace,
          "check_id" => check.id,
          "path" => "/checks/#{check.id}",
          "ref" => "refs/boss/checks/#{check.id}"
        }
      )

    {:ok, view, _} = live(c.conn, path(c))
    settle(view)
    assert has_element?(view, "#start-codex[disabled]")
    assert has_element?(view, "#check-form-#{run.id}")
    refute has_element?(view, "#check-form-#{run.id} button[disabled]")
    assert has_element?(view, "#start-review-#{check.id}")
    refute has_element?(view, "#start-review-#{check.id}[disabled]")
  end

  defp spec(project, id, dependencies) do
    {:ok, saved} =
      Projects.record_spec(project.id, %{
        explicit_id: id,
        relative_path: "#{id}.md",
        title: id,
        original_text: "---\nid: #{id}\ndepends_on: #{JSON.encode!(dependencies)}\n---\n# #{id}"
      })

    saved
  end

  defp state(saved, state),
    do:
      Repo.update_all(from(t in Boss.Tasks.Task, where: t.id == ^saved.task.id),
        set: [state: state]
      )

  defp path(c), do: "/projects/#{c.project.id}/tasks/#{c.saved.task.id}"
  defp start_selector(:manual), do: "#start-codex"
  defp start_selector(:workflow), do: "#start-delivery"
  defp error_selector(:manual), do: "#run-error"
  defp error_selector(:workflow), do: "#delivery-error"

  defp command(view, kind) do
    {selector, attribute} =
      if kind == :manual,
        do: {"#start-codex", "phx-value-command-id"},
        else: {"#delivery-form input[name='command_id']", "value"}

    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute(attribute)
    |> hd()
  end

  defp start(view, kind, id, text \\ "mix test")
  defp start(view, :manual, id, _), do: render_click(view, "start_run", %{"command-id" => id})

  defp start(view, :workflow, id, text),
    do:
      render_submit(view, "start_delivery", %{
        "command_id" => id,
        "command" => text,
        "reviewer" => "codex"
      })

  defp refresh(view, c) do
    send(view.pid, {:run_changed, c.project.id})
    settle(view)
  end

  defp settle(view) do
    render(view)
    for _ <- 1..5, do: render_async(view)
  end
end
