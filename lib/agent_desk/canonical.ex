defmodule AgentDesk.Canonical do
  @moduledoc """
  Stable JSON canonicalization used before hashing idempotency payloads.
  """

  @spec hash(term()) :: String.t()
  def hash(term) do
    term
    |> normalize()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), normalize(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {key, value} -> [key, value] end)
  end

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(other), do: other
end
