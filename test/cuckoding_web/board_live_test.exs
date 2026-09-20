defmodule CuckodingWeb.BoardLiveTest do
  use CuckodingWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows
  alias Cuckoding.Workflows.Definition

  @now ~U[2026-09-17 22:00:00.000000Z]

  setup do
    suffix = System.unique_integer([:positive])

    {:ok, project} =
      Projects.register(%{
        name: "Board project #{suffix}",
        repo_path: "/tmp/board-project-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/board-workspaces-#{suffix}",
        port_range_start: 45_000,
        port_range_end: 45_100
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "default",
        version: 1,
        definition_json: Definition.default(),
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Product",
        description: "Accessible delivery board",
        concurrency_limit: 1
      })

    {:ok, alpha} =
      Workflows.create_task(%{
        board_id: board.id,
        title: "Alpha task",
        description: "First task",
        priority: 2,
        position: 0
      })

    {:ok, beta} =
      Workflows.create_task(%{
        board_id: board.id,
        title: "Beta task",
        priority: 1,
        position: 1
      })

    assert {:ok, %{result: %{"outcome" => "transitioned"}}} =
             Workflows.transition_task(beta.id, "ready", "board:#{beta.id}:ready")

    {:ok, board: board, alpha: alpha, beta: Repo.reload(beta)}
  end

  test "board exposes semantic columns, persistent filters, and non-color status cues", %{
    conn: conn,
    board: board,
    alpha: alpha
  } do
    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}")

    assert has_element?(view, "main#main-content")
    assert has_element?(view, "h1", "Product")
    assert has_element?(view, "form[aria-label='Filter tasks'] input[type=search]")
    assert has_element?(view, "#column-draft[aria-labelledby='column-draft-heading']")
    assert has_element?(view, "#column-draft-heading", "Draft")
    assert has_element?(view, "#task-#{alpha.id}[draggable=true]", "Alpha task")
    refute has_element?(view, "#task-#{alpha.id}", "Knowledge: 0 linked")

    assert has_element?(
             view,
             "nav[aria-label='Main navigation'] a[aria-current=page]",
             "Projects"
           )

    assert has_element?(view, "details#new-task-panel:not([open]) summary", "Add a task")
    assert has_element?(view, "details#agent-task-intake:not([open]) summary", "Ask an agent")
    assert has_element?(view, "#task-#{alpha.id} label", "Move task")
    assert has_element?(view, "#task-#{alpha.id} select[name=to] option[value=ready]")
    assert has_element?(view, "#board-status[role=status][aria-live=polite]")

    path = ~p"/boards/#{board.id}?#{%{q: "Beta", state: "ready"}}"

    view
    |> element("form[aria-label='Filter tasks']")
    |> render_change(%{"filters" => %{"q" => "Beta", "state" => "ready"}})

    assert_patch(view, path)
    assert has_element?(view, "#column-ready", "Beta task")
    refute has_element?(view, "#toggle-board-states")
    refute has_element?(view, "#task-#{alpha.id}")

    {:ok, restored, _html} = live(conn, path)
    assert has_element?(restored, "input[name='filters[q]'][value='Beta']")
    assert has_element?(restored, "select[name='filters[state]'] option[value=ready][selected]")
  end

  test "shows occupied states and updates other browser sessions from durable events", %{
    conn: conn,
    board: board,
    alpha: alpha
  } do
    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}")
    refute has_element?(view, "#column-archived")
    view |> element("#toggle-board-states") |> render_click()
    assert has_element?(view, "#column-archived")
    view |> element("#toggle-board-states") |> render_click()
    refute has_element?(view, "#column-archived")

    assert {:ok, _} = Workflows.transition_task(alpha.id, "archived", "ux:archive:#{alpha.id}")
    assert :sys.get_state(view.pid).socket.assigns.refresh_pending
    send(view.pid, :refresh_board)
    assert has_element?(view, "#column-archived #task-#{alpha.id}")

    {:ok, restored, _html} = live(conn, ~p"/boards/#{board.id}?q=missing")
    assert has_element?(restored, "a", "Clear filters")
    assert render(restored) =~ "No tasks match these filters"
    restored |> element("a", "Clear filters") |> render_click()
    assert_patch(restored, ~p"/boards/#{board.id}")
    assert has_element?(restored, "#task-#{alpha.id}")
  end

  test "task guidance follows state and keeps completed task details readable", %{
    conn: conn,
    board: board,
    alpha: task
  } do
    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}/tasks/#{task.id}")

    assert has_element?(
             view,
             "section[aria-labelledby=task-run-heading]",
             "save the task, then mark it Ready"
           )

    assert has_element?(view, "#task-edit button[phx-disable-with='Saving task…']")
    view |> form("#task-edit", task: %{title: "Unsaved outcome"}) |> render_change()
    view |> element("#mark-task-ready") |> render_click()
    assert has_element?(view, "#task-error", "Save your task changes")
    assert Workflows.get_task(task.id).state == "draft"
    render_click(view, "prepare-run")
    assert has_element?(view, "#task-error", "Save your task changes")
    assert Cuckoding.Execution.list_runs(task.id) == []
    view |> form("#task-edit", task: %{title: "Saved outcome"}) |> render_submit()
    refute has_element?(view, "#task-edit [role=status]")
    view |> element("#mark-task-ready") |> render_click()
    assert Workflows.get_task(task.id).state == "ready"
    task |> Ecto.Changeset.change(state: "done") |> Repo.update!()
    {:ok, finished, _html} = live(conn, ~p"/boards/#{board.id}/tasks/#{task.id}")

    assert has_element?(
             finished,
             "section[aria-labelledby=task-description-heading]",
             "First task"
           )

    refute has_element?(finished, "#task-edit")
    refute has_element?(finished, "#prepare-task-run")

    assert has_element?(
             finished,
             "section[aria-labelledby=task-run-heading]",
             "Review the run history"
           )
  end

  test "keyboard transition reconciles from the durable command result and explains rejection", %{
    conn: conn,
    board: board,
    alpha: alpha
  } do
    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}")

    view
    |> element("#task-#{alpha.id} form")
    |> render_submit(%{"id" => alpha.id, "to" => "ready"})

    assert has_element?(view, "#board-status", "Moved Alpha task to Ready")
    assert has_element?(view, "#column-ready #task-#{alpha.id}")
    assert Repo.get!(Cuckoding.Workflows.Task, alpha.id).state == "ready"
    assert has_element?(view, "#column-ready", "Ready tasks do not start automatically")
    assert has_element?(view, "#start-task-#{alpha.id}", "Set up and start")
    task_path = ~p"/boards/#{board.id}/tasks/#{alpha.id}"

    assert {:error, {:live_redirect, %{to: ^task_path}}} =
             view |> element("#start-task-#{alpha.id}") |> render_click()

    {:ok, task_view, _html} = live(conn, task_path)
    assert has_element?(task_view, "#prepare-task-run", "Prepare run")
    assert has_element?(task_view, "#prepare-task-run[phx-disable-with='Preparing run…']")
    assert Cuckoding.Execution.list_runs(alpha.id) == []

    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}")

    render_hook(view, "transition-task", %{"id" => alpha.id, "to" => "done"})

    assert has_element?(
             view,
             "#board-error[role=alert]",
             "Move rejected: this task cannot move from its current state"
           )

    assert has_element?(view, "#column-ready #task-#{alpha.id}")
  end

  test "creates a bounded draft task from the board", %{conn: conn, board: board} do
    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}")

    view
    |> form("#create-task-form",
      task: %{title: "New outcome", description: "Acceptance details", priority: "7"}
    )
    |> render_submit()

    task = Repo.get_by!(Cuckoding.Workflows.Task, board_id: board.id, title: "New outcome")
    assert task.state == "draft"
    assert task.priority == 7
    assert has_element?(view, "#board-status", "Created New outcome in Draft")
    assert has_element?(view, "#column-draft #task-#{task.id}")

    assert Repo.exists?(
             from(event in RunEvent,
               where: event.run_id == ^("task:" <> task.id) and event.event_type == "task.created"
             )
           )
  end

  test "task detail edits draft tasks with labels and durable audit evidence", %{
    conn: conn,
    board: board,
    alpha: alpha
  } do
    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}/tasks/#{alpha.id}")

    assert has_element?(view, "h1", "Alpha task")
    assert has_element?(view, "#task-edit label", "Title")
    assert has_element?(view, "#task-edit label", "Description")
    assert has_element?(view, "#task-edit label", "Priority")
    assert has_element?(view, "#host-runner-notice", "not a sandbox")

    view
    |> form("#task-edit",
      task: %{title: "Updated task", description: "Clearer scope", priority: "5"}
    )
    |> render_submit()

    assert has_element?(view, "#task-status", "Task details saved")
    assert Repo.get!(Cuckoding.Workflows.Task, alpha.id).title == "Updated task"

    assert Repo.exists?(
             from(event in RunEvent,
               where: event.run_id == ^("task:" <> alpha.id) and event.event_type == "task.edited"
             )
           )

    assert {:ok, %{result: %{"outcome" => "transitioned"}}} =
             Workflows.transition_task(alpha.id, "cancelled", "board:#{alpha.id}:cancelled")

    {:ok, locked, _html} = live(conn, ~p"/boards/#{board.id}/tasks/#{alpha.id}")
    refute has_element?(locked, "#task-edit")
    assert has_element?(locked, "p", "Task details can be edited only in Draft or Ready")
  end
end
