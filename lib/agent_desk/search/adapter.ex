defmodule AgentDesk.Search.Adapter do
  @moduledoc """
  Boundary for optional XERJ search and namespaced memory.
  """

  @callback health(map()) :: :ok | {:error, term()}
  @callback index_project(map()) :: :ok | {:error, term()}
  @callback index_documents(map(), [map()]) :: :ok | {:error, term()}
  @callback search(map(), map()) :: {:ok, [map()]} | {:error, term()}
  @callback remember(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback recall(String.t(), map()) :: {:ok, [map()]} | {:error, term()}
  @callback forget(String.t(), String.t()) :: :ok | {:error, term()}
  @callback rebuild(map()) :: :ok | {:error, term()}
  @callback purge(map()) :: :ok | {:error, term()}
end
