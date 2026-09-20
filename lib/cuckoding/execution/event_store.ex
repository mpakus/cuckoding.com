defmodule Cuckoding.Execution.EventStore do
  @moduledoc """
  Appends strictly sequenced run events in the same transaction as a caller's projection write.
  """

  import Ecto.Query
  require Logger

  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Execution.RunEventSequence
  alias Cuckoding.Repo
  alias Cuckoding.Security.Redactor

  @collector_key {__MODULE__, :events_after_commit}
  @begin_retries 2

  def append(run_id, attrs, projection \\ fn _repo, _sequence -> {:ok, nil} end)
      when is_binary(run_id) and is_map(attrs) and is_function(projection, 2) do
    transaction(fn ->
      case append_in_transaction(run_id, attrs, projection) do
        {:ok, result} -> result
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Runs a transaction and broadcasts every collected event only after a successful commit."
  def transaction(callback) when is_function(callback, 0) do
    if Repo.in_transaction?() do
      Repo.transaction(callback)
    else
      collect_after_commit(callback)
    end
  end

  def append_in_transaction(run_id, attrs, projection \\ fn _repo, _sequence -> {:ok, nil} end)
      when is_binary(run_id) and is_map(attrs) and is_function(projection, 2) do
    if Repo.in_transaction?() do
      sequence = next_sequence(run_id)

      with {:ok, projection_value} <- projection_result(projection, sequence),
           event_attrs = event_attrs(run_id, sequence, attrs),
           {:ok, event} <- Repo.insert(RunEvent.changeset(%RunEvent{}, event_attrs)),
           :ok <- collect(event) do
        {:ok, {event, projection_value}}
      end
    else
      {:error, :transaction_required}
    end
  end

  defp projection_result(projection, sequence) do
    case projection.(Repo, sequence) do
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, {:projection_failed, reason}}
    end
  end

  defp event_attrs(run_id, sequence, attrs) do
    attrs =
      attrs
      |> Map.put_new(:payload, %{})
      |> Map.update(:public_summary, nil, &Redactor.redact/1)
      |> Map.update!(:payload, &Redactor.redact/1)

    correlation = Cuckoding.ActivityStream.correlation(run_id, attrs.payload)

    attrs
    |> Map.put(:run_id, run_id)
    |> Map.put(:sequence, sequence)
    |> Map.update!(:payload, &Map.put(&1, "correlation", correlation))
    |> Map.put_new(:occurred_at, Cuckoding.Clock.wall_now())
  end

  defp collect_after_commit(callback) do
    retry_locked_begin(fn -> collect_once(callback) end, @begin_retries)
  end

  defp collect_once(callback) do
    previous = Process.get(@collector_key)
    Process.put(@collector_key, [])

    try do
      result = Repo.transaction(callback)
      events = Process.get(@collector_key, [])

      if match?({:ok, _value}, result), do: Enum.each(Enum.reverse(events), &broadcast/1)
      result
    after
      if is_nil(previous),
        do: Process.delete(@collector_key),
        else: Process.put(@collector_key, previous)
    end
  end

  defp retry_locked_begin(callback, retries) do
    callback.()
  rescue
    error in Exqlite.Error ->
      if retries > 0 and error.message == "database is locked" and
           error.statement == "BEGIN IMMEDIATE TRANSACTION" do
        Logger.warning("event transaction begin was busy; retrying")
        Process.sleep(10)
        retry_locked_begin(callback, retries - 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  defp collect(event) do
    case Process.get(@collector_key) do
      events when is_list(events) ->
        Process.put(@collector_key, [event | events])
        :ok

      nil ->
        {:error, :event_transaction_required}
    end
  end

  defp broadcast(event) do
    message = {:activity_event, event.run_id, event.sequence}

    ["activity", "activity:#{event.run_id}"]
    |> Enum.each(&safe_broadcast(&1, message))
  end

  defp safe_broadcast(topic, message) do
    Phoenix.PubSub.broadcast(Cuckoding.PubSub, topic, message)
  catch
    :exit, reason ->
      Logger.warning("activity broadcast unavailable topic=#{topic} reason=#{inspect(reason)}")
  end

  defp next_sequence(run_id) do
    Repo.insert!(%RunEventSequence{run_id: run_id}, on_conflict: :nothing)

    {1, nil} =
      Repo.update_all(
        from(sequence in RunEventSequence, where: sequence.run_id == ^run_id),
        inc: [last_sequence: 1]
      )

    Repo.get!(RunEventSequence, run_id).last_sequence
  end
end
