defmodule Cuckoding.Identifier do
  @moduledoc """
  Generates RFC 9562 UUIDv7 identifiers for durable domain rows.
  """

  def generate do
    unix_ms = System.system_time(:millisecond)
    <<random_a::12, random_b::62, _unused::6>> = :crypto.strong_rand_bytes(10)

    <<unix_ms::48, 7::4, random_a::12, 2::2, random_b::62>>
    |> Base.encode16(case: :lower)
    |> format()
  end

  defp format(
         <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4), e::binary>>
       ) do
    Enum.join([a, b, c, d, e], "-")
  end
end
