defmodule Cuckoding.Adapters.ACP.Client do
  @moduledoc "One supervised ACP conversation. Durable workflow authority stays in Cuckoding."
  use GenServer, restart: :temporary

  alias Cuckoding.ActivityStream
  alias Cuckoding.Adapters
  alias Cuckoding.Adapters.ACP.Wire
  alias Cuckoding.Adapters.Types
  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.Commands
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.ProcessRecord
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Identifier
  alias Cuckoding.Repo
  alias Cuckoding.Security.Redactor
  alias Cuckoding.Telemetry.Accounting

  @maximum_message 1_048_576
  @maximum_events 10_000
  @stop_reasons ~w(end_turn max_tokens max_turn_requests refusal cancelled)

  def start(request, grant, launch, options) do
    request = Cuckoding.Plugins.RTK.prepare_request(request)
    args = {request, grant, launch, options, self()}

    with :ok <- duplex_runner(options),
         {:ok, pid} <-
           DynamicSupervisor.start_child(Cuckoding.Execution.ProcessWorkers, {__MODULE__, args}),
         do: GenServer.call(pid, :open, :infinity)
  catch
    :exit, _ -> {:error, :acp_session_lost}
  end

  def start_link(args), do: GenServer.start_link(__MODULE__, args)

  @doc "Binds the saved session before sending the stage's first prompt. Never replays a prompt."
  def execute(pid, %AgentSession{} = stored),
    do: call(pid, {:execute, stored.id})

  def stop(pid), do: call(pid, :stop)

  def live_session?(
        %Types.Session{process: %{runner: __MODULE__, handle: pid}} = session,
        %{process: :matching, session: :available}
      )
      when is_pid(pid) do
    GenServer.call(pid, {:recover, session.session_id, session.external_session_id}, 5_000) == :ok
  catch
    :exit, _ -> false
  end

  def live_session?(_session, _inspection), do: false

  @doc "Checks the live protocol owner during startup/wake inspection; never adopts a process."
  def owns_process?(run_id, process_id) do
    with registry when is_pid(registry) <- Process.whereis(Cuckoding.RunRegistry),
         [{pid, _}] <- Registry.lookup(Cuckoding.RunRegistry, {:acp, run_id}) do
      GenServer.call(pid, {:owns_process, process_id}, 5_000) == :ok
    else
      _ -> false
    end
  catch
    :exit, _ -> false
  end

  def stop_run(run_id) do
    case Registry.lookup(Cuckoding.RunRegistry, {:acp, run_id}) do
      [{pid, _}] ->
        case stop(pid) do
          {:ok, _} -> :ok
          # The caller still verifies all durable process records through the host runner.
          {:error, :acp_session_lost} -> :ok
          error -> error
        end

      [] ->
        :ok
    end
  end

  defp call(pid, message) do
    GenServer.call(pid, message, :infinity)
  catch
    :exit, _ -> {:error, :acp_session_lost}
  end

  defp duplex_runner(options) do
    runner = Keyword.get(options, :runner)

    if is_atom(runner) and Code.ensure_loaded?(runner) and function_exported?(runner, :write, 2) and
         function_exported?(runner, :close_input, 1) and is_map(options[:environment]),
       do: :ok,
       else: {:error, :acp_duplex_runner_required}
  end

  @impl true
  def init({request, grant, launch, options, owner}) do
    runner = Keyword.fetch!(options, :runner)
    environment = Keyword.fetch!(options, :environment)

    with true <-
           environment.run_id == request.run_id and
             environment.worktree_path == request.worktree_path and
             environment.run_dir == request.run_dir,
         {:ok, _} <- Registry.register(Cuckoding.RunRegistry, {:acp, request.run_id}, nil) do
      state = %{
        runner: runner,
        handle: nil,
        environment: environment,
        grace_ms: Keyword.get(options, :termination_grace_ms, 2_000),
        request: request,
        launch: launch,
        owner: owner,
        owner_monitor: Process.monitor(owner),
        worker_monitor: nil,
        wire: %Wire{},
        phase: :unbound,
        waiter: nil,
        pending_write: nil,
        stop_waiters: [],
        stored: nil,
        sequence: 0,
        chunks: [],
        message_bytes: 0,
        message_id: nil,
        last_message: nil,
        selected_model: nil,
        model_config_id: nil,
        error: nil,
        stop_reason: nil,
        close_timer: nil,
        controlled_shutdown?: false,
        secrets: Keyword.get(options, :redact, []),
        runtime: %Types.Session{
          adapter: launch.acp.adapter,
          session_id: Identifier.generate(),
          requested_model: request.requested_model,
          effective_grant: grant,
          state: "starting",
          process: %{runner: __MODULE__, handle: self()}
        },
        resume_session: Keyword.get(options, :resume_session),
        prompt:
          Keyword.get(options, :prompt, request.objective) <>
            "\n\nEnd this turn with one JSON object matching the following schema. " <>
            "Use a separate final message with no surrounding commentary or Markdown fences.\n" <>
            Jason.encode!(request.required_output_schema)
      }

      {:ok, state, {:continue, :launch}}
    else
      false -> {:stop, :acp_owner_mismatch}
      {:error, _} -> {:stop, :acp_run_already_owned}
    end
  end

  @impl true
  def handle_continue(:launch, state) do
    # Start the sibling only after init returns to the shared DynamicSupervisor.
    case state.runner.start(state.environment, state.launch.command,
           env: state.launch.environment,
           environment_allowlist: state.launch.environment_allowlist,
           timeout: state.launch.timeout,
           protocol_owner: self(),
           redact: state.secrets,
           termination_grace_ms: state.grace_ms
         ) do
      {:ok, handle} ->
        {:noreply, %{state | handle: handle, worker_monitor: Process.monitor(handle.worker)}}

      {:error, _reason} ->
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_call(:open, {owner, _}, %{owner: owner, phase: :unbound} = state),
    do: {:reply, {:ok, state.runtime}, state}

  def handle_call({:execute, id}, {owner, _} = from, %{owner: owner, phase: :unbound} = state) do
    state = %{state | waiter: from}

    case bind_session(state, id) do
      {:ok, stored} -> {:noreply, initialize(%{state | stored: stored})}
      {:error, reason} -> {:noreply, fail(%{state | waiter: from}, reason)}
    end
  end

  def handle_call(:stop, from, state) do
    state = %{state | stop_waiters: [from | state.stop_waiters]}
    {:noreply, cancel(state)}
  end

  def handle_call({:recover, id, external_id}, _from, state) do
    live? =
      with true <- state.phase in [:ready, :prompting],
           true <-
             state.runtime.session_id == id and state.runtime.external_session_id == external_id,
           %AgentSession{state: status} <- Repo.get(AgentSession, state.stored.id),
           true <- status in ~w(ready running paused),
           true <- Process.alive?(state.owner) and Process.alive?(state.handle.worker),
           %ProcessRecord{state: "running"} = process <-
             Repo.get(ProcessRecord, state.handle.process.id),
           true <- process.agent_session_id == state.stored.id,
           {:ok, %{status: :matching}} <- state.runner.inspect(process) do
        :ok
      else
        _ -> {:error, :session_recovery_required}
      end

    {:reply, live?, state}
  end

  def handle_call({:owns_process, id}, _from, %{handle: %{process: %{id: id}}} = state) do
    result =
      if Process.alive?(state.owner) and Process.alive?(state.handle.worker),
        do: :ok,
        else: {:error, :acp_owner_lost}

    {:reply, result, state}
  end

  def handle_call(_message, _from, state), do: {:reply, {:error, :acp_command_refused}, state}

  @impl true
  def handle_info(:admit_prompt, %{phase: :ready} = state),
    do: {:noreply, admit_prompt(state)}

  def handle_info(:admit_prompt, state), do: {:noreply, state}

  def handle_info({:runner_resumed, worker}, %{handle: %{worker: worker}} = state) do
    case state.pending_write do
      nil ->
        {:noreply, state}

      bytes ->
        case write_request(%{state | pending_write: nil}, bytes) do
          {:ok, state} -> {:noreply, state}
          {:error, reason} -> {:noreply, fail(state, reason)}
        end
    end
  end

  def handle_info({:runner_stdout, worker, bytes}, %{handle: %{worker: worker}} = state) do
    case Wire.feed(state.wire, bytes) do
      {:ok, wire, messages} -> {:noreply, consume(messages, %{state | wire: wire})}
      {:error, reason} -> {:noreply, fail(state, reason)}
    end
  end

  def handle_info({:runner_protocol_error, worker, reason}, %{handle: %{worker: worker}} = state),
    do: {:noreply, fail(state, reason)}

  def handle_info({:runner_exited, worker, result}, %{handle: %{worker: worker}} = state) do
    if state.close_timer, do: Process.cancel_timer(state.close_timer)
    finish(state, result)
  end

  def handle_info(:close_timeout, state) do
    # Cleanup remains owned by the host runner, even if ACP cancellation was ignored.
    result = state.runner.stop(state.handle)
    error = state.error || if(is_nil(state.stop_reason), do: :acp_shutdown_timeout)
    finish(%{state | error: error, controlled_shutdown?: true}, result)
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{owner_monitor: ref} = state),
    do: {:noreply, fail(state, :acp_owner_lost)}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{worker_monitor: ref} = state),
    do: finish(state, {:error, :acp_transport_lost})

  @impl true
  def format_status(status),
    do: Map.merge(status, %{state: :redacted, message: :redacted, reason: :redacted, log: []})

  defp consume([], state), do: state

  defp consume(_messages, %{phase: :closing, error: error} = state) when not is_nil(error),
    do: state

  defp consume([message | rest], state) do
    case receive_message(state, message) do
      {:ok, state} -> consume(rest, state)
      {:error, reason} -> fail(state, reason)
    end
  end

  defp receive_message(_state, {:response, _id, _method, {:error, code}}),
    do: {:error, if(code == -32_000, do: :acp_authentication_required, else: :acp_request_failed)}

  defp receive_message(
         %{phase: :initializing} = state,
         {:response, _, "initialize", {:ok, result}}
       ) do
    with 1 <- result["protocolVersion"],
         capabilities when is_map(capabilities) <- Map.get(result, "agentCapabilities", %{}),
         :ok <- can_load(state.resume_session, capabilities) do
      params =
        Map.merge(state.launch.acp.session_params, %{
          "cwd" => state.request.worktree_path,
          "mcpServers" => []
        })

      if state.resume_session do
        runtime = %{state.runtime | external_session_id: state.resume_session}

        request(
          %{state | phase: :loading, runtime: runtime},
          "session/load",
          Map.put(params, "sessionId", state.resume_session)
        )
      else
        request(%{state | phase: :creating}, "session/new", params)
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :acp_protocol_mismatch}
    end
  end

  defp receive_message(%{phase: :creating} = state, {:response, _, "session/new", {:ok, result}}) do
    if safe_id?(result["sessionId"], state.secrets) do
      runtime = %{state.runtime | external_session_id: result["sessionId"]}
      configure(%{state | runtime: runtime}, result)
    else
      {:error, :acp_invalid_session}
    end
  end

  defp receive_message(%{phase: :loading} = state, {:response, _, "session/load", {:ok, result}}),
    do: configure(state, result)

  defp receive_message(
         %{phase: :setting_mode} = state,
         {:response, _, "session/set_mode", {:ok, _}}
       ),
       do: select_model(state)

  defp receive_message(
         %{phase: :setting_model} = state,
         {:response, _, "session/set_model", {:ok, _}}
       ),
       do: ready(state)

  defp receive_message(
         %{phase: :setting_model} = state,
         {:response, _, "session/set_config_option", {:ok, result}}
       ) do
    with {:ok, state} <- observe_configuration(state, result["configOptions"]),
         do: ready(state)
  end

  defp receive_message(%{phase: phase} = state, {:response, _, "session/prompt", {:ok, result}})
       when phase in [:prompting, :cancelling] do
    with reason when reason in @stop_reasons <- result["stopReason"],
         {:ok, state} <- flush_message(state),
         :ok <- record_usage(state, result) do
      state = %{state | stop_reason: reason}
      close(state)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :acp_invalid_stop_reason}
    end
  end

  defp receive_message(state, {:notification, "session/update", params}) do
    if params["sessionId"] == state.runtime.external_session_id and is_map(params["update"]),
      do: update(state, params["update"]),
      else: {:error, :acp_session_mismatch}
  end

  defp receive_message(state, {:notification, _method, _params}), do: {:ok, state}

  defp receive_message(state, {:request, id, "session/request_permission", params}) do
    if params["sessionId"] == state.runtime.external_session_id do
      with {:ok, frame} <- Wire.reply(id, %{"outcome" => %{"outcome" => "cancelled"}}),
           :ok <- state.runner.write(state.handle, frame),
           {:ok, state} <-
             record(
               state,
               "approval.requested",
               "Agent requested permission; review is required",
               tool_metadata(params["toolCall"])
             ) do
        {:ok, cancel(%{state | error: :acp_permission_required})}
      end
    else
      {:error, :acp_session_mismatch}
    end
  end

  defp receive_message(state, {:request, id, _method, _params}) do
    with {:ok, frame} <- Wire.reject(id),
         :ok <- state.runner.write(state.handle, frame),
         do: {:error, :acp_unsupported_client_request}
  end

  defp receive_message(_state, _message), do: {:error, :acp_unexpected_message}

  defp configure(state, result) do
    mode = state.launch.acp.mode

    with {:ok, models, config_id} <- model_configuration(result),
         model = requested_model(state, models),
         true <- safe_id?(model, state.secrets),
         %{"availableModes" => modes} when is_list(modes) <- result["modes"],
         true <- Enum.any?(modes, &(is_map(&1) and &1["id"] == mode)),
         true <- Enum.any?(models["availableModels"], &(is_map(&1) and &1["modelId"] == model)) do
      observed = if models["currentModelId"] == model, do: model
      runtime = %{state.runtime | actual_model: observed}

      request(
        %{
          state
          | phase: :setting_mode,
            selected_model: model,
            model_config_id: config_id,
            runtime: runtime
        },
        "session/set_mode",
        session_params(state, %{"modeId" => mode})
      )
    else
      _ -> {:error, :acp_required_configuration_unavailable}
    end
  end

  defp model_configuration(%{"configOptions" => options}) when is_list(options) do
    case Enum.filter(options, &(is_map(&1) and &1["category"] == "model")) do
      [%{"id" => id, "type" => "select", "options" => models, "currentValue" => current}]
      when is_binary(id) and is_list(models) ->
        available =
          Enum.map(models, fn
            %{"value" => value} -> %{"modelId" => value}
            _ -> %{"modelId" => nil}
          end)

        {:ok, %{"availableModels" => available, "currentModelId" => current}, id}

      _ ->
        {:error, :acp_required_configuration_unavailable}
    end
  end

  defp model_configuration(%{"models" => %{"availableModels" => models} = config})
       when is_list(models),
       do: {:ok, config, nil}

  defp model_configuration(_), do: {:error, :acp_required_configuration_unavailable}

  defp requested_model(state, models) do
    requested = state.request.requested_model
    current = models["currentModelId"]

    case state.launch.acp[:model_format] do
      :cursor_cli ->
        # Cursor has already resolved --model; keep that reported canonical choice
        # for configuration and drift checks, while retaining the requested alias.
        current

      :codex when is_binary(current) and is_binary(requested) ->
        if String.starts_with?(current, requested <> "["), do: current, else: requested

      _ ->
        requested || current
    end
  end

  defp select_model(%{model_config_id: id} = state) when is_binary(id),
    do:
      request(
        %{state | phase: :setting_model},
        "session/set_config_option",
        session_params(state, %{"configId" => id, "value" => state.selected_model})
      )

  defp select_model(state),
    do:
      request(
        %{state | phase: :setting_model},
        "session/set_model",
        session_params(state, %{"modelId" => state.selected_model})
      )

  defp ready(state) do
    runtime = %{state.runtime | state: "ready"}
    state = %{state | runtime: runtime, phase: :ready}

    with {:ok, stored} <- Adapters.record_session_observation(state.stored, runtime),
         {:ok, state} <-
           record(%{state | stored: stored}, "session.started", "ACP session ready", %{
             "transport" => "acp",
             "protocol_version" => 1
           }) do
      send(self(), :admit_prompt)
      {:ok, state}
    end
  end

  defp can_load(nil, _capabilities), do: :ok
  defp can_load(_id, %{"loadSession" => true}), do: :ok
  defp can_load(_id, _capabilities), do: {:error, :acp_load_unsupported}

  defp bind_session(state, id) do
    EventStore.transaction(fn -> bind_process_session(state, id) end)
  end

  defp bind_process_session(state, id) do
    with %AgentSession{} = stored <- Repo.get(AgentSession, id),
         true <- stored.state in ["created", "starting", "paused"],
         true <-
           stored.stage_attempt_id == state.request.attempt_id and
             stored.adapter_key == state.runtime.adapter and
             stored.requested_model == state.request.requested_model,
         %StageAttempt{run_id: run_id} <- Repo.get(StageAttempt, stored.stage_attempt_id),
         true <- run_id == state.request.run_id,
         %ProcessRecord{agent_session_id: nil, state: "running"} = process <-
           Repo.get(ProcessRecord, state.handle.process.id),
         true <- process.environment_id == state.environment.id,
         {:ok, _} <-
           EventStore.append_in_transaction(
             run_id,
             %{
               event_type: "agent.process_bound",
               public_summary: "ACP process linked to its saved session",
               payload: %{"agent_session_id" => id, "process_id" => process.id}
             },
             fn repo, _ -> repo.update(Ecto.Changeset.change(process, agent_session_id: id)) end
           ),
         {:ok, stored} <- Adapters.record_session_observation(stored, state.runtime) do
      stored
    else
      _ -> Repo.rollback(:acp_owner_mismatch)
    end
  end

  defp start_prompt(state) do
    Cuckoding.RunControl.try_launch(state.request.run_id, fn ->
      with :ok <- reserve_prompt(state),
           {:ok, _} <-
             Adapters.record_session_observation(state.stored, %{state.runtime | state: "running"}) do
        request(
          %{state | phase: :prompting},
          "session/prompt",
          session_params(state, %{
            "prompt" => [%{"type" => "text", "text" => state.prompt}]
          })
        )
      end
    end)
  end

  defp admit_prompt(state) do
    case start_prompt(state) do
      {:ok, state} ->
        state

      {:error, reason} when reason in [:launch_busy, :launch_paused] ->
        Process.send_after(self(), :admit_prompt, 100)
        state

      {:error, reason} ->
        fail(state, reason)
    end
  end

  defp initialize(state) do
    case request(%{state | phase: :initializing}, "initialize", %{
           "protocolVersion" => 1,
           "clientInfo" => %{"name" => "cuckoding", "version" => "1"},
           "clientCapabilities" => %{
             "fs" => %{"readTextFile" => false, "writeTextFile" => false},
             "terminal" => false
           }
         }) do
      {:ok, state} -> state
      {:error, reason} -> fail(state, reason)
    end
  end

  defp reserve_prompt(state) do
    attrs = %{
      idempotency_key: "acp:prompt:#{state.request.attempt_id}",
      kind: "agent.prompt",
      target_type: "agent_session",
      target_id: state.stored.id,
      payload: %{"command_key" => state.request.idempotency_key}
    }

    with {:ok, command} <-
           Commands.execute_once(attrs, fn _command -> record_reservation(state) end),
         true <- command.result["client_session_id"] == state.runtime.session_id do
      :ok
    else
      false -> {:error, :acp_prompt_already_started}
      {:error, _} -> {:error, :acp_event_persistence_failed}
    end
  end

  defp record_reservation(state) do
    with {:ok, _} <-
           EventStore.append_in_transaction(state.request.run_id, %{
             event_type: "agent.prompt_started",
             public_summary: "ACP prompt started",
             payload: %{
               "agent_session_id" => state.stored.id,
               "stage_attempt_id" => state.request.attempt_id,
               "transport" => "acp"
             }
           }),
         do: {:ok, %{"client_session_id" => state.runtime.session_id}}
  end

  # Loading history is evidence replay, never new activity or new usage.
  defp update(%{phase: :loading} = state, _update), do: {:ok, state}
  defp update(state, %{"sessionUpdate" => "agent_thought_chunk"}), do: {:ok, state}

  defp update(state, %{"sessionUpdate" => kind})
       when kind in ["available_commands_update", "session_info_update"],
       do: {:ok, state}

  defp update(state, %{"sessionUpdate" => "current_mode_update", "currentModeId" => mode}) do
    if mode == state.launch.acp.mode, do: {:ok, state}, else: {:error, :acp_mode_changed}
  end

  defp update(state, %{"sessionUpdate" => "config_option_update", "configOptions" => options}),
    do: observe_configuration(state, options)

  defp update(%{phase: phase} = state, update) when phase in [:prompting, :cancelling],
    do: turn_update(state, update)

  defp update(_state, _update), do: {:error, :acp_update_outside_prompt}

  defp observe_configuration(state, options) when is_list(options) do
    expected = %{
      "mode" => state.launch.acp.mode,
      "model" => state.selected_model,
      "thought_level" => state.launch.acp[:reasoning_effort]
    }

    valid? =
      Enum.all?(options, fn
        %{"category" => category, "currentValue" => value} ->
          is_nil(expected[category]) or expected[category] == value

        option ->
          is_map(option)
      end)

    if valid? do
      observed =
        Enum.any?(
          options,
          &(&1["category"] == "model" and &1["currentValue"] == state.selected_model)
        )

      runtime =
        if observed,
          do: %{state.runtime | actual_model: state.selected_model},
          else: state.runtime

      {:ok, %{state | runtime: runtime}}
    else
      {:error, :acp_configuration_changed}
    end
  end

  defp observe_configuration(_state, _options), do: {:error, :acp_invalid_configuration}

  defp turn_update(
         state,
         %{
           "sessionUpdate" => "agent_message_chunk",
           "content" => %{"type" => "text", "text" => text}
         } = update
       )
       when is_binary(text) do
    with {:ok, state} <- message_boundary(state, update["messageId"]),
         true <- state.message_bytes + byte_size(text) <= @maximum_message,
         {:ok, state} <- responding(state) do
      {:ok,
       %{
         state
         | chunks: [text | state.chunks],
           message_bytes: state.message_bytes + byte_size(text),
           message_id: update["messageId"]
       }}
    else
      false -> {:error, :acp_message_too_large}
      error -> error
    end
  end

  defp turn_update(state, %{"sessionUpdate" => kind} = update)
       when kind in ["tool_call", "tool_call_update"] do
    with {:ok, state} <- flush_message(state),
         true <- safe_id?(update["toolCallId"], state.secrets) do
      status = update["status"] || "pending"

      type =
        case status do
          "pending" -> "tool.requested"
          "in_progress" -> "tool.started"
          "completed" -> "tool.completed"
          "failed" -> "tool.denied"
          _ -> nil
        end

      if type,
        do:
          record(
            state,
            type,
            "Agent tool #{status}",
            %{
              "tool_call_id" => update["toolCallId"],
              "status" => status
            }
            |> Map.merge(tool_metadata(update))
          ),
        else: {:error, :acp_invalid_tool_status}
    else
      false -> {:error, :acp_invalid_tool_call}
      error -> error
    end
  end

  defp turn_update(state, %{"sessionUpdate" => "usage_update", "used" => used, "size" => size})
       when is_integer(used) and used >= 0 and is_integer(size) and size > 0 do
    # Context occupancy is not billable token consumption; never add it to usage totals.
    record(state, "session.heartbeat", "Agent reported context usage", %{
      "context_used" => used,
      "context_size" => size
    })
  end

  defp turn_update(state, %{"sessionUpdate" => kind})
       when kind in [
              "plan",
              "available_commands_update",
              "user_message_chunk",
              "session_info_update"
            ],
       do: {:ok, state}

  defp turn_update(_state, _update), do: {:error, :acp_unsupported_update}

  defp tool_metadata(tool) when is_map(tool) do
    tool
    |> Map.take(["title", "kind"])
    |> Enum.filter(fn {_, value} -> is_binary(value) and byte_size(value) <= 500 end)
    |> Map.new()
  end

  defp tool_metadata(_tool), do: %{}

  defp message_boundary(%{message_id: id} = state, next) when id != next,
    do: flush_message(state)

  defp message_boundary(state, _id), do: {:ok, state}

  defp responding(%{message_bytes: 0} = state),
    do: record(state, "session.heartbeat", "Agent is responding", %{})

  defp responding(state), do: {:ok, state}

  defp flush_message(%{chunks: []} = state), do: {:ok, state}

  defp flush_message(state) do
    text =
      state.chunks |> Enum.reverse() |> IO.iodata_to_binary() |> Redactor.redact(state.secrets)

    summary = String.slice(text, 0, 10_000)

    with {:ok, state} <-
           record(
             state,
             "activity.summary",
             if(summary == "", do: "Agent sent an empty message", else: summary),
             %{}
           ) do
      {:ok, %{state | chunks: [], message_bytes: 0, message_id: nil, last_message: text}}
    end
  end

  defp record(%{sequence: sequence}, _type, _summary, _metadata) when sequence >= @maximum_events,
    do: {:error, :acp_event_limit}

  defp record(%{stored: nil}, _type, _summary, _metadata), do: {:error, :acp_session_not_bound}

  defp record(state, type, summary, metadata) do
    sequence = state.sequence + 1

    event = %Types.Event{
      event_id: "acp:#{state.runtime.session_id}:#{sequence}",
      sequence: sequence,
      type: type,
      public_summary: summary,
      metadata: Redactor.redact(metadata, state.secrets),
      trust: :untrusted
    }

    case ActivityStream.record(state.stored, event) do
      {:ok, _} -> {:ok, %{state | sequence: sequence}}
      {:error, _} -> {:error, :acp_event_persistence_failed}
    end
  end

  defp record_usage(state, result) do
    with {:ok, usage} <- usage(result["usage"]),
         {:ok, _} <-
           Accounting.record_usage(
             state.stored.id,
             "acp:#{state.runtime.session_id}:prompt",
             usage
           ),
         do: :ok
  end

  defp usage(nil), do: {:ok, Types.Usage.unavailable()}

  defp usage(raw) when is_map(raw) do
    fields = [
      {:input_tokens, "inputTokens"},
      {:output_tokens, "outputTokens"},
      {:cache_read_tokens, "cachedReadTokens"},
      {:cache_write_tokens, "cachedWriteTokens"}
    ]

    values = Map.new(fields, fn {key, field} -> {key, raw[field]} end)

    if Enum.all?(values, fn {_, value} ->
         is_nil(value) or (is_integer(value) and value in 0..9_223_372_036_854_775_807)
       end),
       do:
         {:ok,
          struct(Types.Usage, Map.merge(values, %{source: "provider", confidence: "reported"}))},
       else: {:error, :acp_invalid_usage}
  end

  defp usage(_raw), do: {:error, :acp_invalid_usage}

  defp request(state, method, params) do
    with {:ok, wire, _id, bytes} <- Wire.request(state.wire, method, params),
         do: write_request(%{state | wire: wire}, bytes)
  end

  # Negotiation is sequential: at most one bounded request waits for host resume.
  defp write_request(%{pending_write: nil} = state, bytes) do
    case state.runner.write(state.handle, bytes) do
      :ok -> {:ok, state}
      {:error, :protocol_paused} -> {:ok, %{state | pending_write: bytes}}
      error -> error
    end
  end

  defp write_request(_state, _bytes), do: {:error, :acp_request_pending}

  defp session_params(state, params),
    do: Map.put(params, "sessionId", state.runtime.external_session_id)

  defp cancel(%{phase: phase} = state) when phase in [:cancelling, :closing], do: state

  defp cancel(%{phase: :prompting} = state) do
    with {:ok, frame} <- Wire.notification("session/cancel", session_params(state, %{})),
         :ok <- state.runner.write(state.handle, frame) do
      arm_close(%{state | phase: :cancelling, error: state.error || :acp_cancelled})
    else
      {:error, :protocol_paused} -> fail(state, :acp_cancelled)
      _ -> fail(state, :acp_cancel_failed)
    end
  end

  defp cancel(state), do: fail(state, :acp_cancelled)

  defp close(state) do
    with :ok <- state.runner.close_input(state.handle),
         do: {:ok, arm_close(%{state | phase: :closing})}
  end

  defp arm_close(%{close_timer: nil} = state),
    do: %{state | close_timer: Process.send_after(self(), :close_timeout, 2_000)}

  defp arm_close(state), do: state

  defp fail(state, reason) do
    state.runner.close_input(state.handle)

    arm_close(%{
      state
      | phase: :closing,
        error: state.error || reason,
        pending_write: nil,
        chunks: [],
        message_bytes: 0
    })
  end

  defp finish(state, result) do
    outcome = persist_outcome(state, outcome(state, result))
    Registry.unregister(Cuckoding.RunRegistry, {:acp, state.request.run_id})
    if state.waiter, do: GenServer.reply(state.waiter, outcome)
    Enum.each(state.stop_waiters, &GenServer.reply(&1, result))
    {:stop, :normal, state}
  end

  defp persist_outcome(%{stored: nil}, outcome), do: outcome

  defp persist_outcome(state, outcome) do
    case EventStore.transaction(fn -> persist_terminal(state, outcome) end) do
      {:ok, outcome} -> outcome
      {:error, _} -> {:error, :acp_event_persistence_failed}
    end
  end

  defp persist_terminal(state, outcome) do
    outcome =
      if Repo.get!(AgentSession, state.stored.id).state == "cancelled",
        do: {:error, :acp_cancelled},
        else: outcome

    {type, status} =
      cond do
        outcome == {:error, :acp_cancelled} ->
          {"session.cancelled", "cancelled"}

        match?({:ok, _}, outcome) ->
          {"session.completed", "done"}

        true ->
          {"session.failed", "failed"}
      end

    with {:ok, _} <-
           record(state, type, "ACP session #{status}", %{
             "stop_reason" => state.stop_reason,
             "code" => outcome_code(outcome)
           }),
         {:ok, _} <-
           Adapters.record_session_observation(state.stored, %{state.runtime | state: status}) do
      outcome
    else
      _ -> Repo.rollback(:acp_event_persistence_failed)
    end
  end

  defp outcome_code({:ok, _}), do: nil
  defp outcome_code({:error, reason}) when is_atom(reason), do: Atom.to_string(reason)
  defp outcome_code({:error, {:acp_turn_stopped, reason}}), do: reason
  defp outcome_code(_), do: "acp_execution_failed"

  defp outcome(_state, {:error, _} = error), do: error
  defp outcome(%{error: error}, _result) when error != nil, do: {:error, error}
  defp outcome(_state, {:ok, %{timed_out?: true}}), do: {:error, :agent_timeout}

  defp outcome(
         %{stop_reason: "end_turn", last_message: text} = state,
         {:ok, result}
       )
       when is_binary(text) do
    with true <- result.exit_status == 0 or state.controlled_shutdown?,
         :ok <- Wire.finish(state.wire),
         {:ok, output} when is_map(output) <- Jason.decode(text) do
      {:ok,
       Map.merge(result, %{
         transport: :acp,
         stop_reason: "end_turn",
         protocol_completed?: true,
         structured_output: output
       })}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      false -> {:error, :acp_process_failed}
      _ -> {:error, :acp_invalid_structured_output}
    end
  end

  defp outcome(%{stop_reason: nil}, _result), do: {:error, :acp_unexpected_eof}
  defp outcome(%{stop_reason: reason}, _result), do: {:error, {:acp_turn_stopped, reason}}

  defp safe_id?(value, secrets) when is_binary(value) and byte_size(value) in 1..512,
    do: String.valid?(value) and Redactor.redact(value, secrets) == value

  defp safe_id?(_value, _secrets), do: false
end
