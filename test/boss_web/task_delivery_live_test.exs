defmodule BossWeb.TaskDeliveryLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Boss.{Deliveries, LocalAccess, Projects, Repo, Runs, Tasks}
  alias Boss.Runs.Manager
  alias BossWeb.ManagerFixture
  alias Boss.Deliveries.Queue
  import Ecto.Query
  alias BossWeb.ProjectLive

  @moduletag skip: :os.type() != {:unix, :darwin}
  @base String.duplicate("a", 40)
  @candidate String.duplicate("b", 40)
  @hash String.duplicate("c", 64)

  setup %{conn: conn} do
    owner = self()
    original = :sys.get_state(Manager)
    assert original.active == %{}

    :sys.replace_state(Manager, fn state ->
      %{
        state
        | worker: fn run, _, manager -> fake_manual_worker(owner, run, manager) end,
          delivery_worker: fn delivery, _, manager ->
            fake_worker(owner, delivery, manager, :workflow)
          end,
          integration_worker: fn delivery, _, manager ->
            fake_worker(owner, delivery, manager, :integration)
          end
      }
    end)

    on_exit(fn ->
      ManagerFixture.restore(original, [:delivery_worker, :integration_worker, :worker])
    end)

    project =
      Repo.insert!(%Projects.Project{
        name: "Workflow UI",
        root_path: "/workflow-ui",
        git_common_dir: "/workflow-ui/.git",
        specs_path: "/workflow-ui/specs",
        base_branch: "main"
      })

    saved = spec(project, "one")
    {:ok, session} = LocalAccess.exchange(LocalAccess.new_token())
    conn = %{conn | host: "127.0.0.1", port: 4002} |> init_test_session(local_session: session)
    %{conn: conn, project: project, saved: saved}
  end

  test "explicit command starts one workflow on the pinned task and disables manual starts", c do
    spec(c.project, "one", "# New source")
    {:ok, view, _} = live(c.conn, task_path(c) <> "?revision=2")
    settle(view)
    assert has_element?(view, "#delivery-account", "may incur charges")
    assert has_element?(view, "#delivery-help", "snapshot revision 1")
    id = command(view)
    start(view, id)
    assert_receive {:workflow, worker, delivery}, 1_000
    settle(view)
    assert delivery.spec_revision_id == c.saved.task.spec_revision_id
    assert delivery.check_config["argv"] == ["mix", "test"]
    assert delivery.reviewer == "codex"
    assert has_element?(view, "#delivery-#{delivery.id}", "Preparing plan")
    assert has_element?(view, "#start-codex[disabled]")
    start(view, id)
    refute_receive {:workflow, _, _}, 50
    finish(worker, :cancelled)
    settle(view)
    assert Tasks.get_task!(c.saved.task.id).state == "cancelled"
    assert has_element?(view, "#delivery-#{delivery.id}", "Workflow stopped")
  end

  test "Claude is explicitly selected and history keeps its saved reviewer after changing the form",
       c do
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    assert has_element?(view, "label[for='delivery-reviewer']", "Workflow reviewer")
    assert has_element?(view, "#delivery-reviewer option[value='codex'][selected]")
    id = command(view)

    view
    |> form("#delivery-form", %{"command" => "mix test", "reviewer" => "claude"})
    |> render_change()

    assert has_element?(view, "#delivery-reviewer option[value='claude'][selected]")
    assert has_element?(view, "#delivery-reviewer-help", "no model filesystem or shell tools")
    assert has_element?(view, "#delivery-reviewer-help", "Planning and implementation use Codex")
    refute_receive {:workflow, _, _}, 50
    start(view, id, "mix test", "claude")
    assert_receive {:workflow, worker, delivery}, 1_000
    assert delivery.reviewer == "claude"
    finish(worker, :cancelled)
    settle(view)
    assert has_element?(view, "#delivery-#{delivery.id}", "Reviewer: Claude")
    assert has_element?(view, "#delivery-reviewer option[value='claude'][selected]")

    view
    |> form("#delivery-form", %{"command" => "mix test", "reviewer" => "codex"})
    |> render_change()

    assert has_element?(view, "#delivery-reviewer option[value='codex'][selected]")
    assert has_element?(view, "#delivery-reviewer-help", "source read-only")
    assert has_element?(view, "#delivery-#{delivery.id}", "Reviewer: Claude")
    {:ok, reconnected, _} = live(c.conn, task_path(c))
    settle(reconnected)
    assert has_element?(reconnected, "#delivery-#{delivery.id}", "Reviewer: Claude")
    assert has_element?(reconnected, "#delivery-reviewer option[value='codex'][selected]")
  end

  test "unknown start retries identical UUID, text and reviewer, blocking other starts",
       c do
    other = spec(c.project, "other")
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    id = command(view)
    :sys.suspend(Manager)
    start(view, id, "mix test", "claude")
    key = :sys.get_state(view.pid).socket.assigns.delivery_starting

    :sys.replace_state(view.pid, fn state ->
      %{state | socket: Phoenix.LiveView.cancel_async(state.socket, key, :kill)}
    end)

    settle(view)
    assert command(view) == id
    assert has_element?(view, "#delivery-command[readonly][value='mix test']")
    assert has_element?(view, "#delivery-reviewer[disabled] option[value='claude'][selected]")
    assert has_element?(view, "input[type='hidden'][name='reviewer'][value='claude']")
    assert has_element?(view, "#start-delivery", "Retry workflow start")
    assert has_element?(view, "#start-codex[disabled]")
    start(view, id, "changed command", "claude")
    start(view, id, "mix test", "codex")

    render_change(view, "edit_delivery", %{
      "command_id" => id,
      "command" => "mix test",
      "reviewer" => "codex"
    })

    assert has_element?(view, "#delivery-command[value='mix test']")
    assert has_element?(view, "#delivery-reviewer option[value='claude'][selected]")
    render_patch(view, "/projects/#{c.project.id}/tasks/#{other.task.id}")
    settle(view)
    assert has_element?(view, "#start-delivery[disabled]")
    assert has_element?(view, "#start-codex[disabled]")
    render_patch(view, task_path(c))
    settle(view)
    assert has_element?(view, "#delivery-reviewer option[value='claude'][selected]")
    start(view, id, "mix test", "claude")
    :sys.resume(Manager)
    assert_receive {:workflow, worker, delivery}, 1_000
    settle(view)
    assert delivery.command_id == id
    assert delivery.reviewer == "claude"
    refute_receive {:workflow, _, _}, 50
    assert length(Deliveries.list(c.project.id, c.saved.task.id)) == 1
    finish(worker, :cancelled)
  end

  test "invalid reviewer cannot start or replace the saved selection", c do
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    id = command(view)
    payload = %{"command_id" => id, "command" => "mix test", "reviewer" => "other"}
    render_change(view, "edit_delivery", payload)
    render_submit(view, "start_delivery", payload)
    refute_receive {:workflow, _, _}, 50
    assert has_element?(view, "#delivery-reviewer option[value='codex'][selected]")
    refute has_element?(view, "#delivery-request-pending")
    assert command(view) == id
    start(view, id)
    assert_receive {:workflow, worker, delivery}, 1_000
    assert delivery.reviewer == "codex"
    finish(worker, :cancelled)
  end

  test "workflow survives drawer close and only its scoped Stop can cancel it", c do
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    start(view, command(view))
    assert_receive {:workflow, worker, delivery}, 1_000
    settle(view)
    render_click(view, "stop_delivery", %{"delivery-id" => Ecto.UUID.generate()})
    refute_receive {:fixture_finished, _}, 50
    render_patch(view, "/projects/#{c.project.id}")
    assert Process.alive?(worker)
    {:ok, reconnected, _} = live(c.conn, task_path(c))
    settle(reconnected)
    reconnected |> element("#stop-delivery-#{delivery.id}") |> render_click()
    assert_receive {:fixture_finished, _}, 1_000
    settle(reconnected)
    assert has_element?(reconnected, "#delivery-#{delivery.id}", "Workflow stopped")
  end

  test "approved workflow waits for explicit integration and Done follows persisted post-checks",
       c do
    delivery = ready(c)
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    assert Tasks.get_task!(c.saved.task.id).state == "ready_to_merge"
    assert has_element?(view, "#delivery-#{delivery.id}", "Ready to integrate")
    assert has_element?(view, "#delivery-#{delivery.id}", @base)
    assert has_element?(view, "#delivery-#{delivery.id}", @candidate)
    assert has_element?(view, "#delivery-#{delivery.id}", "<script>not executable</script>")
    refute has_element?(view, "#delivery-#{delivery.id} script")
    refute has_element?(view, "#delivery-#{delivery.id}", "Done — integrated")
    view |> element("#integrate-delivery-#{delivery.id}") |> render_click()
    assert_receive {:integration, worker, admitted}, 1_000
    assert admitted.id == delivery.id
    settle(view)
    assert has_element?(view, "#delivery-#{delivery.id}", "Integrating approved result")
    finish(worker, :done)
    settle(view)
    assert has_element?(view, "#delivery-#{delivery.id}", "Done — integrated and checks passed")
    assert has_element?(view, "#delivery-#{delivery.id}", "Post-integration checks")
    assert Tasks.get_task!(c.saved.task.id).state == "done"
    assert has_element?(view, "#column-done #task-#{c.saved.task.id}")
    refute has_element?(view, "#integrate-delivery-#{delivery.id}")
    next = spec(c.project, "next")
    render_patch(view, "/projects/#{c.project.id}/tasks/#{next.task.id}")
    settle(view)
    refute has_element?(view, "#start-delivery[disabled]")
    start(view, command(view))
    assert_receive {:workflow, next_worker, next_delivery}, 1_000
    assert next_delivery.task_id == next.task.id
    finish(next_worker, :cancelled)
  end

  test "a late Stop before Ready does not disable Stop for the subsequent integration", c do
    owner = self()

    :sys.replace_state(Manager, fn state ->
      %{
        state
        | delivery_worker: fn delivery, _, manager ->
            send(owner, {:workflow, self(), delivery})

            receive do
              :stop -> :ok
            after
              10_000 -> :ok
            end

            # Model a Stop received after the last cancellation checkpoint.
            ready = ready_delivery(c.project, delivery)
            send(manager, {:delivery_finished, delivery.id, self(), {:ok, ready}})
            send(owner, {:fixture_finished, delivery.id})
          end
      }
    end)

    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    start(view, command(view))
    assert_receive {:workflow, _, delivery}, 1_000
    settle(view)
    view |> element("#stop-delivery-#{delivery.id}") |> render_click()
    assert_receive {:fixture_finished, _}, 1_000
    settle(view)
    assert has_element?(view, "#delivery-#{delivery.id}", "Ready to integrate")
    view |> element("#integrate-delivery-#{delivery.id}") |> render_click()
    assert_receive {:integration, worker, _}, 1_000
    settle(view)
    stop_enabled = has_element?(view, "#stop-delivery-#{delivery.id}:not([disabled])")

    if stop_enabled,
      do: view |> element("#stop-delivery-#{delivery.id}") |> render_click(),
      else: send(worker, :stop)

    assert_receive {:fixture_finished, _}, 1_000
    settle(view)
    assert stop_enabled
    assert has_element?(view, "#delivery-#{delivery.id}", "Workflow stopped")
  end

  test "unknown integration retries the same request without accepting a stale delivery ID", c do
    delivery = ready(c)
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    id = integration_command(view, delivery.id)
    payload = %{"delivery-id" => delivery.id, "command-id" => id}
    render_click(view, "integrate_delivery", %{payload | "delivery-id" => Ecto.UUID.generate()})
    refute_receive {:integration, _, _}, 50
    :sys.suspend(Manager)
    render_click(view, "integrate_delivery", payload)
    key = :sys.get_state(view.pid).socket.assigns.delivery_starting

    :sys.replace_state(view.pid, fn state ->
      %{state | socket: Phoenix.LiveView.cancel_async(state.socket, key, :kill)}
    end)

    settle(view)
    assert integration_command(view, delivery.id) == id
    assert has_element?(view, "#integrate-delivery-#{delivery.id}", "Retry integration request")
    render_click(view, "integrate_delivery", payload)
    :sys.resume(Manager)
    assert_receive {:integration, worker, admitted}, 1_000
    assert admitted.integration_command_id == id
    refute_receive {:integration, _, _}, 50
    finish(worker, :cancelled)
  end

  test "persisted receipt wins over late errors and old callbacks cannot clear a newer start",
       c do
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    old = command(view)
    start(view, old)
    assert_receive {:workflow, worker, _}, 1_000
    finish(worker, :cancelled)
    settle(view)
    current = command(view)
    refute current == old
    old_key = {:delivery_request, c.saved.task.id, :start, c.saved.task.id, old}

    for reply <- [{:ok, {:error, :storage_error}}, {:exit, :killed}] do
      :sys.replace_state(view.pid, fn state ->
        {:noreply, socket} = ProjectLive.handle_async(old_key, reply, state.socket)
        %{state | socket: socket}
      end)

      settle(view)
      assert command(view) == current
      refute has_element?(view, "#delivery-error")
      refute has_element?(view, "#delivery-request-pending")
    end

    new_key = {:delivery_request, c.saved.task.id, :start, c.saved.task.id, current}

    :sys.replace_state(view.pid, fn state ->
      socket =
        Phoenix.Component.assign(state.socket,
          delivery_starting: new_key,
          delivery_requests: %{
            c.saved.task.id => %{id: current, text: "mix test", reviewer: "codex", locked: true}
          }
        )

      {:noreply, socket} = ProjectLive.handle_async(old_key, {:exit, :killed}, socket)
      %{state | socket: socket}
    end)

    assert :sys.get_state(view.pid).socket.assigns.delivery_starting == new_key
  end

  test "manual active and unknown starts disable managed starts across navigation", c do
    other = spec(c.project, "other")
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    :sys.suspend(Manager)
    view |> element("#start-codex") |> render_click()

    :sys.replace_state(view.pid, fn state ->
      %{state | socket: Phoenix.LiveView.cancel_async(state.socket, :start_run, :kill)}
    end)

    settle(view)
    assert has_element?(view, "#start-delivery[disabled]")
    render_patch(view, "/projects/#{c.project.id}/tasks/#{other.task.id}")
    settle(view)
    assert has_element?(view, "#start-delivery[disabled]")
    :sys.resume(Manager)
    assert_receive {:manual, worker, run}, 1_000
    render_patch(view, task_path(c))
    settle(view)
    assert has_element?(view, "#start-delivery[disabled]")
    send(worker, :stop)
    assert_receive {:manual_finished, id}, 1_000
    assert id == run.id
    settle(view)
    refute has_element?(view, "#start-delivery[disabled]")
  end

  test "invalid command resolves admission and permits a corrected explicit start", c do
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    id = command(view)
    start(view, id, "")
    settle(view)
    assert has_element?(view, "#delivery-error", "Enter one command")
    refute has_element?(view, "#delivery-command[readonly]")
    refute has_element?(view, "#delivery-request-pending")
    assert command(view) == id
    start(view, id, "mix test")
    assert_receive {:workflow, worker, _}, 1_000
    finish(worker, :cancelled)
  end

  test "run notifications cannot hide a pending interrupted sync", c do
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)

    :sys.replace_state(view.pid, fn state ->
      socket =
        Phoenix.Component.assign(state.socket, refreshing: true, refresh_pending: :interrupted)

      {:noreply, socket} = ProjectLive.handle_info({:run_changed, c.project.id}, socket)
      %{state | socket: socket}
    end)

    assert :sys.get_state(view.pid).socket.assigns.refresh_pending == :interrupted
  end

  test "navigation cannot show another task's report or a late admission error", c do
    delivery = ready(c)
    other = spec(c.project, "other")
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    assert has_element?(view, "#delivery-#{delivery.id}")
    render_patch(view, "/projects/#{c.project.id}/tasks/#{other.task.id}")
    settle(view)
    refute has_element?(view, "#delivery-#{delivery.id}")
    refute has_element?(view, "#task-deliveries", "<script>not executable</script>")
    key = {:delivery_request, c.saved.task.id, :start, c.saved.task.id, delivery.command_id}

    :sys.replace_state(view.pid, fn state ->
      {:noreply, socket} = ProjectLive.handle_async(key, {:exit, :killed}, state.socket)
      %{state | socket: socket}
    end)

    settle(view)
    refute has_element?(view, "#delivery-error")
    refute has_element?(view, "#delivery-#{delivery.id}")
  end

  test "Queue waits for dependencies with saved pins and Cancel releases task controls", c do
    c = waiting_task(c)
    spec(c.project, "waiting", "# New source")
    {:ok, view, _} = live(c.conn, task_path(c) <> "?revision=2")
    settle(view)
    assert has_element?(view, "#start-delivery[disabled]")
    refute has_element?(view, "#queue-delivery[disabled]")
    refute has_element?(view, "#delivery-command[disabled]")
    queue(view, command(view), "mix test saved_test.exs", "claude")
    settle(view)
    [saved] = Queue.list(c.project.id, c.saved.task.id)
    assert saved.status == "queued"
    assert saved.spec_revision_id == c.saved.task.spec_revision_id
    assert saved.reviewer == "claude"
    assert saved.check_config["argv"] == ["mix", "test", "saved_test.exs"]
    assert has_element?(view, "#queued-workflow-#{saved.id}", "Waiting for prerequisites")
    assert has_element?(view, "#queued-workflow-#{saved.id}", "Source revision 1")
    assert has_element?(view, "#queued-workflow-#{saved.id}", "Reviewer: Claude")
    assert has_element?(view, "#queue-delivery[disabled]")
    assert has_element?(view, "#start-codex[disabled]")
    assert has_element?(view, "#adopt-revision[disabled]")
    refute_receive {:workflow, _, _}, 50
    assert Tasks.get_task!(c.saved.task.id).state == "new"
    render_click(view, "cancel_queue", %{"queue-id" => Ecto.UUID.generate()})
    assert hd(Queue.list(c.project.id, c.saved.task.id)).status == "queued"
    view |> element("#cancel-queue-#{saved.id}") |> render_click()
    settle(view)
    assert has_element?(view, "#queued-workflow-#{saved.id}", "Queue cancelled")
    refute has_element?(view, "#queue-delivery[disabled]")
    refute has_element?(view, "#adopt-revision[disabled]")
    assert has_element?(view, "#queued-workflow-#{saved.id}", "Reviewer: Claude")
  end

  test "unknown Queue freezes UUID, command, reviewer and action across navigation", c do
    c = waiting_task(c)
    other = spec(c.project, "other")
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    id = command(view)
    :sys.suspend(Manager)
    queue(view, id, "mix test", "claude")
    key = :sys.get_state(view.pid).socket.assigns.delivery_starting

    :sys.replace_state(view.pid, fn state ->
      %{state | socket: Phoenix.LiveView.cancel_async(state.socket, key, :kill)}
    end)

    settle(view)
    assert has_element?(view, "#queue-delivery", "Retry queue request")
    assert has_element?(view, "#start-delivery[disabled]")
    assert has_element?(view, "#delivery-command[readonly]")
    queue(view, id, "mix test changed", "claude")
    queue(view, id, "mix test", "codex")
    start(view, id, "mix test", "claude")

    assert :sys.get_state(view.pid).socket.assigns.delivery_requests[c.saved.task.id].action ==
             :queue

    assert :sys.get_state(view.pid).socket.assigns.delivery_requests[c.saved.task.id].text ==
             "mix test"

    render_patch(view, "/projects/#{c.project.id}/tasks/#{other.task.id}")
    settle(view)
    assert has_element?(view, "#queue-delivery[disabled]")
    assert has_element?(view, "#start-codex[disabled]")
    render_patch(view, task_path(c))
    settle(view)
    queue(view, id, "mix test", "claude")
    :sys.resume(Manager)
    settle(view)
    [saved] = Queue.list(c.project.id, c.saved.task.id)
    assert saved.command_id == id
    assert saved.reviewer == "claude"
    refute_receive {:workflow, _, _}, 50
    refute has_element?(view, "#delivery-request-pending")
    current = command(view)
    refute current == id

    :sys.replace_state(view.pid, fn state ->
      {:noreply, socket} = ProjectLive.handle_async(key, {:exit, :killed}, state.socket)
      %{state | socket: socket}
    end)

    settle(view)
    assert command(view) == current
    refute has_element?(view, "#delivery-error")
    {:ok, _} = Queue.cancel(c.project.id, saved.id)
  end

  test "restart pause refreshes the open queue and exposes Resume without reloading", c do
    c = waiting_task(c)

    {:ok, request} =
      Queue.admit(c.project.id, c.saved.task.id, Ecto.UUID.generate(), "true", "codex")

    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    assert has_element?(view, "#queued-workflow-#{request.id}", "Queued")
    assert {:ok, [_]} = Queue.pause()
    settle(view)
    assert has_element?(view, "#queued-workflow-#{request.id}", "Paused")
    assert has_element?(view, "#resume-queue-#{request.id}")
    refute_receive {:workflow, _, _}, 30
  end

  test "paused queue explicitly resumes its saved provider and revision", c do
    c = waiting_task(c)

    {:ok, saved} =
      Queue.enqueue(
        c.project.id,
        c.saved.task.id,
        Ecto.UUID.generate(),
        "mix test old_test.exs",
        "claude"
      )

    {:ok, [_]} = Queue.pause()
    spec(c.project, "waiting", "# New source")
    {:ok, view, _} = live(c.conn, task_path(c) <> "?revision=2")
    settle(view)
    assert has_element?(view, "#queued-workflow-#{saved.id}", "Paused")
    assert has_element?(view, "#queued-workflow-#{saved.id}", "Source revision 1")
    assert has_element?(view, "#queued-workflow-#{saved.id}", "Reviewer: Claude")
    view |> element("#resume-queue-#{saved.id}") |> render_click()
    settle(view)
    [resumed] = Queue.list(c.project.id, c.saved.task.id)
    assert resumed.id == saved.id
    assert resumed.command_id == saved.command_id
    assert resumed.spec_revision_id == saved.spec_revision_id
    assert resumed.check_config == saved.check_config
    assert resumed.reviewer == "claude"
    assert resumed.status == "queued"
    assert has_element?(view, "#queued-workflow-#{saved.id}", "Queued")
    refute has_element?(view, "#resume-queue-#{saved.id}")
    {:ok, _} = Queue.cancel(c.project.id, saved.id)
  end

  test "unknown Resume keeps Cancel disabled and a saved receipt defeats late errors", c do
    c = waiting_task(c)

    {:ok, saved} =
      Queue.enqueue(c.project.id, c.saved.task.id, Ecto.UUID.generate(), "mix test", "claude")

    {:ok, [_]} = Queue.pause()
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    :sys.suspend(Manager)
    view |> element("#resume-queue-#{saved.id}") |> render_click()
    key = :sys.get_state(view.pid).socket.assigns.queue_starting

    :sys.replace_state(view.pid, fn state ->
      %{state | socket: Phoenix.LiveView.cancel_async(state.socket, key, :kill)}
    end)

    settle(view)
    assert has_element?(view, "#resume-queue-#{saved.id}", "Retry Resume")
    assert has_element?(view, "#cancel-queue-#{saved.id}[disabled]")
    render_click(view, "cancel_queue", %{"queue-id" => saved.id})
    assert hd(Queue.list(c.project.id, c.saved.task.id)).status == "paused"
    view |> element("#resume-queue-#{saved.id}") |> render_click()
    :sys.resume(Manager)
    settle(view)
    assert hd(Queue.list(c.project.id, c.saved.task.id)).status == "queued"
    refute has_element?(view, "#cancel-queue-#{saved.id}[disabled]")

    :sys.replace_state(view.pid, fn state ->
      {:noreply, socket} = ProjectLive.handle_async(key, {:exit, :killed}, state.socket)
      %{state | socket: socket}
    end)

    settle(view)
    refute has_element?(view, "#queue-error")
    refute has_element?(view, "#delivery-request-pending")
    {:ok, _} = Queue.cancel(c.project.id, saved.id)
  end

  test "unknown manual admission blocks Resume on another task until its receipt is reconciled",
       c do
    c = waiting_task(c)
    other = spec(c.project, "manual")

    {:ok, saved} =
      Queue.enqueue(c.project.id, c.saved.task.id, Ecto.UUID.generate(), "mix test", "codex")

    {:ok, [_]} = Queue.pause()
    {:ok, view, _} = live(c.conn, "/projects/#{c.project.id}/tasks/#{other.task.id}")
    settle(view)
    :sys.suspend(Manager)
    view |> element("#start-codex") |> render_click()

    :sys.replace_state(view.pid, fn state ->
      %{state | socket: Phoenix.LiveView.cancel_async(state.socket, :start_run, :kill)}
    end)

    settle(view)
    render_patch(view, task_path(c))
    settle(view)
    assert has_element?(view, "#resume-queue-#{saved.id}[disabled]")
    render_click(view, "resume_queue", %{"queue-id" => saved.id})
    assert hd(Queue.list(c.project.id, c.saved.task.id)).status == "paused"
    :sys.resume(Manager)
    assert_receive {:manual, worker, _}, 1_000
    send(worker, :stop)
    assert_receive {:manual_finished, _}, 1_000
    render_patch(view, "/projects/#{c.project.id}/tasks/#{other.task.id}")
    settle(view)
    render_patch(view, task_path(c))
    settle(view)
    refute has_element?(view, "#resume-queue-#{saved.id}[disabled]")
    {:ok, _} = Queue.cancel(c.project.id, saved.id)
  end

  test "a queue dispatched during Cancel refreshes the saved workflow and offers Stop", c do
    c = waiting_task(c)
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    queue(view, command(view))
    settle(view)
    [saved] = Queue.list(c.project.id, c.saved.task.id)

    Repo.update_all(from(t in Tasks.Task, where: t.id == ^c.dependency.task.id),
      set: [state: "done"]
    )

    assert_receive {:workflow, worker, delivery}, 1_500

    :sys.replace_state(view.pid, fn state ->
      socket =
        Phoenix.Component.assign(state.socket,
          queued_workflows: [saved],
          detail_loading: false,
          queue_starting: nil
        )

      {:noreply, socket} =
        ProjectLive.handle_event("cancel_queue", %{"queue-id" => saved.id}, socket)

      %{state | socket: socket}
    end)

    settle(view)
    assert has_element?(view, "#queued-workflow-#{saved.id}", "Started workflow")
    refute has_element?(view, "#cancel-queue-#{saved.id}")
    assert has_element?(view, "#stop-delivery-#{delivery.id}", "Stop workflow")
    assert Process.alive?(worker)
    view |> element("#stop-delivery-#{delivery.id}") |> render_click()
    assert_receive {:fixture_finished, _}, 1_000
    settle(view)
    assert has_element?(view, "#delivery-#{delivery.id}", "Workflow stopped")
  end

  test "two workflows run independently and a queued third starts when one finishes", c do
    second = spec(c.project, "second")
    third = spec(c.project, "third")
    {:ok, view, _} = live(c.conn, task_path(c))
    settle(view)
    start(view, command(view))
    assert_receive {:workflow, first_worker, _}, 1_000
    settle(view)
    render_patch(view, "/projects/#{c.project.id}/tasks/#{second.task.id}")
    settle(view)
    start(view, command(view))
    assert_receive {:workflow, second_worker, _}, 1_000
    settle(view)
    render_patch(view, "/projects/#{c.project.id}/tasks/#{third.task.id}")
    settle(view)
    queue(view, command(view))
    settle(view)
    [saved] = Queue.list(c.project.id, third.task.id)
    assert saved.status == "queued"
    assert map_size(:sys.get_state(Manager).active) == 2

    {third_worker, third_delivery} =
      with_suspended_view(view, fn ->
        hold_next_detail_read(view)
        send(view.pid, {:run_changed, c.project.id})
        refute_receive {:detail_reader_held, _}, 50
        finish(first_worker, :cancelled)
        assert_receive {:workflow, third_worker, third_delivery}, 1_500
        assert Process.alive?(second_worker)
        {third_worker, third_delivery}
      end)

    assert_receive {:detail_reader_held, reader}, 1_000
    send(reader, :release_detail_reader)
    settle(view)
    assert Process.alive?(second_worker)
    assert has_element?(view, "#queued-workflow-#{saved.id}", "Started workflow")
    assert has_element?(view, "#stop-delivery-#{third_delivery.id}")

    with_suspended_view(view, fn ->
      finish(second_worker, :cancelled)
      finish(third_worker, :cancelled)
    end)
  end

  defp waiting_task(c) do
    {:ok, dependency} =
      Projects.record_spec(c.project.id, %{
        explicit_id: "prerequisite",
        relative_path: "prerequisite.md",
        title: "Prerequisite",
        original_text: "---\nid: prerequisite\n---\n# Prerequisite"
      })

    saved = spec(c.project, "waiting", "---\ndepends_on: [prerequisite]\n---\n# Waiting")
    Map.merge(c, %{saved: saved, dependency: dependency})
  end

  defp queue(view, id, text \\ "mix test", reviewer \\ "codex"),
    do:
      render_submit(view, "start_delivery", %{
        "command_id" => id,
        "command" => text,
        "reviewer" => reviewer,
        "intent" => "queue"
      })

  defp fake_manual_worker(owner, run, manager) do
    send(owner, {:manual, self(), run})

    receive do
      :stop -> :ok
    after
      10_000 -> :ok
    end

    result = Runs.update(run.id, status: "cancelled", cleanup: "group_empty")
    send(manager, {:run_finished, run.id, self(), result})
    send(owner, {:manual_finished, run.id})
  end

  defp fake_worker(owner, delivery, manager, kind) do
    send(owner, {kind, self(), delivery})

    result =
      receive do
        {:finish, :done} -> integrated(delivery)
        {:finish, :cancelled} -> Deliveries.complete(delivery.id, "cancelled")
        :stop -> Deliveries.complete(delivery.id, "cancelled")
      after
        10_000 -> Deliveries.complete(delivery.id, "cancelled")
      end

    send(manager, {:delivery_finished, delivery.id, self(), result})
    if !match?({:ok, _}, result), do: send(owner, {:fixture_error, {self(), result}})
    send(owner, {:fixture_finished, {self(), delivery.id}})
  end

  defp ready(c) do
    {:ok, {:new, delivery}} =
      Deliveries.admit(c.project.id, c.saved.task.id, Ecto.UUID.generate(), "mix test")

    ready_delivery(c.project, delivery)
  end

  defp ready_delivery(project, delivery) do
    intent = %{
      "project_id" => to_string(project.id),
      "run_id" => delivery.id,
      "repo_path" => project.root_path,
      "git_common_dir" => project.git_common_dir,
      "base_branch" => "main",
      "base_commit" => @base,
      "path" => "/retained/workflow"
    }

    {:ok, _} = Deliveries.set_intent(delivery.id, intent)

    plan =
      stage(delivery, "plan", 0, %{"workspace" => intent}, %{
        "report" => %{
          "summary" => "Saved plan",
          "steps" => ["Implement and verify"],
          "acceptance" => ["Saved criterion"]
        }
      })

    implementation =
      stage(delivery, "implement", 1, %{"plan_step_id" => plan.id}, %{
        "workspace" => intent,
        "head_commit" => @base
      })

    snapshot =
      stage(delivery, "snapshot", 1, %{"implementation_step_id" => implementation.id}, %{
        "workspace" => intent,
        "candidate_commit" => @candidate
      })

    check =
      stage(
        delivery,
        "check",
        1,
        %{
          "snapshot_step_id" => snapshot.id,
          "candidate_commit" => @candidate,
          "workspace" => intent,
          "config_hash" => delivery.config_hash
        },
        %{"output_complete" => true, "output_hash" => @hash}
      )

    stage(
      delivery,
      "review",
      1,
      %{
        "check_step_id" => check.id,
        "plan_step_id" => plan.id,
        "candidate_commit" => @candidate,
        "config_hash" => delivery.config_hash,
        "original_base" => @base,
        "input_hash" => @hash
      },
      %{
        "report" => %{
          "verdict" => "approved",
          "summary" => "<script>not executable</script>",
          "acceptance" => [
            %{
              "criterion" => "Saved criterion",
              "status" => "passed",
              "evidence" => "Inspected code"
            }
          ],
          "issues" => []
        }
      }
    )

    {:ok, delivery} = Deliveries.complete(delivery.id, "ready_to_merge")
    delivery
  end

  defp integrated(delivery) do
    steps = Deliveries.steps(delivery.id)
    review = Enum.find(steps, &(&1.kind == "review"))
    check = Enum.find(steps, &(&1.id == review.input["check_step_id"]))

    intent = %{
      "delivery_id" => delivery.id,
      "base_commit" => @base,
      "candidate_commit" => @candidate,
      "candidate" => check.input["workspace"],
      "repo_path" => delivery.intent["repo_path"],
      "base_branch" => "main"
    }

    {:ok, _} = Deliveries.set_integration_intent(delivery.id, intent)

    publish =
      stage(delivery, "publish", 1, %{"intent" => intent, "review_step_id" => review.id}, %{
        "candidate_commit" => @candidate
      })

    stage(
      delivery,
      "post_check",
      1,
      %{
        "publish_step_id" => publish.id,
        "intent" => intent,
        "config_hash" => delivery.config_hash
      },
      %{"candidate_commit" => @candidate, "output_complete" => true, "output_hash" => @hash}
    )

    Deliveries.complete(delivery.id, "done")
  end

  defp stage(delivery, kind, cycle, input, receipt) do
    {:ok, step} = Deliveries.begin_step(delivery.id, kind, cycle, input)

    {:ok, step} =
      Deliveries.finish_step(
        step.id,
        Map.merge(
          %{
            "status" => "finished",
            "cleanup" => "group_empty",
            "exit_kind" => "exit",
            "exit_code" => 0,
            "eof" => %{"stdout" => true, "stderr" => true}
          },
          receipt
        )
      )

    step
  end

  defp with_suspended_view(view, fun) do
    # Shared Sandbox has one checkout; separate fake persistence from UI refresh reads.
    settle(view)
    :sys.suspend(view.pid)

    try do
      fun.()
    after
      :sys.resume(view.pid)
    end
  end

  defp hold_next_detail_read(view) do
    owner = self()
    gate = :atomics.new(1, [])
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:boss, :repo, :query],
        fn _, _, metadata, _ ->
          if metadata[:source] == "tasks" and Repo.in_transaction?() and
               view.pid in Process.get(:"$callers", []) and
               :atomics.compare_exchange(gate, 1, 0, 1) == :ok do
            ref = Process.monitor(owner)
            send(owner, {:detail_reader_held, self()})

            receive do
              :release_detail_reader -> :ok
              {:DOWN, ^ref, :process, ^owner, _} -> :ok
            after
              3_000 -> :ok
            end

            Process.demonitor(ref, [:flush])
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  defp finish(worker, status) do
    send(worker, {:finish, status})
    assert_receive {:fixture_finished, {^worker, _}}, 1_000
    refute_receive {:fixture_error, _}, 10
    :sys.get_state(Manager)
  end

  defp spec(project, name, source \\ "# One\nSaved criterion") do
    {:ok, saved} =
      Projects.record_spec(project.id, %{
        relative_path: "#{name}.md",
        title: name,
        original_text: source
      })

    saved
  end

  defp start(view, id, text \\ "mix test", reviewer \\ "codex"),
    do:
      render_submit(view, "start_delivery", %{
        "command_id" => id,
        "command" => text,
        "reviewer" => reviewer
      })

  defp task_path(c), do: "/projects/#{c.project.id}/tasks/#{c.saved.task.id}"

  defp command(view),
    do:
      view
      |> element("#delivery-form input[name='command_id']")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("value")
      |> hd()

  defp integration_command(view, id),
    do:
      view
      |> element("#integrate-delivery-#{id}")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("phx-value-command-id")
      |> hd()

  defp settle(view) do
    render(view)
    for _ <- 1..5, do: render_async(view, 2_000)
  end
end
