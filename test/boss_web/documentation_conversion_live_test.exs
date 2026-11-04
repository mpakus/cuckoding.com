defmodule BossWeb.DocumentationConversionLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Boss.{Deliveries, LocalAccess, Projects, Repo, Tasks}
  alias Boss.Deliveries.Autopilot, as: Engine
  alias Boss.Projects.{Documentation, Intake}
  alias BossWeb.Autopilot

  setup %{conn: conn} do
    manager = :sys.get_state(Boss.Runs.Manager)
    assert manager.active == %{}
    on_exit(fn -> BossWeb.ManagerFixture.restore(manager, []) end)

    project =
      Repo.insert!(%Projects.Project{
        name: "Instruction documents",
        root_path: "/documentation-conversion-ui",
        git_common_dir: "/documentation-conversion-ui/.git",
        specs_path: "/documentation-conversion-ui/docs",
        base_branch: "main"
      })

    {:ok, saved} =
      Projects.record_spec(project.id, %{
        relative_path: "AGENTS.md",
        title: "Agent instructions <script>",
        original_text: "# Instructions\nPreserve source and verify the application."
      })

    {:ok, {:new, delivery}} =
      Deliveries.admit(project.id, saved.task.id, Ecto.UUID.generate(), "true")

    {:ok, failed} = Deliveries.complete(delivery.id, "failed", "Earlier instruction attempt")
    {:ok, session} = LocalAccess.exchange(LocalAccess.new_token())
    conn = %{conn | host: "127.0.0.1", port: 4002} |> init_test_session(local_session: session)
    %{conn: conn, project: project, task: Tasks.get_task!(saved.task.id), failed: failed}
  end

  test "planning attempt history refreshes from a rejected report to a different model", c do
    {:ok, _} = Documentation.admit(c.project.id, Ecto.UUID.generate(), false)

    {:ok, {:new, request}} =
      Intake.admit(c.project.id, Ecto.UUID.generate(), "true", "codex", false)

    primary = %{"model" => "gpt-5.6-sol", "reasoning_effort" => "high"}
    resolver = %{"model" => "gpt-5.6-terra", "reasoning_effort" => "xhigh"}

    catalog = %{
      "version" => 2,
      "primary" => primary,
      "resolver" => resolver,
      "small" => %{"model" => "gpt-5.6-luna", "reasoning_effort" => "medium"},
      "fallbacks" => [%{"model" => "gpt-5.6-sol", "reasoning_effort" => "xhigh"}, resolver]
    }

    {:ok, _} = Intake.set_model_catalog(request.id, catalog)

    :ok =
      Intake.pin(request.id, %{
        "project_id" => to_string(c.project.id),
        "run_id" => request.id,
        "repo_path" => c.project.root_path,
        "git_common_dir" => c.project.git_common_dir,
        "base_branch" => "main",
        "base_commit" => String.duplicate("a", 40),
        "path" => c.project.root_path <> "/work",
        "branch" => "boss/" <> request.id
      })

    {:ok, view, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(view)
    refute has_element?(view, "#intake-attempt-history")
    {:ok, first} = Intake.begin_attempt(request.id)
    settle(view)
    assert has_element?(view, "#intake-attempt-1", "gpt-5.6-sol")
    assert has_element?(view, "#intake-attempt-1", "Running")

    receipt = %{
      "status" => "failed",
      "cleanup" => "group_empty",
      "outcome" => "invalid_report",
      "exit_kind" => "exit",
      "exit_code" => 0,
      "signal" => nil,
      "eof" => %{"stdout" => true, "stderr" => true},
      "usage" => %{},
      "error_class" => nil,
      "report_bytes" => 36_335,
      "validation_code" => "report_too_large",
      "plan_hash" => nil
    }

    {:ok, saved} = Intake.finish_attempt(first.id, receipt)
    {:ok, second} = Intake.begin_attempt(request.id)
    settle(view)
    assert has_element?(view, "#intake-attempt-1", "32 KiB")
    assert has_element?(view, "#intake-attempt-1", "Failed")
    assert has_element?(view, "#intake-attempt-2", "gpt-5.6-terra")
    assert has_element?(view, "#intake-attempt-2", "Running")
    assert has_element?(view, "#stop-autopilot-intake:not([disabled])")
    assert {:ok, ^saved} = Intake.finish_attempt(first.id, receipt)
    settle(view)
    assert length(Intake.attempts(request.id)) == 2
    assert second.number == 2
    refute has_element?(view, "#intake-attempt-3")
    assert has_element?(view, "#reference-history #task-#{c.task.id}")
  end

  test "conversion moves failed instructions to reference history and preserves their drawer",
       c do
    {:ok, first, _} = live(c.conn, "/projects/#{c.project.id}")
    {:ok, second, _} = live(c.conn, "/projects/#{c.project.id}/tasks/#{c.task.id}")
    settle(first)
    settle(second)
    first |> element("#project-autopilot") |> render_click()
    assert has_element?(first, "#column-needs-attention #task-#{c.task.id}")
    assert has_element?(first, "#autopilot-task-#{c.task.id}")
    assert has_element?(first, "#plan-from-documentation:not([disabled])")
    refute Documentation.latest(c.project.id)

    first |> element("#plan-from-documentation") |> render_click()
    settle(first)
    settle(second)

    assert %{source_count: 1} = Documentation.latest(c.project.id)
    assert Projects.get_project!(c.project.id).intake_mode == "documentation"
    assert Repo.get!(Deliveries.Delivery, c.failed.id) == c.failed
    assert Tasks.get_task!(c.task.id) == c.task
    assert Intake.latest(c.project.id) == nil
    assert {:ok, []} = Engine.selection(c.project.id)
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1

    for view <- [first, second] do
      refute has_element?(view, "#sync-specs")
      refute has_element?(view, "#plan-from-documentation")
      refute has_element?(view, "#task-board #task-#{c.task.id}")
      refute has_element?(view, "#autopilot-task-#{c.task.id}")
      assert has_element?(view, "#reference-history #task-#{c.task.id}", c.task.title)
      assert has_element?(view, "#reference-#{c.task.id}", "Failed · reference only")
      assert has_element?(view, "#autopilot-selection-help", "committed documentation")
      refute has_element?(view, "#autopilot-selection-count")
    end

    assert has_element?(second, "#task-reference-only", "saved task and attempt history")
    assert has_element?(second, "#delivery-#{c.failed.id}", "Earlier instruction attempt")
    assert has_element?(second, "#start-delivery[disabled]")
    assert has_element?(second, "#queue-delivery[disabled]")
    assert has_element?(second, "#start-codex[disabled]")
    refute render(second) =~ "Agent instructions <script>"
    first |> element("#reference-history #task-#{c.task.id}") |> render_click()
    settle(first)
    assert has_element?(first, "#task-reference-only")
    assert has_element?(first, "#task-drawer", "Preserve source and verify the application.")
  end

  test "the conversion button rejects a foreign UUID and an active batch keeps Stop", c do
    {:ok, view, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(view)

    view
    |> element("#plan-from-documentation")
    |> render_click(%{"command-id" => Ecto.UUID.generate()})

    settle(view)
    assert Documentation.latest(c.project.id) == nil

    {:ok, batch} =
      Engine.admit(c.project.id, Ecto.UUID.generate(), [c.task.id], "true", "codex")

    Boss.Runs.broadcast(%{project_id: c.project.id})
    settle(view)
    assert has_element?(view, "#plan-from-documentation[disabled]")
    assert has_element?(view, "#stop-autopilot:not([disabled])")
    view |> element("#stop-autopilot") |> render_click()
    settle(view)
    assert {:ok, %{id: id, status: "cancelled"}} = Engine.current(c.project.id)
    assert id == batch.id
    assert Documentation.latest(c.project.id) == nil
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1
  end

  test "unknown conversion retains its UUID and confirms only the matching saved receipt", c do
    id = Ecto.UUID.generate()
    request = %{kind: :documentation_convert, id: id}
    socket = component(c.project, pending: request, command: id, acting: true)
    {:noreply, unknown} = Autopilot.handle_async({:action, id}, {:exit, :timeout}, socket)
    assert unknown.assigns.pending == request
    assert unknown.assigns.command == id
    assert unknown.assigns.error =~ "Retry the same saved"

    {:noreply, frozen} =
      Autopilot.handle_event("edit", %{"command" => "false", "reviewer" => "claude"}, unknown)

    assert frozen.assigns.text == "true"
    {:noreply, retried} = Autopilot.handle_event("retry", %{}, unknown)
    assert retried.assigns.pending == request
    assert retried.assigns.acting

    {:ok, receipt} = Documentation.convert(c.project.id, id)
    generation = unknown.assigns.generation

    for unrelated <- [
          nil,
          %{receipt | command_id: Ecto.UUID.generate()},
          %{receipt | project_id: c.project.id + 1}
        ] do
      {:noreply, unchanged} =
        Autopilot.handle_async(
          {:load, generation},
          {:ok, {{:ok, nil}, nil, {:ok, []}, unrelated}},
          unknown
        )

      assert unchanged.assigns.pending == request
      assert unchanged.assigns.command == id
    end

    {:noreply, confirmed} =
      Autopilot.handle_async(
        {:load, generation},
        {:ok, {{:ok, nil}, nil, {:ok, []}, receipt}},
        unknown
      )

    assert confirmed.assigns.pending == nil
    refute confirmed.assigns.command == id
    assert confirmed.assigns.error == nil
    assert_receive {:project_documentation, project}
    assert project == c.project.id
    assert {:ok, ^receipt} = Documentation.convert(c.project.id, id)

    {:noreply, late} = Autopilot.handle_async({:action, id}, {:ok, {:error, :busy}}, confirmed)
    assert late.assigns == confirmed.assigns
    assert Intake.latest(c.project.id) == nil
  end

  test "the next Start requests documentation planning and preserves planning Stop", c do
    {:ok, _} = Documentation.convert(c.project.id, Ecto.UUID.generate())
    project = Projects.get_project!(c.project.id)
    entries = Projects.list_spec_entries(c.project.id)
    socket = component(project, entries: entries, eligible_task_ids: [c.task.id])

    {:noreply, started} =
      Autopilot.handle_event("start", %{"command" => "true", "reviewer" => "codex"}, socket)

    assert started.assigns.pending.kind == :intake_start
    assert started.assigns.pending.tasks == []
    assert started.assigns.pending.text == "true"
    assert Repo.aggregate(Deliveries.Delivery, :count) == 1

    {:ok, {:new, intake}} =
      Intake.admit(c.project.id, started.assigns.pending.id, "true", "codex", false)

    {:ok, view, _} = live(c.conn, "/projects/#{c.project.id}")
    settle(view)
    assert has_element?(view, "#stop-autopilot-intake:not([disabled])")
    refute has_element?(view, "#autopilot-task-#{c.task.id}")
    view |> element("#stop-autopilot-intake") |> render_click()
    settle(view)
    assert Repo.get!(Intake.Request, intake.id).stop_requested
    assert Repo.get!(Deliveries.Delivery, c.failed.id) == c.failed
  end

  test "a stale run request rejected after conversion releases its unknown admission state", c do
    {:ok, view, _} = live(c.conn, "/projects/#{c.project.id}/tasks/#{c.task.id}")
    settle(view)
    {:ok, _} = Documentation.convert(c.project.id, Ecto.UUID.generate())
    settle(view)
    id = Ecto.UUID.generate()

    :sys.replace_state(view.pid, fn state ->
      socket =
        Phoenix.Component.assign(state.socket,
          manual_pending: %{c.task.id => id},
          run_starting: {c.task.id, id}
        )

      {:noreply, socket} =
        BossWeb.ProjectLive.handle_async(
          :start_run,
          {:ok, {c.task.id, id, {:error, :reference_only}}},
          socket
        )

      %{state | socket: socket}
    end)

    settle(view)
    assert :sys.get_state(view.pid).socket.assigns.manual_pending == %{}
    assert has_element?(view, "#run-error", "reference only")
    assert has_element?(view, "#start-codex[disabled]")
    assert BossWeb.TaskRevision.resolved?({:error, :reference_only})
    assert BossWeb.TaskRevision.error({:error, :reference_only}) =~ "original task snapshots"
  end

  defp component(project, overrides) do
    {:ok, socket} = Autopilot.mount(%Phoenix.LiveView.Socket{})

    Phoenix.Component.assign(
      socket,
      [project: project, supported: true, loaded: true, open: true, text: "true"] ++ overrides
    )
  end

  defp settle(view) do
    render(view)
    for _ <- 1..5, do: render_async(view, 2_000)
  end
end
