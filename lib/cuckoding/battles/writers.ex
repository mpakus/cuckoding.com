defmodule Cuckoding.Battles.Writers do
  @moduledoc "Cumulative edits from exact immutable successful writer attempts."
  import Ecto.Query
  alias Cuckoding.Battles.{Attempt, Receipts, Stages}
  alias Cuckoding.Repo

  def files(attempt) do
    if Stages.writers?(attempt.request["snapshot"]),
      do: checkpoint_files(attempt),
      else: legacy_files(attempt.request["task_context"]["provider"])
  end

  defp legacy_files(provider) do
    if provider["status"] == "task_finished" and provider["access"] == "write" and
         is_list(provider["changes"]),
       do: {:ok, provider["changes"]},
       else: {:error, "missing_edit_evidence"}
  end

  defp checkpoint_files(attempt) do
    snapshot = attempt.request["snapshot"]
    context = attempt.request["task_context"]
    writers = Enum.filter(Stages.pipeline(snapshot), &(Stages.access(snapshot, &1) == "write"))
    through = Enum.find_index(writers, &(&1 == context["writer_stage"]))
    expected = if is_integer(through), do: Enum.take(writers, through + 1), else: []
    attempts = writer_attempts(attempt, writers, context["preparation"]["key"])

    if expected != [] and Enum.sort(Enum.map(attempts, & &1.stage)) == Enum.sort(expected) and
         Enum.all?(attempts, &valid?(&1, attempt)) do
      files = cumulative_files(expected, attempts)
      if length(files) <= 64, do: {:ok, files}, else: {:error, "writer_file_limit"}
    else
      {:error, "missing_edit_evidence"}
    end
  end

  defp writer_attempts(attempt, writers, preparation) do
    if match?({:ok, ^preparation}, Ecto.UUID.cast(preparation)) do
      Repo.all(
        from a in Attempt,
          where:
            a.battle_id == ^attempt.battle_id and a.task_id == ^attempt.task_id and
              a.state == "completed" and a.stage in ^writers and
              fragment("json_extract(?, '$.task_context.preparation.key')", a.request) ==
                ^preparation,
          limit: 6
      )
    else
      []
    end
  end

  defp cumulative_files(stages, attempts) do
    Enum.reduce(stages, %{}, fn stage, files ->
      writer = Enum.find(attempts, &(&1.stage == stage))
      Enum.reduce(writer.result["provider"]["changes"], files, &Map.put(&2, &1["path"], &1))
    end)
    |> Map.values()
    |> Enum.sort_by(& &1["path"])
  end

  defp valid?(attempt, capture) do
    result = attempt.result

    same_scope?(attempt.request, capture.request) and result["status"] == "completed" and
      result["cleanup_verified"] == true and
      Stages.role(attempt.request["snapshot"], attempt.stage) == attempt.role and
      Receipts.bound?(attempt, result) and Receipts.provider_valid?(attempt, result) and
      result["provider"]["access"] == "write" and is_list(result["provider"]["changes"])
  end

  defp same_scope?(writer, capture),
    do:
      writer["snapshot"] == capture["snapshot"] and writer["task"] == capture["task"] and
        writer["task_context"]["preparation"] == capture["task_context"]["preparation"]
end
