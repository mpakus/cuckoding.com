defmodule Cuckoding.ClockTest do
  use ExUnit.Case, async: false

  test "delegates wall and monotonic time to the configured clock" do
    original = Application.fetch_env!(:cuckoding, :clock)
    Application.put_env(:cuckoding, :clock, Cuckoding.TestClock)
    on_exit(fn -> Application.put_env(:cuckoding, :clock, original) end)

    assert Cuckoding.Clock.wall_now() == ~U[2026-09-17 18:53:48Z]
    assert Cuckoding.Clock.monotonic_time(:millisecond) == 12_345
  end
end
