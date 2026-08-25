defmodule AgentDesk.Providers do
  @moduledoc """
  Provider adapter registry and session lifecycle facade.
  """

  alias AgentDesk.Agents
  alias AgentDesk.Agents.Session
  alias AgentDesk.Providers.Capabilities
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Discovery
  alias AgentDesk.Providers.ProjectSupervisor
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Repo
  alias AgentDesk.Scope
  alias AgentDesk.Storage
  alias AgentDesk.Worktrees

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

    with {:ok, preflight} <- preflight(scope.project, attrs, opts),
         attrs <- put_provider_version(attrs, preflight),
         {:ok, session} <-
           Agents.create_session(scope, AgentDesk.Roles.attach(scope.project, attrs)) do
      provision_session(scope, session, opts)
    end
  end

  @spec resume_session(Session.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def resume_session(%Session{} = session, opts \\ []) do
    :global.trans({{__MODULE__, :resume, session.id}, self()}, fn ->
      case SessionWorker.fetch(session.id) do
        {:ok, pid} -> {:ok, pid}
        {:error, :not_started} -> do_resume_session(session, opts)
      end
    end)
  end

  @spec start_worker(Session.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_worker(%Session{} = session, opts \\ []) do
    if AgentDesk.Circuit.allow?("provider:" <> session.provider) do
      spec = {SessionWorker, [session: session, adapter_opts: opts]}

      with {:ok, supervisor} <- ProjectSupervisor.fetch(session.project_id) do
        case DynamicSupervisor.start_child(supervisor, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, reason} -> {:error, reason}
        end
      end
    else
      {:error, :circuit_open}
    end
  end

  defp provision_session(scope, session, opts) do
    state = %{
      project: scope.project,
      scope: scope,
      session: session,
      worktree: nil,
      port_allocated?: false,
      templates_written?: false,
      compose_attempted?: false,
      external_process_started?: false,
      worker_started?: false
    }

    case run_start_steps(state, opts) do
      {:ok, provisioned} ->
        {:ok, provisioned.session}

      {:error, reason, partial} ->
        case compensate_start(partial) do
          :ok -> {:error, reason}
          {:error, cleanup} -> {:error, {:start_failed, reason, cleanup}}
        end
    end
  end

  defp do_resume_session(session, opts) do
    result =
      with {:ok, project} <- AgentDesk.Projects.get_project(session.project_id),
           {:ok, persisted} <- Agents.get_session(Scope.for_project(project), session.id),
           :ok <- Worktrees.validate_for_resume(project, persisted),
           {:ok, preflight} <- preflight(project, session_attrs(persisted), opts),
           :ok <- ensure_resume_supported(preflight.adapter, persisted),
           {:ok, starting} <- mark_starting(persisted),
           {:ok, _port} <- ensure_port(project, starting),
           {:ok, _dir} <- write_isolation_templates(starting),
           :ok <- AgentDesk.Containers.start(project, starting),
           {:ok, pid} <- start_worker(starting, opts) do
        {:ok, pid}
      end

    case result do
      {:ok, _pid} = ok ->
        ok

      {:error, reason} ->
        record_resume_failure(session, reason)
        {:error, reason}
    end
  end

  defp run_start_steps(state, opts) do
    with {:ok, state} <- start_step(state, :status),
         {:ok, state} <- start_step(state, :worktree),
         {:ok, state} <- start_step(state, :port),
         {:ok, state} <- start_step(state, :templates),
         {:ok, state} <- start_step(state, :compose),
         {:ok, state} <- start_step(state, {:worker, opts}) do
      {:ok, state}
    else
      {:error, reason, partial} -> {:error, reason, partial}
    end
  end

  defp start_step(state, :status) do
    case mark_starting(state.session) do
      {:ok, session} -> {:ok, %{state | session: session}}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp start_step(state, :worktree) do
    case Worktrees.ensure_for_session(state.project, state.session) do
      {:ok, worktree} -> {:ok, %{state | worktree: worktree}}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp start_step(state, :port) do
    case maybe_allocate_port(state.scope, state.session) do
      {:ok, _port} -> {:ok, %{state | port_allocated?: true}}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp start_step(state, :templates) do
    case write_isolation_templates(state.session) do
      {:ok, _dir} -> {:ok, %{state | templates_written?: true}}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp start_step(state, :compose) do
    attempted = %{
      state
      | compose_attempted?: AgentDesk.Containers.enabled?(state.session),
        external_process_started?:
          state.external_process_started? or AgentDesk.Containers.enabled?(state.session)
    }

    case AgentDesk.Containers.start(state.project, state.session) do
      :ok -> {:ok, attempted}
      {:error, reason} -> {:error, reason, attempted}
    end
  end

  defp start_step(state, {:worker, opts}) do
    attempted = %{state | external_process_started?: true}

    case start_worker(state.session, opts) do
      {:ok, _pid} -> {:ok, %{attempted | worker_started?: true}}
      {:error, reason} -> {:error, reason, attempted}
    end
  end

  defp preflight(project, attrs, opts) do
    with {:ok, provider} <- provider_from(attrs),
         {:ok, adapter} <- adapter(provider),
         :ok <- allow_provider(provider),
         {:ok, capabilities} <- validate_capabilities(adapter, provider),
         {:ok, command} <- preflight_command(adapter, project, attrs, opts),
         {:ok, probe} <- adapter.probe(opts) do
      {:ok, %{adapter: adapter, capabilities: capabilities, command: command, probe: probe}}
    end
  rescue
    error in [ArgumentError, ErlangError, File.Error] ->
      {:error, {:preflight_failed, Exception.message(error)}}
  end

  defp provider_from(attrs) do
    case Map.get(attrs, :provider) || Map.get(attrs, "provider") do
      provider when is_binary(provider) and provider != "" -> {:ok, provider}
      _ -> {:error, :unknown_provider}
    end
  end

  defp allow_provider(provider) do
    if AgentDesk.Circuit.allow?("provider:" <> provider), do: :ok, else: {:error, :circuit_open}
  end

  defp validate_capabilities(adapter, provider) do
    case adapter.capabilities() do
      %Capabilities{key: ^provider, internal_a2a: true, safe_boundary_delivery: true} = caps ->
        {:ok, caps}

      %Capabilities{} ->
        {:error, :incompatible_capabilities}

      _ ->
        {:error, :invalid_capabilities}
    end
  end

  defp preflight_command(adapter, project, attrs, opts) do
    session = %Session{
      id: "preflight",
      project_id: project.id,
      provider: Map.get(attrs, :provider) || Map.get(attrs, "provider"),
      display_name: Map.get(attrs, :display_name) || Map.get(attrs, "display_name"),
      settings: Map.get(attrs, :settings) || Map.get(attrs, "settings") || %{}
    }

    with {:ok, command} <-
           adapter.command_spec(session, Keyword.put(opts, :cwd, project.canonical_path)),
         :ok <- validate_command(command) do
      {:ok, command}
    end
  end

  defp validate_command(:attach), do: :ok

  defp validate_command(%CommandSpec{executable: executable, args: args, cwd: cwd})
       when is_binary(executable) and is_list(args) and is_binary(cwd) do
    with true <- Enum.all?(args, &is_binary/1),
         {:ok, _resolved} <- Discovery.find_executable(executable, executable: executable) do
      :ok
    else
      false -> {:error, :invalid_command_spec}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_command(_), do: {:error, :invalid_command_spec}

  defp put_provider_version(attrs, %{probe: probe}) do
    case Map.get(probe, :version) || Map.get(probe, "version") do
      version when is_binary(version) and version != "" ->
        Map.put_new(attrs, :provider_version, version)

      _ ->
        attrs
    end
  end

  defp session_attrs(session) do
    %{
      provider: session.provider,
      display_name: session.display_name,
      settings: session.settings
    }
  end

  defp write_isolation_templates(session) do
    {:ok, AgentDesk.Isolation.write_templates!(session)}
  rescue
    error in [ArgumentError, File.Error] ->
      {:error, {:isolation_failed, Exception.message(error)}}
  end

  defp compensate_start(state) do
    session = Repo.get(Session, state.session.id) || state.session

    errors =
      []
      |> cleanup_result(:stop_worker, stop_worker(session.id), [:not_started])
      |> cleanup_result(
        :revoke_capability,
        AgentDesk.Security.Capability.revoke(session)
      )
      |> cleanup_result(
        :expire_leases,
        AgentDesk.Resources.Manager.expire_session(session.id)
      )
      |> maybe_stop_compose(state, session)
      |> cleanup_result(:mcp_cleanup, AgentDesk.Providers.MCPInjection.cleanup(session))
      |> maybe_discard_worktree(state, session)

    if errors == [] do
      errors =
        []
        |> cleanup_result(:session_files, remove_session_dir(state.project, session))
        |> cleanup_result(:session_record, delete_session(session))

      if errors == [], do: :ok, else: retain_failed_start(session, errors)
    else
      retain_failed_start(session, errors)
    end
  end

  defp maybe_stop_compose(errors, %{compose_attempted?: true}, session) do
    cleanup_result(errors, :compose_teardown, AgentDesk.Containers.stop(session))
  end

  defp maybe_stop_compose(errors, _state, _session), do: errors

  defp maybe_discard_worktree(errors, %{worktree: nil}, _session), do: errors

  defp maybe_discard_worktree(errors, state, session) do
    cleanup_result(
      errors,
      :worktree_cleanup,
      Worktrees.discard_start_attempt(state.project, session, state.worktree,
        external_process_started?: state.external_process_started?
      )
    )
  end

  defp cleanup_result(errors, step, result, ignored \\ [])
  defp cleanup_result(errors, _step, :ok, _ignored), do: errors
  defp cleanup_result(errors, _step, {:ok, _value}, _ignored), do: errors

  defp cleanup_result(errors, step, {:error, reason}, ignored) do
    if reason in ignored, do: errors, else: [{step, reason} | errors]
  end

  defp cleanup_result(errors, step, other, _ignored), do: [{step, other} | errors]

  defp remove_session_dir(project, session) do
    case File.rm_rf(Storage.session_dir(project.id, session.id)) do
      {:ok, _paths} -> :ok
      {:error, reason, path} -> {:error, {:remove_failed, path, reason}}
    end
  end

  defp delete_session(session) do
    case Repo.get(Session, session.id) do
      nil -> :ok
      persisted -> Repo.delete(persisted)
    end
  end

  defp retain_failed_start(session, errors) do
    reason = cleanup_failure_text("start compensation incomplete", errors)

    case Agents.update_session(Repo.get(Session, session.id) || session, %{
           status: "failed",
           ended_at: AgentDesk.Clock.utc_now(),
           exit_reason: reason
         }) do
      {:ok, _} ->
        {:error, {:cleanup_incomplete, Enum.reverse(errors)}}

      {:error, persist_reason} ->
        {:error,
         {:cleanup_incomplete, Enum.reverse([{:persist_failure, persist_reason} | errors])}}
    end
  end

  defp record_resume_failure(session, reason) do
    persisted = Repo.get(Session, session.id) || session
    _ = AgentDesk.Security.Capability.revoke(persisted)
    _ = AgentDesk.Resources.Manager.expire_session(persisted.id)
    compose_result = AgentDesk.Containers.stop(persisted)
    _ = AgentDesk.Providers.MCPInjection.cleanup(persisted)

    cleanup_errors =
      []
      |> cleanup_result(:compose_teardown, compose_result)

    text =
      if cleanup_errors == [] do
        "resume failed: " <> inspect(reason, limit: 20, printable_limit: 500)
      else
        cleanup_failure_text("resume failed: #{inspect(reason)}", cleanup_errors)
      end

    _ =
      Agents.update_session(Repo.get(Session, session.id) || session, %{
        status: "failed",
        ended_at: AgentDesk.Clock.utc_now(),
        exit_reason: text
      })

    :ok
  end

  defp cleanup_failure_text(prefix, errors) do
    details =
      errors
      |> Enum.reverse()
      |> Enum.map_join(", ", fn {step, reason} ->
        "#{step}=#{inspect(reason, limit: 10, printable_limit: 300)}"
      end)

    String.slice(prefix <> ": " <> details, 0, 2_000)
  end

  defp mark_starting(session) do
    Agents.update_session(session, %{
      status: "starting",
      started_at: session.started_at || AgentDesk.Clock.utc_now(),
      ended_at: nil,
      exit_reason: nil,
      process_identity: %{}
    })
  end

  defp ensure_resume_supported(adapter, %Session{provider_session_id: id})
       when is_binary(id) and id != "" do
    if adapter.capabilities().resume, do: :ok, else: {:error, :resume_unsupported}
  end

  defp ensure_resume_supported(_adapter, _session), do: :ok

  defp ensure_port(project, session) do
    case AgentDesk.Isolation.assigned_port(session) do
      nil -> maybe_allocate_port(Scope.for_project(project), session)
      port -> {:ok, port}
    end
  end

  @spec stop_worker(Ecto.UUID.t()) :: :ok | {:error, :not_started | term()}
  def stop_worker(session_id) when is_binary(session_id) do
    SessionWorker.terminate_session(session_id)
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

      reason == :not_started ->
        "That session is not running. Use Resume, then send the prompt."

      reason == :handshake_timeout or handshake_timeout?(reason) ->
        "The provider did not finish starting. Use Resume, then send the prompt."

      reason == :circuit_open ->
        "That provider is paused after repeated failures."

      reason == :unknown_provider ->
        "That provider is not supported."

      empty_repository?(reason) ->
        "Could not create an isolated worktree from this empty Git repository."

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

  defp handshake_timeout?(reason) do
    reason == "handshake_timeout" or nested?(reason, :handshake_timeout)
  end

  defp empty_repository?(reason) do
    reason == :empty_repository or nested?(reason, :empty_repository) or
      empty_head_output?(reason)
  end

  defp empty_head_output?({_code, output}) when is_binary(output) do
    String.contains?(output, "ambiguous argument 'HEAD'") or
      String.contains?(output, "unknown revision") or
      String.contains?(output, "does not have any commits")
  end

  defp empty_head_output?(_), do: false

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
