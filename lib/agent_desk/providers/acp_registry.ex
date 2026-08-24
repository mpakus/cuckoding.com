defmodule AgentDesk.Providers.AcpRegistry do
  @moduledoc """
  Official ACP Registry catalog plus local install records.

  Fetches `registry.json` when configured to, otherwise uses the bundled snapshot.
  Registry ids stay strings. Installs persist command specs as executable + argv,
  never a shell string. Provider secrets are not stored.
  """

  alias AgentDesk.Ids
  alias AgentDesk.Providers.AcpInstall
  alias AgentDesk.Providers.Discovery
  alias AgentDesk.Repo

  @cdn "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json"
  @snapshot Path.expand("priv/acp/registry.snapshot.json", File.cwd!())
  @filters ~w(all installed not_installed)
  @native %{
    "codex-acp" => {"codex", "codex"},
    "claude-acp" => {"claude", "claude"},
    "cursor" => {"cursor", "agent"},
    "opencode" => {"opencode", "opencode"}
  }

  @spec catalog() :: {:ok, [map()]} | {:error, term()}
  def catalog do
    case load_raw() do
      {:ok, agents} ->
        installs = installs_by_id()
        {:ok, Enum.map(agents, &annotate(&1, installs))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec list(String.t(), String.t()) :: [map()]
  def list(query, filter) when is_binary(query) and is_binary(filter) do
    q = query |> String.trim() |> String.downcase()
    selected = if filter in @filters, do: filter, else: "all"

    case catalog() do
      {:ok, agents} ->
        agents
        |> Enum.filter(fn agent ->
          matches_query?(agent, q) and matches_filter?(agent, selected)
        end)

      {:error, _} ->
        []
    end
  end

  @spec refresh() :: {:ok, [map()]} | {:error, term()}
  def refresh do
    :persistent_term.erase({__MODULE__, :catalog})
    catalog()
  end

  @spec install(String.t()) :: {:ok, AcpInstall.t()} | {:error, term()}
  def install(registry_id) when is_binary(registry_id) do
    with {:ok, agent} <- fetch_agent(registry_id),
         {:ok, command} <- command_spec(agent) do
      persist(agent, command, "installed")
    end
  end

  @spec remove(String.t()) :: {:ok, AcpInstall.t()} | {:error, term()}
  def remove(registry_id) when is_binary(registry_id) do
    with {:ok, agent} <- fetch_agent(registry_id) do
      persist(agent, command_or_empty(agent), "removed")
    end
  end

  @spec session_attrs(String.t()) :: {:ok, map()} | {:error, term()}
  def session_attrs(registry_id) when is_binary(registry_id) do
    with {:ok, agent} <- fetch_agent(registry_id),
         true <- installed?(agent) || {:error, :not_installed},
         {:ok, command} <- command_spec(agent) do
      {:ok,
       %{
         provider: command.provider_key,
         display_name: agent["name"],
         settings: %{
           "tab_open" => true,
           "acp_registry_id" => agent["id"],
           "acp_executable" => command.executable,
           "acp_args" => command.args
         }
       }}
    end
  end

  defp fetch_agent(registry_id) do
    case catalog() do
      {:ok, agents} ->
        case Enum.find(agents, &(&1["id"] == registry_id)) do
          nil -> {:error, :unknown_agent}
          agent -> {:ok, agent}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp installs_by_id do
    AcpInstall
    |> Repo.all()
    |> Map.new(&{&1.registry_id, &1})
  end

  defp annotate(raw, installs) do
    id = to_string(raw["id"] || "")
    {provider_key, binary} = Map.get(@native, id, {"acp", nil})
    native? = native_available?(binary)
    install = Map.get(installs, id)
    dist = distribution_kind(raw["distribution"] || %{})

    %{
      "id" => id,
      "name" => to_string(raw["name"] || id),
      "version" => to_string(raw["version"] || ""),
      "description" => to_string(raw["description"] || ""),
      "repository" => raw["repository"],
      "website" => raw["website"],
      "license" => to_string(raw["license"] || ""),
      "distribution" => dist,
      "provider_key" => provider_key,
      "installed" => installed_status(install, native?),
      "native" => native?,
      "icon" => raw["icon"]
    }
  end

  defp installed_status(%AcpInstall{status: "installed"}, _), do: true
  defp installed_status(%AcpInstall{status: "removed"}, _), do: false
  defp installed_status(_, true), do: true
  defp installed_status(_, _), do: false

  defp installed?(agent), do: agent["installed"] == true

  defp native_available?(nil), do: false

  defp native_available?(binary) do
    match?({:ok, _}, Discovery.find_executable(binary))
  end

  defp matches_query?(_agent, ""), do: true

  defp matches_query?(agent, q) do
    [agent["id"], agent["name"], agent["description"]]
    |> Enum.filter(&is_binary/1)
    |> Enum.any?(&String.contains?(String.downcase(&1), q))
  end

  defp matches_filter?(agent, "installed"), do: agent["installed"]
  defp matches_filter?(agent, "not_installed"), do: not agent["installed"]
  defp matches_filter?(_agent, _), do: true

  defp persist(agent, command, status) do
    attrs = %{
      id: Ids.generate(),
      registry_id: agent["id"],
      name: agent["name"],
      version: agent["version"],
      status: status,
      provider_key: command.provider_key,
      executable: command.executable,
      args: command.args,
      distribution: %{"kind" => agent["distribution"]}
    }

    case Repo.get_by(AcpInstall, registry_id: agent["id"]) do
      nil ->
        %AcpInstall{}
        |> AcpInstall.changeset(attrs)
        |> Repo.insert()

      %AcpInstall{} = row ->
        row
        |> AcpInstall.changeset(Map.delete(attrs, :id))
        |> Repo.update()
    end
  end

  defp command_or_empty(agent) do
    case command_spec(agent) do
      {:ok, command} -> command
      {:error, _} -> %{provider_key: agent["provider_key"], executable: nil, args: []}
    end
  end

  defp command_spec(agent) do
    with {:ok, raw} <- raw_agent(agent["id"]),
         {:ok, executable, args} <- distribution_command(raw["distribution"] || %{}) do
      {:ok,
       %{
         provider_key: agent["provider_key"] || "acp",
         executable: executable,
         args: args
       }}
    else
      {:error, :unsupported_distribution} ->
        native_command(agent)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp native_command(%{"provider_key" => key}) when key in ~w(codex claude cursor opencode) do
    binary =
      case key do
        "cursor" -> "agent"
        other -> other
      end

    args =
      case key do
        "codex" -> ["app-server"]
        "cursor" -> ["acp"]
        "opencode" -> ["acp"]
        _ -> []
      end

    {:ok, %{provider_key: key, executable: binary, args: args}}
  end

  defp native_command(_), do: {:error, :unsupported_distribution}

  defp distribution_command(%{"npx" => npx}) when is_map(npx) do
    package = to_string(npx["package"] || "")

    if package == "" or String.contains?(package, "\0") do
      {:error, :invalid_package}
    else
      {:ok, "npx", ["-y", package] ++ string_args(npx["args"])}
    end
  end

  defp distribution_command(%{"uvx" => uvx}) when is_map(uvx) do
    package = to_string(uvx["package"] || "")

    if package == "" or String.contains?(package, "\0") do
      {:error, :invalid_package}
    else
      {:ok, "uvx", [package] ++ string_args(uvx["args"])}
    end
  end

  defp distribution_command(_), do: {:error, :unsupported_distribution}

  defp string_args(list) when is_list(list) do
    list
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.contains?(&1, "\0")))
    |> Enum.take(16)
  end

  defp string_args(_), do: []

  defp distribution_kind(%{"npx" => _}), do: "npx"
  defp distribution_kind(%{"uvx" => _}), do: "uvx"
  defp distribution_kind(%{"binary" => _}), do: "binary"
  defp distribution_kind(_), do: "unknown"

  defp raw_agent(id) do
    case load_raw() do
      {:ok, agents} ->
        case Enum.find(agents, &(to_string(&1["id"] || "") == id)) do
          nil -> {:error, :unknown_agent}
          agent -> {:ok, agent}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_raw do
    case :persistent_term.get({__MODULE__, :catalog}, :miss) do
      {:ok, agents} ->
        {:ok, agents}

      :miss ->
        result = fetch_raw()

        case result do
          {:ok, agents} -> :persistent_term.put({__MODULE__, :catalog}, {:ok, agents})
          _ -> :ok
        end

        result
    end
  end

  defp fetch_raw do
    case Keyword.get(config(), :source, :snapshot) do
      :cdn -> fetch_cdn()
      :snapshot -> read_snapshot()
      :fixture -> read_snapshot()
    end
  end

  defp fetch_cdn do
    url = Keyword.get(config(), :url, @cdn)

    case http_get(url) do
      {:ok, body} -> decode_agents(body)
      {:error, _} -> read_snapshot()
    end
  end

  defp read_snapshot do
    path = Keyword.get(config(), :snapshot, snapshot_path())

    case File.read(path) do
      {:ok, body} -> decode_agents(body)
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_agents(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"agents" => agents}} when is_list(agents) ->
        {:ok, Enum.filter(agents, &is_map/1)}

      {:ok, _} ->
        {:error, :invalid_registry}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp http_get(url) when is_binary(url) do
    request = {String.to_charlist(url), []}

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3
    ]

    http_opts = [timeout: 8_000, connect_timeout: 5_000, ssl: ssl]

    case :httpc.request(:get, request, http_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} when is_binary(body) -> {:ok, body}
      {:ok, {{_, status, _}, _, _}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp snapshot_path do
    Application.app_dir(:agent_desk, "priv/acp/registry.snapshot.json")
  rescue
    _ -> @snapshot
  end

  defp config, do: Application.get_env(:agent_desk, :acp_registry, [])
end
