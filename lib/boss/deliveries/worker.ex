defmodule Boss.Deliveries.Worker do
  @moduledoc false
  alias Boss.{Deliveries, Repo}
  alias Boss.Agents.{Claude, Codex, ReportFile, Workspace}
  alias Boss.Agents.Process, as: Runner
  alias Boss.Checks.Candidate
  alias Boss.Deliveries.Protocol

  def execute(delivery, repo, manager) do
    Repo.put_dynamic_repo(repo)

    result =
      try do
        perform(delivery)
      rescue
        _ -> halt(delivery, :storage_error)
      catch
        :throw, {:halt, reason} -> halt(delivery, reason)
        _, _ -> halt(delivery, :storage_error)
      end

    send(manager, {:delivery_finished, delivery.id, self(), result})
  end

  defp perform(delivery) do
    {project, revision} = Deliveries.inputs(delivery)
    continue!()

    if delivery.reviewer == "claude" and is_nil(System.find_executable("claude")),
      do: throw({:halt, :claude_unavailable})

    intent = ok!(Workspace.plan(project, delivery.id)) |> string_keys()
    delivery = stored!(Deliveries.set_intent(delivery.id, intent))
    input = %{"specification" => revision.original_text, "base_commit" => intent["base_commit"]}
    prompt = ok!(Protocol.prompt(:plan, input))

    {plan_step, plan} =
      step(
        delivery,
        "plan",
        0,
        %{"workspace" => intent, "input_hash" => Protocol.digest(input)},
        fn ->
          continue!()
          ok!(Workspace.prepare(intent))
          verify = fn -> Candidate.verify_tree(intent["path"], intent["base_commit"]) end
          receipt = run_agent(:plan, intent["path"], prompt, &Protocol.plan/1)
          receipt = verify_agent(receipt, verify)
          {Map.put(receipt, "workspace", intent), receipt["report"]}
        end
      )

    successful!(plan_step)
    cycle(delivery, project, revision.original_text, plan_step, plan, 1, nil, nil, MapSet.new())
  end

  defp cycle(delivery, project, source, plan_step, plan, cycle, previous, feedback, failures) do
    continue!()
    base = if previous, do: previous.candidate_commit, else: delivery.intent["base_commit"]
    workspace = ok!(Workspace.plan(project, Ecto.UUID.generate())) |> string_keys()
    workspace = Map.put(workspace, "base_commit", base)

    input = %{
      "specification" => source,
      "plan" => plan,
      "cycle" => cycle,
      "base_commit" => base,
      "previous_feedback" => feedback
    }

    prompt = ok!(Protocol.prompt(:implement, input))

    {implementation, _} =
      step(
        delivery,
        "implement",
        cycle,
        %{
          "workspace" => workspace,
          "plan_step_id" => plan_step.id,
          "parent_step_id" => if(previous, do: previous.step_id, else: plan_step.id),
          "feedback_hash" => Protocol.digest(feedback),
          "input_hash" => Protocol.digest(input)
        },
        fn ->
          continue!()
          ok!(Workspace.prepare(workspace))
          receipt = run_agent(:implement, workspace["path"], prompt, nil)

          receipt =
            if receipt["status"] == "finished" do
              case Workspace.inspect(workspace) do
                {:ok, info} -> Map.put(receipt, "head_commit", info.head_commit)
                {:error, reason} -> failure(reason)
              end
            else
              receipt
            end

          {Map.put(receipt, "workspace", workspace), nil}
        end
      )

    successful!(implementation)
    continue!()
    candidate = ok!(Candidate.plan(workspace, Ecto.UUID.generate()))

    {snapshot, sha} =
      step(
        delivery,
        "snapshot",
        cycle,
        %{
          "workspace" => candidate,
          "implementation_step_id" => implementation.id,
          "plan_step_id" => plan_step.id
        },
        fn ->
          continue!()
          saved = ok!(Candidate.prepare(candidate))

          {%{
             "status" => "finished",
             "cleanup" => "group_empty",
             "candidate_commit" => saved.candidate_commit,
             "workspace" => candidate
           }, saved.candidate_commit}
        end
      )

    {check, output} =
      step(
        delivery,
        "check",
        cycle,
        %{
          "snapshot_step_id" => snapshot.id,
          "plan_step_id" => plan_step.id,
          "workspace" => candidate,
          "candidate_commit" => sha,
          "config_hash" => delivery.config_hash
        },
        fn ->
          {receipt, output} =
            run_check(candidate["path"], delivery.check_config, fn ->
              Candidate.verify(candidate, sha)
            end)

          {Map.put(receipt, "candidate_commit", sha), output}
        end
      )

    case check.receipt do
      %{"status" => "finished"} ->
        review(
          delivery,
          project,
          source,
          plan_step,
          plan,
          cycle,
          candidate,
          sha,
          check,
          output,
          feedback,
          failures
        )

      %{"outcome" => "checks_failed", "output_complete" => true} ->
        feedback = %{
          "kind" => "checks",
          "exit_code" => check.receipt["exit_code"],
          "check_receipt" => check.receipt,
          "output" => output
        }

        repeat(
          delivery,
          project,
          source,
          plan_step,
          plan,
          cycle,
          candidate,
          sha,
          check.id,
          feedback,
          failures
        )

      _ ->
        successful!(check)
    end
  end

  defp review(
         delivery,
         project,
         source,
         plan_step,
         plan,
         cycle,
         candidate,
         sha,
         check,
         output,
         feedback,
         failures
       ) do
    continue!()
    path = candidate["path"]
    base = delivery.intent["base_commit"]
    ok!(Workspace.git(path, ["merge-base", "--is-ancestor", base, sha]))

    diff =
      ok!(
        Workspace.git(path, [
          "diff",
          "--no-ext-diff",
          "--no-textconv",
          "--binary",
          "--full-index",
          base,
          sha,
          "--"
        ])
      )

    unless String.valid?(diff), do: throw({:halt, :invalid_input})

    input = %{
      "specification" => source,
      "plan" => plan,
      "base_commit" => base,
      "candidate_commit" => sha,
      "diff" => diff,
      "check_config" => delivery.check_config,
      "check_receipt" => check.receipt,
      "check_output" => output,
      "previous_feedback" => feedback,
      "reviewer" => delivery.reviewer
    }

    kind = if delivery.reviewer == "claude", do: :claude_review, else: :review
    prompt = ok!(Protocol.prompt(kind, input))

    {review, report} =
      step(
        delivery,
        "review",
        cycle,
        %{
          "plan_step_id" => plan_step.id,
          "check_step_id" => check.id,
          "workspace" => candidate,
          "original_base" => base,
          "candidate_commit" => sha,
          "config_hash" => delivery.config_hash,
          "output_hash" => check.receipt["output_hash"],
          "feedback_hash" => Protocol.digest(feedback),
          "input_hash" => Protocol.digest(input)
        },
        fn ->
          continue!()
          ok!(Candidate.verify(candidate, sha))
          receipt = run_reviewer(delivery.reviewer, path, prompt, &Protocol.review(&1, plan))
          receipt = verify_agent(receipt, fn -> Candidate.verify(candidate, sha) end)
          {Map.put(receipt, "candidate_commit", sha), receipt["report"]}
        end
      )

    successful!(review)
    continue!()

    case report["verdict"] do
      "approved" ->
        Deliveries.complete(delivery.id, "ready_to_merge", nil)

      "needs_spec_revision" ->
        Deliveries.complete(
          delivery.id,
          "needs_input",
          "The saved specification needs clarification. Original source retained."
        )

      "changes_requested" ->
        feedback = %{
          "kind" => "review",
          "report" => report,
          "check_receipt" => check.receipt,
          "check_output" => output
        }

        repeat(
          delivery,
          project,
          source,
          plan_step,
          plan,
          cycle,
          candidate,
          sha,
          review.id,
          feedback,
          failures
        )
    end
  end

  defp repeat(
         delivery,
         project,
         source,
         plan_step,
         plan,
         cycle,
         candidate,
         sha,
         step_id,
         feedback,
         failures
       ) do
    continue!()
    tree = ok!(Workspace.git(candidate["path"], ["rev-parse", "#{sha}^{tree}"]))

    findings =
      if feedback["kind"] == "review",
        do: feedback["report"]["issues"],
        else: Map.take(feedback, ["exit_code", "output"])

    fingerprint = Protocol.digest([tree, delivery.config_hash, normalize_feedback(findings)])

    cond do
      MapSet.member?(failures, fingerprint) ->
        Deliveries.complete(
          delivery.id,
          "blocked",
          "The same failure repeated for unchanged candidate content. No further automatic attempt."
        )

      cycle >= 3 ->
        Deliveries.complete(
          delivery.id,
          "blocked",
          "The three-cycle implementation/check/review budget is exhausted."
        )

      true ->
        cycle(
          delivery,
          project,
          source,
          plan_step,
          plan,
          cycle + 1,
          %{candidate_commit: sha, step_id: step_id},
          feedback,
          MapSet.put(failures, fingerprint)
        )
    end
  end

  @doc false
  def run_check(path, config, verify) do
    with :ok <- continue(),
         :ok <- verify.(),
         {:ok, executable, args} <- executable(config["argv"], path),
         :ok <- continue() do
      capture = :ets.new(:delivery_check_output, [:set, :public])
      :ets.insert(capture, [{:stdout, []}, {:stderr, []}, {:bytes, 0}])
      limit = min(config["output_limit"], 1_048_576)

      try do
        callback = fn
          {stream, bytes} when stream in [:stdout, :stderr] ->
            if :ets.update_counter(capture, :bytes, byte_size(bytes)) <= limit do
              [{^stream, chunks}] = :ets.lookup(capture, stream)
              :ets.insert(capture, {stream, [bytes | chunks]})
              :ok
            else
              :stop
            end

          _ ->
            :ok
        end

        result =
          Runner.run(executable, args,
            cd: path,
            input: "",
            timeout_ms: config["timeout_ms"],
            output_limit: limit,
            on_event: callback
          )

        output =
          Map.new([:stdout, :stderr], fn stream ->
            [{^stream, chunks}] = :ets.lookup(capture, stream)
            {Atom.to_string(stream), chunks |> Enum.reverse() |> IO.iodata_to_binary()}
          end)

        complete =
          result.outcome == :exited and result.exit_kind == :exit and
            result.eof == %{stdout: true, stderr: true} and result.cleanup == :group_empty and
            result.stdout_bytes + result.stderr_bytes <= limit and
            Enum.all?(output, fn {_, text} -> String.valid?(text) end)

        receipt = process_receipt(result)

        receipt =
          Map.merge(receipt, %{
            "output_complete" => complete,
            "output_hash" => if(complete, do: Protocol.digest(output)),
            "stdout_bytes" => result.stdout_bytes,
            "stderr_bytes" => result.stderr_bytes
          })

        receipt =
          if complete do
            case verify.() do
              :ok ->
                Map.merge(receipt, %{
                  "status" => if(result.exit_code == 0, do: "finished", else: "failed"),
                  "outcome" => if(result.exit_code == 0, do: nil, else: "checks_failed")
                })

              {:error, reason} ->
                Map.merge(receipt, failure(reason))
            end
          else
            receipt
          end

        {receipt, if(complete, do: output, else: %{})}
      after
        :ets.delete(capture)
      end
    else
      {:error, reason} -> {failure(reason), %{}}
    end
  end

  @doc false
  def run_reviewer("codex", path, prompt, decode),
    do: run_agent(:review, path, prompt, decode)

  def run_reviewer("claude", _path, prompt, decode) do
    continue!()
    executable = System.find_executable("claude") || throw({:halt, :claude_unavailable})
    # No repository discovery: this reviewer receives its entire evidence on stdin.
    scratch = Path.join(System.tmp_dir!(), "boss-claude-review-#{Ecto.UUID.generate()}")
    ok!(File.mkdir(scratch))

    ok!(File.chmod(scratch, 0o700))
    receipt = claude_process(executable, scratch, prompt, decode)
    # Unknown ownership or a crashed worker leaves scratch intact for inspection.
    if receipt["cleanup"] != "unknown", do: File.rm_rf(scratch)
    receipt
  end

  defp claude_process(executable, path, prompt, decode) do
    parser = :ets.new(:delivery_claude, [:set, :public])
    :ets.insert(parser, {:state, Claude.new()})

    try do
      callback = fn event ->
        [{:state, state}] = :ets.lookup(parser, :state)
        state = Claude.feed(state, event)
        :ets.insert(parser, {:state, state})
        if state.error, do: :stop, else: :ok
      end

      result =
        Runner.run(executable, Claude.args(),
          cd: path,
          input: prompt,
          timeout_ms: 1_200_000,
          output_limit: 8_388_608,
          on_event: callback
        )

      [{:state, state}] = :ets.lookup(parser, :state)
      receipt = process_receipt(result) |> Map.put("summary", Claude.summary(state))

      cond do
        receipt["status"] in ["interrupted", "cancelled"] ->
          receipt

        result.outcome == :exited and result.exit_kind == :exit and result.exit_code == 0 and
          result.eof == %{stdout: true, stderr: true} and Claude.complete?(state) ->
          case decode.(state.report) do
            {:ok, report} -> Map.merge(receipt, %{"status" => "finished", "report" => report})
            _ -> Map.merge(receipt, failure(:invalid_report))
          end

        true ->
          Map.put(
            receipt,
            "reason",
            "Claude review did not finish with a valid structured result and clean exit. No fallback was started."
          )
      end
    after
      :ets.delete(parser)
    end
  end

  defp run_agent(kind, path, prompt, decode) do
    continue!()
    executable = System.find_executable("codex") || throw({:halt, :codex_unavailable})

    if kind == :implement do
      agent_process(executable, Codex.args(), path, prompt)
    else
      case ReportFile.with_file(fn output, file ->
             receipt = agent_process(executable, Codex.args(kind, output), path, prompt)

             if receipt["status"] == "finished" do
               with {:ok, text} <- ReportFile.read(output, file),
                    {:ok, report} <- decode.(text) do
                 Map.put(receipt, "report", report)
               else
                 _ -> Map.merge(receipt, failure(:invalid_report))
               end
             else
               receipt
             end
           end) do
        {:error, reason} -> failure(reason)
        receipt -> receipt
      end
    end
  end

  defp agent_process(executable, args, path, prompt) do
    continue!()
    parser = :ets.new(:delivery_codex, [:set, :public])
    :ets.insert(parser, {:state, Codex.new()})

    try do
      callback = fn event ->
        [{:state, state}] = :ets.lookup(parser, :state)
        state = Codex.feed(state, event)
        :ets.insert(parser, {:state, state})
        if state.error, do: :stop, else: :ok
      end

      result =
        Runner.run(executable, args,
          cd: path,
          input: prompt,
          timeout_ms: 1_200_000,
          output_limit: 8_388_608,
          on_event: callback
        )

      [{:state, state}] = :ets.lookup(parser, :state)
      receipt = Boss.Runs.Worker.receipt(result, state) |> Map.new() |> string_keys()

      Map.merge(process_receipt(result), receipt)
      |> Map.put("summary", Codex.summary(state))
    after
      :ets.delete(parser)
    end
  end

  defp process_receipt(result) do
    status =
      cond do
        result.cleanup != :group_empty ->
          "interrupted"

        result.outcome == :cancelled and Map.get(result, :reason) != :consumer_stopped ->
          "cancelled"

        true ->
          "failed"
      end

    %{
      "status" => status,
      "cleanup" => to_string(result.cleanup),
      "exit_kind" => if(result.exit_kind, do: to_string(result.exit_kind)),
      "exit_code" => result.exit_code,
      "signal" => result.signal,
      "eof" => string_keys(result.eof),
      "outcome" => to_string(result.outcome)
    }
  end

  @doc false
  def verify_agent(%{"status" => "finished"} = receipt, verify) do
    case verify.() do
      :ok -> receipt
      {:error, reason} -> receipt |> Map.delete("report") |> Map.merge(failure(reason))
    end
  end

  def verify_agent(receipt, _), do: receipt

  defp step(delivery, kind, cycle, input, run) do
    continue!()

    input =
      Map.merge(input, %{
        "spec_revision_id" => delivery.spec_revision_id,
        "config_hash" => delivery.config_hash
      })

    step = begin_step(delivery, kind, cycle, input)
    Process.put(:delivery_step, step.id)
    continue!()
    {receipt, value} = run.()
    saved = stored!(Deliveries.finish_step(step.id, receipt))
    Process.delete(:delivery_step)
    {saved, value}
  end

  defp begin_step(delivery, kind, cycle, input) do
    continue!()

    case Deliveries.begin_step(delivery.id, kind, cycle, input) do
      {:error, :scope_conflict} when kind == "implement" and cycle == 1 ->
        receive do
          :stop -> throw({:halt, :cancelled})
        after
          500 -> begin_step(delivery, kind, cycle, input)
        end

      {:error, :execution_quarantined} when kind == "implement" and cycle == 1 ->
        throw({:halt, :execution_quarantined})

      result ->
        stored!(result)
    end
  end

  defp successful!(%{receipt: %{"status" => "finished"}}), do: :ok
  defp successful!(%{receipt: %{"status" => "cancelled"}}), do: throw({:halt, :cancelled})
  defp successful!(%{receipt: %{"status" => "interrupted"}}), do: throw({:halt, :cleanup_unknown})
  defp successful!(_), do: throw({:halt, :stage_failed})

  defp halt(delivery, reason) do
    receipt = failure(reason)
    if id = Process.delete(:delivery_step), do: Deliveries.finish_step(id, receipt)
    Deliveries.complete(delivery.id, receipt["status"], receipt["reason"])
  rescue
    _ -> {:error, :storage_error}
  catch
    _, _ -> {:error, :storage_error}
  end

  defp failure(reason) do
    {status, cleanup, message} =
      case reason do
        :cancelled ->
          {"cancelled", "group_empty", "Stopped. No further automatic stage will start."}

        reason when reason in [:storage_error, :cleanup_unknown] ->
          {"interrupted", "unknown",
           "Execution or storage outcome is unknown. Retained for inspection; no automatic restart."}

        :input_too_large ->
          {"failed", "group_empty",
           "Complete delivery input exceeds the 1 MiB limit. Nothing was truncated."}

        :execution_quarantined ->
          {"failed", "group_empty",
           "Another execution has unknown cleanup. Implementation was not started; inspect the interrupted workflow."}

        :claude_unavailable ->
          {"failed", "not_started",
           "Claude is unavailable in BOSS's PATH. No fallback was started."}

        :codex_unavailable ->
          {"failed", "not_started", "Codex is unavailable in BOSS's PATH."}

        _ ->
          {"failed", "group_empty",
           "Delivery stage failed validation or execution. Retained evidence requires attention."}
      end

    %{
      "status" => status,
      "cleanup" => cleanup,
      "reason" => message,
      "outcome" => error_tag(reason)
    }
  end

  defp error_tag(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_tag({reason, _}) when is_atom(reason), do: Atom.to_string(reason)
  defp error_tag(_), do: "stage_failed"

  defp normalize_feedback(value) when is_binary(value),
    do: value |> String.split() |> Enum.join(" ")

  defp normalize_feedback(value) when is_list(value),
    do: value |> Enum.map(&normalize_feedback/1) |> Enum.sort()

  defp normalize_feedback(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, normalize_feedback(item)} end)

  defp normalize_feedback(value), do: value

  defp executable([name | args], path) do
    executable =
      if String.contains?(name, "/"),
        do: Path.expand(name, path),
        else: System.find_executable(name)

    if is_binary(executable) and File.regular?(executable),
      do: {:ok, executable, args},
      else: {:error, :command_unavailable}
  end

  defp continue do
    receive do
      :stop -> {:error, :cancelled}
    after
      0 -> :ok
    end
  end

  defp continue!, do: ok!(continue())
  defp ok!(:ok), do: :ok
  defp ok!({:ok, value}), do: value
  defp ok!({:error, reason}), do: throw({:halt, reason})
  defp stored!({:ok, value}), do: value
  defp stored!(_), do: throw({:halt, :storage_error})
  defp string_keys(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
end
