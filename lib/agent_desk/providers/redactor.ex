defmodule AgentDesk.Providers.Redactor do
  @moduledoc """
  Redacts likely credentials before transcript persistence or diagnostic export.
  """

  @redacted "[REDACTED]"

  @sensitive_keys ~w(
    authorization
    proxy_authorization
    api_key
    apikey
    x_api_key
    x_auth_token
    token
    access_token
    refresh_token
    id_token
    auth_token
    bearer_token
    basic_token
    capability_token
    secret
    client_secret
    password
    cookie
    set_cookie
    session_cookie
  )

  @sensitive_suffixes ~w(_authorization _token _api_key _secret _password)

  @sensitive_key_source """
  (?:authorization|proxy[-_]?authorization|api[-_]?key|apikey|x[-_]?api[-_]?key|
  x[-_]?auth[-_]?token|token|access[-_]?token|refresh[-_]?token|id[-_]?token|
  auth[-_]?token|bearer[-_]?token|basic[-_]?token|capability[-_]?token|secret|
  client[-_]?secret|password|cookie|set[-_]?cookie|session[-_]?cookie|
  (?:[a-z0-9]+[-_])+(?:authorization|token|api[-_]?key|secret|password))
  """
  @sensitive_key_source String.replace(@sensitive_key_source, ~r/\s+/, "")

  @sensitive_header Regex.compile!(
                      "^([\\t ]*(?:authorization|proxy[-_]?authorization|(?:[a-z0-9]+[-_])authorization|x[-_]?api[-_]?key|x[-_]?auth[-_]?token|api[-_]?key|access[-_]?token|auth[-_]?token|cookie|set[-_]?cookie)\\s*[:=]\\s*)[^\\r\\n]*(?:\\r?\\n[\\t ]+[^\\r\\n]*)*",
                      "im"
                    )

  @env_assignment Regex.compile!(
                    "^([\\t ]*(?:export[\\t ]+)?[a-z_][a-z0-9_]*(?:_authorization|_token|_api_key|_secret|_password)[\\t ]*=[\\t ]*)(?:\"(?:\\\\.|[^\"\\\\])*\"|'[^']*'|[^\\r\\n]*)",
                    "im"
                  )

  @structured_assignment Regex.compile!(
                           "^([\\t ]*[a-z_][a-z0-9_]*(?:_authorization|_token|_api_key|_secret|_password)[\\t ]*:[\\t ]*)(?:\"(?:\\\\.|[^\"\\\\])*\"|'[^']*'|[^\\r\\n]*)",
                           "im"
                         )

  @json_credential Regex.compile!(
                     "(\"#{@sensitive_key_source}\"\\s*:\\s*\")((?:\\\\.|[^\"\\\\])*)(\")",
                     "i"
                   )

  @double_quoted_query Regex.compile!(
                         "((?:^|[?&;\\s])#{@sensitive_key_source}=)\"(?:\\\\.|[^\"\\\\])*\"",
                         "i"
                       )

  @single_quoted_query Regex.compile!(
                         "((?:^|[?&;\\s])#{@sensitive_key_source}=)'[^']*'",
                         "i"
                       )

  @unquoted_query Regex.compile!(
                    "((?:^|[?&;\\s])#{@sensitive_key_source}=)(?![\"'])[^&#;\\s,\\]\\}]+",
                    "i"
                  )

  @inline_authorization Regex.compile!(
                          "((?:authorization|proxy[-_]?authorization|(?:[a-z0-9]+[-_])authorization)\\s*[:=]\\s*)(?!\\[REDACTED\\])[^\\r\\n\"']+",
                          "i"
                        )

  @database_url Regex.compile!(
                  "((?:postgres(?:ql)?|mysql|mariadb|mongodb(?:\\+srv)?|redis(?:s)?|cockroachdb|sqlserver):\\/\\/)[^\\s\\/@]+(?::[^\\s\\/@]*)?@",
                  "i"
                )

  @pem_private_key Regex.compile!(
                     "(-----BEGIN ([A-Z0-9 ]*PRIVATE KEY)-----).*?(-----END \\2-----)",
                     "s"
                   )

  @token_patterns [
    ~r/(?<![A-Za-z0-9_.-])sk-[A-Za-z0-9_.-]{8,}(?![A-Za-z0-9_.-])/,
    ~r/(?<![A-Za-z0-9_])gh[pousr]_[A-Za-z0-9]{16,}(?![A-Za-z0-9_])/,
    ~r/(?<![A-Za-z0-9-])xox[baprs]-[A-Za-z0-9-]+(?![A-Za-z0-9-])/
  ]

  @spec redact(term()) :: term()
  def redact(text) when is_binary(text) do
    text
    |> replace(@pem_private_key, "\\1\n#{@redacted}\n\\3")
    |> replace(@database_url, "\\1#{@redacted}@")
    |> replace(@inline_authorization, "\\1#{@redacted}")
    |> replace(@env_assignment, "\\1#{@redacted}")
    |> replace(@structured_assignment, "\\1#{@redacted}")
    |> replace(@sensitive_header, "\\1#{@redacted}")
    |> replace(@json_credential, "\\1#{@redacted}\\3")
    |> replace(@double_quoted_query, "\\1\"#{@redacted}\"")
    |> replace(@single_quoted_query, "\\1'#{@redacted}'")
    |> replace(@unquoted_query, "\\1#{@redacted}")
    |> redact_token_patterns()
  end

  def redact(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      if sensitive_key?(key), do: {key, @redacted}, else: {key, redact(value)}
    end)
  end

  def redact(list) when is_list(list), do: Enum.map(list, &redact/1)

  def redact({key, value}) do
    if sensitive_key?(key), do: {key, @redacted}, else: {key, redact(value)}
  end

  def redact(other), do: other

  defp replace(text, pattern, replacement), do: Regex.replace(pattern, text, replacement)

  defp redact_token_patterns(text) do
    Enum.reduce(@token_patterns, text, fn pattern, acc ->
      Regex.replace(pattern, acc, @redacted)
    end)
  end

  defp sensitive_key?(key) when is_atom(key), do: key |> Atom.to_string() |> sensitive_key?()

  defp sensitive_key?(key) when is_binary(key) do
    normalized =
      key
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    normalized in @sensitive_keys or
      Enum.any?(@sensitive_suffixes, &String.ends_with?(normalized, &1))
  end

  defp sensitive_key?(_key), do: false
end
