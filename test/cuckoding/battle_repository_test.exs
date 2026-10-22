defmodule Cuckoding.BattleRepositoryTest do
  use ExUnit.Case, async: true
  alias Cuckoding.BattleRepository

  test "same-repository I/O waits while another repository continues" do
    supervisor = start_supervised!(Task.Supervisor)
    owner = self()
    source = source()

    first =
      Task.Supervisor.async_nolink(supervisor, fn ->
        BattleRepository.run(source, fn -> true end, fn ->
          send(owner, :holding)
          receive do: (:release -> :first)
        end)
      end)

    assert_receive :holding

    second =
      Task.Supervisor.async_nolink(supervisor, fn ->
        BattleRepository.run(source, fn -> true end, fn ->
          send(owner, :second_entered)
          :second
        end)
      end)

    refute_receive :second_entered, 50
    assert :independent == BattleRepository.run(source(), fn -> true end, fn -> :independent end)
    send(first.pid, :release)
    assert Task.await(first) == :first
    assert Task.await(second) == :second
    assert_receive :second_entered
  end

  test "queued cancellation launches nothing and owner death releases only the VM queue" do
    supervisor = start_supervised!(Task.Supervisor)
    owner = self()
    source = source()

    holder =
      Task.Supervisor.async_nolink(supervisor, fn ->
        BattleRepository.run(source, fn -> true end, fn ->
          send(owner, :holding)
          receive do: (:release -> :released)
        end)
      end)

    assert_receive :holding
    flag = start_supervised!({Agent, fn -> true end})

    queued =
      Task.Supervisor.async_nolink(supervisor, fn ->
        BattleRepository.run(source, fn -> Agent.get(flag, & &1) end, fn ->
          flunk("cancelled I/O ran")
        end)
      end)

    Agent.update(flag, fn _ -> false end)
    assert Task.await(queued) == %{"status" => "cancelled", "cleanup_verified" => true}
    Process.exit(holder.pid, :kill)
    assert {:exit, :killed} = Task.yield(holder)
    assert :new_owner == BattleRepository.run(source, fn -> true end, fn -> :new_owner end)
  end

  defp source, do: %{"device" => 1, "inode" => System.unique_integer([:positive])}
end
