defmodule Cuckoding.Config do
  @moduledoc """
  Produces allowlisted diagnostics and redacts sensitive configuration values.
  """

  @redacted "[REDACTED]"
  @secret_fragments ~w(authorization cookie credential password secret token)

  def safe_snapshot do
    endpoint = Application.get_env(:cuckoding, CuckodingWeb.Endpoint, [])
    http = Keyword.get(endpoint, :http, [])

    %{
      environment: Application.fetch_env!(:cuckoding, :environment),
      endpoint: %{
        bind: "127.0.0.1",
        port: Keyword.get(http, :port),
        server: Keyword.get(endpoint, :server, false)
      }
    }
  end

  def sanitize(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {key, sanitize_entry(key, item)} end)
  end

  def sanitize(value) when is_list(value) do
    if Keyword.keyword?(value) do
      Enum.map(value, fn {key, item} -> {key, sanitize_entry(key, item)} end)
    else
      Enum.map(value, &sanitize/1)
    end
  end

  def sanitize(value), do: value

  defp sanitize_entry(key, value) do
    if secret_key?(key), do: @redacted, else: sanitize(value)
  end

  defp secret_key?(key) do
    normalized = key |> to_string() |> String.downcase()
    Enum.any?(@secret_fragments, &String.contains?(normalized, &1))
  end
end
