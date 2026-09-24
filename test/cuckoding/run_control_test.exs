defmodule Cuckoding.RunControlTest do
  use CuckodingWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.LocalProcessRunner
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Repo
  alias Cuckoding.RunControl
  alias Cuckoding.WalkingSkeleton

  defmodule GateRunner do
    def result(handle) do
      with {:ok, result} <- LocalProcessRunner.result(handle),
           do: {:ok, Map.put(result, :adapter, "fake")}
    end
  end

  defmodule GateAdapter do
    def start(%{stage_key: "specification"} = request, options) do
      with {:ok, session} <- Cuckoding.Adapters.FakeAdapter.start(request, options),
           {:ok, handle} <-
             LocalProcessRunner.start(
               Keyword.fetch!(options, :environment),
               %{
                 executable: "/bin/sh",
                 args: [
                   "-c",
                   "while [ ! -f continue-stage ]; do printf x >> heartbeat; sleep 0.02; done"
                 ]
               },
               timeout: 10_000,
               termination_grace_ms: 25
             ) do
        send(Keyword.fetch!(options, :caller), {:stage_started, handle})
        {:ok, %{session | process: %{runner: GateRunner, handle: handle}}}
      end
    end

    def start(request, options), do: Cuckoding.Adapters.FakeAdapter.start(request, options)
  end

  setup do
    root = Path.join(System.tmp_dir!(), "run-controls-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "pause stops stage progress, resumes the same attempt and restores a waiting approval", %{
    root: root
  } do
    run = fixture(root, "pause")
    worker = start_gated(run)
    assert_receive {:stage_started, handle}
    cleanup(handle)
    wait_for_session(run.run.id)
    heartbeat = Path.join(run.environment.worktree_path, "heartbeat")
    eventually(fn -> File.exists?(heartbeat) end)

    assert {:ok, paused} = RunControl.control(run.run.id, "pause")
    assert paused.state == "paused"
    size = File.stat!(heartbeat).size
    Process.sleep(150)
    assert File.stat!(heartbeat).size == size

    refute Repo.exists?(
             from a in StageAttempt,
               where: a.run_id == ^run.run.id and a.stage_key == "development"
           )

    File.write!(Path.join(run.environment.worktree_path, "continue-stage"), "resume\n")
    assert Task.yield(worker, 50) == nil
    assert {:ok, resumed} = RunControl.control(run.run.id, "resume")
    assert resumed.state == "running"
    assert {:ok, pending} = Task.await(worker, 5_000)
    assert pending.run.state == "waiting"
    assert pending.run.wait_reason == "approval"
    attempt = Repo.get_by!(StageAttempt, run_id: run.run.id, stage_key: "specification")
    assert attempt.attempt == 1
    assert attempt.wall_ms - attempt.active_ms >= 150
    assert Repo.get!(Cuckoding.Execution.ProcessRecord, handle.process.id).state == "exited"

    assert {:ok, _paused} = RunControl.control(run.run.id, "pause")
    assert {:ok, waiting} = RunControl.control(run.run.id, "resume")
    assert waiting.state == "waiting"
    assert waiting.wait_reason == "approval"
    assert {:ok, stopped} = RunControl.control(run.run.id, "stop")
    assert stopped.state == "cancelled"
    assert Repo.get!(Cuckoding.Workflows.Approval, pending.approval.id).decision == "rejected"
  end

  test "stop ends a paused workflow, retains files and does not record a provider failure", %{
    root: root
  } do
    run = fixture(root, "stop")
    worker = start_gated(run)
    assert_receive {:stage_started, handle}
    cleanup(handle)
    wait_for_session(run.run.id)
    assert {:ok, _paused} = RunControl.control(run.run.id, "pause")
    assert {:ok, stopped} = RunControl.control(run.run.id, "stop")
    assert stopped.state == "cancelled"
    assert {:error, _interruption} = Task.await(worker, 5_000)
    assert File.dir?(run.environment.worktree_path)
    assert File.dir?(Path.join(run.environment.run_dir, "artifacts"))
    assert Cuckoding.Execution.LocalHostInspector.groups_empty?([handle.process.pgid])

    refute Repo.exists?(
             from a in StageAttempt, where: a.run_id == ^run.run.id and a.state == "failed"
           )

    refute Repo.exists?(
             from e in RunEvent,
               where: e.run_id == ^run.run.id and e.event_type == "workflow.failed"
           )

    assert {:ok, _same} = RunControl.control(run.run.id, "stop")
  end

  test "global pause prevents starts, resumes only its own pauses, and stop retains queued worktrees",
       %{root: root} do
    manual = fixture(root, "manual")
    {:ok, pending} = WalkingSkeleton.run(manual, simulate_sleep_gap: false)
    assert {:ok, _paused} = RunControl.control(manual.run.id, "pause")
    queued = fixture(root, "queued", false)
    active = fixture(root, "global")
    worker = start_gated(active)
    assert_receive {:stage_started, handle}
    cleanup(handle)
    wait_for_session(active.run.id)

    assert {:ok, %{failures: []}} = RunControl.control_all("pause")
    refute RunControl.admission_open?()
    assert Repo.get!(Run, active.run.id).state == "paused"
    assert {:error, :application_paused} = Cuckoding.GuidedRun.start(queued.run.id, async: false)
    assert Repo.get!(Run, queued.run.id).state == "queued"
    File.write!(Path.join(active.environment.worktree_path, "continue-stage"), "resume\n")
    assert {:ok, %{failures: []}} = RunControl.control_all("resume")
    assert {:ok, _reviewed} = Task.await(worker, 5_000)
    assert Repo.get!(Run, pending.run.id).state == "paused"
    assert {:ok, %{failures: []}} = RunControl.control_all("stop")
    assert Repo.get!(Run, queued.run.id).state == "cancelled"
    assert File.dir?(queued.environment.worktree_path)
    assert RunControl.application_state()["mode"] == "stopped"
  end

  test "missing live worker fails resume closed", %{root: root} do
    run = fixture(root, "missing-worker")
    assert {:ok, _paused} = RunControl.control(run.run.id, "pause")
    assert {:error, :resume_worker_unavailable} = RunControl.control(run.run.id, "resume")
    assert Repo.get!(Run, run.run.id).state == "paused"
  end

  test "run and workspace controls are accessible and persist their actions", %{
    root: root,
    conn: conn
  } do
    run = fixture(root, "controls-ui", false)
    assert {:ok, view, _html} = live(conn, ~p"/runs/#{run.run.id}")
    assert has_element?(view, "#run-execution-controls button[data-confirm]", "Stop run")
    view |> element("#run-execution-controls button", "Stop run") |> render_click()
    assert Repo.get!(Run, run.run.id).state == "cancelled"
    assert has_element?(view, "[role=status]", "Run stopped")
    assert {:ok, task_view, _html} = live(conn, ~p"/boards/#{run.board.id}/tasks/#{run.task.id}")
    assert has_element?(task_view, "#retry-task", "Retry with a new run")
    task_view |> element("#retry-task") |> render_click()
    assert Repo.get!(Run, run.run.id).state == "cancelled"
    assert length(Cuckoding.Execution.list_runs(run.task.id)) == 2
    assert File.dir?(run.environment.worktree_path)
    assert {:ok, dashboard, _html} = live(conn, ~p"/")
    dashboard |> element("#workspace-execution-controls button", "Pause all") |> render_click()
    assert has_element?(dashboard, "#workspace-execution-controls [role=status]", "Paused")

    assert has_element?(
             dashboard,
             "#workspace-execution-controls button[data-confirm]",
             "Stop all"
           )

    dashboard
    |> element("#workspace-execution-controls button", "Resume workspace")
    |> render_click()

    assert has_element?(dashboard, "#workspace-execution-controls [role=status]", "Active")
  end

  defp start_gated(run) do
    parent = self()

    Task.async(fn ->
      RunControl.track(run.run.id, :workflow, fn ->
        WalkingSkeleton.run(run,
          adapter: GateAdapter,
          adapter_options: [caller: parent],
          simulate_sleep_gap: false
        )
      end)
    end)
  end

  defp cleanup(handle) do
    on_exit(fn -> if Process.alive?(handle.worker), do: LocalProcessRunner.stop(handle) end)
  end

  defp wait_for_session(id) do
    eventually(fn ->
      Repo.exists?(
        from s in AgentSession,
          join: a in StageAttempt,
          on: a.id == s.stage_attempt_id,
          where: a.run_id == ^id
      )
    end)
  end

  defp fixture(root, name, start_run \\ true) do
    repo = Path.join(root, name)
    File.mkdir_p!(repo)
    git!(repo, ["init", "-b", "main"])
    git!(repo, ["config", "user.name", "Control Test"])
    git!(repo, ["config", "user.email", "test@example.invalid"])
    File.write!(Path.join(repo, "README.md"), "# Controls\n")
    git!(repo, ["add", "."])
    git!(repo, ["commit", "-m", "Fixture"])
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)

    {:ok, run} =
      WalkingSkeleton.create(%{
        name: name,
        repo_path: repo,
        workspace_root: Path.join(root, "workspaces-#{name}"),
        task_title: name,
        adapter_key: "fake",
        start_run: start_run,
        port_range_start: port,
        port_range_end: port
      })

    run
  end

  defp git!(repo, args) do
    {_output, 0} = System.cmd("/usr/bin/git", args, cd: repo, stderr_to_stdout: true)
  end

  defp eventually(callback, attempts \\ 100)

  defp eventually(callback, attempts) when attempts > 0 do
    if callback.(),
      do: :ok,
      else:
        (
          Process.sleep(20)
          eventually(callback, attempts - 1)
        )
  end

  defp eventually(_callback, 0), do: flunk("expected durable run control state")
end
