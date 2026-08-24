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
    "fake" => AgentDesk.Providers.Fake,
    "sdk" => AgentDesk.Providers.SDK,
    "remote" => AgentDesk.Providers.Remote,
    "acp" => AgentDesk.Providers.AcpGeneric
  }

  @spec keys() :: [String.t()]
  def keys, do: @adapters |> Map.keys() |> Enum.sort()

  @spec ui_keys() :: [String.t()]
  def ui_keys, do: Enum.reject(keys(), &(&1 in ["codex-exec", "acp", "fake"]))

  @spec ui_label(String.t()) :: String.t()
  def ui_label("codex"), do: "Codex"
  def ui_label("claude"), do: "Claude"
  def ui_label("cursor"), do: "Cursor"
  def ui_label("opencode"), do: "OpenCode"
  def ui_label("sdk"), do: "SDK"
  def ui_label("remote"), do: "Remote"
  def ui_label(key) when is_binary(key), do: key

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

    with {:ok, session} <-
           Agents.create_session(scope, AgentDesk.Roles.attach(scope.project, attrs)),
         {:ok, _worktree} <- AgentDesk.Worktrees.ensure_for_session(scope.project, session) do
      _ = maybe_allocate_port(scope, session)
      _ = AgentDesk.Isolation.write_templates!(session)

      with :ok <- AgentDesk.Containers.start(scope.project, session),
           {:ok, _pid} <- start_worker(session, opts) do
        {:ok, session}
      end
    end
  end

  @spec resume_session(Session.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def resume_session(%Session{} = session, opts \\ []) do
    _ = AgentDesk.Isolation.write_templates!(session)
    start_worker(session, opts)
  end

  @spec start_worker(Session.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_worker(%Session{} = session, opts \\ []) do
    if AgentDesk.Circuit.allow?("provider:" <> session.provider) do
      spec = {SessionWorker, [session: session, adapter_opts: opts]}

      case DynamicSupervisor.start_child(AgentDesk.ProviderProcessSupervisor, spec) do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :circuit_open}
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

  @spec start_error_message(term()) :: String.t()
  def start_error_message(reason) do
    cond do
      not_found?(reason) ->
        "Could not find that provider CLI on PATH. Install Codex/Claude/Cursor/OpenCode, then try again."

      git_missing?(reason) ->
        "Git was not found. Install the Xcode command-line tools, then try again."

      reason == :circuit_open ->
        "That provider is paused after repeated failures."

      match?(%Ecto.Changeset{}, reason) ->
        "Could not save that session."

      worktree_error?(reason) ->
        "Could not create an isolated worktree. #{truncate(git_output(reason))}"

      true ->
        "Could not start that provider session."
    end
  end

  defp maybe_allocate_port(scope, session) do
    AgentDesk.Isolation.allocate_port(AgentDesk.Scope.for_agent(scope.project, session))
  end

  defp not_found?(reason) do
    reason in [:not_found, :enoent] or
      match?({:error, :not_found}, reason) or
      match?({:spawn_failed, _}, reason) or
      nested?(reason, :enoent) or
      nested?(reason, :not_found)
  end

  defp git_missing?(reason), do: reason == :git_not_found or nested?(reason, :git_not_found)

  defp worktree_error?({code, output}) when is_integer(code) and is_binary(output), do: true
  defp worktree_error?(_), do: false

  defp git_output({_code, output}), do: output

  defp nested?(tuple, atom) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.any?(&(&1 == atom or (is_tuple(&1) and nested?(&1, atom))))
  end

  defp nested?(%{original: original}, atom), do: original == atom
  defp nested?(_, _), do: false

  defp truncate(text) when is_binary(text) do
    text
    |> String.split("\n", parts: 2)
    |> List.first()
    |> String.slice(0, 180)
  end
end
