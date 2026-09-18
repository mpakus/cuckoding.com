defmodule Cuckoding.PluginConformance do
  @moduledoc "Reusable contract check for plugin implementations and stubs."

  alias Cuckoding.Plugins.Contracts
  alias Cuckoding.Plugins.Result

  def check(kind, implementation, context) do
    with {:ok, behaviour} <- Contracts.behaviour(kind),
         true <- declared?(implementation, behaviour),
         {:ok, operations} <- Contracts.operations(kind),
         results <- Enum.map(operations, &call(kind, implementation, &1, context)),
         [] <- Enum.reject(results, &match?({:ok, %Result{}}, &1)) do
      :ok
    else
      false -> {:error, :plugin_behaviour_not_declared}
      [_result | _rest] = failures -> {:error, {:plugin_conformance_failed, failures}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp call(kind, implementation, operation, context) do
    Contracts.call(kind, implementation, operation, %{"fixture" => "conformance"}, context)
  end

  defp declared?(implementation, behaviour) do
    implementation.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.member?(behaviour)
  end
end
