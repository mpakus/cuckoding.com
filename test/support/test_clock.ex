defmodule Cuckoding.TestClock do
  @moduledoc false
  @behaviour Cuckoding.Clock

  @wall_now ~U[2026-09-17 18:53:48Z]
  @monotonic_milliseconds 12_345

  @impl true
  def wall_now, do: @wall_now

  @impl true
  def monotonic_time(unit) do
    System.convert_time_unit(@monotonic_milliseconds, :millisecond, unit)
  end
end
