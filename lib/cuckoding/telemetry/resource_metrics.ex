defmodule Cuckoding.Telemetry.MetricCollector do
  @moduledoc "Replaceable host-resource sampling boundary."

  @callback sample(struct(), keyword()) :: {:ok, map()} | :missing | {:error, term()}
end

defmodule Cuckoding.Telemetry.LocalMetricCollector do
  @moduledoc "Reads metrics only for a recorded process whose start identity still matches."
  @behaviour Cuckoding.Telemetry.MetricCollector

  alias Cuckoding.Execution.LocalHostInspector

  @impl true
  def sample(process, options) do
    inspector = Keyword.get(options, :inspector, LocalHostInspector)

    case inspector.resource_sample(process) do
      {:ok, %{status: :matching} = sample} -> {:ok, Map.delete(sample, :status)}
      {:ok, %{status: :gone}} -> :missing
      {:error, reason} -> {:error, reason}
    end
  end
end

defmodule Cuckoding.Telemetry.ResourceSampler do
  @moduledoc "Samples active recorded process groups without inventing missing measurements."

  use GenServer
  import Ecto.Query

  alias Cuckoding.Execution.ProcessRecord
  alias Cuckoding.Identifier
  alias Cuckoding.Repo
  alias Cuckoding.Telemetry.LocalMetricCollector
  alias Cuckoding.Telemetry.ResourceRollups
  alias Cuckoding.Telemetry.ResourceSample

  @default_interval 3_000
  @maintenance_interval 60_000

  def start_link(options) do
    options = Keyword.merge(Application.get_env(:cuckoding, :resource_sampler, []), options)

    if Keyword.get(options, :enabled, true) do
      GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))
    else
      :ignore
    end
  end

  def sample_now(collector \\ LocalMetricCollector, options \\ []) do
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())

    samples =
      ProcessRecord
      |> where([process], process.state == "running" and not is_nil(process.agent_session_id))
      |> order_by([process], asc: process.id)
      |> Repo.all()
      |> Enum.map(&sample(&1, collector, options, now))

    {:ok,
     %{
       recorded: Enum.count(samples, &match?({:ok, _sample}, &1)),
       missing: Enum.count(samples, &match?({:missing, _process_id}, &1)),
       errors: for({:error, process_id, reason} <- samples, do: {process_id, reason})
     }}
  end

  @impl true
  def init(options) do
    interval = Keyword.get(options, :interval_ms, @default_interval)

    if interval in 2_000..5_000 do
      schedule(:sample, interval)
      schedule(:maintain, @maintenance_interval)

      {:ok,
       %{interval: interval, collector: Keyword.get(options, :collector, LocalMetricCollector)}}
    else
      {:stop, :invalid_sampling_interval}
    end
  end

  @impl true
  def handle_info(:sample, state) do
    sample_now(state.collector)
    schedule(:sample, state.interval)
    {:noreply, state}
  end

  def handle_info(:maintain, state) do
    ResourceRollups.maintain()
    schedule(:maintain, @maintenance_interval)
    {:noreply, state}
  end

  defp sample(process, collector, options, now) do
    case collector.sample(process, options) do
      {:ok, metrics} -> insert(process, metrics, now)
      :missing -> {:missing, process.id}
      {:error, reason} -> {:error, process.id, reason}
    end
  end

  defp insert(process, metrics, now) do
    attrs =
      metrics
      |> Map.take([:cpu_nanos, :memory_bytes, :process_count, :open_ports_json])
      |> Map.merge(%{
        id: Identifier.generate(),
        agent_session_id: process.agent_session_id,
        process_id: process.id,
        sampled_at: now,
        limits_enforced: false
      })

    %ResourceSample{}
    |> ResourceSample.create_changeset(attrs)
    |> Repo.insert()
  end

  defp schedule(message, interval), do: Process.send_after(self(), message, interval)
end

defmodule Cuckoding.Telemetry.ResourceRollups do
  @moduledoc "Builds replaceable minute and stage rollups from measured resource rows only."

  import Ecto.Query

  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Identifier
  alias Cuckoding.Repo
  alias Cuckoding.Telemetry.MetricRollup
  alias Cuckoding.Telemetry.ResourceSample

  @replace_fields ~w(sample_count cpu_nanos average_memory_bytes maximum_memory_bytes maximum_process_count open_ports_json active_ms wall_ms limits_enforced computed_at)a
  @raw_retention_seconds 7 * 24 * 60 * 60
  @rollup_retention_seconds 30 * 24 * 60 * 60

  def maintain(options \\ []) do
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())
    bucket_start = now |> minute_start() |> DateTime.add(-60, :second)
    bucket_end = DateTime.add(bucket_start, 60, :second)

    minute_results =
      from(sample in ResourceSample,
        where: sample.sampled_at >= ^bucket_start and sample.sampled_at < ^bucket_end,
        distinct: true,
        select: sample.agent_session_id
      )
      |> Repo.all()
      |> Enum.map(&minute(&1, bucket_start, now: now))

    stage_results =
      from(attempt in StageAttempt,
        join: session in AgentSession,
        on: session.stage_attempt_id == attempt.id,
        join: sample in ResourceSample,
        on: sample.agent_session_id == session.id,
        left_join: rollup in MetricRollup,
        on:
          rollup.scope_type == "stage_attempt" and rollup.scope_id == attempt.id and
            rollup.window == "stage",
        where: not is_nil(attempt.finished_at) and is_nil(rollup.id),
        distinct: true,
        select: attempt.id
      )
      |> Repo.all()
      |> Enum.map(&stage(&1, now: now))

    {:ok, deleted} =
      prune(
        DateTime.add(now, -@raw_retention_seconds, :second),
        DateTime.add(now, -@rollup_retention_seconds, :second)
      )

    {:ok,
     %{
       minute_rollups: Enum.count(minute_results, &match?({:ok, %MetricRollup{}}, &1)),
       stage_rollups: Enum.count(stage_results, &match?({:ok, %MetricRollup{}}, &1)),
       deleted: deleted
     }}
  end

  def minute(agent_session_id, bucket_start, options \\ []) do
    bucket_start = minute_start(bucket_start)
    bucket_end = DateTime.add(bucket_start, 60, :second)

    samples =
      Repo.all(
        from(sample in ResourceSample,
          where:
            sample.agent_session_id == ^agent_session_id and
              sample.sampled_at >= ^bucket_start and sample.sampled_at < ^bucket_end,
          order_by: [asc: sample.sampled_at, asc: sample.id]
        )
      )

    rollup("agent_session", agent_session_id, "minute", bucket_start, samples, nil, options)
  end

  def stage(stage_attempt_id, options \\ []) do
    case Repo.get(StageAttempt, stage_attempt_id) do
      %StageAttempt{} = attempt -> stage_rollup(attempt, options)
      nil -> {:error, :stage_attempt_not_found}
    end
  end

  defp stage_rollup(attempt, options) do
    session_ids =
      Repo.all(
        from(session in AgentSession,
          where: session.stage_attempt_id == ^attempt.id,
          select: session.id
        )
      )

    samples =
      Repo.all(
        from(sample in ResourceSample,
          where: sample.agent_session_id in ^session_ids,
          order_by: [asc: sample.sampled_at, asc: sample.id]
        )
      )

    timing = %{active_ms: attempt.active_ms, wall_ms: attempt.wall_ms}
    bucket_start = attempt.started_at || attempt.inserted_at
    rollup("stage_attempt", attempt.id, "stage", bucket_start, samples, timing, options)
  end

  def prune_raw(before) when is_struct(before, DateTime) do
    {count, _rows} =
      Repo.delete_all(from(sample in ResourceSample, where: sample.sampled_at < ^before))

    {:ok, count}
  end

  def prune(raw_before, rollup_before)
      when is_struct(raw_before, DateTime) and is_struct(rollup_before, DateTime) do
    Repo.transaction(fn ->
      {raw_count, _rows} =
        Repo.delete_all(from(sample in ResourceSample, where: sample.sampled_at < ^raw_before))

      {rollup_count, _rows} =
        Repo.delete_all(from(rollup in MetricRollup, where: rollup.computed_at < ^rollup_before))

      %{raw_samples: raw_count, rollups: rollup_count}
    end)
  end

  defp rollup(_scope_type, _scope_id, _window, _bucket, [], _timing, _options),
    do: {:ok, :missing}

  defp rollup(scope_type, scope_id, window, bucket, samples, timing, options) do
    now = Keyword.get(options, :now, Cuckoding.Clock.wall_now())
    attrs = aggregate(scope_type, scope_id, window, bucket, samples, timing, now)
    changeset = MetricRollup.changeset(%MetricRollup{}, attrs)

    Repo.insert(changeset,
      on_conflict: {:replace, @replace_fields},
      conflict_target: [:scope_type, :scope_id, :window, :bucket_start],
      returning: true
    )
  end

  defp aggregate(scope_type, scope_id, window, bucket, samples, timing, now) do
    memory = Enum.map(samples, & &1.memory_bytes)

    %{
      id: Identifier.generate(),
      scope_type: scope_type,
      scope_id: scope_id,
      window: window,
      bucket_start: bucket,
      sample_count: length(samples),
      cpu_nanos: cpu_delta(samples),
      average_memory_bytes: div(Enum.sum(memory), length(memory)),
      maximum_memory_bytes: Enum.max(memory),
      maximum_process_count: samples |> Enum.map(& &1.process_count) |> Enum.max(),
      open_ports_json:
        samples |> Enum.flat_map(& &1.open_ports_json) |> Enum.uniq() |> Enum.sort(),
      active_ms: timing && timing.active_ms,
      wall_ms: timing && timing.wall_ms,
      limits_enforced: false,
      computed_at: now
    }
  end

  defp cpu_delta(samples) do
    samples
    |> Enum.group_by(& &1.process_id)
    |> Enum.reduce(0, fn {_process_id, process_samples}, total ->
      values = Enum.map(process_samples, & &1.cpu_nanos)
      total + max(Enum.max(values) - Enum.min(values), 0)
    end)
  end

  defp minute_start(datetime), do: datetime |> DateTime.truncate(:second) |> Map.put(:second, 0)
end
