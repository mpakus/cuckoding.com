defmodule Cuckoding.Clock do
  @moduledoc """
  Injectable wall and monotonic time used by durable domain code.
  """

  @callback wall_now() :: DateTime.t()
  @callback monotonic_time(System.time_unit()) :: integer()

  def wall_now, do: implementation().wall_now()
  def monotonic_time(unit), do: implementation().monotonic_time(unit)

  defp implementation, do: Application.fetch_env!(:cuckoding, :clock)
end

defmodule Cuckoding.SystemClock do
  @moduledoc false
  @behaviour Cuckoding.Clock

  @impl true
  def wall_now, do: DateTime.utc_now()

  @impl true
  def monotonic_time(unit), do: System.monotonic_time(unit)
end
