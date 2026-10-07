defmodule Cuckoding.BoardControl.Budget do
  @moduledoc "A finite goal deadline shared by planning, delivery, retries and continuations."
  alias Cuckoding.{BoardControl, Clock}
  alias Cuckoding.BoardControl.Plans

  # UTC is the durable admission deadline across restarts. Each launched process
  # receives the remaining interval for its monotonic runtime timer; measured
  # stage active/wall/sleep accounting remains separate in Statistics.
  def remaining_ms(e) do
    if Plans.prepared_goal?(e) do
      minutes = e.snapshot_json["execution_profile"]["wall_minutes"]

      max(
        minutes * 60_000 - max(DateTime.diff(Clock.wall_now(), e.inserted_at, :millisecond), 0),
        0
      )
    end
  end

  def check(e) do
    if remaining_ms(e) == 0, do: {:error, :goal_budget_exhausted}, else: :ok
  end

  def timeout(%{board_execution_id: nil}, default), do: default

  def timeout(run, default) do
    case remaining_ms(BoardControl.get(run.board_execution_id)) do
      nil -> default
      remaining -> max(min(remaining, default), 1)
    end
  end
end
