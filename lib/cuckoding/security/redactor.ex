defmodule Cuckoding.Security.Redactor do
  @moduledoc "Recursively removes registered secret values and sensitive keyed fields."

  @redacted "[REDACTED]"
  @sensitive_keys ~w(authorization cookie set-cookie password secret token api_key access_token refresh_token environment env argv)

  def redact(value, secrets \\ []) do
    secrets = Enum.filter(secrets, &(is_binary(&1) and byte_size(&1) > 0))
    do_redact(value, secrets)
  end

  defp do_redact(value, secrets) when is_binary(value) do
    Enum.reduce(secrets, value, &String.replace(&2, &1, @redacted))
  end

  defp do_redact(value, secrets) when is_list(value), do: Enum.map(value, &do_redact(&1, secrets))

  defp do_redact(value, secrets) when is_map(value) do
    Map.new(value, fn {key, item} ->
      if sensitive_key?(key), do: {key, @redacted}, else: {key, do_redact(item, secrets)}
    end)
  end

  defp do_redact(value, _secrets), do: value

  defp sensitive_key?(key) do
    normalized = key |> to_string() |> String.downcase() |> String.replace("-", "_")
    normalized in @sensitive_keys
  end
end
