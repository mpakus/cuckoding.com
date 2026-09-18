defmodule Cuckoding.Power.MacOSClock do
  @moduledoc false

  @env "/usr/bin/env"
  @path "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
  @ruby "/usr/bin/ruby"
  @script "puts [Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond), Process.clock_gettime(Process::CLOCK_UPTIME_RAW, :millisecond)].join(',')"

  def sample do
    case System.cmd(@env, ["-i", @path, @ruby, "-e", @script], stderr_to_stdout: true) do
      {output, 0} -> parse(output)
      {_output, _status} -> {:error, :power_clock_unavailable}
    end
  end

  defp parse(output) do
    case output |> String.trim() |> String.split(",") |> Enum.map(&Integer.parse/1) do
      [{continuous, ""}, {uptime, ""}] -> {:ok, %{continuous_ms: continuous, uptime_ms: uptime}}
      _other -> {:error, :invalid_power_clock_sample}
    end
  end
end

defmodule Cuckoding.Power.Caffeinate do
  @moduledoc false

  alias Cuckoding.Execution.LocalHostInspector

  @env "/usr/bin/env"
  @path "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
  @caffeinate "/usr/bin/caffeinate"

  defmodule Handle do
    @moduledoc false
    defstruct [:port, :pid, :start_identity]
  end

  def hold(owner_pid, options \\ []) when is_binary(owner_pid) do
    args = ["-i", @path, @caffeinate, "-i"] ++ display_flag(options) ++ ["-w", owner_pid]

    port =
      Port.open({:spawn_executable, @env}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args
      ])

    with {:os_pid, pid} <- Port.info(port, :os_pid),
         {:ok, identity} <- await_identity(pid) do
      {:ok, %Handle{port: port, pid: pid, start_identity: identity}}
    else
      _error ->
        safe_close(port)
        {:error, :assertion_start_failed}
    end
  end

  def release(%Handle{} = handle) do
    result =
      case LocalHostInspector.process_identity(handle.pid, []) do
        {:ok, identity} when identity == handle.start_identity -> stop(handle)
        {:ok, _identity} -> {:error, :assertion_identity_mismatch}
        :gone -> :ok
        {:error, reason} -> {:error, reason}
      end

    safe_close(handle.port)
    result
  end

  defp stop(handle) do
    case System.cmd("/bin/kill", ["-TERM", Integer.to_string(handle.pid)], stderr_to_stdout: true) do
      {_output, 0} -> await_exit(handle, System.monotonic_time(:millisecond) + 1_000)
      {_output, _status} -> {:error, :assertion_stop_failed}
    end
  end

  defp await_exit(handle, deadline) do
    case LocalHostInspector.process_identity(handle.pid, []) do
      :gone ->
        :ok

      {:ok, identity} when identity != handle.start_identity ->
        :ok

      {:ok, _identity} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(20)
          await_exit(handle, deadline)
        else
          kill(handle)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp kill(handle) do
    case LocalHostInspector.process_identity(handle.pid, []) do
      {:ok, identity} when identity == handle.start_identity ->
        case System.cmd("/bin/kill", ["-KILL", Integer.to_string(handle.pid)],
               stderr_to_stdout: true
             ) do
          {_output, 0} -> :ok
          {_output, _status} -> {:error, :assertion_stop_failed}
        end

      :gone ->
        :ok

      _other ->
        {:error, :assertion_identity_mismatch}
    end
  end

  defp await_identity(pid, attempts \\ 100)
  defp await_identity(_pid, 0), do: {:error, :assertion_identity_unavailable}

  defp await_identity(pid, attempts) do
    case LocalHostInspector.process_identity(pid, []) do
      {:ok, identity} ->
        {:ok, identity}

      _other ->
        Process.sleep(10)
        await_identity(pid, attempts - 1)
    end
  end

  defp display_flag(options) do
    if Keyword.get(options, :prevent_display_sleep, false), do: ["-d"], else: []
  end

  defp safe_close(port) do
    if Port.info(port), do: Port.close(port)
  rescue
    ArgumentError -> :ok
  end
end

defmodule Cuckoding.Power.Manager do
  @moduledoc "Supervises the macOS idle-sleep assertion and durable wake reconciliation."

  use GenServer

  import Ecto.Query

  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.Reconciler
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Power
  alias Cuckoding.Power.Caffeinate
  alias Cuckoding.Power.MacOSClock
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Approval
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Task

  @active_attempt_states ~w(pending running waiting)
  @active_run_states ~w(queued running waiting paused hibernated blocked)
  @active_session_states ~w(created starting running waiting paused interrupted)
  @active_task_states ~w(ready running waiting paused hibernated blocked)

  def start_link(options) do
    options = Keyword.merge(Application.get_env(:cuckoding, :power_manager, []), options)
    name = Keyword.get(options, :name, __MODULE__)

    if name,
      do: GenServer.start_link(__MODULE__, options, name: name),
      else: GenServer.start_link(__MODULE__, options)
  end

  def tick(server \\ __MODULE__), do: GenServer.call(server, :tick, :infinity)
  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  def project_idle?(project_id) when is_binary(project_id) do
    not Repo.exists?(
      from(attempt in StageAttempt,
        join: run in Run,
        on: run.id == attempt.run_id,
        join: task in Task,
        on: task.id == run.task_id,
        join: board in Board,
        on: board.id == task.board_id,
        where:
          board.project_id == ^project_id and run.state in ^@active_run_states and
            attempt.state in ^@active_attempt_states
      )
    )
  end

  def project_idle?(_project_id), do: false

  @impl true
  def init(options) do
    state = %{
      assertion: nil,
      assertion_module: Keyword.get(options, :assertion_module, Caffeinate),
      clock: Keyword.get(options, :clock, MacOSClock),
      enabled?: Keyword.get(options, :enabled, true),
      last_error: nil,
      pending_reconciliation: nil,
      previous_sample: nil,
      prevent_display_sleep?: Keyword.get(options, :prevent_display_sleep, false),
      reconciler: Keyword.get(options, :reconciler, Reconciler),
      tick_ms: Keyword.get(options, :tick_ms, 5_000),
      tolerance_ms: Keyword.get(options, :tolerance_ms, 1_000)
    }

    schedule(state)
    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, public_status(state), state}

  def handle_call(:tick, _from, state) do
    {result, updated} = do_tick(state)
    {:reply, result, updated}
  end

  @impl true
  def handle_info(:tick, state) do
    {_result, updated} = do_tick(state)
    schedule(updated)
    {:noreply, updated}
  end

  def handle_info({port, {:exit_status, status}}, %{assertion: %{port: port}} = state) do
    {:ok, _event} =
      power_event("assertion_off", eligible_run_ids(), %{
        "exit_status" => status,
        "reason" => "process_exited"
      })

    {:noreply, %{state | assertion: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{assertion: nil}), do: :ok

  def terminate(_reason, state), do: release(state.assertion_module, state.assertion)

  def gap_ms(previous, current, tolerance_ms) do
    continuous_elapsed = current.continuous_ms - previous.continuous_ms
    uptime_elapsed = current.uptime_ms - previous.uptime_ms
    gap = continuous_elapsed - uptime_elapsed
    if gap > tolerance_ms, do: gap, else: 0
  end

  defp do_tick(%{enabled?: false} = state), do: {{:ok, public_status(state)}, state}

  defp do_tick(state) do
    case sample(state.clock) do
      {:ok, sample} -> sampled_tick(state, sample)
      {:error, reason} -> {{:error, reason}, %{state | last_error: reason}}
    end
  end

  defp sampled_tick(state, sample) do
    gap = detected_gap(state.previous_sample, sample, state.tolerance_ms)
    sampled = %{state | previous_sample: sample}

    case prepare_gap(sampled, gap) do
      {:ok, prepared} -> finish_sample(prepared)
      {:error, reason} -> {{:error, reason}, %{sampled | last_error: reason}}
    end
  end

  defp detected_gap(nil, _sample, _tolerance), do: 0
  defp detected_gap(previous, sample, tolerance), do: gap_ms(previous, sample, tolerance)

  defp prepare_gap(%{pending_reconciliation: pending} = state, _gap) when not is_nil(pending),
    do: {:ok, state}

  defp prepare_gap(state, 0), do: {:ok, state}

  defp prepare_gap(state, gap) do
    run_ids = active_run_ids()

    with {:ok, event} <- power_event("sleep_gap", run_ids, %{}, gap) do
      {:ok,
       %{
         state
         | pending_reconciliation: %{event_id: event.id, gap_ms: gap, run_ids: run_ids}
       }}
    end
  end

  defp finish_sample(state) do
    case reconcile_pending(state) do
      {:ok, reconciled} ->
        case sync_assertion(%{reconciled | last_error: nil}) do
          {:ok, synced} -> {{:ok, public_status(synced)}, synced}
          {:error, reason} -> {{:error, reason}, %{reconciled | last_error: reason}}
        end

      {:error, reason} ->
        {{:error, reason}, %{state | last_error: reason}}
    end
  end

  defp reconcile_pending(%{pending_reconciliation: nil} = state), do: {:ok, state}

  defp reconcile_pending(%{pending_reconciliation: pending} = state) do
    options = [
      gap_ms: pending.gap_ms,
      cycle_id: "sleep:#{pending.event_id}",
      run_ids: pending.run_ids
    ]

    with {:ok, summary} <- reconcile(state.reconciler, options),
         {:ok, _event} <-
           power_event(
             "wake_reconciled",
             pending.run_ids,
             reconciliation_metadata(summary),
             pending.gap_ms
           ) do
      {:ok, %{state | pending_reconciliation: nil}}
    end
  end

  defp sync_assertion(state) do
    reasons = assertion_reasons()

    cond do
      reasons == %{run_ids: [], board_ids: []} and state.assertion ->
        release_assertion(state)

      reasons != %{run_ids: [], board_ids: []} and is_nil(state.assertion) ->
        hold_assertion(state, reasons)

      true ->
        {:ok, state}
    end
  end

  defp hold_assertion(state, reasons) do
    options = [prevent_display_sleep: state.prevent_display_sleep?]

    with {:ok, assertion} <- hold(state.assertion_module, System.pid(), options),
         {:ok, _event} <-
           power_event("assertion_on", reasons.run_ids, %{
             "assertion_pid" => assertion.pid,
             "unattended_board_ids" => reasons.board_ids
           }) do
      {:ok, %{state | assertion: assertion}}
    end
  end

  defp release_assertion(state) do
    with :ok <- release(state.assertion_module, state.assertion),
         {:ok, _event} <-
           power_event("assertion_off", [], %{
             "assertion_pid" => state.assertion.pid,
             "reason" => "no_eligible_work"
           }) do
      {:ok, %{state | assertion: nil}}
    end
  end

  defp assertion_reasons do
    %{run_ids: eligible_run_ids(), board_ids: unattended_board_ids()}
  end

  defp eligible_run_ids do
    candidates =
      Repo.all(
        from(run in Run,
          join: attempt in StageAttempt,
          on: attempt.run_id == run.id,
          join: session in AgentSession,
          on: session.stage_attempt_id == attempt.id,
          where:
            run.state in ["running", "waiting"] and
              attempt.state in ^@active_attempt_states and
              session.state in ^@active_session_states,
          distinct: true,
          select: {run.id, run.state}
        )
      )

    waiting_ids = for {id, "waiting"} <- candidates, do: id

    pending_approval_ids =
      Repo.all(
        from(approval in Approval,
          where: approval.run_id in ^waiting_ids and approval.decision == "pending",
          select: approval.run_id
        )
      )
      |> MapSet.new()

    for {id, state} <- candidates,
        state == "running" or not MapSet.member?(pending_approval_ids, id),
        do: id
  end

  defp unattended_board_ids do
    now = Cuckoding.Clock.wall_now()

    Repo.all(
      from(board in Board,
        join: task in Task,
        on: task.board_id == board.id,
        where:
          board.status == "active" and board.unattended_until > ^now and
            task.state in ^@active_task_states,
        distinct: true,
        select: board.id
      )
    )
  end

  defp active_run_ids do
    Repo.all(
      from(run in Run,
        where: run.state in ^@active_run_states,
        order_by: run.id,
        select: run.id
      )
    )
  end

  defp reconciliation_metadata(summary) do
    %{
      "extended_leases" => summary.extended_leases,
      "expired_lease_ids" => Enum.map(summary.expired_leases, & &1.id),
      "recovered_commands" => summary.recovered_commands,
      "dispatched_commands" => summary.dispatched_commands
    }
  end

  defp power_event(kind, run_ids, metadata, gap_ms \\ nil) do
    Power.record_event(%{
      kind: kind,
      gap_ms: gap_ms,
      affected_runs_json: run_ids,
      metadata_json: metadata
    })
  end

  defp public_status(state) do
    %{
      assertion_held?: not is_nil(state.assertion),
      assertion_pid: if(state.assertion, do: state.assertion.pid),
      enabled?: state.enabled?,
      last_error: state.last_error,
      wake_reconciliation_pending?: not is_nil(state.pending_reconciliation)
    }
  end

  defp schedule(%{enabled?: true, tick_ms: milliseconds}) when is_integer(milliseconds) do
    Process.send_after(self(), :tick, milliseconds)
  end

  defp schedule(_state), do: :ok

  defp sample(clock) when is_function(clock, 0), do: clock.()
  defp sample(clock), do: clock.sample()

  defp reconcile(callback, options) when is_function(callback, 1), do: callback.(options)
  defp reconcile(module, options), do: module.run(options)

  defp hold(%{hold: callback}, owner_pid, options), do: callback.(owner_pid, options)
  defp hold(module, owner_pid, options), do: module.hold(owner_pid, options)

  defp release(%{release: callback}, assertion), do: callback.(assertion)
  defp release(module, assertion), do: module.release(assertion)
end
