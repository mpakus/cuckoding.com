defmodule AgentDesk.Providers.Discovery do
  @moduledoc """
  Probes installed provider executables and reports versions.
  """

  alias AgentDesk.Providers

  @spec probe(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def probe(key, opts \\ []) when is_binary(key) do
    case Providers.adapter(key) do
      {:ok, adapter} -> adapter.probe(opts)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec probe_all(keyword()) :: [map()]
  def probe_all(opts \\ []) do
    Enum.map(Providers.keys(), fn key ->
      case probe(key, opts) do
        {:ok, result} -> Map.put(result, :available, true)
        {:error, reason} -> %{key: key, available: false, error: reason}
      end
    end)
  end

  @spec find_executable(String.t(), keyword()) :: {:ok, String.t()} | {:error, :not_found}
  def find_executable(name, opts \\ []) do
    override = Keyword.get(opts, :executable) || configured_executable(name)

    [override, name]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.find_value({:error, :not_found}, &locate/1)
  end

  defp locate(candidate) do
    cond do
      File.regular?(candidate) -> {:ok, candidate}
      found = System.find_executable(candidate) -> {:ok, found}
      true -> nil
    end
  end

  @spec version(String.t(), [String.t()]) :: {:ok, String.t()} | {:error, term()}
  def version(executable, args \\ ["--version"]) when is_binary(executable) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output |> String.trim() |> String.slice(0, 200)}
      {output, status} -> {:error, {:probe_failed, status, String.slice(output, 0, 200)}}
    end
  end

  defp configured_executable(name) do
    :agent_desk
    |> Application.get_env(:providers, [])
    |> Keyword.get(:executables, %{})
    |> Map.get(name)
  end
end
