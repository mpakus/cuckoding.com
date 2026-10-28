defmodule BossWeb.ManagerFixture do
  @moduledoc false
  import ExUnit.Assertions
  alias Boss.Runs.Manager

  def restore(original, worker_keys) do
    :sys.resume(Manager)
    :sys.suspend(Manager)
    workers = :sys.get_state(Manager).active |> Map.values() |> Enum.map(&elem(&1, 1))
    monitors = Enum.map(workers, &{&1, Process.monitor(&1)})

    try do
      Enum.each(workers, &send(&1, :stop))

      for {pid, ref} <- monitors do
        assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
      end
    after
      # Keep the singleton quiet before the earlier sandbox-owner callback runs.
      for {pid, ref} <- monitors, Process.alive?(pid) do
        Process.exit(pid, :kill)
        assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
      end

      :sys.replace_state(Manager, fn state ->
        if state.queue_timer, do: Process.cancel_timer(elem(state.queue_timer, 0))
        drain(Map.new(workers, &{&1, true}))
        # This fixture bypasses Manager.finish, including its Autopilot alias cleanup.
        Enum.each(workers, &:ets.match_delete(state.registry, {:_, :_, &1}))

        state
        |> Map.merge(Map.take(original, worker_keys))
        |> Map.merge(%{
          active: %{},
          finished: %{},
          queue_timer: nil,
          queue_cursor: nil,
          autopilot_cursor: nil
        })
      end)

      :sys.resume(Manager)
    end
  end

  defp drain(workers) do
    receive do
      {:queue_tick, _} ->
        drain(workers)

      {:EXIT, pid, _} when is_map_key(workers, pid) ->
        drain(workers)

      {kind, _, pid, _}
      when kind in [:run_finished, :delivery_finished] and is_map_key(workers, pid) ->
        drain(workers)
    after
      0 -> :ok
    end
  end
end
