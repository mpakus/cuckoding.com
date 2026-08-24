defmodule AgentDesk.Search do
  @moduledoc """
  Search and memory facade. Never lets XERJ failure block coordination.
  """

  alias AgentDesk.Projects.Project
  alias AgentDesk.Scope
  alias AgentDesk.Search.Disabled
  alias AgentDesk.Search.Indexer
  alias AgentDesk.Search.Namespaces
  alias AgentDesk.Search.Projection
  alias AgentDesk.Search.Xerj
  alias AgentDesk.Search.Xerj.Discovery

  @spec adapter() :: module()
  def adapter do
    case Keyword.get(config(), :adapter, :auto) do
      :projection -> Projection
      :xerj -> Xerj
      :disabled -> Disabled
      :auto -> auto_adapter()
    end
  end

  @spec health(Project.t()) :: :ok | {:error, term()}
  def health(%Project{} = project), do: safe(fn -> adapter().health(%{id: project.id}) end)

  @spec search(Scope.t(), map()) :: {:ok, [map()]} | {:error, term()}
  def search(%Scope{project: project}, query) do
    ctx = %{id: project.id, canonical_path: project.canonical_path}
    safe(fn -> adapter().search(ctx, query) end)
  end

  @spec remember(Scope.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def remember(%Scope{} = scope, namespace, memory) do
    if Namespaces.allow?(scope, namespace) do
      payload = Map.put(memory, :project_id, scope.project.id)
      safe(fn -> adapter().remember(namespace, payload) end)
    else
      {:error, :forbidden}
    end
  end

  @spec recall(Scope.t(), String.t(), map()) :: {:ok, [map()]} | {:error, term()}
  def recall(%Scope{} = scope, namespace, query) do
    if Namespaces.allow?(scope, namespace) do
      safe(fn -> adapter().recall(namespace, query) end)
    else
      {:error, :forbidden}
    end
  end

  @spec forget(Scope.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def forget(%Scope{} = scope, namespace, id) do
    if Namespaces.allow?(scope, namespace) do
      safe(fn -> adapter().forget(namespace, id) end)
    else
      {:error, :forbidden}
    end
  end

  @spec rebuild(Project.t()) :: :ok | {:error, term()}
  def rebuild(%Project{} = project), do: safe(fn -> Indexer.rebuild(project) end)

  @spec status(Project.t()) :: map()
  def status(%Project{} = project) do
    state = Indexer.status(project.id)
    health = health(project)

    %{
      adapter: adapter() |> Module.split() |> List.last(),
      health: health,
      status: (state && state.status) || default_status(health),
      last_indexed_at: state && state.last_indexed_at,
      error: state && state.error
    }
  end

  defp auto_adapter do
    cond do
      not feature_on?() -> Disabled
      is_nil(Discovery.executable()) -> Disabled
      true -> Xerj
    end
  end

  @spec feature_on?() :: boolean()
  def feature_on? do
    Application.get_env(:agent_desk, :features, [])[:xerj] == true
  end

  @spec put_xerj(boolean()) :: :ok
  def put_xerj(enabled) when is_boolean(enabled) do
    features = Application.get_env(:agent_desk, :features, [])
    Application.put_env(:agent_desk, :features, Keyword.put(features, :xerj, enabled))
    :ok
  end

  defp config, do: Application.get_env(:agent_desk, :search, [])

  defp default_status(:ok), do: "ready"
  defp default_status(_), do: "unavailable"

  defp safe(fun) do
    fun.()
  rescue
    _ -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
