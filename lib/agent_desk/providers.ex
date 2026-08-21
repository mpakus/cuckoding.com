defmodule AgentDesk.Providers do
  @moduledoc """
  Provider adapter registry and session lifecycle facade.
  """

  alias AgentDesk.Agents
  alias AgentDesk.Agents.Session
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Scope

  @adapters %{
    "codex" => AgentDesk.Providers.Codex.AppServer,
    "codex-exec" => AgentDesk.Providers.Codex.Exec,
    "claude" => AgentDesk.Providers.Claude,
    "cursor" => AgentDesk.Providers.Cursor,
    "opencode" => AgentDesk.Providers.OpenCode,
    "fake" => AgentDesk.Providers.Fake
  }

  @spec keys() :: [String.t()]
  def keys, do: @adapters |> Map.keys() |> Enum.sort()

  @spec ui_keys() :: [String.t()]
  def ui_keys, do: Enum.reject(keys(), &(&1 in ["codex-exec"]))

  @spec adapter(String.t()) :: {:ok, module()} | {:error, :unknown_provider}
  def adapter(key) when is_binary(key) do
    case Map.fetch(@adapters, key) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_provider}
    end
  end

  @spec start_session(Scope.t(), map(), keyword()) :: {:ok, Session.t()} | {:error, term()}
  def start_session(%Scope{} = scope, attrs, opts \\ []) do
    attrs =
      attrs
      |> Map.put_new(:status, "queued")
      |> Map.put_new(:settings, %{"tab_open" => true})

    with {:ok, session} <- Agents.create_session(scope, attrs),
         {:ok, _pid} <- start_worker(session, opts) do
      {:ok, session}
    end
  end

  @spec resume_session(Session.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def resume_session(%Session{} = session, opts \\ []) do
    start_worker(session, opts)
  end

  @spec start_worker(Session.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_worker(%Session{} = session, opts \\ []) do
    spec = {SessionWorker, [session: session, adapter_opts: opts]}

    case DynamicSupervisor.start_child(AgentDesk.ProviderProcessSupervisor, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stop_worker(Ecto.UUID.t()) :: :ok
  def stop_worker(session_id) when is_binary(session_id) do
    case SessionWorker.fetch(session_id) do
      {:ok, pid} ->
        _ = DynamicSupervisor.terminate_child(AgentDesk.ProviderProcessSupervisor, pid)
        if Process.alive?(pid), do: GenServer.stop(pid, :shutdown, 2_000)
        :ok

      {:error, :not_started} ->
        :ok
    end
  end

  @spec stop_for_project(Ecto.UUID.t()) :: :ok
  def stop_for_project(project_id) when is_binary(project_id) do
    project_id
    |> Agents.list_sessions()
    |> Enum.each(&stop_worker(&1.id))

    :ok
  end
end
