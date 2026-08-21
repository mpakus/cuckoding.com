defmodule AgentDesk.Resources.Overlap do
  @moduledoc false

  @spec conflict?(map(), map()) :: boolean()
  def conflict?(requested, held) do
    requested.resource_type == held.resource_type and
      overlaps?(requested.resource_type, requested.resource_key, held.resource_key) and
      mode_conflict?(requested.mode, held.mode) and
      requested.agent_session_id != held.agent_session_id
  end

  @spec overlaps?(String.t(), String.t(), String.t()) :: boolean()
  def overlaps?(type, a, b) when type in ["file", "directory"] do
    a = normalize(a)
    b = normalize(b)
    a == b or String.starts_with?(a, b <> "/") or String.starts_with?(b, a <> "/")
  end

  def overlaps?(_type, a, b), do: a == b

  defp mode_conflict?("exclusive", _held), do: true
  defp mode_conflict?(_requested, "exclusive"), do: true
  defp mode_conflict?(_requested, _held), do: false

  defp normalize(path) do
    path
    |> String.replace("\\", "/")
    |> String.trim("/")
    |> String.downcase()
  end
end
