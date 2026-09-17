defmodule Cuckoding.Execution.CommandsTest do
  use Cuckoding.DataCase, async: false
  use ExUnitProperties

  alias Cuckoding.Execution.Command
  alias Cuckoding.Execution.CommandDispatcher
  alias Cuckoding.Execution.CommandRecovery
  alias Cuckoding.Execution.Commands

  defmodule SuccessHandler do
    @behaviour Cuckoding.Execution.CommandHandler

    @impl true
    def execute(command) do
      :ets.update_counter(
        :command_test_counts,
        command.idempotency_key,
        {2, 1},
        {command.idempotency_key, 0}
      )

      {:ok, %{"accepted" => command.payload["value"]}}
    end
  end

  defmodule FailingHandler do
    @behaviour Cuckoding.Execution.CommandHandler

    @impl true
    def execute(command) do
      :ets.update_counter(
        :command_test_counts,
        command.idempotency_key,
        {2, 1},
        {command.idempotency_key, 0}
      )

      {:error, :temporary_failure}
    end
  end

  defmodule CrashHandler do
    @behaviour Cuckoding.Execution.CommandHandler

    @impl true
    def execute(_command), do: raise("injected handler crash")
  end

  defmodule SensitiveFailureHandler do
    @behaviour Cuckoding.Execution.CommandHandler

    @impl true
    def execute(_command), do: {:error, "credential=must-not-be-persisted"}
  end

  setup do
    :ets.new(:command_test_counts, [:named_table, :public])

    on_exit(fn ->
      if :ets.whereis(:command_test_counts) != :undefined do
        :ets.delete(:command_test_counts)
      end
    end)
  end

  property "duplicate idempotency keys return the original result" do
    check all(duplicate_count <- integer(1..8), max_runs: 20) do
      key = Ecto.UUID.generate()
      now = ~U[2026-09-17 19:22:19.000000Z]

      assert {:ok, original} =
               Commands.enqueue(command_attrs(key, "original"), handler: SuccessHandler, now: now)

      for duplicate <- 1..duplicate_count do
        assert {:ok, repeated} =
                 Commands.enqueue(command_attrs(key, "duplicate-#{duplicate}"),
                   handler: SuccessHandler,
                   now: now
                 )

        assert repeated.id == original.id
        assert repeated.result == %{"accepted" => "original"}
      end

      assert execution_count(key) == 1

      assert Repo.aggregate(
               from(command in Command, where: command.idempotency_key == ^key),
               :count
             ) == 1
    end
  end

  test "a crash after commit replays the command once" do
    key = Ecto.UUID.generate()
    now = ~U[2026-09-17 19:22:19.000000Z]

    assert_raise RuntimeError, "injected post-commit crash", fn ->
      Commands.enqueue(command_attrs(key, "replay"),
        now: now,
        after_commit: fn _command -> raise "injected post-commit crash" end
      )
    end

    assert %Command{state: "pending", attempts: 0} =
             Repo.get_by!(Command, idempotency_key: key)

    assert [{:ok, %Command{state: "succeeded"}}] =
             CommandDispatcher.dispatch_due(handler: SuccessHandler, now: now)

    assert [] = CommandDispatcher.dispatch_due(handler: SuccessHandler, now: now)
    assert execution_count(key) == 1
  end

  test "an interrupted claim is recovered and replayed once" do
    key = Ecto.UUID.generate()
    now = ~U[2026-09-17 19:22:19.000000Z]

    assert {:ok, %Command{state: "pending"} = command} =
             Commands.enqueue(command_attrs(key, "recover"),
               now: now,
               after_commit: fn _ -> :ok end
             )

    assert_raise RuntimeError, "injected handler crash", fn ->
      CommandDispatcher.dispatch(command.id, handler: CrashHandler, now: now)
    end

    assert %Command{state: "running", attempts: 1} = Repo.get!(Command, command.id)

    previous_handler = Application.get_env(:cuckoding, :command_handler)
    Application.put_env(:cuckoding, :command_handler, SuccessHandler)

    on_exit(fn ->
      Application.put_env(:cuckoding, :command_handler, previous_handler)
    end)

    assert {:ok, 1, [{:ok, %Command{state: "succeeded", attempts: 1}}]} =
             CommandRecovery.run()

    assert execution_count(key) == 1
  end

  test "failed commands use bounded not-before backoff and stop at max attempts" do
    key = Ecto.UUID.generate()
    now = ~U[2026-09-17 19:22:19.000000Z]

    assert {:ok, %Command{state: "pending", attempts: 1} = command} =
             Commands.enqueue(command_attrs(key, "retry", 2), handler: FailingHandler, now: now)

    assert command.not_before == DateTime.add(now, 1_000, :millisecond)

    assert {:ok, %Command{attempts: 1}} =
             CommandDispatcher.dispatch(command.id, handler: FailingHandler, now: now)

    retry_at = DateTime.add(now, 1_000, :millisecond)

    assert {:ok, %Command{state: "failed", attempts: 2}} =
             CommandDispatcher.dispatch(command.id, handler: FailingHandler, now: retry_at)

    assert execution_count(key) == 2
  end

  test "failure details are not persisted" do
    key = Ecto.UUID.generate()

    assert {:ok, %Command{last_error: "command failed"} = command} =
             Commands.enqueue(command_attrs(key, "redact"), handler: SensitiveFailureHandler)

    refute command.last_error =~ "credential"
    refute inspect(Repo.get!(Command, command.id)) =~ "must-not-be-persisted"
  end

  defp command_attrs(key, value, max_attempts \\ 3) do
    %{
      idempotency_key: key,
      kind: "test.command",
      target_type: "run",
      target_id: Ecto.UUID.generate(),
      payload: %{"value" => value},
      max_attempts: max_attempts
    }
  end

  defp execution_count(key) do
    case :ets.lookup(:command_test_counts, key) do
      [{^key, count}] -> count
      [] -> 0
    end
  end
end
