defmodule AgentDesk.Providers.Probe do
  @moduledoc false

  alias AgentDesk.Providers.Discovery
  alias AgentDesk.Providers.Fixture

  @spec probe(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def probe(key, binary_name, opts) do
    if Fixture.enabled?(opts) do
      {:ok, %{key: key, executable: "fixture", version: "fixture", protocol: "fixture"}}
    else
      with {:ok, executable} <- Discovery.find_executable(binary_name, opts),
           {:ok, version} <- Discovery.version(executable) do
        {:ok, %{key: key, executable: executable, version: version}}
      end
    end
  end
end
