defmodule Cuckoding.DispatcherTest do
  use Cuckoding.DataCase

  alias Cuckoding.{Codex, Command, Dispatcher, Event, ExecutionSupervisor, Foundation}

  @url "https://auth.openai.com/oauth/authorize?state=otp-login-canary"

  setup do
    root = Path.join("/private/tmp", "cuckoding-dispatcher-" <> Ecto.UUID.generate())
    File.mkdir!(root)
    path = Path.join(root, "codex")
    File.write!(path, "#!/bin/sh\nexit 1\n")
    File.chmod!(path, 0o700)
    previous = Application.get_env(:cuckoding, :native_helper)

    on_exit(fn ->
      Application.put_env(:cuckoding, :native_helper, previous)
      File.rm_rf!(root)
    end)

    %{root: root, path: path}
  end

  test "a waiting worker leaves its coordinator responsive and admission serialized" do
    {:ok, command} = Foundation.discover(Ecto.UUID.generate(), 0)
    dispatcher = start_dispatcher(controlled_executor())
    assert_receive {:executing, worker, claim}, 1_000
    assert claim.id == command.id
    refute worker == dispatcher
    refute worker == self()
    assert Task.Supervisor.children(Cuckoding.SetupTasks) == [worker]
    assert %{job: {%Task{pid: ^worker}, _}} = :sys.get_state(dispatcher, 100)

    send(dispatcher, :tick)
    send(dispatcher, :updated)
    send(dispatcher, {make_ref(), %{"status" => "checked"}})
    refute_receive {:executing, _, _}, 100
    assert Repo.get!(Command, command.id).state == "running"
    send(worker, {:finish, %{}})
    await(fn -> Repo.get!(Command, command.id).state == "completed" end)
    assert Process.alive?(dispatcher)
    assert count_events("discovery.completed", command.id) == 1
  end

  test "the default provider transport owns its Port in a task, not the coordinator", ctx do
    helper = Path.join(ctx.root, "helper")

    File.write!(helper, """
    #!/bin/sh
    touch '#{ctx.root}/started'
    while [ ! -f '#{ctx.root}/release' ]; do sleep 0.01; done
    printf '%s\\n' '{"status":"observed","version":"0.146.0"}'
    """)

    File.chmod!(helper, 0o700)
    Application.put_env(:cuckoding, :native_helper, helper)
    {:ok, command} = Foundation.check_codex(Ecto.UUID.generate(), 0, ctx.path, true)
    dispatcher = start_dispatcher()
    await(fn -> File.exists?(Path.join(ctx.root, "started")) end)
    assert %{job: {%Task{pid: worker}, _}} = :sys.get_state(dispatcher, 100)
    {:links, links} = Process.info(worker, :links)
    assert [port] = Enum.filter(links, &is_port/1)
    assert Port.info(port, :connected) == {:connected, worker}
    File.write!(Path.join(ctx.root, "release"), "finish")
    await(fn -> Repo.get!(Command, command.id).state == "completed" end)
    assert Foundation.workspace().codex["status"] == "supported"
  end

  test "completed setup survives a coordinator crash before its notification is handled", ctx do
    {:ok, command} = Foundation.check_codex(Ecto.UUID.generate(), 0, ctx.path, true)
    dispatcher = start_dispatcher(controlled_executor())
    assert_receive {:executing, worker, claim}, 1_000
    :sys.suspend(dispatcher)
    monitor = Process.monitor(worker)
    send(worker, {:finish, %{"status" => "supported", "version" => "0.146.0"}})
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1_000
    completed = Repo.get!(Command, command.id)
    assert completed.state == "completed"
    assert Foundation.workspace().codex["status"] == "supported"

    Process.exit(dispatcher, :kill)

    await(fn ->
      is_pid(Process.whereis(Dispatcher)) and Process.whereis(Dispatcher) != dispatcher
    end)

    assert Repo.get!(Command, command.id) == completed
    assert count_events("codex.completed", command.id) == 1
    assert count_events("codex.interrupted", command.id) == 0
    assert {:error, :lost_claim} = Foundation.finish(claim, %{"status" => "cancelled"})
    refute_receive {:executing, _, _}, 100
  end

  test "cancellation commits while its coordinator is suspended and late success stays rejected",
       ctx do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, ctx.path, true)
    {:ok, probe} = Foundation.claim()
    Foundation.finish(probe, %{"status" => "supported", "version" => "0.146.0"})
    {:ok, command} = Foundation.authorize_codex(Ecto.UUID.generate(), 1, :login, true)
    dispatcher = start_dispatcher(controlled_executor())
    assert_receive {:executing, worker, _}, 1_000
    send(worker, {:progress, @url})
    assert_receive {:progress_sent, ^worker}, 1_000
    await(fn -> Foundation.login_link(Foundation.last_probe("login_codex")) == @url end)
    :sys.suspend(dispatcher)
    Foundation.cancel_probe(command.id)
    monitor = Process.monitor(worker)

    send(
      worker,
      {:finish,
       %{
         "status" => "checked",
         "authorization" => "chatgpt",
         "catalog_status" => "fresh",
         "models" => []
       }}
    )

    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1_000
    cancelled = Repo.get!(Command, command.id)
    assert cancelled.state == "cancelled"
    refute Foundation.login_redirect(command.id)
    refute Foundation.workspace().connection["authorization"] == "chatgpt"
    assert Map.get(Foundation.workspace().connection, "models", []) == []
    Process.exit(dispatcher, :kill)

    await(fn ->
      is_pid(Process.whereis(Dispatcher)) and Process.whereis(Dispatcher) != dispatcher
    end)

    assert Repo.get!(Command, command.id) == cancelled
    assert count_events("login.cancelled", command.id) == 1
    refute_receive {:executing, _, _}, 100
  end

  test "a settlement exception rolls back and is interrupted without printing its payload", ctx do
    {:ok, command} = Foundation.check_codex(Ecto.UUID.generate(), 0, ctx.path, true)
    dispatcher = start_dispatcher(controlled_executor())
    assert_receive {:executing, worker, _}, 1_000

    Repo.query!("""
    CREATE TRIGGER refuse_setup_settlement BEFORE UPDATE ON commands
    WHEN NEW.state = 'completed'
    BEGIN SELECT RAISE(ABORT, 'private-settlement-canary'); END
    """)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        send(worker, {:finish, %{"status" => "supported", "version" => "0.146.0"}})
        await(fn -> Repo.get!(Command, command.id).state == "failed" end)
      end)

    refute log =~ "private-settlement-canary"
    assert Process.whereis(Dispatcher) == dispatcher
    assert Repo.get!(Command, command.id).result == "interrupted"
    assert Foundation.workspace().codex == %{}
    assert count_events("codex.completed", command.id) == 0
    assert count_events("codex.interrupted", command.id) == 1
    refute_receive {:executing, _, _}, 100
  end

  test "worker death records interruption once without restarting the coordinator or replaying",
       ctx do
    {:ok, command} = Foundation.check_codex(Ecto.UUID.generate(), 0, ctx.path, true)
    dispatcher = start_dispatcher(controlled_executor())
    assert_receive {:executing, worker, _}, 1_000
    Process.exit(worker, :kill)
    await(fn -> Repo.get!(Command, command.id).state == "failed" end)
    assert Repo.get!(Command, command.id).result == "interrupted"
    assert Process.whereis(Dispatcher) == dispatcher
    assert count_events("codex.interrupted", command.id) == 1
    refute_receive {:executing, _, _}, 100
    assert {:error, :lost_claim} = Foundation.finish(command, %{"status" => "supported"})
  end

  test "coordinator restart stops old workers before recovering their claims", ctx do
    assert_restart(ctx, :coordinator)
  end

  test "task supervisor restart also stops its coordinator without affecting battle workers",
       ctx do
    assert_restart(ctx, :tasks)
  end

  test "startup rejects an old unexpired external claim without replay", ctx do
    {:ok, command} = Foundation.check_codex(Ecto.UUID.generate(), 0, ctx.path, true)
    {:ok, claim} = Foundation.claim()
    assert claim.lease_until > System.system_time(:millisecond)
    start_dispatcher(controlled_executor())
    assert Repo.get!(Command, command.id).state == "failed"
    assert Repo.get!(Command, command.id).result == "interrupted"
    assert {:ok, []} = Foundation.recover()
    assert {:error, :lost_claim} = Foundation.interrupt(claim)
    assert count_events("codex.interrupted", command.id) == 1
    refute_receive {:executing, _, _}, 100
  end

  test "login progress stays transient, task-bound and protected through cancellation", ctx do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, ctx.path, true)
    {:ok, probe} = Foundation.claim()
    Foundation.finish(probe, %{"status" => "supported", "version" => "0.146.0"})
    {:ok, command} = Foundation.authorize_codex(Ecto.UUID.generate(), 1, :login, true)
    dispatcher = start_dispatcher(controlled_executor())
    assert_receive {:executing, worker, _}, 1_000
    assert :ets.info(:cuckoding_login_link, :owner) == dispatcher
    assert :ets.info(:cuckoding_login_link, :protection) == :protected

    send(dispatcher, {:login_link, self(), @url})
    send(worker, {:progress, "https://foreign.invalid/oauth/authorize"})
    assert_receive {:progress_sent, ^worker}, 1_000
    assert :sys.get_state(dispatcher, 100).job
    refute Foundation.login_link(Foundation.last_probe("login_codex"))
    send(worker, {:progress, @url})
    assert_receive {:progress_sent, ^worker}, 1_000
    await(fn -> Foundation.login_link(Foundation.last_probe("login_codex")) == @url end)
    assert count_events("login.awaiting_browser", command.id) == 1

    Foundation.cancel_probe(command.id)
    send(worker, {:progress, @url <> "-late"})
    assert_receive {:progress_sent, ^worker}, 1_000
    refute Foundation.login_link(Foundation.last_probe("login_codex"))
    assert Codex.login_link(command.id) == @url
    send(worker, {:finish, %{"status" => "cancelled"}})
    await(fn -> Repo.get!(Command, command.id).state == "cancelled" end)
    refute Foundation.login_redirect(command.id)
    await(fn -> is_nil(Codex.login_link(command.id)) end)
    refute inspect(Repo.all(Command)) =~ "otp-login-canary"
    refute inspect(Repo.all(Event)) =~ "otp-login-canary"
    refute inspect(Foundation.workspace()) =~ "otp-login-canary"
  end

  test "a crash while accepting login progress cannot print the transient URL", ctx do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, ctx.path, true)
    {:ok, probe} = Foundation.claim()
    Foundation.finish(probe, %{"status" => "supported", "version" => "0.146.0"})
    {:ok, command} = Foundation.authorize_codex(Ecto.UUID.generate(), 1, :login, true)
    dispatcher = start_dispatcher(controlled_executor())
    assert_receive {:executing, worker, _}, 1_000

    Repo.query!("""
    CREATE TRIGGER refuse_login_progress BEFORE UPDATE ON commands
    WHEN NEW.result = 'awaiting_login'
    BEGIN SELECT RAISE(ABORT, 'fixture login progress failure'); END
    """)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        send(worker, {:progress, @url})
        await(fn -> Repo.get!(Command, command.id).state == "failed" end)
      end)

    assert log =~ "redacted"
    refute log =~ "otp-login-canary"
    refute log =~ "auth.openai.com"
    refute Process.whereis(Dispatcher) == dispatcher
    refute Codex.login_link(command.id)
    assert Repo.get!(Command, command.id).result == "interrupted"
  end

  defp assert_restart(ctx, target) do
    start_supervised!(
      {ExecutionSupervisor, coordinator: Cuckoding.BattleRunner, tasks: Cuckoding.BattleTasks}
    )

    battle_runner = Process.whereis(Cuckoding.BattleRunner)
    {:ok, command} = Foundation.check_codex(Ecto.UUID.generate(), 0, ctx.path, true)
    dispatcher = start_dispatcher(controlled_executor())
    tasks = Process.whereis(Cuckoding.SetupTasks)
    assert_receive {:executing, worker, claim}, 1_000
    assert %{job: {%Task{pid: ^worker}, _}} = :sys.get_state(dispatcher, 100)
    # Keep the fault outside a shared sandbox transaction owned by this test.
    if target == :tasks, do: :sys.suspend(dispatcher)
    monitor = Process.monitor(worker)
    Process.exit(if(target == :coordinator, do: dispatcher, else: tasks), :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, reason}, 1_000
    assert reason in [:shutdown, :killed]

    await(fn ->
      is_pid(Process.whereis(Dispatcher)) and Process.whereis(Dispatcher) != dispatcher
    end)

    await(fn -> Repo.get!(Command, command.id).state == "failed" end)
    refute Process.whereis(Cuckoding.SetupTasks) == tasks
    assert Process.whereis(Cuckoding.BattleRunner) == battle_runner
    assert Task.Supervisor.children(Cuckoding.SetupTasks) == []
    assert Repo.get!(Command, command.id).result == "interrupted"
    assert count_events("codex.interrupted", command.id) == 1
    assert {:error, :lost_claim} = Foundation.finish(claim, %{"status" => "supported"})
    refute_receive {:executing, _, _}, 100
  end

  defp start_dispatcher(executor \\ nil) do
    options = if executor, do: [executor: executor], else: []

    start_supervised!(
      {ExecutionSupervisor,
       coordinator: Dispatcher, tasks: Cuckoding.SetupTasks, options: options}
    )

    Process.whereis(Dispatcher)
  end

  defp controlled_executor do
    test = self()

    fn command, progress ->
      send(test, {:executing, self(), command})
      wait_for_result(test, progress)
    end
  end

  defp wait_for_result(test, progress) do
    receive do
      {:progress, url} ->
        progress.(url)
        send(test, {:progress_sent, self()})
        wait_for_result(test, progress)

      {:finish, result} ->
        result
    end
  end

  defp count_events(kind, command_id),
    do:
      Repo.aggregate(
        from(e in Event, where: e.kind == ^kind and e.command_id == ^command_id),
        :count
      )

  defp await(fun, remaining \\ 100)
  defp await(fun, 0), do: assert(fun.())

  defp await(fun, remaining) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      await(fun, remaining - 1)
    end
  end
end
