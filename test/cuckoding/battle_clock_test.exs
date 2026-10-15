defmodule Cuckoding.BattleClockTest do
  use ExUnit.Case, async: true
  alias Cuckoding.BattleClock

  test "ordinary samples tolerate timer jitter without fabricating a sleep observation" do
    now = ~U[2026-10-15 12:00:00.000Z]

    for {wall, elapsed} <- [{0, 0}, {1_000, 1_000}, {1_100, 1_000}, {4_999, 4_999}, {1_999, 0}] do
      assert BattleClock.gap(
               {now, -100_000},
               {DateTime.add(now, wall, :millisecond), -100_000 + elapsed}
             ) == nil
    end
  end

  test "elapsed gaps and forward clock divergence report both measured deltas" do
    now = ~U[2026-10-15 12:00:00.000Z]

    for {wall, elapsed} <- [{5_000, 5_000}, {60_000, 1_000}, {2_000, 0}] do
      gap =
        BattleClock.gap(
          {now, -100_000},
          {DateTime.add(now, wall, :millisecond), -100_000 + elapsed}
        )

      assert gap["kind"] == "timing_gap"
      assert gap["wall_elapsed_ms"] == wall
      assert gap["monotonic_elapsed_ms"] == elapsed
      assert gap["divergence_ms"] == wall - elapsed
    end
  end

  test "backward clock movement cannot extend an existing grant" do
    now = ~U[2026-10-15 12:00:00.000Z]

    for {wall, elapsed} <- [{-1, 0}, {-60_000, 1_000}, {1_000, 3_000}] do
      assert %{"kind" => "clock_backward"} =
               BattleClock.gap({now, 0}, {DateTime.add(now, wall, :millisecond), elapsed})
    end

    assert_raise FunctionClauseError, fn -> BattleClock.gap({now, 1}, {now, 0}) end
  end
end
