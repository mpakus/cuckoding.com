defmodule AgentDesk.Providers.SessionWorker do
  @moduledoc """
  One OS process and decode state per provider session.
  """

  use GenServer, restart: :temporary

  alias AgentDesk.A2A
  alias AgentDesk.A2A.MessageRouter
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
    pending_approval: nil
  ]

  @flush_ms 50
  @handshake_ms 8_000
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

  @spec prompt(Ecto.UUID.t(), String.t()) :: :ok | {:error, term()}
  def prompt(session_id, text), do: call(session_id, {:prompt, text})

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

    {:ok, spec} =
      adapter.command_spec(
        session,
        Keyword.get(opts, :adapter_opts, []) ++
          [cwd: AgentDesk.Worktrees.working_copy_path(project, session)]
      )

    {:ok, token, session} = AgentDesk.Security.Capability.issue(session)
    mcp_path = MCPInjection.write!(session, token)
    port = open_port(spec, token)

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
  end

  @impl true
  def handle_continue(:handshake, state) do
    state =
      state
      |> send_action(:initialize)
      |> send_action(:initialized)
      |> send_start_or_resume()

    {:noreply, persist_status(state, "starting")}
  end

  @impl true
  def handle_call({:prompt, text}, _from, state) do
    state = persist_status(send_action(state, {:prompt, text}), "working")

    {:reply, :ok,
     emit(state, [Event.new(:turn_started, %{"text" => text}, state.session.provider)])}
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
        {:noreply, Enum.reduce(lines, %{state | framer: framer}, &decode_line/2)}

      {:error, :line_too_large} ->
        event =
          Event.new(:provider_error, %{"reason" => "line_too_large"}, state.session.provider)

        {:noreply, emit(%{state | framer: Framer.new()}, [event])}
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
    _ = AgentDesk.Resources.Manager.expire_session(state.session.id)
    :ok
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
    state = register_card(state)
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

    persist_status(
      emit(state, [Event.new(:provider_error, %{"exit" => status}, state.session.provider)]),
      "failed"
    )
  end

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
        description: "#{state.adapter.display_name()} session",
        skills: [%{"name" => state.adapter.key()}],
        availability: "idle",
        features: %{"resume" => caps.resume, "approvals" => caps.approvals}
      })

    state
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
    case state.session.provider_session_id do
      id when is_binary(id) and id != "" ->
        send_action(state, {:resume, id})

      _ ->
        send_action(state, {:start_session, state.project.canonical_path})
    end
  end

  defp send_action(state, action) do
    case state.adapter.encode(action, state.decode) do
      {:ok, "", decode} ->
        %{state | decode: decode}

      {:ok, payload, decode} ->
        true = Port.command(state.port, payload)
        %{state | decode: decode}

      {:error, :unsupported_action} ->
        state
    end
  end

  defp emit(state, events) do
    Enum.each(events, &Transcript.append(state.project.id, state.session.id, &1))
    buffer = Enum.take(state.buffer ++ events, -@visible_cap)
    state = %{state | buffer: buffer}
    schedule_flush(state)
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
      {:session_activity, state.session.id, state.buffer, state.status, state.pending_approval}
    )

    Phoenix.PubSub.broadcast(
      AgentDesk.PubSub,
      project_topic(state.project.id),
      {:session_updated, state.session}
    )

    %{state | buffer: []}
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

  defp open_port(%CommandSpec{} = spec, token) do
    env =
      System.get_env()
      |> Map.merge(spec.env)
      |> Map.put("AGENTDESK_CAPABILITY_TOKEN", token)
      |> Enum.map(fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)

    Port.open({:spawn_executable, spec.executable}, [
      :binary,
      :exit_status,
      :use_stdio,
      {:args, spec.args},
      {:cd, spec.cwd},
      {:env, env}
    ])
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
