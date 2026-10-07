defmodule Cuckoding.BoardControl.GoalReview do
  @moduledoc "Final criterion assessment bound to host checks and the authorized goal."
  import Ecto.Query
  alias Cuckoding.BoardControl.{GoalChecks, Plans}
  alias Cuckoding.Execution.{EventStore, Run, RunEvent}
  alias Cuckoding.Repo

  def latest(id) do
    Repo.one(
      from event in RunEvent,
        join: run in Run,
        on: event.run_id == run.id,
        where: run.board_execution_id == ^id and event.event_type == "goal.reviewed",
        order_by: [desc: event.occurred_at, desc: event.sequence],
        limit: 1,
        select: event.payload
    )
  end

  def accept(e, run, input, output) do
    with :ok <- Plans.envelope(output, input, ~w(criteria execution_id head_sha revision summary)),
         true <- output["head_sha"] == e.head_sha,
         true <- valid_criteria?(output["criteria"], Plans.goal(e)["criteria"]),
         :ok <- GoalChecks.verify(e, run, input["checks"]),
         {:ok, clean} <- GoalChecks.candidate(e, run) do
      passed =
        clean and GoalChecks.passed?(input["checks"]) and
          Enum.all?(output["criteria"], &(&1["verdict"] == "pass"))

      evidence =
        Map.merge(output, %{
          "checks" => input["checks"],
          "candidate_clean" => clean,
          "passed" => passed,
          "authorization_digest" => e.delivery_authorization_json["digest"],
          "run_id" => run.id
        })

      {:ok, _} =
        EventStore.append(run.id, %{
          event_type: "goal.reviewed",
          public_summary: "Final goal review recorded",
          payload: evidence
        })

      {:ok, next(e, passed)}
    else
      false -> {:error, :invalid_final_goal_review}
      error -> error
    end
  end

  defp valid_criteria?(assessments, expected) when is_list(assessments) do
    Enum.all?(assessments, fn
      %{"id" => id, "verdict" => verdict, "evidence" => evidence} = assessment ->
        map_size(assessment) == 3 and is_binary(id) and verdict in ~w(pass revise) and
          is_binary(evidence) and byte_size(evidence) in 1..2_000 and String.trim(evidence) != ""

      _ ->
        false
    end) and
      Enum.sort(Enum.map(assessments, & &1["id"])) == Enum.sort(Enum.map(expected, & &1["id"]))
  end

  defp valid_criteria?(_, _), do: false

  defp next(_e, true),
    do: %{state: "done", current_run_id: nil, finished_at: Cuckoding.Clock.wall_now(), issue: nil}

  defp next(e, false) do
    if e.plan_cycle < e.snapshot_json["autonomy"]["limits"]["revisions"],
      do: %{
        phase: "planning",
        state: "running",
        current_run_id: nil,
        plan_cycle: e.plan_cycle + 1
      },
      else: %{state: "attention", current_run_id: nil, issue: "goal_repair_limit"}
  end
end
