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
      sequence = next_sequence(run_id)

      projection_value =
        case projection.(Repo, sequence) do
          {:ok, value} -> value
          {:error, reason} -> Repo.rollback({:projection_failed, reason})
        end

      event_attrs =
        attrs
        |> Map.put(:run_id, run_id)
        |> Map.put(:sequence, sequence)
        |> Map.put_new(:payload, %{})
        |> Map.put_new(:occurred_at, Cuckoding.Clock.wall_now())

      case Repo.insert(RunEvent.changeset(%RunEvent{}, event_attrs)) do
        {:ok, event} -> {event, projection_value}
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
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
