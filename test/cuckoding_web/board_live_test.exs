defmodule CuckodingWeb.BoardLiveTest do
  use CuckodingWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuckoding.Execution
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Projects
  alias Cuckoding.Projects.ProjectAutopilot, as: AutopilotProjection
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

  test "parallel cards show current stages, snapshotted roles, models and elapsed time", %{
    conn: conn,
    board: board,
    alpha: alpha,
    beta: beta
  } do
    {:ok, policy} =
      Projects.add_config_version(%{
        project_id: board.project_id,
        revision: 1,
        source_hash: "board-progress",
        config_json: %{},
        trusted_at: @now
      })

    for {key, name} <- [{"spec_writer", "Speculator"}, {"implementer", "Implementor"}] do
      {:ok, _} =
        Workflows.assign_role(%{
          board_id: board.id,
          role_key: key,
          role_kind: "agent",
          adapter_key: "codex",
          settings_json: %{"role_name" => name}
        })
    end

    {:ok, _} = Workflows.transition_task(alpha.id, "ready", "progress-alpha-ready")

    runs =
      for {task, stage, role} <- [
            {alpha, "specification", "spec_writer"},
            {beta, "development", "implementer"}
          ] do
        {:ok, run} =
          Execution.create_run(%{
            task_id: task.id,
            sequence: 1,
            policy_snapshot_id: policy.id,
            branch: "feature/#{task.id}",
            base_sha: String.duplicate("a", 40)
          })

        {:ok, _} = Execution.transition_run(run.id, "running", "progress:#{run.id}")

        {:ok, attempt} =
          Execution.create_stage_attempt(%{
            run_id: run.id,
            stage_key: stage,
            attempt: 1,
            role_key: role,
            role_kind: "agent"
          })

        {:ok, _} =
          Execution.transition_stage_attempt(attempt.id, "running", "progress:#{attempt.id}")

        {:ok, session} =
          Execution.create_agent_session(%{
            stage_attempt_id: attempt.id,
            adapter_key: "codex",
            requested_model: "selected-model",
            effective_grant_json: %{}
          })

        if task.id == beta.id do
          session |> Ecto.Changeset.change(actual_model: "observed-model") |> Repo.update!()
        end

        run
      end

    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}")
    assert has_element?(view, "#task-progress-#{alpha.id}", "Speculator")
    assert has_element?(view, "#task-progress-#{alpha.id}", "requested selected-model")
    assert has_element?(view, "#task-progress-#{beta.id}", "Implementor")
    assert has_element?(view, "#task-progress-#{beta.id}", "observed-model")
    assert has_element?(view, "#task-progress-#{beta.id}", "Stage elapsed:")
    assert has_element?(view, "#column-running #task-#{beta.id}[data-task-state=running]")
    {:ok, _} = Execution.transition_run(hd(runs).id, "paused", "progress:pause")
    send(view.pid, :refresh_board)
    assert has_element?(view, "#column-paused #task-#{alpha.id}[data-task-state=paused]")
    assert has_element?(view, "#column-running #task-#{beta.id}")
    send(view.pid, :board_tick)
    assert has_element?(view, "#task-progress-#{alpha.id}", "includes pauses")
  end

  test "board exposes semantic columns, persistent filters, and non-color status cues", %{
    conn: conn,
    board: board,
    alpha: alpha
  } do
    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}")

    assert has_element?(view, "main#main-content")
    assert has_element?(view, "h1", "Product")
    assert has_element?(view, "#board-project-operation", "Paused")
    assert has_element?(view, "#board-project-operation a", "Start or monitor project")
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

    assert has_element?(view, "button#add-task-button[aria-haspopup=dialog]", "Add a task")
    assert has_element?(view, "button#plan-tasks-button[aria-haspopup=dialog]", "Ask an agent")
    refute has_element?(view, "#create-task-form")
    refute has_element?(view, "#task-intake-form")
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

    assert has_element?(
             view,
             "#column-ready",
             "Start the project to run eligible tasks automatically"
           )

    assert has_element?(view, "#task-#{alpha.id}", "Project is not running automatically")
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

  test "running project explains an unmet prerequisite on its Ready card", %{
    conn: conn,
    board: board,
    alpha: alpha,
    beta: beta
  } do
    assert {:ok, _dependency} = Workflows.add_dependency(beta.id, alpha.id)

    %AutopilotProjection{project_id: board.project_id}
    |> AutopilotProjection.changeset(%{
      state: "running",
      max_active_runs: 2,
      critical_blocker_limit: 1
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}")

    assert has_element?(view, "#board-project-operation", "Running")
    assert has_element?(view, "#task-#{beta.id}", "Waiting for a prerequisite task to finish")
    assert has_element?(view, "#start-task-#{beta.id}", "Open task")

    assert {:ok, _board} = Workflows.set_board_status(board.id, "paused")
    send(view.pid, :refresh_board)
    assert has_element?(view, "#task-#{beta.id}", "Board is paused")
  end

  test "running project renders an eligible Ready task", %{conn: conn, board: board, beta: beta} do
    %AutopilotProjection{project_id: board.project_id}
    |> AutopilotProjection.changeset(%{
      state: "running",
      max_active_runs: 2,
      critical_blocker_limit: 1
    })
    |> Repo.insert!()

    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}")

    assert has_element?(view, "#task-#{beta.id}", "Eligible for the next automatic start")
  end

  test "creates a bounded draft task from the board", %{conn: conn, board: board} do
    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}")
    view |> element("#add-task-button") |> render_click()

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
    refute has_element?(view, "#new-task-modal")

    view |> element("#add-task-button") |> render_click()
    assert has_element?(view, "#create-task-form input[name='task[title]'][value='']")

    assert Repo.exists?(
             from(event in RunEvent,
               where: event.run_id == ^("task:" <> task.id) and event.event_type == "task.created"
             )
           )
  end

  test "task modal retains drafts and validation across refresh and dismissal", %{
    conn: conn,
    board: board
  } do
    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}")
    view |> element("#add-task-button") |> render_click()

    assert has_element?(view, "dialog#new-task-modal[aria-labelledby=new-task-modal-heading]")
    assert has_element?(view, "#new-task-modal input[name='task[title]'][autofocus]")
    refute has_element?(view, "#agent-task-intake")

    view
    |> form("#create-task-form", task: %{title: "Keep this draft", description: "Keep details"})
    |> render_change()

    send(view.pid, :board_tick)
    send(view.pid, :refresh_board)
    assert has_element?(view, "#new-task-modal input[value='Keep this draft']")
    view |> element("#new-task-modal button", "Cancel") |> render_click()
    refute has_element?(view, "dialog")
    view |> element("#add-task-button") |> render_click()
    assert has_element?(view, "#new-task-modal input[value='Keep this draft']")
    assert has_element?(view, "#new-task-modal textarea", "Keep details")

    view |> form("#create-task-form", task: %{title: " "}) |> render_submit()

    assert has_element?(
             view,
             "#new-task-modal #create-task-error[role=alert]",
             "Enter a task title"
           )

    refute has_element?(view, "#board-error")
    assert length(Workflows.list_tasks(board.id)) == 2
  end

  test "planning modal retains its prompt and explains missing roles", %{conn: conn, board: board} do
    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}")
    view |> element("#plan-tasks-button") |> render_click()

    assert has_element?(
             view,
             "dialog#agent-task-intake[aria-labelledby=agent-task-intake-heading]"
           )

    assert has_element?(view, "#task-intake-form button[type=submit][disabled]")
    assert has_element?(view, "#agent-task-intake", "no assigned agent roles")
    refute has_element?(view, "#create-task-form")

    view |> form("#task-intake-form", intake: %{prompt: "Read docs/PLAN.md"}) |> render_change()
    send(view.pid, :board_tick)
    send(view.pid, :refresh_board)
    assert has_element?(view, "#agent-task-intake textarea", "Read docs/PLAN.md")
    render_hook(view, "close-task-modal")
    refute has_element?(view, "dialog")
    view |> element("#plan-tasks-button") |> render_click()
    assert has_element?(view, "#agent-task-intake textarea", "Read docs/PLAN.md")
    assert length(Workflows.list_tasks(board.id)) == 2
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
