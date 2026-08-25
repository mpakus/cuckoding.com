defmodule AgentDesk.Env do
  @moduledoc """
  Desktop PATH bootstrap and provider child environment policy.

  Finder-launched macOS apps inherit a stripped PATH, so Homebrew/npm CLIs like
  `codex` are invisible until we merge the login-shell PATH and common bin dirs.

  Provider processes receive only local CLI runtime essentials. Provider- and
  session-specific variables are merged explicitly by the caller.
  """

  @provider_environment_variables ~w(
    PATH
    HOME
    TMPDIR
    TMP
    TEMP
    SHELL
    USER
    LOGNAME
    LANG
    LANGUAGE
    LC_ALL
    LC_CTYPE
    LC_MESSAGES
    LC_COLLATE
    LC_MONETARY
    LC_NUMERIC
    LC_TIME
    TERM
    COLORTERM
    NO_COLOR
    FORCE_COLOR
    __CF_USER_TEXT_ENCODING
    XDG_CONFIG_HOME
    XDG_CACHE_HOME
    XDG_DATA_HOME
    XDG_STATE_HOME
    XDG_RUNTIME_DIR
    SSH_AUTH_SOCK
    SSL_CERT_FILE
    SSL_CERT_DIR
    CURL_CA_BUNDLE
    REQUESTS_CA_BUNDLE
    NODE_EXTRA_CA_CERTS
    HTTP_PROXY
    HTTPS_PROXY
    ALL_PROXY
    NO_PROXY
    http_proxy
    https_proxy
    all_proxy
    no_proxy
  )

  @provider_env_passthrough %{
    "codex" => ~w(OPENAI_API_KEY OPENAI_BASE_URL),
    "claude" => ~w(ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL),
    "cursor" => ~w(CURSOR_API_KEY),
    "opencode" => ~w(
      OPENCODE_API_KEY
      OPENCODE_BASE_URL
      OPENAI_API_KEY
      OPENAI_BASE_URL
      ANTHROPIC_API_KEY
      ANTHROPIC_AUTH_TOKEN
      ANTHROPIC_BASE_URL
      GEMINI_API_KEY
      GOOGLE_GENERATIVE_AI_API_KEY
      GROQ_API_KEY
      MISTRAL_API_KEY
      OPENROUTER_API_KEY
      XAI_API_KEY
      AWS_ACCESS_KEY_ID
      AWS_SECRET_ACCESS_KEY
      AWS_SESSION_TOKEN
      AWS_REGION
    )
  }

  @max_env_passthrough 64
  @env_name ~r/\A[A-Za-z_][A-Za-z0-9_]*\z/

  @spec bootstrap!() :: :ok
  def bootstrap! do
    System.put_env("PATH", merge_path([login_path(), System.get_env("PATH") | extra_dirs()]))
    :ok
  end

  @spec extra_dirs() :: [String.t()]
  def extra_dirs do
    home = System.user_home()

    [
      "/opt/homebrew/bin",
      "/opt/homebrew/sbin",
      "/usr/local/bin",
      "/usr/bin",
      "/bin",
      home && Path.join(home, ".local/bin"),
      home && Path.join(home, ".cursor/bin"),
      home && Path.join(home, "Applications/Cursor.app/Contents/Resources/app/bin"),
      "/Applications/Cursor.app/Contents/Resources/app/bin",
      home && Path.join(home, ".cargo/bin"),
      home && Path.join(home, ".npm-global/bin"),
      home && Path.join(home, ".volta/bin"),
      home && Path.join(home, ".asdf/shims"),
      home && Path.join(home, ".bun/bin"),
      home && Path.join(home, "Library/pnpm")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&File.dir?/1)
  end

  @spec merge_path([String.t() | nil]) :: String.t()
  def merge_path(parts) when is_list(parts) do
    parts
    |> Enum.flat_map(&split_path/1)
    |> Enum.uniq()
    |> Enum.join(":")
  end

  @doc """
  Selects the inherited values that a local provider CLI may receive.

  The allowlist covers executable/config discovery, temporary files, locale,
  terminal behavior, local credential-agent sockets, and TLS/proxy settings.
  Provider credentials are intentionally absent.
  """
  @spec provider_environment(%{optional(String.t()) => String.t()}) :: %{
          optional(String.t()) => String.t()
        }
  def provider_environment(source \\ System.get_env()) when is_map(source) do
    Map.take(source, @provider_environment_variables)
  end

  @doc """
  Returns the fixed environment pass-through policy for a first-party provider.

  These names are deliberately adapter-specific. There is no global provider
  credential inheritance policy.
  """
  @spec provider_env_passthrough(String.t()) :: [String.t()]
  def provider_env_passthrough(provider) when is_binary(provider) do
    Map.get(@provider_env_passthrough, provider, [])
  end

  @spec validate_env_passthrough(term()) ::
          {:ok, [String.t()]} | {:error, :invalid_env_passthrough}
  def validate_env_passthrough(names)
      when is_list(names) and length(names) <= @max_env_passthrough do
    if Enum.all?(names, &(is_binary(&1) and Regex.match?(@env_name, &1))) do
      {:ok, Enum.uniq(names)}
    else
      {:error, :invalid_env_passthrough}
    end
  end

  def validate_env_passthrough(_names), do: {:error, :invalid_env_passthrough}

  @doc """
  Builds an Erlang `Port` environment that removes non-allowlisted inheritance.

  `Port.open/2` otherwise retains parent variables omitted from its `:env`
  option, so every inherited key outside the allowlist must be explicitly
  unset with `false`.
  """
  @spec provider_port_environment(
          %{optional(String.t()) => String.t()},
          %{optional(String.t()) => String.t()}
        ) :: [{charlist(), charlist() | false}]
  def provider_port_environment(explicit, source \\ System.get_env())
      when is_map(explicit) and is_map(source) do
    child =
      source
      |> provider_environment()
      |> Map.merge(explicit)

    port_environment(child, source)
  end

  @doc """
  Builds a provider environment with an explicit, validated pass-through list.

  Explicit values override inherited values. Every parent variable absent from
  the base or per-command allowlists is explicitly unset.
  """
  @spec provider_port_environment(
          %{optional(String.t()) => String.t()},
          [String.t()],
          %{optional(String.t()) => String.t()}
        ) ::
          {:ok, [{charlist(), charlist() | false}]}
          | {:error, :invalid_env_passthrough}
  def provider_port_environment(explicit, passthrough, source)
      when is_map(explicit) and is_map(source) do
    with {:ok, passthrough} <- validate_env_passthrough(passthrough) do
      child =
        source
        |> provider_environment()
        |> Map.merge(Map.take(source, passthrough))
        |> Map.merge(explicit)

      {:ok, port_environment(child, source)}
    end
  end

  defp port_environment(child, source) do
    source
    |> Map.keys()
    |> Kernel.++(Map.keys(child))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn key ->
      value =
        case Map.fetch(child, key) do
          {:ok, allowed} -> String.to_charlist(allowed)
          :error -> false
        end

      {String.to_charlist(key), value}
    end)
  end

  defp split_path(nil), do: []
  defp split_path(""), do: []

  defp split_path(part) when is_binary(part) do
    part
    |> String.split(":")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp login_path do
    if Application.get_env(:agent_desk, :inherit_login_path, false) do
      read_login_path()
    else
      ""
    end
  end

  defp read_login_path do
    shell = System.get_env("SHELL") || "/bin/zsh"

    if File.regular?(shell) do
      task =
        Task.async(fn ->
          System.cmd(shell, ["-l", "-c", "printf %s \"$PATH\""], stderr_to_stdout: true)
        end)

      case Task.yield(task, 2_000) || Task.shutdown(task, :brutal_kill) do
        {:ok, {path, 0}} -> path
        _ -> ""
      end
    else
      ""
    end
  end
end
