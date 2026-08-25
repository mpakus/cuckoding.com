defmodule AgentDesk.Providers.SessionWorker do
  @moduledoc """
  One OS process and decode state per provider session.
  """

  use GenServer, restart: :temporary

  alias AgentDesk.A2A
  alias AgentDesk.A2A.MessageRouter
  alias AgentDesk.Activity
  alias AgentDesk.Agents
  alias AgentDesk.Clock
  alias AgentDesk.Paths
  alias AgentDesk.Projects
  alias AgentDesk.Providers
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Event
  alias AgentDesk.Providers.Framer
  alias AgentDesk.Providers.MCPInjection
  alias AgentDesk.Providers.Process, as: ProviderProcess
  alias AgentDesk.Providers.Transcript
  alias AgentDesk.Scope
  alias AgentDesk.Telemetry

  defstruct [
    :session,
    :project,
    :adapter,
    :decode,
    :port,
    :framer,
    :status,
    :mcp_path,
    :token,
    :stderr_path,
    :termination_from,
    :termination_timer,
    buffer: [],
    flush_ref: nil,
    stderr_offset: 0,
    handshake: :awaiting_ready,
    pending_approval: nil,
    pending_prompts: [],
    message_draft: "",
    termination: :restart,
    cleanup_done: false,
    cleanup_errors: []
  ]

  @flush_ms 50
  @default_handshake_ms 60_000
  @stderr_poll_ms 100
  @interrupt_grace_ms 250
  @terminate_grace_ms 500
  @visible_cap 200
  @max_fs_bytes 1_000_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)
    GenServer.start_link(__MODULE__, opts, name: via(session.id))
  end

  @spec via(Ecto.UUID.t()) :: {:via, module(), {module(), Ecto.UUID.t()}}
  def via(session_id), do: {:via, Registry, {AgentDesk.SessionRegistry, session_id}}

  @spec fetch(Ecto.UUID.t()) :: {:ok, pid()} | {:error, :not_started}
  def fetch(session_id) do
    case Registry.lookup(AgentDesk.SessionRegistry, session_id) do
      [{pid, _}] when is_pid(pid) ->
        if Process.alive?(pid), do: {:ok, pid}, else: {:error, :not_started}

      [] ->
        {:error, :not_started}
    end
  end

  @spec prompt(Ecto.UUID.t(), String.t(), [map()]) :: :ok | {:error, term()}
  def prompt(session_id, text, attachments \\ []) when is_list(attachments) do
    call(session_id, {:prompt, text, attachments})
  end

  @spec interrupt(Ecto.UUID.t()) :: :ok | {:error, term()}
  def interrupt(session_id), do: call(session_id, :interrupt)

  @spec approve(Ecto.UUID.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def approve(session_id, request_id, decision),
    do: call(session_id, {:approve, request_id, decision})

  @spec terminate_session(Ecto.UUID.t()) :: :ok | {:error, term()}
  def terminate_session(session_id), do: call(session_id, :terminate)

  defp call(session_id, message) do
    case fetch(session_id) do
      {:ok, pid} ->
        try do
          GenServer.call(pid, message, 10_000)
        catch
          :exit, _reason -> {:error, :not_started}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    session = Keyword.fetch!(opts, :session)

    with {:ok, project} <- Projects.get_project(session.project_id),
         {:ok, adapter} <- Providers.adapter(session.provider),
         adapter_opts <-
           Keyword.get(opts, :adapter_opts, []) ++
             [cwd: AgentDesk.Worktrees.working_copy_path(project, session)],
         decode <- adapter.init_decode(),
         {:ok, state} <- bootstrap_process(session, project, adapter, adapter_opts, decode) do
      Process.send_after(self(), :handshake_timeout, handshake_ms())
      schedule_stderr_poll(state)
      Telemetry.provider_started(state.session.id, state.session.provider)
      {:ok, state, {:continue, :handshake}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp bootstrap_process(session, project, adapter, adapter_opts, decode) do
    with {:ok, token, issued_session} <- AgentDesk.Security.Capability.issue(session),
         {:ok, mcp_path} <- write_mcp(issued_session, token) do
      case spawn_or_attach(adapter, issued_session, adapter_opts, token) do
        {:ok, port, started_session, stderr_path} ->
          {:ok,
           %__MODULE__{
             session: started_session,
             project: project,
             adapter: adapter,
             decode: decode,
             port: port,
             framer: Framer.new(),
             status: "starting",
             mcp_path: mcp_path,
             token: token,
             stderr_path: stderr_path
           }}

        {:error, reason} ->
          cleanup_bootstrap(issued_session)
          {:error, reason}
      end
    end
  end

  defp write_mcp(session, token) do
    {:ok, MCPInjection.write!(session, token)}
  rescue
    error in [ArgumentError, File.Error] ->
      cleanup_bootstrap(session)
      {:error, {:mcp_injection_failed, Exception.message(error)}}
  end

  defp cleanup_bootstrap(session) do
    _ = MCPInjection.cleanup(session)
    _ = AgentDesk.Security.Capability.revoke(session)
    :ok
  end

  @impl true
  def handle_continue(:handshake, %{port: nil} = state) do
    event =
      Event.new(
        :session_ready,
        %{"provider_session_id" => "attach-" <> state.session.id},
        state.session.provider
      )

    {:noreply, apply_event(state, event)}
  end

  def handle_continue(:handshake, state) do
    previous = state.decode
    state = send_action(state, :initialize)

    state =
      if state.decode != previous do
        state
      else
        finish_immediate_handshake(state)
      end

    {:noreply, persist_status(state, "starting")}
  end

  @impl true
  def handle_call({:prompt, text}, from, state), do: handle_call({:prompt, text, []}, from, state)

  def handle_call({:prompt, text, attachments}, _from, %{handshake: :awaiting_ready} = state)
      when is_list(attachments) do
    {:reply, :ok, %{state | pending_prompts: state.pending_prompts ++ [{text, attachments}]}}
  end

  def handle_call({:prompt, _text, _attachments}, _from, %{status: status} = state)
      when status in ["failed", "terminated"] do
    {:reply, {:error, :not_started}, state}
  end

  def handle_call({:prompt, text, attachments}, _from, state) when is_list(attachments) do
    {:reply, :ok, deliver_prompt(state, text, attachments)}
  end

  def handle_call(_message, _from, %{termination: :terminate} = state) do
    {:reply, {:error, :not_started}, state}
  end

  def handle_call(:interrupt, _from, state) do
    {:reply, :ok, persist_status(send_action(state, :interrupt), "interrupted")}
  end

  def handle_call({:approve, request_id, decision}, _from, state) do
    {:reply, :ok, send_action(%{state | pending_approval: nil}, {:approve, request_id, decision})}
  end

  def handle_call(:terminate, from, %{port: nil} = state) do
    state = %{state | termination: :terminate, termination_from: from}
    {state, reply} = finish_termination(state, [])
    {:stop, :normal, reply, state}
  end

  def handle_call(:terminate, from, state) do
    state =
      state
      |> Map.put(:termination, :terminate)
      |> Map.put(:termination_from, from)
      |> send_action(:interrupt)
      |> persist_status("terminating")

    timer = Process.send_after(self(), :interrupt_grace_elapsed, interrupt_grace_ms())
    {:noreply, %{state | termination_timer: timer}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    case Framer.push(state.framer, IO.iodata_to_binary(data)) do
      {:ok, lines, framer} ->
        dropped = framer.dropped
        state = %{state | framer: %{framer | dropped: 0}}

        state =
          if dropped > 0 do
            emit(
              state,
              [
                Event.new(
                  :stderr,
                  %{
                    "reason" => "line_too_large",
                    "text" => "Skipped #{dropped} oversized provider frame(s)."
                  },
                  state.session.provider
                )
              ]
            )
          else
            state
          end

        {:noreply, Enum.reduce(lines, state, &decode_line/2)}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    state = drain_stderr(state)

    if state.termination == :terminate do
      {state, reply} = finish_termination(state, [])
      reply_termination(state, reply)
      {:stop, :normal, state}
    else
      state = state |> Map.put(:termination, :provider_exit) |> handle_exit(status) |> flush()
      {:stop, :normal, state}
    end
  end

  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    Process.send_after(self(), {:port_exit_without_status, port, reason}, 0)
    {:noreply, state}
  end

  def handle_info({port, :closed}, %{port: port} = state) do
    Process.send_after(self(), {:port_exit_without_status, port, :closed}, 0)
    {:noreply, state}
  end

  def handle_info({:port_exit_without_status, port, reason}, %{port: port} = state) do
    state = drain_stderr(state)

    if state.termination == :terminate do
      {state, reply} = finish_termination(state, [])
      reply_termination(state, reply)
      {:stop, :normal, state}
    else
      state =
        state
        |> Map.put(:termination, :provider_exit)
        |> handle_port_exit(reason)
        |> flush()

      {:stop, :normal, state}
    end
  end

  def handle_info(:flush, state) do
    {:noreply, flush(%{state | flush_ref: nil})}
  end

  def handle_info(:stderr_poll, state) do
    state = drain_stderr(state)
    schedule_stderr_poll(state)
    {:noreply, state}
  end

  def handle_info(:interrupt_grace_elapsed, %{termination: :terminate} = state) do
    if ProviderProcess.alive?(state.port) do
      errors =
        signal_error([], :term, ProviderProcess.signal_group(process_group_id(state), :term))

      timer = Process.send_after(self(), :terminate_grace_elapsed, terminate_grace_ms())
      {:noreply, %{state | termination_timer: timer, cleanup_errors: errors}}
    else
      {state, reply} = finish_termination(state, [])
      reply_termination(state, reply)
      {:stop, :normal, state}
    end
  end

  def handle_info(:terminate_grace_elapsed, %{termination: :terminate} = state) do
    prior_errors = Map.get(state, :cleanup_errors, [])

    errors =
      if ProviderProcess.alive?(state.port) do
        signal_error(
          prior_errors,
          :kill,
          ProviderProcess.signal_group(process_group_id(state), :kill)
        )
      else
        prior_errors
      end

    ProviderProcess.close(state.port)
    {state, reply} = finish_termination(state, errors)
    reply_termination(state, reply)
    {:stop, :normal, state}
  end

  def handle_info(message, %{termination: :terminate} = state)
      when message in [:interrupt_grace_elapsed, :terminate_grace_elapsed] do
    {:noreply, state}
  end

  def handle_info(:handshake_timeout, %{handshake: :awaiting_ready} = state) do
    event = Event.new(:provider_error, %{"reason" => "handshake_timeout"}, state.session.provider)
    state = persist_terminal(emit(state, [event]), "failed", "provider handshake timed out")
    {:stop, :normal, flush(state)}
  end

  def handle_info(:handshake_timeout, state), do: {:noreply, state}

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if !state.cleanup_done do
      errors = terminate_owned_process(state)
      state = drain_stderr(state)
      _ = cleanup_runtime(state, errors)
    end

    :ok
  end

  defp finish_termination(state, prior_errors) do
    cancel_timer(state.termination_timer)
    ProviderProcess.close(state.port)
    {state, errors} = cleanup_runtime(state, prior_errors)
    reason = terminal_reason("terminated by user", errors)
    state = persist_terminal(state, "terminated", reason)
    reply = if errors == [], do: :ok, else: {:error, {:cleanup_failed, Enum.reverse(errors)}}
    {%{state | cleanup_done: true, cleanup_errors: errors}, reply}
  end

  defp cleanup_runtime(state, prior_errors) do
    session = AgentDesk.Repo.get(AgentDesk.Agents.Session, state.session.id) || state.session

    errors =
      prior_errors
      |> cleanup_result(:revoke_capability, AgentDesk.Security.Capability.revoke(session))
      |> cleanup_result(:expire_leases, expire_session(session.id))
      |> cleanup_result(:compose_teardown, AgentDesk.Containers.stop(session))
      |> cleanup_result(:mcp_cleanup, MCPInjection.cleanup(session))
      |> cleanup_result(
        :delivery_cleanup,
        MessageRouter.mark_interrupted(
          session.id,
          delivery_interruption_reason(state),
          terminal: state.termination == :terminate
        )
      )

    state = %{state | session: session, cleanup_done: true, cleanup_errors: errors}

    if errors == [] do
      {state, errors}
    else
      {persist_cleanup_failure(state, errors), errors}
    end
  end

  defp expire_session(session_id) do
    AgentDesk.Resources.Manager.expire_session(session_id)
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp terminate_owned_process(%{port: port} = state) when is_port(port) do
    state = send_action(state, :interrupt)

    if wait_for_port_exit(port, interrupt_grace_ms()) do
      []
    else
      errors =
        signal_error([], :term, ProviderProcess.signal_group(process_group_id(state), :term))

      if wait_for_port_exit(port, terminate_grace_ms()) do
        errors
      else
        errors =
          signal_error(
            errors,
            :kill,
            ProviderProcess.signal_group(process_group_id(state), :kill)
          )

        ProviderProcess.close(port)
        errors
      end
    end
  end

  defp terminate_owned_process(_state), do: []

  defp wait_for_port_exit(port, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_port_exit(port, deadline)
  end

  defp await_port_exit(port, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:exit_status, _status}} -> true
      {^port, :closed} -> true
      {:EXIT, ^port, _reason} -> true
      {^port, {:data, _data}} -> await_port_exit(port, deadline)
    after
      remaining -> !ProviderProcess.alive?(port)
    end
  end

  defp decode_line(line, state) do
    if String.trim(line) == "" do
      state
    else
      case state.adapter.decode_line(line, state.decode) do
        {:error, {:invalid_json, _reason}} ->
          emit_stderr(state, line)

        {:error, reason} when reason in [:not_jsonrpc, :unrecognized_jsonrpc] ->
          emit_stderr(state, line)

        result ->
          apply_decode(result, state)
      end
    end
  end

  defp emit_stderr(state, line) do
    emit(state, [
      Event.new(:stderr, %{"text" => String.slice(line, 0, 4_000)}, state.session.provider)
    ])
  end

  defp apply_decode({:ok, events, decode}, state) do
    Enum.reduce(events, %{state | decode: decode}, fn event, acc -> apply_event(acc, event) end)
  end

  defp apply_decode({:error, reason}, state)
       when reason in [:not_jsonrpc, :unrecognized_jsonrpc] do
    state
  end

  defp apply_decode({:error, {:invalid_json, _}}, state), do: state

  defp apply_decode({:error, reason}, state) do
    event = Event.new(:provider_error, %{"reason" => inspect(reason)}, state.session.provider)
    emit(state, [event])
  end

  defp apply_event(state, %Event{type: :initialize_result} = event) do
    state
    |> emit([event])
    |> continue_after_initialize(event.payload)
  end

  defp apply_event(state, %Event{type: :authenticated} = event) do
    state
    |> emit([event])
    |> send_start_or_resume()
  end

  defp apply_event(state, %Event{type: :client_request, payload: payload}) do
    handle_client_request(state, payload)
  end

  defp apply_event(state, %Event{type: :session_ready} = event) do
    session = remember_provider_session(state.session, event)
    state = %{state | session: session, handshake: :ready}
    state = persist_status(state, "idle")
    AgentDesk.Circuit.success("provider:" <> state.session.provider)
    state = register_card(state)
    state = maybe_inject_role_prompt(state)
    state = emit(state, [event]) |> deliver_inbox()
    drain_prompts(state)
  end

  defp apply_event(state, %Event{type: :approval_requested} = event) do
    emit(%{state | pending_approval: event, status: "waiting"}, [event])
  end

  defp apply_event(state, %Event{type: :turn_completed} = event) do
    next = if state.adapter.capabilities().multi_turn, do: "idle", else: "completed"

    persist_status(emit(state, [event]), next)
    |> deliver_inbox()
  end

  defp apply_event(state, %Event{type: :session_exited} = event) do
    persist_status(emit(state, [event]), "terminated")
  end

  defp apply_event(state, %Event{type: :provider_error} = event) do
    persist_status(emit(state, [event]), "failed")
  end

  defp apply_event(state, %Event{type: :usage} = event) do
    _ = AgentDesk.Usage.record(state.session, event.payload)
    emit(state, [event])
  end

  defp apply_event(state, %Event{} = event), do: emit(state, [event])

  defp handle_exit(state, 0) do
    Telemetry.provider_exited(state.session.id, 0)

    if state.status in ["terminated", "completed", "failed"] do
      state
    else
      persist_terminal(
        emit(state, [Event.new(:session_exited, %{"status" => 0}, state.session.provider)]),
        "completed",
        nil
      )
    end
  end

  defp handle_exit(state, status) do
    Telemetry.provider_exited(state.session.id, status)
    AgentDesk.Circuit.failure("provider:" <> state.session.provider)

    persist_terminal(
      emit(state, [Event.new(:provider_error, %{"exit" => status}, state.session.provider)]),
      "failed",
      "provider exited with status #{status}"
    )
  end

  defp handle_port_exit(state, reason) do
    Telemetry.provider_exited(state.session.id, reason)
    AgentDesk.Circuit.failure("provider:" <> state.session.provider)
    text = "provider port exited: " <> inspect(reason, limit: 20, printable_limit: 200)

    persist_terminal(
      emit(state, [Event.new(:provider_error, %{"reason" => text}, state.session.provider)]),
      "failed",
      text
    )
  end

  defp deliver_inbox(%{port: nil} = state), do: state
  defp deliver_inbox(%{handshake: handshake} = state) when handshake != :ready, do: state

  defp deliver_inbox(state) do
    deliveries = MessageRouter.pending(state.session.id)
    injection = MessageRouter.render_injection(deliveries)

    if injection == "" do
      state
    else
      case inject_prompt(state, injection) do
        {:ok, state} ->
          MessageRouter.mark_injected(state.session, deliveries)
          state

        {:error, state, reason} ->
          MessageRouter.mark_injection_failed(state.session, deliveries, reason)
          state
      end
    end
  end

  defp inject_prompt(state, text) do
    if ProviderProcess.alive?(state.port) do
      case state.adapter.encode({:prompt, text}, state.decode) do
        {:ok, "", decode} ->
          {:error, %{state | decode: decode}, :empty_payload}

        {:ok, payload, decode} ->
          state = %{state | decode: decode}

          if safe_port_command(state.port, payload) do
            {:ok, state}
          else
            {:error, state, :port_command_failed}
          end

        {:error, reason} ->
          {:error, state, reason}
      end
    else
      {:error, state, :port_not_alive}
    end
  end

  defp register_card(state) do
    scope = Scope.for_agent(state.project, state.session)
    caps = state.adapter.capabilities()

    _ =
      A2A.register_card(scope, %{
        name: state.session.display_name,
        description:
          AgentDesk.Roles.card_description(state.session, state.adapter.display_name()),
        skills: card_skills(state),
        availability: "idle",
        features: %{"resume" => caps.resume, "approvals" => caps.approvals}
      })

    state
  end

  defp maybe_inject_role_prompt(state) do
    case AgentDesk.Roles.prompt_for(state.session) do
      {:ok, text} -> send_action(state, {:prompt, text})
      :none -> state
    end
  end

  defp card_skills(state) do
    [%{"name" => state.adapter.key(), "role" => state.session.role || "agent"}]
  end

  defp deliver_prompt(state, text, attachments) do
    names = AgentDesk.Providers.Prompt.names(attachments)

    state
    |> persist_status("working")
    |> send_action({:prompt, text, attachments})
    |> emit([
      Event.new(
        :turn_started,
        %{"text" => text, "attachments" => names},
        state.session.provider
      )
    ])
  end

  defp drain_prompts(%{pending_prompts: []} = state), do: state

  defp drain_prompts(state) do
    Enum.reduce(state.pending_prompts, %{state | pending_prompts: []}, fn {text, attachments},
                                                                          acc ->
      deliver_prompt(acc, text, attachments)
    end)
  end

  defp continue_after_initialize(state, payload) do
    state = send_action(state, :initialized)

    case auth_method_id(payload) do
      id when is_binary(id) -> send_action(state, {:authenticate, id})
      _ -> send_start_or_resume(state)
    end
  end

  defp finish_immediate_handshake(state) do
    state
    |> send_action(:initialized)
    |> send_start_or_resume()
  end

  defp auth_method_id(payload) when is_map(payload) do
    payload
    |> Map.get("authMethods", payload["auth_methods"] || [])
    |> List.wrap()
    |> Enum.map(&auth_id/1)
    |> Enum.find(&(is_binary(&1) and &1 != ""))
  end

  defp auth_id(%{"id" => id}) when is_binary(id), do: id
  defp auth_id(%{"methodId" => id}) when is_binary(id), do: id
  defp auth_id(_), do: nil

  defp handle_client_request(state, %{"method" => "fs/read_text_file"} = payload) do
    id = payload["request_id"]
    cwd = AgentDesk.Worktrees.working_copy_path(state.project, state.session)

    send_action(state, fs_read_action(cwd, id, payload["params"]))
  end

  defp handle_client_request(state, %{"method" => "fs/write_text_file", "request_id" => id}) do
    send_action(state, {:jsonrpc_error, id, -32_601, "Client file writes are disabled"})
  end

  defp handle_client_request(state, %{"request_id" => id, "method" => method}) do
    send_action(state, {:reject_method, id, method})
  end

  defp handle_client_request(state, _), do: state

  @doc false
  @spec fs_read_action(Path.t(), term(), map() | term()) :: tuple()
  def fs_read_action(cwd, id, %{} = params) do
    case params["path"] do
      path when is_binary(path) and path != "" ->
        fs_read_path(cwd, id, path, params)

      _missing ->
        {:jsonrpc_error, id, -32_602, "Missing path"}
    end
  end

  def fs_read_action(_cwd, id, _params),
    do: {:jsonrpc_error, id, -32_602, "Missing path"}

  defp fs_read_path(cwd, id, path, params) do
    case Paths.read_bounded_regular(cwd, path, @max_fs_bytes) do
      {:ok, _canonical_path, content} ->
        if String.valid?(content) do
          sliced = slice_text(content, params["line"], params["limit"])
          {:jsonrpc_result, id, %{"content" => sliced}}
        else
          {:jsonrpc_error, id, -32_000, "File is not valid UTF-8 text"}
        end

      {:error, reason} ->
        fs_read_error(id, reason)
    end
  end

  defp fs_read_error(id, reason) when reason in [:invalid_path, :outside_root, :symlink_loop],
    do: {:jsonrpc_error, id, -32_000, "Path is outside the session worktree"}

  defp fs_read_error(id, :not_found),
    do: {:jsonrpc_error, id, -32_000, "File not found"}

  defp fs_read_error(id, :too_large),
    do: {:jsonrpc_error, id, -32_000, "File is too large to read"}

  defp fs_read_error(id, :not_regular),
    do: {:jsonrpc_error, id, -32_000, "Path is not a regular file"}

  defp fs_read_error(id, :file_changed),
    do: {:jsonrpc_error, id, -32_000, "File changed while being read"}

  defp fs_read_error(id, _reason),
    do: {:jsonrpc_error, id, -32_000, "Could not read file"}

  defp slice_text(content, line, limit) do
    start = if is_integer(line) and line > 0, do: line, else: 1
    count = if is_integer(limit) and limit > 0, do: limit, else: nil
    lines = String.split(content, "\n")

    lines
    |> Enum.drop(start - 1)
    |> then(fn rest -> if count, do: Enum.take(rest, count), else: rest end)
    |> Enum.join("\n")
  end

  defp spawn_or_attach(adapter, session, opts, token) do
    case adapter.command_spec(session, opts) do
      {:ok, :attach} ->
        {:ok, nil, remember_attach(session), nil}

      {:ok, %CommandSpec{} = spec} ->
        case open_port(spec, token, session) do
          {:ok, port, identity, stderr_path} ->
            case remember_process(session, identity) do
              {:ok, started_session} ->
                {:ok, port, started_session, stderr_path}

              {:error, reason} ->
                ProviderProcess.close(port)
                {:error, {:process_identity_failed, reason}}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remember_attach(session) do
    case Agents.update_session(session, %{process_identity: %{"mode" => "attach"}}) do
      {:ok, updated} -> updated
      {:error, _} -> session
    end
  end

  defp enqueue_attach_prompt(state, text) do
    scope = Scope.for_agent(state.project, state.session)

    with {:ok, context} <- A2A.ensure_working_context(scope),
         {:ok, _} <-
           A2A.send_direct_message(scope, %{
             recipient_agent_id: state.session.id,
             context_id: context.id,
             body: text,
             idempotency_key: AgentDesk.Ids.generate()
           }) do
      state
    else
      _ -> state
    end
  end

  defp remember_process(session, identity) do
    case Agents.update_session(session, %{process_identity: identity}) do
      {:ok, updated} -> {:ok, updated}
      {:error, reason} -> {:error, reason}
    end
  end

  defp remember_provider_session(session, %Event{payload: payload}) do
    provider_session_id = payload["provider_session_id"]

    {:ok, updated} =
      Agents.update_session(session, %{
        provider_session_id: provider_session_id,
        provider_version: session.provider_version,
        status: "idle"
      })

    updated
  end

  defp send_start_or_resume(state) do
    cwd = AgentDesk.Worktrees.working_copy_path(state.project, state.session)

    case state.session.provider_session_id do
      id when is_binary(id) and id != "" ->
        if state.adapter.capabilities().resume do
          send_action(state, {:resume, id})
        else
          state
          |> emit([
            Event.new(
              :provider_error,
              %{"reason" => "resume_unsupported"},
              state.session.provider
            )
          ])
          |> persist_terminal("failed", "provider adapter does not support resume")
        end

      _ ->
        send_new_session(state, cwd)
    end
  end

  defp send_new_session(state, cwd) do
    servers = MCPInjection.acp_servers(state.mcp_path)

    case state.adapter.encode({:start_session, cwd, servers}, state.decode) do
      {:error, :unsupported_action} ->
        send_action(state, {:start_session, cwd})

      other ->
        apply_encode_result(state, other)
    end
  end

  defp send_action(%{port: nil} = state, {:prompt, text}) do
    enqueue_attach_prompt(state, text)
  end

  defp send_action(%{port: nil} = state, {:prompt, text, _attachments}) do
    enqueue_attach_prompt(state, text)
  end

  defp send_action(%{port: nil} = state, _action), do: state

  defp send_action(state, {:prompt, text, attachments} = action) do
    case state.adapter.encode(action, state.decode) do
      {:error, :unsupported_action} ->
        noted = AgentDesk.Providers.Prompt.with_file_notes(text, attachments)
        send_action(state, {:prompt, noted})

      other ->
        apply_encode_result(state, other)
    end
  end

  defp send_action(state, action) do
    apply_encode_result(state, state.adapter.encode(action, state.decode))
  end

  defp apply_encode_result(state, {:ok, "", decode}) do
    %{state | decode: decode}
  end

  defp apply_encode_result(state, {:ok, payload, decode}) do
    if ProviderProcess.alive?(state.port) do
      _ = safe_port_command(state.port, payload)
    end

    %{state | decode: decode}
  end

  defp apply_encode_result(state, {:error, :unsupported_action}) do
    state
  end

  defp safe_port_command(port, payload) do
    Port.command(port, payload)
  rescue
    ArgumentError -> false
  catch
    :error, :badarg -> false
  end

  defp emit(state, events) do
    {state, persisted} = persist_stream(state, events)
    Enum.each(persisted, &Transcript.append(state.project.id, state.session.id, &1))
    buffer = Enum.take(state.buffer ++ events, -@visible_cap)
    schedule_flush(%{state | buffer: buffer})
  end

  defp schedule_flush(%{flush_ref: nil} = state) do
    %{state | flush_ref: Process.send_after(self(), :flush, @flush_ms)}
  end

  defp schedule_flush(state), do: state

  defp flush(%{buffer: []} = state), do: state

  defp flush(state) do
    Phoenix.PubSub.broadcast(
      AgentDesk.PubSub,
      topic(state.session.id),
      {:session_activity, state.session.id, Activity.coalesce_events(state.buffer), state.status,
       state.pending_approval}
    )

    Phoenix.PubSub.broadcast(
      AgentDesk.PubSub,
      project_topic(state.project.id),
      {:session_updated, state.session}
    )

    %{state | buffer: []}
  end

  defp persist_stream(state, events) do
    {state, persisted} = Enum.reduce(events, {state, []}, &persist_event/2)
    {state, Enum.reverse(persisted)}
  end

  defp persist_event(%Event{type: :message_delta} = event, {state, acc}) do
    {%{state | message_draft: Activity.join(state.message_draft, event_text(event))}, acc}
  end

  defp persist_event(%Event{type: :message_completed} = event, {state, acc}) do
    text = completed_or_draft(state.message_draft, event)
    completed = %{event | payload: Map.put(event.payload, "text", text)}
    {%{state | message_draft: ""}, [completed | acc]}
  end

  defp persist_event(%Event{type: type}, acc)
       when type in [:reasoning_delta, :command_output, :client_request, :authenticated] do
    acc
  end

  defp persist_event(%Event{} = event, {state, acc}) do
    {state, acc} = flush_message_draft(state, acc, event)
    {state, [event | acc]}
  end

  defp flush_message_draft(%{message_draft: ""} = state, acc, _event), do: {state, acc}

  defp flush_message_draft(state, acc, event) do
    completed = Event.new(:message_completed, %{"text" => state.message_draft}, event.provider)
    {%{state | message_draft: ""}, [completed | acc]}
  end

  defp completed_or_draft(draft, event) do
    incoming = event_text(event)

    if incoming != "" and String.length(incoming) >= String.length(draft) do
      incoming
    else
      Activity.join(draft, incoming)
    end
  end

  defp event_text(%Event{payload: payload}) when is_map(payload) do
    payload["text"] || payload["delta"] || payload["summary"] || ""
  end

  defp persist_status(state, status) do
    {:ok, session} =
      Agents.update_session(state.session, %{status: status, last_heartbeat_at: Clock.utc_now()})

    publish_session(state, session)
    %{state | session: session, status: status}
  end

  defp persist_terminal(state, status, reason) do
    now = Clock.utc_now()

    {:ok, session} =
      Agents.update_session(state.session, %{
        status: status,
        last_heartbeat_at: now,
        ended_at: now,
        exit_reason: reason
      })

    publish_session(state, session)
    %{state | session: session, status: status}
  end

  defp publish_session(state, session) do
    Phoenix.PubSub.broadcast(
      AgentDesk.PubSub,
      project_topic(state.project.id),
      {:session_updated, session}
    )
  end

  defp delivery_interruption_reason(%{termination: :terminate}), do: "session terminated"

  defp delivery_interruption_reason(%{termination: :provider_exit}),
    do: "provider exited before delivery completed"

  defp delivery_interruption_reason(_state),
    do: "provider worker stopped before delivery completed"

  defp open_port(%CommandSpec{} = spec, token, session) do
    ProviderProcess.open(spec, token, session)
  end

  defp schedule_stderr_poll(%{stderr_path: path}) when is_binary(path) do
    Process.send_after(self(), :stderr_poll, @stderr_poll_ms)
  end

  defp schedule_stderr_poll(_state), do: :ok

  defp drain_stderr(state) do
    case ProviderProcess.read_stderr(state.stderr_path, state.stderr_offset) do
      {:ok, "", offset} ->
        %{state | stderr_offset: offset}

      {:ok, data, offset} ->
        state
        |> Map.put(:stderr_offset, offset)
        |> emit_stderr(data)

      {:error, reason} ->
        emit(state, [
          Event.new(
            :stderr,
            %{"reason" => "capture_failed", "text" => inspect(reason)},
            state.session.provider
          )
        ])
    end
  end

  defp cleanup_result(errors, _step, :ok), do: errors
  defp cleanup_result(errors, _step, {:ok, _value}), do: errors
  defp cleanup_result(errors, step, {:error, reason}), do: [{step, reason} | errors]
  defp cleanup_result(errors, step, other), do: [{step, other} | errors]

  defp persist_cleanup_failure(state, errors) do
    reason = terminal_reason(state.session.exit_reason || "provider cleanup failed", errors)

    case Agents.update_session(state.session, %{exit_reason: reason}) do
      {:ok, session} -> %{state | session: session}
      {:error, _reason} -> state
    end
  end

  defp terminal_reason(base, []), do: base

  defp terminal_reason(base, errors) do
    details =
      errors
      |> Enum.reverse()
      |> Enum.map_join(", ", fn {step, reason} ->
        "#{step}=#{inspect(reason, limit: 10, printable_limit: 300)}"
      end)

    String.slice("#{base}; cleanup failed: #{details}", 0, 2_000)
  end

  defp process_group_id(state) do
    state.session.process_identity["process_group_id"] ||
      state.session.process_identity["os_pid"]
  end

  defp signal_error(errors, _signal, :ok), do: errors
  defp signal_error(errors, signal, {:error, reason}), do: [{signal, reason} | errors]

  defp reply_termination(%{termination_from: nil}, _reply), do: :ok
  defp reply_termination(%{termination_from: from}, reply), do: GenServer.reply(from, reply)

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer) do
    _ = Process.cancel_timer(timer)
    :ok
  end

  defp interrupt_grace_ms do
    shutdown_config(:interrupt_grace_ms, @interrupt_grace_ms)
  end

  defp terminate_grace_ms do
    shutdown_config(:terminate_grace_ms, @terminate_grace_ms)
  end

  defp shutdown_config(key, default) do
    :agent_desk
    |> Application.get_env(:provider_shutdown, [])
    |> Keyword.get(key, default)
  end

  defp topic(session_id), do: "session:" <> session_id

  defp handshake_ms do
    Application.get_env(:agent_desk, :provider_handshake_ms, @default_handshake_ms)
  end

  defp project_topic(project_id), do: "project:" <> project_id <> ":sessions"
end
