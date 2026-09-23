defmodule CuckodingWeb.StatusLiveTest do
  use CuckodingWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cuckoding.Execution
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Task

  test "renders the project-first dashboard and resource status", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Your Cuckoding workspace"
    assert has_element?(view, "main#main-content")
    assert has_element?(view, "h1", "Your Cuckoding workspace")
    assert has_element?(view, "#overview-heading", "Application and resources")
    assert has_element?(view, "#active-agent-count", "0")
    assert has_element?(view, "#projects-heading", "Projects")

    assert has_element?(
             view,
             "#agent-activity-chart",
             "No samples from currently active agents yet"
           )

    assert has_element?(
             view,
             "#agent-activity-chart details table caption",
             "Measured current-agent activity by UTC minute"
           )

    assert :binary.match(html, "id=\"projects-heading\"") <
             :binary.match(html, "id=\"activity-heading\"")

    assert :binary.match(html, "id=\"activity-heading\"") <
             :binary.match(html, "id=\"operations-heading\"")

    assert :binary.match(html, "id=\"operations-heading\"") <
             :binary.match(html, "id=\"overview-heading\"")

    assert has_element?(view, "#projects-empty", "Nothing runs during project setup")
    assert has_element?(view, "#operation-filters select[name='filter[state]']")
    assert has_element?(view, "button[phx-click='filter-activity'][phx-value-category='agent']")
    assert has_element?(view, "a[href='/projects/new']", "Add project")
    refute has_element?(view, "#guided-run-form")
    refute html =~ "Create queued run"
    assert has_element?(view, "nav[aria-label=Diagnostics] a[href='/health']", "Health JSON")
  end

  test "activity chart filters committed events and survives durable refresh", %{conn: conn} do
    run = run_fixture("Activity task")

    {:ok, _} =
      EventStore.append(run.id, %{
        event_type: "agent.message",
        public_summary: "Agent note",
        payload: %{}
      })

    {:ok, _} =
      EventStore.append(run.id, %{
        event_type: "run.updated",
        public_summary: "Workflow note",
        payload: %{}
      })

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#activity-log-heading", "Committed events")
    assert has_element?(view, "[aria-label='Recent activity table']", "Agent note")
    assert has_element?(view, "[aria-label='Recent activity table']", "Workflow note")

    view |> element("button[phx-value-category='agent']") |> render_click()
    assert has_element?(view, "[aria-label='Recent activity table']", "Agent note")
    refute has_element?(view, "[aria-label='Recent activity table']", "Workflow note")

    {:ok, _} =
      EventStore.append(run.id, %{
        event_type: "agent.message",
        public_summary: "Live agent note",
        payload: %{}
      })

    assert has_element?(view, "[aria-label='Recent activity table']", "Live agent note")
    assert has_element?(view, "button[phx-value-category='agent']", "2")

    send(view.pid, :refresh_dashboard)
    assert has_element?(view, "button[phx-value-category='agent'][aria-pressed='true']")
    refute has_element?(view, "[aria-label='Recent activity table']", "Workflow note")
  end

  test "operations table filters by state and search without changing runs", %{conn: conn} do
    run = run_fixture("Filter target task")
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#operation-#{run.id} a", "Inspect run")
    assert has_element?(view, "#operation-#{run.id} a", "Task")

    view
    |> form("#operation-filters")
    |> render_change(%{"filter" => %{"state" => "attention", "project" => "all", "query" => ""}})

    refute has_element?(view, "#operation-#{run.id}")
    assert has_element?(view, "#operations-filter-empty")

    view
    |> form("#operation-filters")
    |> render_change(%{
      "filter" => %{"state" => "active", "project" => "all", "query" => "Filter target"}
    })

    assert has_element?(view, "#operation-#{run.id}")
    send(view.pid, :refresh_dashboard)
    assert has_element?(view, "#operation-#{run.id}")
  end

  test "project cards count blocked and completed delivery tasks after durable changes", %{
    conn: conn
  } do
    blocked_run = run_fixture("Blocked dashboard task")
    blocked_task = Repo.get!(Task, blocked_run.task_id)
    board = Repo.get!(Board, blocked_task.board_id)

    assert {:ok, _} =
             Workflows.transition_task(blocked_task.id, "ready", "dashboard:blocked:ready")

    assert {:ok, _} =
             Execution.transition_run(blocked_run.id, "running", "dashboard:blocked:running")

    assert {:ok, _} =
             Execution.transition_run(blocked_run.id, "blocked", "dashboard:blocked:blocked")

    {:ok, done_task} =
      Workflows.create_task(%{board_id: board.id, title: "Completed dashboard task", position: 1})

    assert {:ok, _} = Workflows.transition_task(done_task.id, "ready", "dashboard:done:ready")

    {:ok, done_run} =
      Execution.create_run(%{
        task_id: done_task.id,
        sequence: 1,
        policy_snapshot_id: blocked_run.policy_snapshot_id,
        branch: "feature/dashboard-done-#{done_task.id}",
        base_sha: blocked_run.base_sha
      })

    assert {:ok, _} = Execution.transition_run(done_run.id, "running", "dashboard:done:running")

    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#project-state-#{board.project_id}-blocked", "1")
    assert has_element?(view, "#project-state-#{board.project_id}-done", "0")

    assert {:ok, _} = Execution.transition_run(done_run.id, "done", "dashboard:done:done")
    send(view.pid, :refresh_dashboard)
    assert has_element?(view, "#project-state-#{board.project_id}-blocked", "1")
    assert has_element?(view, "#project-state-#{board.project_id}-done", "1")
    assert has_element?(view, "#project-state-#{board.project_id}-done", "Completed")
  end

  defp run_fixture(title) do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Dashboard #{suffix}",
        repo_path: "/tmp/dashboard-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/dashboard-workspaces-#{suffix}",
        port_range_start: 47_000,
        port_range_end: 47_100
      })

    {:ok, config} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: String.pad_leading(Integer.to_string(suffix, 16), 64, "0"),
        config_json: %{"version" => 1},
        trusted_at: DateTime.utc_now()
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "default",
        version: 1,
        definition_json: %{"stages" => [%{"key" => "agent", "role" => "implementer"}]},
        published_at: DateTime.utc_now()
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Dashboard board",
        concurrency_limit: 1
      })

    {:ok, task} = Workflows.create_task(%{board_id: board.id, title: title, position: 0})

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: config.id,
        branch: "feature/dashboard-#{suffix}",
        base_sha: String.duplicate("a", 40)
      })

    run
  end

  test "lists a previously registered project and its next action", %{conn: conn} do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Existing project #{suffix}",
        repo_path: "/tmp/existing-project-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/existing-workspaces-#{suffix}",
        port_range_start: 47_000,
        port_range_end: 47_100
      })

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#project-#{project.id}", project.name)
    assert has_element?(view, "#project-#{project.id}", "main")

    assert has_element?(
             view,
             "#project-#{project.id} a[href='/projects/#{project.id}/edit']",
             "Set up or start project"
           )

    assert has_element?(view, "#project-#{project.id} a", "Create board")
  end

  test "sets a restrictive content security policy", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert [policy] = get_resp_header(conn, "content-security-policy")
    assert policy =~ "default-src 'self'"
    assert policy =~ "frame-ancestors 'none'"
    refute policy =~ "unsafe-inline"
  end
end
