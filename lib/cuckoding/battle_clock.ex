defmodule Cuckoding.BattleClock do
  @moduledoc "Observe timing gaps independently of the coordinator; SQLite owns the fence."
  use GenServer
  alias Cuckoding.Battles

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)
  def check, do: GenServer.call(__MODULE__, :check)

  @impl true
  def init(options) do
    clock = Keyword.get(options, :clock, &sample/0)
    Process.send_after(self(), :tick, 1_000)
    {:ok, %{clock: clock, previous: clock.()}}
  end

  @impl true
  def handle_call(:check, _, state), do: {:reply, :ok, observe(state)}

  @impl true
  def handle_info(:tick, state) do
    state = observe(state)
    Process.send_after(self(), :tick, 1_000)
    {:noreply, state}
  end

  defp sample, do: {DateTime.utc_now(), System.monotonic_time(:millisecond)}

  defp observe(state) do
    current = state.clock.()
    if gap = gap(state.previous, current), do: {:ok, _} = Battles.observe_timing_gap(gap)
    %{state | previous: current}
  end

  def gap({%DateTime{} = previous, monotonic}, {%DateTime{} = current, next})
      when is_integer(monotonic) and is_integer(next) and next >= monotonic do
    wall = DateTime.diff(current, previous, :millisecond)
    elapsed = next - monotonic
    divergence = wall - elapsed

    if wall < 0 or elapsed >= 5_000 or wall >= 5_000 or abs(divergence) >= 2_000 do
      %{
        "previous_at" => DateTime.to_iso8601(previous),
        "observed_at" => DateTime.to_iso8601(current),
        "wall_elapsed_ms" => wall,
        "monotonic_elapsed_ms" => elapsed,
        "divergence_ms" => divergence,
        "kind" => if(wall < 0 or divergence <= -2_000, do: "clock_backward", else: "timing_gap")
      }
    end
  end
end
