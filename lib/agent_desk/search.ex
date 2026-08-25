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
      payload = Map.put(query, :project_id, scope.project.id)
      safe(fn -> adapter().recall(namespace, payload) end)
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
    adapter_name = adapter() |> Module.split() |> List.last()
    {status, error} = present_status(adapter_name, health, state)

    %{
      adapter: adapter_name,
      health: health,
      status: status,
      last_indexed_at: state && state.last_indexed_at,
      error: error
    }
  end

  defp auto_adapter do
    if feature_on?() and not is_nil(Discovery.executable()) do
      Xerj
    else
      Projection
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

  defp present_status("Disabled", _health, _state), do: {"unavailable", nil}

  defp present_status(_adapter, {:error, :unavailable}, _state), do: {"unavailable", nil}

  defp present_status(_adapter, _health, %{status: "error", error: error}) do
    if unavailable_error?(error) do
      {"unavailable", nil}
    else
      {"error", present_error(error) || "Indexing failed. Rebuild the index."}
    end
  end

  defp present_status(_adapter, health, state) do
    {(state && state.status) || default_status(health), present_error(state && state.error)}
  end

  defp unavailable_error?(error) when error in [nil, "", ":unavailable", "unavailable"], do: true

  defp unavailable_error?(error) when is_binary(error),
    do: String.contains?(error, "unavailable")

  defp unavailable_error?(_), do: false

  defp present_error(error) when error in [nil, ""], do: nil
  defp present_error(error) when is_binary(error), do: error
  defp present_error(_), do: nil

  defp safe(fun) do
    fun.()
  rescue
    _ -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
