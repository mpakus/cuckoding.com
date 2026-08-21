defmodule AgentDesk.Clock do
  @moduledoc """
  UTC clock used by durable records.

  Tests can stub this module later; production always uses microsecond UTC.
  """

  @spec utc_now() :: DateTime.t()
  def utc_now do
    DateTime.utc_now(:microsecond)
  end
end
