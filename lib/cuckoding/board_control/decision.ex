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

  def resume(run_id, options \\ []) do
    options = Keyword.merge(options, board_controller: true, resume: true)

    with {:ok, skeleton} <- WalkingSkeleton.load(run_id),
         :ok <- BoardControl.Recovery.preflight(skeleton),
         {:ok, runtime} <- AgentRuntime.resolve(skeleton, role(skeleton.run)),
         {:ok, _} <-
           RunControl.admit(run_id, fn -> BoardControl.Recovery.claim(skeleton.run) end, options) do
      launch(skeleton, runtime, options)
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
         input = recovery_input(input, e, run, options),
         {:ok, input} <- BoardControl.GoalChecks.run(skeleton, input),
         {:ok, output} <-
           WalkingSkeleton.control_stage(%{skeleton | run: run}, runtime, input, options) do
      BoardControl.accept_decision(run.id, input, output)
    end
  end

  defp recovery_input(input, e, run, options) do
    if options[:resume] do
      recovery =
        e
        |> BoardControl.Recovery.events()
        |> Enum.reverse()
        |> Enum.find(&(&1["source_run_id"] == run.id))

      Map.put(input, "recovery", Map.take(recovery || %{}, ~w(code kind count limit)))
    else
      input
    end
  end

  def validate_stage(output, %{"phase" => "decision", "prepared_goal" => true} = input) do
    next = if input["next_task_id"], do: %{task_id: input["next_task_id"]}

    case validate(output, input, next) do
      :ok -> :ok
      {:error, _} -> {:error, :invalid_goal_decision}
    end
  end

  def validate_stage(_output, _input), do: :ok

  def validate(output, input, next) when is_map(output) do
    if valid_envelope?(output, input) and valid_action?(output, input, next) and
         valid_question?(output, input),
       do: :ok,
       else: {:error, :invalid_controller_output}
  end

  def validate(_, _, _), do: {:error, :invalid_controller_output}

  defp valid_envelope?(output, input) do
    keys =
      ~w(action execution_id revision summary task_id) ++
        if(input["prepared_goal"], do: ["question"], else: [])

    Enum.sort(Map.keys(output)) == Enum.sort(keys) and
      output["execution_id"] == input["execution_id"] and
      is_integer(output["revision"]) and
      output["revision"] == input["revision"] and
      is_binary(output["summary"]) and String.trim(output["summary"]) != "" and
      byte_size(output["summary"]) <= 2000
  end

  def question_schema do
    %{
      "type" => ["object", "null"],
      "additionalProperties" => false,
      "required" => ~w(kind criterion_id checked why_needed),
      "properties" => %{
        "kind" => %{"type" => "string", "enum" => ~w(requirement_choice external_input)},
        "criterion_id" => %{"type" => "string"},
        "checked" => %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 5,
          "items" => %{"type" => "string", "minLength" => 1, "maxLength" => 500}
        },
        "why_needed" => %{"type" => "string", "minLength" => 1, "maxLength" => 1000}
      }
    }
  end

  defp valid_question?(
         %{"action" => "ask", "question" => question},
         %{"prepared_goal" => true} = input
       )
       when is_map(question) do
    Enum.sort(Map.keys(question)) == ~w(checked criterion_id kind why_needed) and
      question["kind"] in ~w(requirement_choice external_input) and
      Enum.any?(input["goal"]["criteria"], &(&1["id"] == question["criterion_id"])) and
      checked_evidence?(question["checked"]) and text?(question["why_needed"], 1000)
  end

  defp valid_question?(output, %{"prepared_goal" => true}),
    do: output["action"] != "ask" and is_nil(output["question"])

  defp valid_question?(_output, _input), do: true

  defp checked_evidence?(values) when is_list(values),
    do: length(values) in 1..5 and Enum.all?(values, &text?(&1, 500))

  defp checked_evidence?(_), do: false

  defp text?(value, maximum) when is_binary(value),
    do: String.valid?(value) and String.trim(value) != "" and byte_size(value) <= maximum

  defp text?(_, _), do: false

  def question_text(%{"question" => question} = output) when is_map(question) do
    output["summary"] <>
      "\n\nRequirement: " <>
      question["criterion_id"] <>
      "\nReason: " <>
      question["why_needed"] <>
      "\nAlready checked: " <>
      Enum.join(question["checked"], "; ")
  end

  def question_text(output), do: output["summary"]

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

  def fake_output(%{"phase" => phase} = input)
      when phase in ~w(planning plan_review final_review),
      do: Cuckoding.BoardControl.Plans.fake_output(input)

  def fake_output(input) do
    output = %{
      "action" => if(input["next_task_id"], do: "start_task", else: "finish"),
      "execution_id" => input["execution_id"],
      "revision" => input["revision"],
      "task_id" => input["next_task_id"],
      "summary" => "Validated board queue decision"
    }

    if input["prepared_goal"], do: Map.put(output, "question", nil), else: output
  end
end
