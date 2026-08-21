defmodule AgentDesk.Providers.Redactor do
  @moduledoc """
  Redacts likely credentials before transcript persistence or diagnostic export.
  """

  @patterns [
    ~r/(?i)(api[_-]?key|token|secret|password|authorization|bearer)\s*[:=]\s*\S+/,
    ~r/\bsk-[A-Za-z0-9_-]{8,}\b/,
    ~r/\bghp_[A-Za-z0-9]{16,}\b/,
    ~r/\bxox[baprs]-[A-Za-z0-9-]+\b/
  ]

  @spec redact(term()) :: term()
  def redact(text) when is_binary(text) do
    Enum.reduce(@patterns, text, fn pattern, acc ->
      Regex.replace(pattern, acc, "[REDACTED]")
    end)
  end

  def redact(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, redact(value)} end)
  end

  def redact(list) when is_list(list), do: Enum.map(list, &redact/1)
  def redact(other), do: other
end
