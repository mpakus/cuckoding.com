defmodule Cuckoding.BoardControl.Decision do
  @moduledoc "One bounded, read-only Speculator decision using the normal stage runtime."
  alias Cuckoding.{AgentRuntime, BoardControl, Repo, RunControl, WalkingSkeleton}
  alias Cuckoding.Execution.Run

  def start(run_id, options \\ []) do
    options = Keyword.put(options, :board_controller, true)

    with {:ok, skeleton} <- WalkingSkeleton.load(run_id),
         "queued" <- skeleton.run.state,
         true <- BoardControl.controller?(skeleton.run),
         {:ok, runtime} <- AgentRuntime.resolve(skeleton, role(skeleton.run)),
         {:ok, _} <- RunControl.admit(run_id, fn -> mark_running(run_id) end, options) do
      launch(skeleton, runtime, options)
    else
      false -> {:error, :not_board_controller}
      state when is_binary(state) -> {:error, :run_not_queued}
      error -> error
    end
  end

  defp mark_running(id) do
    case Cuckoding.Execution.transition_run(
           id,
           "running",
           "board:#{id}:start:#{Cuckoding.Identifier.generate()}"
         ) do
      {:ok, %{result: %{"outcome" => "transitioned"}}} = result -> result
      _ -> {:error, :transition_rejected}
    end
  end

  defp launch(skeleton, runtime, options) do
    work = fn ->
      RunControl.track(skeleton.run.id, :workflow, fn -> run(skeleton, runtime, options) end)
    end

    if options[:async] == false,
      do: work.(),
      else: Task.Supervisor.start_child(Cuckoding.GuidedRunSupervisor, work)
  end

  defp run(skeleton, runtime, options) do
    run = Repo.get!(Run, skeleton.run.id)
    e = BoardControl.get(run.board_execution_id)

    with {:ok, input} <- BoardControl.decision_input(e),
         {:ok, output} <-
           WalkingSkeleton.control_stage(%{skeleton | run: run}, runtime, input, options) do
      BoardControl.accept_decision(run.id, input, output)
    end
  end

  def validate(output, input, next) when is_map(output) do
    if valid_envelope?(output, input) and valid_action?(output, input, next),
      do: :ok,
      else: {:error, :invalid_controller_output}
  end

  def validate(_, _, _), do: {:error, :invalid_controller_output}

  defp valid_envelope?(output, input) do
    Enum.sort(Map.keys(output)) == ~w(action execution_id revision summary task_id) and
      output["execution_id"] == input["execution_id"] and
      is_integer(output["revision"]) and
      output["revision"] == input["revision"] and
      is_binary(output["summary"]) and String.trim(output["summary"]) != "" and
      byte_size(output["summary"]) <= 2000
  end

  defp valid_action?(%{"action" => "start_task", "task_id" => id}, _input, %{task_id: id}),
    do: true

  defp valid_action?(%{"action" => "finish", "task_id" => nil}, _input, nil), do: true

  defp valid_action?(%{"action" => "block", "task_id" => id}, _input, next),
    do: id == (next && next.task_id)

  defp valid_action?(
         %{"action" => "replan", "task_id" => nil},
         %{"mode" => "autonomous_goal"},
         _next
       ),
       do: true

  defp valid_action?(%{"action" => "ask", "task_id" => id}, %{"mode" => "autonomous_goal"}, next),
    do: id in [nil, next && next.task_id]

  defp valid_action?(
         %{"action" => "recover", "task_id" => id},
         %{"mode" => "autonomous_goal"} = input,
         _next
       ),
       do: Enum.any?(input["members"], &(&1["task_id"] == id and &1["state"] == "blocked"))

  defp valid_action?(_, _, _), do: false

  def role(run), do: hd(run.workflow_snapshot_json["definition"]["stages"])["role"]

  def schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(action execution_id revision summary task_id),
      "properties" => %{
        "action" => %{"type" => "string", "enum" => ~w(start_task block finish)},
        "execution_id" => %{"type" => "string"},
        "revision" => %{"type" => "integer"},
        "summary" => %{"type" => "string", "minLength" => 1, "maxLength" => 2000},
        "task_id" => %{"type" => ["string", "null"]}
      }
    }
  end

  def fake_output(%{"phase" => phase} = input) when phase in ~w(planning plan_review),
    do: Cuckoding.BoardControl.Plans.fake_output(input)

  def fake_output(input) do
    %{
      "action" => if(input["next_task_id"], do: "start_task", else: "finish"),
      "execution_id" => input["execution_id"],
      "revision" => input["revision"],
      "task_id" => input["next_task_id"],
      "summary" => "Validated board queue decision"
    }
  end
end
