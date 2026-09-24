defmodule Cuckoding.BoardTaskIntakeTest do
  use CuckodingWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuckoding.BoardTaskIntake
  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.ProjectWorkflow
  alias Cuckoding.Repo
  alias Cuckoding.TaskProposalReview
  alias Cuckoding.WalkingSkeleton
  alias Cuckoding.Workflows
  alias Cuckoding.Workflows.Task

  @git "/usr/bin/git"

  setup do
    root = Path.join(System.tmp_dir!(), "cuckoding-intake-#{System.unique_integer([:positive])}")
    repo = Path.join(root, "repo")
    workspace = Path.join(root, "workspaces")
    File.mkdir_p!(Path.join(repo, "docs"))
    git!(repo, ["init", "-b", "main"])
    git!(repo, ["config", "user.email", "test@example.com"])
    git!(repo, ["config", "user.name", "Cuckoding Test"])
    File.write!(Path.join(repo, "README.md"), "# Intake fixture\n")
    File.write!(Path.join(repo, "docs/PLAN.md"), "# Plan\n\nBuild the first release.\n")
    File.write!(Path.join(repo, "docs/tasks.md"), "# Tasks\n\n- Add the dashboard.\n")
    File.ln_s!("/etc/hosts", Path.join(repo, "docs/outside-link"))
    git!(repo, ["add", "."])
    git!(repo, ["commit", "-m", "initial"])

    port = free_port()

    assert {:ok, created} =
             WalkingSkeleton.create(%{
               name: "Intake #{System.unique_integer([:positive])}",
               repo_path: repo,
               workspace_root: workspace,
               task_title: "Existing delivery task",
               adapter_key: "fake",
               start_run: false,
               port_range_start: port,
               port_range_end: port
             })

    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, created: created}
  end

  test "read-only planning output is persisted and imported idempotently", %{created: created} do
    role =
      Repo.get_by!(Cuckoding.Workflows.RoleAssignment,
        board_id: created.board.id,
        role_key: "spec_writer"
      )

    role |> Ecto.Changeset.change(model_ref: "planning-model") |> Repo.update!()
    assert {:ok, intake} = create_intake(created.board.id)

    assert intake.task.kind == "board_intake"
    assert intake.task.intake_role_key == "spec_writer"
    assert Enum.all?(Workflows.list_tasks(created.board.id), &(&1.kind == "delivery"))

    output = %{
      "tasks" => [
        %{
          "title" => "Build the dashboard",
          "description" => "Implement the dashboard described by the project plan.",
          "priority" => 8,
          "sources" => [%{"path" => "docs/PLAN.md", "line" => 3}]
        },
        %{
          "title" => "Cover task creation",
          "description" => "Add regression coverage for task creation.",
          "priority" => 5,
          "sources" => [%{"path" => "docs/tasks.md", "line" => 3}]
        }
      ]
    }

    assert {:ok, proposals} =
             BoardTaskIntake.start(intake.run.id, async: false, fake_output: output)

    assert Enum.map(proposals, & &1.title) == ["Build the dashboard", "Cover task creation"]
    assert Repo.get!(Run, intake.run.id).state == "waiting"

    session =
      Repo.one!(
        from(session in AgentSession,
          join: attempt in Cuckoding.Execution.StageAttempt,
          on: attempt.id == session.stage_attempt_id,
          where: attempt.run_id == ^intake.run.id
        )
      )

    assert session.effective_grant_json["requested"]["tools"] == ["read", "shell"]
    assert session.requested_model == "planning-model"
    assert session.effective_grant_json["requested"]["deny_tools"] == ["write", "network"]
    assert session.effective_grant_json["requested"]["approval_mode"] == "plan"
    assert session.effective_grant_json["requested"]["network"] == "deny"

    schema =
      BoardTaskIntake.output_schema()
      |> get_in(["properties", "tasks", "items", "properties", "sources", "items"])

    assert schema["required"] == ["path", "line"]
    assert schema["properties"]["line"]["type"] == ["integer", "null"]

    selected = Enum.map(proposals, & &1.id)
    assert {:ok, imported} = BoardTaskIntake.import(intake.run.id, selected)
    assert Enum.map(imported, & &1.title) == ["Build the dashboard", "Cover task creation"]
    assert Repo.get!(Run, intake.run.id).state == "done"

    assert {:ok, repeated} = BoardTaskIntake.import(intake.run.id, selected)
    assert Enum.map(repeated, & &1.id) == Enum.map(imported, & &1.id)

    assert Repo.aggregate(from(task in Task, where: task.board_id == ^created.board.id), :count) ==
             4

    assert Repo.exists?(
             from(event in RunEvent,
               where:
                 event.run_id == ^intake.run.id and
                   event.event_type == "task_intake.proposals_created"
             )
           )
  end

  test "rejects proposal evidence outside the owned worktree and shows the failure", %{
    conn: conn,
    created: created
  } do
    assert {:ok, intake} = create_intake(created.board.id)

    output = %{
      "tasks" => [
        %{
          "title" => "Unsafe proposal",
          "description" => "References a file outside the project.",
          "priority" => 0,
          "sources" => [%{"path" => "docs/outside-link"}]
        }
      ]
    }

    assert {:error, :invalid_task_proposals} =
             BoardTaskIntake.start(intake.run.id, async: false, fake_output: output)

    assert Repo.get!(Run, intake.run.id).state == "blocked"
    assert Workflows.list_task_proposals(intake.task.id) == []

    session =
      Repo.one!(
        from(session in AgentSession,
          join: attempt in Cuckoding.Execution.StageAttempt,
          on: attempt.id == session.stage_attempt_id,
          where: attempt.run_id == ^intake.run.id
        )
      )

    assert session.state == "failed"

    failure =
      Repo.one!(
        from(event in RunEvent,
          where: event.run_id == ^intake.run.id and event.event_type == "task_intake.failed"
        )
      )

    assert failure.payload["code"] == "invalid_task_proposals"

    assert {:ok, run_view, _html} = live(conn, ~p"/runs/#{intake.run.id}")

    assert has_element?(
             run_view,
             "#run-failure[role=alert]",
             "The agent returned task proposals that failed validation"
           )
  end

  test "planning requires only the selected role to have a runnable adapter", %{created: created} do
    Repo.update_all(
      from(role in Cuckoding.Workflows.RoleAssignment,
        where: role.board_id == ^created.board.id and role.role_key == "implementer"
      ),
      set: [adapter_key: "opencode"]
    )

    assert {:ok, intake} = create_intake(created.board.id)
    assert intake.task.intake_role_key == "spec_writer"
    assert intake.run.state == "queued"
  end

  test "another model revises proposals, preserves history and renders a report before import", %{
    conn: conn,
    created: created
  } do
    set_review_model(created.board.id)
    assert {:ok, intake} = create_intake(created.board.id)
    assert {:ok, [proposal]} = BoardTaskIntake.start(intake.run.id, async: false)
    assert {:ok, view, _html} = live(conn, ~p"/runs/#{intake.run.id}")

    assert has_element?(
             view,
             "#proposal-model-review-form option[value=reviewer]",
             "review-model"
           )

    refute has_element?(view, "#proposal-model-review-form option[value=spec_writer]")

    output = review_output(proposal)

    assert {:ok, [reviewed]} =
             BoardTaskIntake.review(intake.run.id, "reviewer", async: false, fake_output: output)

    assert reviewed.id == proposal.id
    assert reviewed.description == output["tasks"] |> hd() |> Map.fetch!("description")
    assert reviewed.source_json["review_comments"] == ["Added measurable acceptance criteria."]
    assert Repo.get!(Run, intake.run.id).state == "waiting"
    report = TaskProposalReview.latest_report(intake.run.id)
    assert [%{"before" => before, "after" => after_revision}] = report["revisions"]
    assert before["description"] == proposal.description
    assert after_revision["description"] == reviewed.description
    path = Path.join([intake.environment.run_dir, "artifacts", report["report"]["path"]])
    contents = File.read!(path)
    assert contents =~ output["summary"]
    assert contents =~ reviewed.description
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600

    assert report["report"]["sha256"] ==
             Base.encode16(:crypto.hash(:sha256, contents), case: :lower)

    session =
      Repo.one!(
        from session in AgentSession,
          join: attempt in StageAttempt,
          on: attempt.id == session.stage_attempt_id,
          where: attempt.run_id == ^intake.run.id and attempt.stage_key == "task_proposal_review"
      )

    assert session.requested_model == "review-model"
    assert session.effective_grant_json["requested"]["deny_tools"] == ["write", "network"]
    eventually(fn -> has_element?(view, "#proposal-review-report", output["summary"]) end)
    assert has_element?(view, "#task-proposal-form", "Added measurable acceptance criteria.")

    assert {:ok, [_again]} =
             BoardTaskIntake.review(intake.run.id, "reviewer", async: false, fake_output: output)

    assert Repo.aggregate(
             from(a in StageAttempt,
               where: a.run_id == ^intake.run.id and a.stage_key == "task_proposal_review"
             ),
             :count
           ) == 2

    assert TaskProposalReview.latest_report(intake.run.id)["review_id"] != report["review_id"]

    assert {:ok, [task]} = BoardTaskIntake.import(intake.run.id, [reviewed.id])
    assert task.description == reviewed.description

    assert {:error, :proposals_not_reviewable} =
             BoardTaskIntake.review(intake.run.id, "reviewer", async: false, fake_output: output)
  end

  test "rejects same-model review and preserves proposals across failed reviews and retry", %{
    created: created
  } do
    assert {:ok, same_model} = create_intake(created.board.id)
    assert {:ok, [_proposal]} = BoardTaskIntake.start(same_model.run.id, async: false)

    assert {:error, :different_review_model_required} =
             BoardTaskIntake.review(same_model.run.id, "reviewer", async: false)

    assert Repo.get!(Run, same_model.run.id).state == "waiting"

    set_review_model(created.board.id)
    assert {:ok, intake} = create_intake(created.board.id)
    assert {:ok, [proposal]} = BoardTaskIntake.start(intake.run.id, async: false)
    valid = review_output(proposal)
    [task] = valid["tasks"]

    for invalid <- [
          %{valid | "tasks" => [Map.put(task, "id", "another-proposal")]},
          %{valid | "tasks" => [task, task]},
          %{
            valid
            | "tasks" => [
                Map.put(task, "sources", [%{"path" => "docs/outside-link", "line" => 1}])
              ]
          },
          Map.put(valid, "command", "approve")
        ] do
      assert {:error, :invalid_task_proposal_review} =
               BoardTaskIntake.review(intake.run.id, "reviewer",
                 async: false,
                 fake_output: invalid
               )

      assert Repo.get!(Run, intake.run.id).state == "blocked"
      assert Workflows.list_task_proposals(intake.task.id) == [proposal]
      assert TaskProposalReview.latest_report(intake.run.id) == nil
    end

    assert {:ok, [reviewed]} =
             BoardTaskIntake.review(intake.run.id, "reviewer", async: false, fake_output: valid)

    assert reviewed.id == proposal.id
    assert Repo.get!(Run, intake.run.id).state == "waiting"
  end

  test "active proposal review prevents another reviewer and task import", %{
    conn: conn,
    created: created
  } do
    set_review_model(created.board.id)
    assert {:ok, intake} = create_intake(created.board.id)
    assert {:ok, [proposal]} = BoardTaskIntake.start(intake.run.id, async: false)
    assert {:ok, _review} = TaskProposalReview.begin_review(intake, "reviewer")

    assert {:error, :proposals_not_reviewable} =
             TaskProposalReview.begin_review(intake, "reviewer")

    assert {:error, :proposal_selection_required} =
             BoardTaskIntake.import(intake.run.id, [proposal.id])

    assert {:ok, view, _html} = live(conn, ~p"/runs/#{intake.run.id}")
    assert has_element?(view, "#task-proposal-form input[disabled]")
    assert has_element?(view, "#task-proposal-form button[disabled]")
    refute has_element?(view, "#proposal-model-review-form")
  end

  test "explains a legacy planning failure without a recorded cause", %{
    conn: conn,
    created: created
  } do
    assert {:ok, intake} = create_intake(created.board.id)

    assert {:ok, _command} =
             Cuckoding.Execution.transition_run(
               intake.run.id,
               "running",
               "test:#{intake.run.id}:running"
             )

    assert {:ok, _event} =
             EventStore.append(intake.run.id, %{
               event_type: "task_intake.failed",
               public_summary: "Task planning failed.",
               payload: %{"code" => "task_intake_failed"}
             })

    assert {:ok, _command} =
             Cuckoding.Execution.transition_run(
               intake.run.id,
               "blocked",
               "test:#{intake.run.id}:blocked",
               wait_reason: "Task planning failed."
             )

    assert {:ok, run_view, _html} = live(conn, ~p"/runs/#{intake.run.id}")

    assert has_element?(
             run_view,
             "#run-failure[role=alert]",
             "This older run did not record a specific validation error"
           )
  end

  test "board creates the planning run and run page imports reviewed proposals", %{
    conn: conn,
    created: created
  } do
    {:ok, board_view, _html} = live(conn, ~p"/boards/#{created.board.id}")
    refute has_element?(board_view, "#task-intake-form")
    board_view |> element("#plan-tasks-button") |> render_click()
    assert has_element?(board_view, "#agent-task-intake", "Ask an agent to plan tasks")
    assert has_element?(board_view, "#task-intake-form option[value=spec_writer]")

    assert has_element?(
             board_view,
             "#task-intake-form button[phx-disable-with='Creating planning run…'][aria-describedby='task-intake-submit-status']"
           )

    assert has_element?(
             board_view,
             "#task-intake-submit-status[role=status][aria-live=polite]"
           )

    board_view
    |> form("#task-intake-form", intake: %{role_key: "spec_writer", prompt: ""})
    |> render_submit()

    assert has_element?(
             board_view,
             "#agent-task-intake #task-intake-error[role=alert]",
             "Enter a planning prompt"
           )

    redirect =
      board_view
      |> form("#task-intake-form",
        intake: %{
          role_key: "spec_writer",
          prompt: "Analyze docs/PLAN.md and docs/tasks.md, then propose board tasks."
        }
      )
      |> render_submit()

    intake =
      Repo.one!(
        from(task in Task,
          where: task.board_id == ^created.board.id and task.kind == "board_intake",
          order_by: [desc: task.inserted_at],
          limit: 1
        )
      )

    [run] = Cuckoding.Execution.list_runs(intake.id)
    assert {:ok, run_view, _html} = follow_redirect(redirect, conn, ~p"/runs/#{run.id}")
    assert has_element?(run_view, "#flash-info[role=status]", "Planning run created")

    assert has_element?(
             run_view,
             "#planning-progress [role=status]",
             "Verify agent authentication below, then start analysis"
           )

    assert {:ok, [proposal]} = BoardTaskIntake.start(run.id, async: false)

    eventually(fn ->
      render(run_view) =~ "Analysis finished. Review the proposed tasks below."
    end)

    assert has_element?(run_view, "#task-proposal-review", "Review proposed tasks")
    assert has_element?(run_view, "input[name='proposal_ids[]'][value='#{proposal.id}']")

    run_view
    |> form("#task-proposal-form", proposal_ids: [proposal.id])
    |> render_submit()

    assert has_element?(run_view, "[role=status]", "Imported 1 reviewed proposal")
    assert Repo.get!(Task, proposal.intake_task_id).state == "done"
    assert Repo.get_by!(Task, board_id: created.board.id, title: "Review project documentation")
  end

  defp eventually(assertion, attempts \\ 100)

  defp eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      :ok
    else
      Process.sleep(20)
      eventually(assertion, attempts - 1)
    end
  end

  defp eventually(_assertion, 0), do: flunk("LiveView did not show the durable planning state")

  defp create_intake(board_id) do
    ProjectWorkflow.create_task_intake(board_id, %{
      "role_key" => "spec_writer",
      "prompt" => "Analyze docs/PLAN.md and docs/tasks.md, then propose board tasks."
    })
  end

  defp set_review_model(board_id) do
    Repo.update_all(
      from(role in Cuckoding.Workflows.RoleAssignment,
        where: role.board_id == ^board_id and role.role_key == "reviewer"
      ),
      set: [model_ref: "review-model"]
    )
  end

  defp review_output(proposal) do
    %{
      "summary" => "Clarified the specification and its acceptance checks.",
      "tasks" => [
        %{
          "id" => proposal.id,
          "title" => proposal.title,
          "description" =>
            "Implement the documented dashboard.\nAcceptance: show persisted task state.\nTest: verify refresh preserves task state.",
          "priority" => 5,
          "sources" => [%{"path" => "docs/PLAN.md", "line" => 3}],
          "comments" => ["Added measurable acceptance criteria."]
        }
      ]
    }
  end

  defp git!(directory, args) do
    {_output, 0} = System.cmd(@git, args, cd: directory, stderr_to_stdout: true)
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
