defmodule Boss.Deliveries.Worker do
  @moduledoc false
  alias Boss.{Deliveries, Repo}
  alias Boss.Agents.{Claude, Codex, ModelCatalog, ReportFile, Workspace}
  alias Boss.Agents.Process, as: Runner
  alias Boss.Checks.Candidate
  alias Boss.Deliveries.{Diagnostics, ExecutionRetry, ModelPolicy, Protocol, Retry}

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
    delivery = prepare_models(delivery)
    {project, revision} = Deliveries.inputs(delivery)

    case ok!(ExecutionRetry.source(delivery)) do
      nil -> perform_standard(delivery, project, revision)
      source -> perform_timeout_retry(delivery, project, revision, source)
    end
  end

  defp perform_standard(delivery, project, revision) do
    source = ok!(Retry.source(delivery))
    continue!()

    if delivery.reviewer == "claude" and is_nil(System.find_executable("claude")),
      do: throw({:halt, :claude_unavailable})

    ok!(Retry.verify(source))
    intent = ok!(Workspace.plan(project, delivery.id)) |> string_keys()

    if expected = Boss.Projects.Intake.expected_delivery_base(delivery) do
      unless intent["base_commit"] == expected, do: throw({:halt, :target_changed})
    end

    intent =
      if source,
        do: Map.put(intent, "base_commit", source.parent.intent["base_commit"]),
        else: intent

    delivery = stored!(Deliveries.set_intent(delivery.id, intent))

    input = %{
      "specification" => revision.original_text,
      "base_commit" => intent["base_commit"],
      "check_config" => delivery.check_config
    }

    input = retry_plan_input(input, source)

    {plan_step, plan} = plan(delivery, source, input)

    {previous, feedback} = retry_seed(delivery, project, plan_step, source)
    failures = retry_failures(delivery, source)

    cycle(
      delivery,
      project,
      revision.original_text,
      plan_step,
      plan,
      1,
      previous,
      feedback,
      failures
    )
  end

  defp perform_timeout_retry(delivery, project, revision, source) do
    continue!()

    if delivery.reviewer == "claude" and is_nil(System.find_executable("claude")),
      do: throw({:halt, :claude_unavailable})

    ok!(ExecutionRetry.verify(source))

    intent = ok!(Workspace.plan(project, delivery.id)) |> string_keys()

    expected =
      Boss.Projects.Intake.expected_delivery_base(delivery) ||
        Boss.Projects.Intake.expected_delivery_base(source.parent)

    if expected do
      unless intent["base_commit"] == expected, do: throw({:halt, :target_changed})
      ok!(Boss.Deliveries.Integration.preflight(project, delivery.id, expected))
    end

    intent = Map.put(intent, "base_commit", source.parent.intent["base_commit"])

    delivery = stored!(Deliveries.set_intent(delivery.id, intent))
    plan = source.plan.receipt["report"]

    {plan_step, ^plan} =
      step(
        delivery,
        "plan",
        0,
        %{
          "workspace" => intent,
          "source_implementation_id" => source.implementation.id,
          "source_plan_id" => source.plan.id
        },
        fn ->
          ok!(ExecutionRetry.verify(source))
          ok!(Protocol.plan(JSON.encode!(plan)))

          {%{
             "status" => "finished",
             "cleanup" => "group_empty",
             "outcome" => "retained_plan",
             "report" => plan,
             "workspace" => intent
           }, plan}
        end
      )

    recover_timeout(
      delivery,
      project,
      revision.original_text,
      plan_step,
      plan,
      0,
      source.implementation,
      nil,
      MapSet.new()
    )
  end

  defp prepare_models(%{routing_version: 2, model_catalog: catalog} = delivery) do
    if catalog == %{} do
      continue!()

      case ModelCatalog.discover() do
        {:ok, snapshot} -> stored!(Deliveries.set_model_catalog(delivery.id, snapshot))
        {:error, :catalog_cleanup_unknown} -> throw({:halt, :cleanup_unknown})
        {:error, reason} -> throw({:halt, reason})
      end
    else
      ok!(ModelCatalog.validate(catalog))
      delivery
    end
  end

  defp prepare_models(delivery), do: delivery

  defp plan(delivery, source, input, parent \\ nil, previous_plan \\ nil, attempt \\ 0) do
    intent = delivery.intent

    prior =
      if parent,
        do: Enum.find(Deliveries.steps(delivery.id), &(&1.id == parent.input["plan_step_id"]))

    profile = profile(delivery, :plan, 0, prior)

    prompt = ok!(Protocol.prompt(:plan, input))
    previous_plan = previous_plan || if(source, do: source.plan.receipt["report"])

    saved_input =
      retry_input(
        %{
          "workspace" => intent,
          "input_hash" => Protocol.digest(input),
          "model_profile" => profile
        },
        delivery
      )

    saved_input =
      if parent do
        Map.merge(saved_input, %{
          "parent_step_id" => parent.id,
          "plan_step_id" => parent.input["plan_step_id"],
          "replan_attempt" => attempt
        })
      else
        saved_input
      end

    {plan_step, report} =
      step(delivery, "plan", 0, saved_input, fn ->
        continue!()
        if is_nil(parent), do: ok!(Workspace.prepare(intent))

        verify = fn ->
          with :ok <- Candidate.verify_tree(intent["path"], intent["base_commit"]),
               do: Retry.verify(source)
        end

        ok!(verify.())

        receipt =
          run_agent(:plan, intent["path"], prompt, &Protocol.plan(&1, previous_plan), profile)

        receipt = verify_agent(receipt, verify)
        {Map.put(receipt, "workspace", intent), receipt["report"]}
      end)

    question = if report, do: report["clarification"]

    cond do
      plan_step.status == "finished" and is_nil(question) ->
        {plan_step, report}

      autonomous?(delivery) and attempt < 2 and recoverable?(plan_step) ->
        feedback = %{"kind" => "plan", "report" => report, "receipt" => plan_step.receipt}

        {resolution, advice} =
          resolve(
            delivery,
            plan_step,
            report,
            plan_step,
            intent,
            intent["base_commit"],
            feedback,
            input["specification"]
          )

        preserved =
          cond do
            previous_plan -> previous_plan
            report && report["acceptance"] != [] -> report
            true -> nil
          end

        next_input =
          input
          |> Map.put("resolution", advice)
          |> Map.put("previous_plan", preserved)

        plan(delivery, source, next_input, resolution, preserved, attempt + 1)

      question ->
        throw({:halt, {:needs_input, Diagnostics.planning_question(question)}})

      true ->
        successful!(plan_step)
    end
  end

  defp retry_plan_input(input, nil), do: input

  defp retry_plan_input(input, source) do
    diff =
      ok!(
        Workspace.git(source.parent.intent["repo_path"], [
          "diff",
          "--no-ext-diff",
          "--no-textconv",
          "--binary",
          "--full-index",
          source.parent.intent["base_commit"],
          source.candidate_commit,
          "--"
        ])
      )

    unless String.valid?(diff), do: throw({:halt, :invalid_input})

    Map.merge(input, %{
      "previous_plan" => source.plan.receipt["report"],
      "previous_review" => source.review.receipt["report"],
      "previous_review_candidate_commit" => source.review.input["candidate_commit"],
      "previous_candidate_commit" => source.candidate_commit,
      "previous_diff" => diff
    })
  end

  defp retry_failures(_, nil), do: MapSet.new()

  defp retry_failures(delivery, source) do
    reviewed_sha = source.review.input["candidate_commit"]

    tree =
      ok!(
        Workspace.git(source.parent.intent["repo_path"], ["rev-parse", "#{reviewed_sha}^{tree}"])
      )

    findings = source.review.receipt["report"]["issues"]
    MapSet.new([Protocol.digest([tree, delivery.config_hash, normalize_feedback(findings)])])
  end

  defp retry_seed(_, _, _, nil), do: {nil, nil}

  defp retry_seed(delivery, project, plan, source) do
    continue!()
    ok!(Retry.verify(source))
    source_sha = source.candidate_commit
    seed = ok!(Workspace.plan(project, Ecto.UUID.generate())) |> string_keys()
    seed = Map.put(seed, "base_commit", source_sha)
    check_id = Ecto.UUID.generate()

    {snapshot, {candidate, sha}} =
      step(
        delivery,
        "retry_snapshot",
        0,
        %{
          "run_workspace" => seed,
          "check_id" => check_id,
          "source_review_id" => source.review.id,
          "source_candidate_commit" => source_sha,
          "plan_step_id" => plan.id
        },
        fn ->
          continue!()
          {candidate, saved} = prepare_retry_snapshot(seed, check_id, source_sha)

          {%{
             "status" => "finished",
             "cleanup" => "group_empty",
             "candidate_commit" => saved.candidate_commit,
             "workspace" => candidate
           }, {candidate, saved.candidate_commit}}
        end
      )

    {check, output} =
      step(
        delivery,
        "retry_check",
        0,
        %{
          "snapshot_step_id" => snapshot.id,
          "plan_step_id" => plan.id,
          "source_review_id" => source.review.id,
          "workspace" => candidate,
          "candidate_commit" => sha,
          "config_hash" => delivery.config_hash
        },
        fn ->
          {receipt, output} =
            run_check(candidate["path"], delivery.check_config, fn ->
              with :ok <- Candidate.verify(candidate, sha), do: Retry.verify(source)
            end)

          {Map.put(receipt, "candidate_commit", sha), output}
        end
      )

    case check.receipt do
      %{"status" => "finished"} ->
        :ok

      %{"outcome" => "checks_failed", "output_complete" => true, "cleanup" => "group_empty"} ->
        :ok

      _ ->
        successful!(check)
    end

    {%{candidate_commit: sha, step_id: check.id},
     %{
       "kind" => "review",
       "source_review_id" => source.review.id,
       "review_candidate_commit" => source.review.input["candidate_commit"],
       "prepared_candidate_commit" => source_sha,
       "report" => source.review.receipt["report"],
       "check_receipt" => check.receipt,
       "check_output" => output
     }}
  end

  @doc false
  def prepare_retry_snapshot(seed, check_id, source_sha) do
    ok!(Workspace.prepare(seed))
    ok!(Candidate.verify_tree(seed["path"], source_sha))
    candidate = ok!(Candidate.plan(seed, check_id))
    saved = ok!(Candidate.prepare(candidate))

    parents =
      ok!(
        Workspace.git(candidate["path"], [
          "rev-list",
          "--parents",
          "-n",
          "1",
          saved.candidate_commit
        ])
      )

    source_tree = ok!(Workspace.git(candidate["path"], ["rev-parse", "#{source_sha}^{tree}"]))

    snapshot_tree =
      ok!(Workspace.git(candidate["path"], ["rev-parse", "#{saved.candidate_commit}^{tree}"]))

    unless parents == "#{saved.candidate_commit} #{source_sha}" and source_tree == snapshot_tree,
      do: throw({:halt, :candidate_changed})

    {candidate, saved}
  end

  defp retry_input(input, delivery) do
    case Map.get(delivery, :retry_review_id) do
      nil -> input
      id -> Map.put(input, "source_review_id", id)
    end
  end

  defp cycle(delivery, project, source, plan_step, plan, cycle, previous, feedback, failures) do
    continue!()
    base = if previous, do: previous.candidate_commit, else: delivery.intent["base_commit"]
    workspace = ok!(Workspace.plan(project, Ecto.UUID.generate())) |> string_keys()
    workspace = Map.put(workspace, "base_commit", base)
    profile = profile(delivery, :implement, cycle, plan_step)

    input = %{
      "specification" => source,
      "plan" => plan,
      "cycle" => cycle,
      "base_commit" => base,
      "check_config" => delivery.check_config,
      "previous_feedback" => feedback
    }

    prompt = ok!(Protocol.prompt(:implement, input))

    {implementation, _} =
      step(
        delivery,
        "implement",
        cycle,
        retry_input(
          %{
            "workspace" => workspace,
            "plan_step_id" => plan_step.id,
            "parent_step_id" => if(previous, do: previous.step_id, else: plan_step.id),
            "resolution_step_id" => if(previous, do: Map.get(previous, :resolution_step_id)),
            "source_step_id" => if(previous, do: Map.get(previous, :source_step_id)),
            "model_profile" => profile,
            "feedback_hash" => Protocol.digest(feedback),
            "input_hash" => Protocol.digest(input)
          },
          delivery
        ),
        fn ->
          continue!()
          ok!(Workspace.prepare(workspace))
          if cycle == 1, do: ok!(Retry.verify(ok!(Retry.source(delivery))))
          receipt = run_agent(:implement, workspace["path"], prompt, nil, profile)

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

    cond do
      ModelPolicy.timeout_recoverable?(
        Map.get(delivery, :execution_recovery_version, 0),
        implementation
      ) ->
        recover_timeout(
          delivery,
          project,
          source,
          plan_step,
          plan,
          cycle,
          implementation,
          feedback,
          failures
        )

      autonomous?(delivery) and failed_execution?(delivery, implementation) ->
        recover_implementation(
          delivery,
          project,
          source,
          plan_step,
          plan,
          cycle,
          implementation,
          feedback,
          failures
        )

      true ->
        successful!(implementation)

        check_implementation(
          delivery,
          project,
          source,
          plan_step,
          plan,
          cycle,
          workspace,
          implementation,
          feedback,
          failures
        )
    end
  end

  defp recover_timeout(
         delivery,
         project,
         source,
         plan_step,
         plan,
         cycle,
         implementation,
         previous_feedback,
         failures
       ) do
    continue!()

    if cycle >= ModelPolicy.max_cycles(version(delivery)) do
      Deliveries.complete(
        delivery.id,
        "blocked",
        "The five-cycle implementation budget is exhausted. Timed-out workspaces remain retained."
      )
    else
      {candidate, sha, check, output} =
        timeout_snapshot(delivery, plan_step, implementation, cycle)

      feedback = %{
        "kind" => "implementation_timeout",
        "source_implementation_id" => implementation.id,
        "implementation_receipt" => implementation.receipt,
        "check_receipt" => check.receipt,
        "check_output" => output,
        "previous_feedback" => previous_feedback
      }

      {resolution, advice} =
        resolve(delivery, plan_step, plan, check, candidate, sha, feedback, source)

      cycle(
        delivery,
        project,
        source,
        plan_step,
        plan,
        cycle + 1,
        %{
          candidate_commit: sha,
          step_id: resolution.id,
          resolution_step_id: resolution.id,
          source_step_id: check.id
        },
        Map.put(feedback, "resolution", advice),
        failures
      )
    end
  end

  defp timeout_snapshot(delivery, plan, implementation, cycle) do
    continue!()
    candidate = ok!(Candidate.plan(implementation.input["workspace"], Ecto.UUID.generate()))

    {snapshot, sha} =
      step(
        delivery,
        "timeout_snapshot",
        cycle,
        %{
          "workspace" => candidate,
          "implementation_step_id" => implementation.id,
          "plan_step_id" => plan.id
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
        "timeout_check",
        cycle,
        %{
          "snapshot_step_id" => snapshot.id,
          "implementation_step_id" => implementation.id,
          "plan_step_id" => plan.id,
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
      %{"status" => "finished", "output_complete" => true} ->
        :ok

      %{"outcome" => "checks_failed", "output_complete" => true, "cleanup" => "group_empty"} ->
        :ok

      _ ->
        successful!(check)
    end

    {candidate, sha, check, output}
  end

  defp recover_implementation(
         delivery,
         project,
         source,
         plan_step,
         plan,
         cycle,
         implementation,
         feedback,
         failures
       ) do
    continue!()

    if cycle >= ModelPolicy.max_cycles(version(delivery)) do
      Deliveries.complete(
        delivery.id,
        "blocked",
        "The five-cycle implementation budget is exhausted. Failed workspaces remain retained."
      )
    else
      base = implementation.input["workspace"]["base_commit"]
      workspace = ok!(Workspace.plan(project, Ecto.UUID.generate())) |> string_keys()
      workspace = Map.put(workspace, "base_commit", base)

      problem = %{
        "kind" => "implementation",
        "receipt" => implementation.receipt,
        "previous_feedback" => feedback
      }

      {resolution, advice} =
        resolve(delivery, plan_step, plan, implementation, workspace, base, problem, source)

      feedback =
        (feedback || problem)
        |> Map.put("implementation_failure", implementation.receipt)
        |> Map.put("resolution", advice)

      cycle(
        delivery,
        project,
        source,
        plan_step,
        plan,
        cycle + 1,
        %{
          candidate_commit: base,
          step_id: resolution.id,
          resolution_step_id: resolution.id,
          source_step_id: implementation.id
        },
        feedback,
        failures
      )
    end
  end

  defp check_implementation(
         delivery,
         project,
         source,
         plan_step,
         plan,
         cycle,
         workspace,
         implementation,
         feedback,
         failures
       ) do
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
    profile = if delivery.reviewer == "codex", do: profile(delivery, :review, cycle, plan_step)

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
          "input_hash" => Protocol.digest(input),
          "model_profile" => profile
        },
        fn ->
          continue!()
          ok!(Candidate.verify(candidate, sha))

          receipt =
            run_reviewer(delivery.reviewer, path, prompt, &Protocol.review(&1, plan), profile)

          receipt = verify_agent(receipt, fn -> Candidate.verify(candidate, sha) end)
          {Map.put(receipt, "candidate_commit", sha), receipt["report"]}
        end
      )

    continue!()

    case {review.status, report && report["verdict"]} do
      {"finished", "approved"} ->
        Deliveries.complete(delivery.id, "ready_to_merge", nil)

      {"finished", "needs_spec_revision"} when not is_nil(report) ->
        if autonomous?(delivery) do
          review_retry(
            delivery,
            project,
            source,
            plan_step,
            plan,
            cycle,
            candidate,
            sha,
            review,
            output,
            failures
          )
        else
          Deliveries.complete(
            delivery.id,
            "needs_input",
            Diagnostics.clarification(report)
          )
        end

      {"finished", "changes_requested"} ->
        review_retry(
          delivery,
          project,
          source,
          plan_step,
          plan,
          cycle,
          candidate,
          sha,
          review,
          output,
          failures
        )

      _ ->
        if autonomous?(delivery) and recoverable?(review) do
          review_retry(
            delivery,
            project,
            source,
            plan_step,
            plan,
            cycle,
            candidate,
            sha,
            review,
            output,
            failures
          )
        else
          successful!(review)
        end
    end
  end

  defp review_retry(
         delivery,
         project,
         source,
         plan_step,
         plan,
         cycle,
         candidate,
         sha,
         review,
         output,
         failures
       ) do
    check = Enum.find(Deliveries.steps(delivery.id), &(&1.id == review.input["check_step_id"]))

    feedback = %{
      "kind" => "review",
      "report" => review.receipt["report"],
      "receipt" => review.receipt,
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
        do: get_in(feedback, ["report", "issues"]) || feedback["receipt"],
        else: Map.take(feedback, ["exit_code", "output"])

    fingerprint = Protocol.digest([tree, delivery.config_hash, normalize_feedback(findings)])

    cond do
      not autonomous?(delivery) and MapSet.member?(failures, fingerprint) ->
        Deliveries.complete(
          delivery.id,
          "blocked",
          Diagnostics.repair_stop(
            "The same failure repeated for unchanged candidate content.",
            feedback
          )
        )

      cycle >= ModelPolicy.max_cycles(version(delivery)) ->
        Deliveries.complete(
          delivery.id,
          "blocked",
          Diagnostics.repair_stop(
            if(autonomous?(delivery),
              do:
                "The five-cycle implementation/check/review budget is exhausted after model escalation.",
              else: "The three-cycle implementation/check/review budget is exhausted."
            ),
            feedback
          )
        )

      true ->
        {previous, feedback} =
          if autonomous?(delivery) do
            rejected = Enum.find(Deliveries.steps(delivery.id), &(&1.id == step_id))

            {resolution, advice} =
              resolve(delivery, plan_step, plan, rejected, candidate, sha, feedback, source)

            {%{
               candidate_commit: sha,
               step_id: resolution.id,
               resolution_step_id: resolution.id,
               source_step_id: step_id
             }, Map.put(feedback, "resolution", advice)}
          else
            {%{candidate_commit: sha, step_id: step_id}, feedback}
          end

        cycle(
          delivery,
          project,
          source,
          plan_step,
          plan,
          cycle + 1,
          previous,
          feedback,
          MapSet.put(failures, fingerprint)
        )
    end
  end

  defp resolve(
         delivery,
         plan_step,
         plan,
         problem,
         workspace,
         sha,
         feedback,
         source,
         attempt \\ 1,
         parent \\ nil
       ) do
    continue!()
    parent = parent || problem
    profile = profile(delivery, :resolve, attempt, plan_step)
    prepare? = problem.kind == "implement" and attempt == 1

    verify = fn ->
      if problem.kind in ["plan", "implement"],
        do: Candidate.verify_tree(workspace["path"], sha),
        else: Candidate.verify(workspace, sha)
    end

    unless prepare?, do: ok!(verify.())

    input = %{
      "specification" => source,
      "plan" => plan,
      "base_commit" => delivery.intent["base_commit"],
      "candidate_commit" => sha,
      "check_config" => delivery.check_config,
      "previous_feedback" => feedback,
      "resolution_attempt" => attempt,
      "previous_resolution" => if(parent.kind == "resolve", do: parent.receipt["report"]),
      "previous_resolution_diagnostic" =>
        if(parent.kind == "resolve" and parent.receipt["outcome"] == "invalid_report",
          do:
            parent.receipt
            |> Map.get("summary", %{})
            |> Map.take(["validation_code", "report_bytes"])
            |> Map.put("outcome", "invalid_report")
        )
    }

    prompt = ok!(Protocol.prompt(:resolve, input))

    {resolution, report} =
      step(
        delivery,
        "resolve",
        problem.cycle,
        %{
          "parent_step_id" => parent.id,
          "source_step_id" => problem.id,
          "plan_step_id" => plan_step.id,
          "workspace" => workspace,
          "candidate_commit" => sha,
          "feedback_hash" => Protocol.digest(feedback),
          "input_hash" => Protocol.digest(input),
          "model_profile" => profile,
          "resolution_attempt" => attempt
        },
        fn ->
          continue!()
          if prepare?, do: ok!(Workspace.prepare(workspace))
          ok!(verify.())

          receipt = run_resolution(workspace["path"], prompt, profile)

          receipt = verify_agent(receipt, verify)
          {Map.put(receipt, "candidate_commit", sha), receipt["report"]}
        end
      )

    cond do
      resolution.status == "finished" and is_nil(report["external_action"]) ->
        {resolution, report}

      attempt == 1 and recoverable?(resolution) ->
        resolve(
          delivery,
          plan_step,
          plan,
          problem,
          workspace,
          sha,
          feedback,
          source,
          2,
          resolution
        )

      resolution.status == "finished" ->
        throw({:halt, {:needs_input, Diagnostics.planning_question(report["external_action"])}})

      true ->
        successful!(resolution)
    end
  end

  defp recoverable?(%{status: "finished", receipt: %{"cleanup" => "group_empty"}}), do: true

  defp recoverable?(%{status: "failed", receipt: receipt}) do
    receipt["cleanup"] == "group_empty" and
      receipt["outcome"] in ["invalid_report", "exited"] and
      receipt["exit_kind"] == "exit" and is_integer(receipt["exit_code"]) and
      receipt["eof"] == %{"stdout" => true, "stderr" => true}
  end

  defp recoverable?(_), do: false

  defp failed_execution?(%{routing_version: 2}, %{status: "failed", receipt: r}),
    do:
      r["outcome"] == "exited" and r["cleanup"] == "group_empty" and
        r["exit_kind"] == "exit" and is_integer(r["exit_code"]) and
        (r["exit_code"] != 0 or
           get_in(r, ["summary", "error_class"]) in ["model_unavailable", "unknown"]) and
        r["eof"] == %{"stdout" => true, "stderr" => true}

  defp failed_execution?(_, %{status: "failed", receipt: r}),
    do:
      r["outcome"] == "exited" and r["cleanup"] == "group_empty" and
        r["exit_kind"] == "exit" and is_integer(r["exit_code"]) and r["exit_code"] != 0 and
        r["eof"] == %{"stdout" => true, "stderr" => true}

  defp failed_execution?(_, _), do: false

  defp version(delivery), do: Map.get(delivery, :autonomy_version, 0)
  defp autonomous?(delivery), do: version(delivery) == 1

  defp profile(delivery, kind, cycle, plan_step),
    do: ok!(Deliveries.model_profile(delivery, kind, cycle, if(plan_step, do: plan_step.id)))

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
  def run_reviewer(reviewer, path, prompt, decode, profile \\ nil)

  def run_reviewer("codex", path, prompt, decode, profile),
    do: run_agent(:review, path, prompt, decode, profile)

  def run_reviewer("claude", _path, prompt, decode, _profile) do
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

  @doc false
  def run_resolution(path, prompt, profile) do
    receipt =
      run_agent(:resolve, path, prompt, &Protocol.resolution_detailed/1, profile,
        report_diagnostics: true
      )

    diagnostics = Map.take(receipt, ["validation_code", "report_bytes"])

    receipt
    |> Map.drop(["validation_code", "report_bytes"])
    |> Map.update("summary", diagnostics, &Map.merge(&1, diagnostics))
  end

  @doc false
  def run_agent(kind, path, prompt, decode, profile \\ nil, opts \\ []) do
    continue!()
    executable = System.find_executable("codex") || throw({:halt, :codex_unavailable})

    if kind == :implement do
      agent_process(
        executable,
        Codex.args(:implement, nil, profile),
        path,
        prompt,
        not is_nil(profile),
        opts
      )
    else
      case ReportFile.with_file(fn output, file ->
             receipt =
               agent_process(
                 executable,
                 Codex.args(kind, output, profile),
                 path,
                 prompt,
                 not is_nil(profile),
                 opts
               )

             if Keyword.get(opts, :report_diagnostics, false) do
               decode_report(receipt, output, file, decode)
             else
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
             end
           end) do
        {:error, reason} ->
          if Keyword.get(opts, :report_diagnostics, false),
            do: %{
              "status" => "failed",
              "cleanup" => "not_started",
              "outcome" => "failed",
              "validation_code" => "report_unavailable",
              "report_bytes" => nil
            },
            else: failure(reason)

        receipt ->
          receipt
      end
    end
  end

  defp decode_report(receipt, output, file, decode) do
    receipt =
      Map.merge(receipt, %{"report_bytes" => ReportFile.size(file), "validation_code" => nil})

    if receipt["status"] == "finished" do
      case ReportFile.read_checked(output, file) do
        {:ok, text, bytes} ->
          case decode.(text) do
            {:ok, report} ->
              Map.merge(receipt, %{
                "report" => report,
                "report_bytes" => bytes,
                "validation_code" => "valid"
              })

            {:error, code} when is_atom(code) ->
              receipt
              |> Map.merge(failure(:invalid_report))
              |> Map.put("validation_code", Atom.to_string(code))
          end

        {:error, code, bytes} ->
          receipt
          |> Map.merge(failure(:invalid_report))
          |> Map.merge(%{"report_bytes" => bytes, "validation_code" => Atom.to_string(code)})
      end
    else
      receipt
    end
  end

  defp agent_process(executable, args, path, prompt, drain_model_errors?, opts) do
    continue!()
    parser = :ets.new(:delivery_codex, [:set, :public])
    :ets.insert(parser, {:state, Codex.new()})

    try do
      callback = fn event ->
        [{:state, state}] = :ets.lookup(parser, :state)
        state = Codex.feed(state, event)
        :ets.insert(parser, {:state, state})
        # A framed model error may precede its natural nonzero exit. Preserve that
        # evidence for routing, while the transport keeps its time/output/Stop bounds.
        if state.error && not (drain_model_errors? and state.error == :agent_error),
          do: :stop,
          else: :ok
      end

      result =
        Runner.run(executable, args,
          cd: path,
          input: prompt,
          timeout_ms: agent_timeout(opts),
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

  defp agent_timeout(opts) do
    case Keyword.get(opts, :deadline_ms) do
      nil ->
        1_200_000

      deadline when is_integer(deadline) ->
        remaining = deadline - System.monotonic_time(:millisecond) - 5_000
        if remaining > 0, do: min(remaining, 1_200_000), else: throw({:halt, :planning_deadline})
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
    shared_agent_failure!(delivery, saved)
    {saved, value}
  end

  defp shared_agent_failure!(%{routing_version: 2}, %{status: "failed", receipt: receipt}) do
    if receipt["cleanup"] == "group_empty" and
         receipt["eof"] == %{"stdout" => true, "stderr" => true} do
      case get_in(receipt, ["summary", "error_class"]) do
        "auth" -> throw({:halt, :provider_auth})
        "rate_limit" -> throw({:halt, :provider_rate_limit})
        "schema" -> throw({:halt, :provider_schema})
        "transport" -> throw({:halt, :provider_transport})
        _ -> :ok
      end
    end
  end

  defp shared_agent_failure!(_, _), do: :ok

  defp begin_step(delivery, kind, cycle, input) do
    continue!()

    case Deliveries.begin_step(delivery.id, kind, cycle, input) do
      {:error, :scope_conflict} when kind == "implement" and cycle == 1 ->
        receive do
          :stop -> throw({:halt, :cancelled})
        after
          500 -> begin_step(delivery, kind, cycle, input)
        end

      {:error, :execution_quarantined} when kind == "implement" ->
        throw({:halt, :execution_quarantined})

      result ->
        stored!(result)
    end
  end

  defp successful!(%{receipt: %{"status" => "finished"}}), do: :ok
  defp successful!(%{receipt: %{"status" => "cancelled"}}), do: throw({:halt, :cancelled})
  defp successful!(%{receipt: %{"status" => "interrupted"}}), do: throw({:halt, :cleanup_unknown})

  defp successful!(%{receipt: %{"outcome" => "candidate_changed"}}),
    do: throw({:halt, :candidate_changed})

  defp successful!(%{kind: kind, receipt: receipt}),
    do: throw({:halt, {:stage_failed, Diagnostics.step_failure(kind, receipt)}})

  defp halt(delivery, reason) do
    receipt = failure(reason)
    if id = Process.delete(:delivery_step), do: Deliveries.finish_step(id, receipt)
    Deliveries.complete(delivery.id, receipt["status"], receipt["reason"], failure_code(reason))
  rescue
    _ -> {:error, :storage_error}
  catch
    _, _ -> {:error, :storage_error}
  end

  defp failure_code(reason)
       when reason in [
              :catalog_unavailable,
              :catalog_invalid,
              :catalog_insufficient_models,
              :codex_unavailable,
              :models_exhausted,
              :provider_auth,
              :provider_rate_limit,
              :provider_schema,
              :provider_transport
            ],
       do: Atom.to_string(reason)

  defp failure_code(_), do: nil

  defp failure(reason) do
    {status, cleanup, message} =
      case reason do
        {:needs_input, message} ->
          {"needs_input", "group_empty", message}

        {:stage_failed, message} ->
          {"failed", "group_empty", message}

        reason when reason in [:command_unavailable, :target_changed] ->
          {"failed", "group_empty", Diagnostics.message(Atom.to_string(reason))}

        :cancelled ->
          {"cancelled", "group_empty", "Stopped. No further automatic stage will start."}

        reason when reason in [:storage_error, :cleanup_unknown] ->
          {"interrupted", "unknown",
           "Execution or storage outcome is unknown. Retained for inspection; no automatic restart."}

        :input_too_large ->
          {"failed", "group_empty",
           "Complete delivery input exceeds the 1 MiB limit. Nothing was truncated."}

        :candidate_changed ->
          {"failed", "group_empty", Boss.Deliveries.Diagnostics.message("candidate_changed")}

        :execution_quarantined ->
          {"failed", "group_empty",
           "Another execution has unknown cleanup. No further implementation started; inspect the interrupted workflow."}

        :claude_unavailable ->
          {"failed", "not_started",
           "Claude is unavailable in BOSS's PATH. No fallback was started."}

        :codex_unavailable ->
          {"failed", "not_started", "Codex is unavailable in BOSS's PATH."}

        :models_exhausted ->
          {"failed", "group_empty",
           "No eligible model remains after recorded execution failures. Restore model access before starting another workflow."}

        reason
        when reason in [
               :catalog_unavailable,
               :catalog_invalid,
               :catalog_insufficient_models,
               :provider_auth,
               :provider_rate_limit,
               :provider_schema,
               :provider_transport
             ] ->
          {"failed", "group_empty", Diagnostics.message(Atom.to_string(reason))}

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
