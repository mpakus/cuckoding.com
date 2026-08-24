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
  alias AgentDesk.Projects
  alias AgentDesk.Providers
  alias AgentDesk.Providers.CommandSpec
  alias AgentDesk.Providers.Event
  alias AgentDesk.Providers.Framer
  alias AgentDesk.Providers.MCPInjection
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
    buffer: [],
    flush_ref: nil,
    handshake: :awaiting_ready,
    pending_approval: nil,
    message_draft: ""
  ]

  @flush_ms 50
  @handshake_ms 20_000
  @visible_cap 200

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
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_started}
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
      {:ok, pid} -> GenServer.call(pid, message, 10_000)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def init(opts) do
    session = Keyword.fetch!(opts, :session)
    {:ok, project} = Projects.get_project(session.project_id)
    {:ok, adapter} = Providers.adapter(session.provider)

    adapter_opts =
      Keyword.get(opts, :adapter_opts, []) ++
        [cwd: AgentDesk.Worktrees.working_copy_path(project, session)]

    {:ok, token, session} = AgentDesk.Security.Capability.issue(session)
    mcp_path = MCPInjection.write!(session, token)

    case spawn_or_attach(adapter, session, adapter_opts, token) do
      {:ok, port, session} ->
        Process.send_after(self(), :handshake_timeout, @handshake_ms)
        Telemetry.provider_started(session.id, session.provider)

        state = %__MODULE__{
          session: session,
          project: project,
          adapter: adapter,
          decode: adapter.init_decode(),
          port: port,
          framer: Framer.new(),
          status: "starting",
          mcp_path: mcp_path,
          token: token
        }

        {:ok, state, {:continue, :handshake}}

      {:error, reason} ->
        {:stop, reason}
    end
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
    state =
      state
      |> send_action(:initialize)
      |> send_action(:initialized)
      |> send_start_or_resume()

    {:noreply, persist_status(state, "starting")}
  end

  @impl true
  def handle_call({:prompt, text}, from, state), do: handle_call({:prompt, text, []}, from, state)

  def handle_call({:prompt, text, attachments}, _from, state) when is_list(attachments) do
    names = AgentDesk.Providers.Prompt.names(attachments)
    state = persist_status(send_action(state, {:prompt, text, attachments}), "working")

    {:reply, :ok,
     emit(
       state,
       [
         Event.new(
           :turn_started,
           %{"text" => text, "attachments" => names},
           state.session.provider
         )
       ]
     )}
  end

  def handle_call(:interrupt, _from, state) do
    {:reply, :ok, persist_status(send_action(state, :interrupt), "interrupted")}
  end

  def handle_call({:approve, request_id, decision}, _from, state) do
    {:reply, :ok, send_action(%{state | pending_approval: nil}, {:approve, request_id, decision})}
  end

  def handle_call(:terminate, _from, state) do
    _ = send_action(state, :interrupt)
    close_port(state)
    {:stop, :normal, :ok, persist_status(state, "terminated")}
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
    {:noreply, handle_exit(state, status)}
  end

  def handle_info(:flush, state) do
    {:noreply, flush(%{state | flush_ref: nil})}
  end

  def handle_info(:handshake_timeout, %{handshake: :awaiting_ready} = state) do
    event = Event.new(:provider_error, %{"reason" => "handshake_timeout"}, state.session.provider)
    {:noreply, persist_status(emit(state, [event]), "failed")}
  end

  def handle_info(:handshake_timeout, state), do: {:noreply, state}

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    close_port(state)
    _ = AgentDesk.Containers.stop(state.session)
    _ = expire_session(state.session.id)
    _ = AgentDesk.Security.Capability.revoke(state.session)
    :ok
  end

  defp expire_session(session_id) do
    AgentDesk.Resources.Manager.expire_session(session_id)
  catch
    :exit, _ -> :ok
  end

  defp decode_line(line, state) do
    if String.trim(line) == "" do
      state
    else
      apply_decode(state.adapter.decode_line(line, state.decode), state)
    end
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
    emit(state, [event])
  end

  defp apply_event(state, %Event{type: :session_ready} = event) do
    session = remember_provider_session(state.session, event)
    state = %{state | session: session, handshake: :ready}
    state = persist_status(state, "idle")
    AgentDesk.Circuit.success("provider:" <> state.session.provider)
    state = register_card(state)
    state = maybe_inject_role_prompt(state)
    state = send_action(state, {:configure_mcp, state.mcp_path})
    emit(state, [event]) |> deliver_inbox()
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
    if state.status in ["terminated", "completed", "failed"] do
      state
    else
      persist_status(
        emit(state, [Event.new(:session_exited, %{"status" => 0}, state.session.provider)]),
        "completed"
      )
    end
  end

  defp handle_exit(state, status) do
    Telemetry.provider_exited(state.session.id, status)
    AgentDesk.Circuit.failure("provider:" <> state.session.provider)

    persist_status(
      emit(state, [Event.new(:provider_error, %{"exit" => status}, state.session.provider)]),
      "failed"
    )
  end

  defp deliver_inbox(%{port: nil} = state), do: state

  defp deliver_inbox(state) do
    deliveries = MessageRouter.pending(state.session.id)
    injection = MessageRouter.render_injection(deliveries)

    if injection == "" do
      state
    else
      state = send_action(state, {:prompt, injection})
      MessageRouter.acknowledge_injected(state.session, deliveries)
      state
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

  defp spawn_or_attach(adapter, session, opts, token) do
    case adapter.command_spec(session, opts) do
      {:ok, :attach} ->
        {:ok, nil, remember_attach(session)}

      {:ok, %CommandSpec{} = spec} ->
        case open_port(spec, token, session) do
          {:ok, port} -> {:ok, port, remember_process(session, port)}
          {:error, reason} -> {:error, reason}
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

  defp remember_process(session, port) do
    os_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, pid} -> pid
        _ -> nil
      end

    identity = %{"os_pid" => os_pid, "port" => inspect(port)}

    case Agents.update_session(session, %{process_identity: identity}) do
      {:ok, updated} -> updated
      {:error, _} -> session
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
        send_action(state, {:resume, id})

      _ ->
        send_action(state, {:start_session, cwd})
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
    true = Port.command(state.port, payload)
    %{state | decode: decode}
  end

  defp apply_encode_result(state, {:error, :unsupported_action}) do
    state
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
       when type in [:reasoning_delta, :command_output] do
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

    Phoenix.PubSub.broadcast(
      AgentDesk.PubSub,
      project_topic(state.project.id),
      {:session_updated, session}
    )

    %{state | session: session, status: status}
  end

  defp open_port(%CommandSpec{} = spec, token, session) do
    with {:ok, executable} <- Providers.Discovery.find_executable(spec.executable) do
      env =
        System.get_env()
        |> Map.merge(AgentDesk.Isolation.env(session))
        |> Map.merge(spec.env)
        |> Map.put("AGENTDESK_CAPABILITY_TOKEN", token)
        |> Enum.map(fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)

      {:ok,
       Port.open({:spawn_executable, executable}, [
         :binary,
         :exit_status,
         :use_stdio,
         {:args, spec.args},
         {:cd, spec.cwd},
         {:env, env}
       ])}
    end
  rescue
    e in [ArgumentError, ErlangError] ->
      {:error, {:spawn_failed, Exception.message(e)}}
  end

  defp close_port(%{port: port}) when is_port(port) do
    if Port.info(port), do: Port.close(port)
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp close_port(_state), do: :ok

  defp topic(session_id), do: "session:" <> session_id
  defp project_topic(project_id), do: "project:" <> project_id <> ":sessions"
end
