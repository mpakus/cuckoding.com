defmodule Cuckoding.Execution.EventStore do
  @moduledoc """
  Appends strictly sequenced run events in the same transaction as a caller's projection write.
  """

  import Ecto.Query

  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Execution.RunEventSequence
  alias Cuckoding.Repo

  def append(run_id, attrs, projection \\ fn _repo, _sequence -> {:ok, nil} end)
      when is_binary(run_id) and is_map(attrs) and is_function(projection, 2) do
    Repo.transaction(fn ->
      case append_in_transaction(run_id, attrs, projection) do
        {:ok, result} -> result
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def append_in_transaction(run_id, attrs, projection \\ fn _repo, _sequence -> {:ok, nil} end)
      when is_binary(run_id) and is_map(attrs) and is_function(projection, 2) do
    if Repo.in_transaction?() do
      sequence = next_sequence(run_id)

      with {:ok, projection_value} <- projection_result(projection, sequence),
           event_attrs = event_attrs(run_id, sequence, attrs),
           {:ok, event} <- Repo.insert(RunEvent.changeset(%RunEvent{}, event_attrs)) do
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
    attrs
    |> Map.put(:run_id, run_id)
    |> Map.put(:sequence, sequence)
    |> Map.put_new(:payload, %{})
    |> Map.put_new(:occurred_at, Cuckoding.Clock.wall_now())
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
