defmodule Boss.Deliveries.IntegrationWorker do
  @moduledoc false
  alias Boss.{Deliveries, Repo}
  alias Boss.Deliveries.{Integration, Protocol, Worker}
  alias Boss.Agents.Workspace
  alias Boss.Checks.Candidate

  def execute(delivery, repo, manager) do
    Repo.put_dynamic_repo(repo)

    result =
      try do
        perform(delivery)
      rescue
        _ -> Deliveries.interrupt(delivery.id)
      catch
        :throw, {:halt, reason} -> halt(delivery, reason)
        _, _ -> Deliveries.interrupt(delivery.id)
      end

    send(manager, {:delivery_finished, delivery.id, self(), result})
  end

  defp perform(delivery) do
    {project, revision} = Deliveries.inputs(delivery)
    steps = Deliveries.steps(delivery.id)
    review = steps |> Enum.reverse() |> Enum.find(&(&1.kind == "review"))
    check = Enum.find(steps, &(&1.id == review.input["check_step_id"]))
    plan = Enum.find(steps, &(&1.id == review.input["plan_step_id"]))
    ok!(continue())
    target = ok!(Workspace.plan(project, delivery.id)).base_commit
    ok!(Integration.preflight(project, delivery.id, target))
    original = check.input["workspace"]
    approved = review.input["candidate_commit"]
    ok!(Candidate.verify(original, approved))

    {candidate, sha, final_review} =
      if target == delivery.intent["base_commit"] do
        {original, approved, review}
      else
        merge(delivery, project, revision.original_text, plan, review, check, target)
      end

    ok!(continue())
    intent = ok!(Integration.plan(project, delivery.id, candidate, sha, target))
    ok!(Deliveries.set_integration_intent(delivery.id, intent))

    step =
      ok!(
        Deliveries.begin_step(delivery.id, "publish", delivery.cycle, %{
          "intent" => intent,
          "review_step_id" => final_review.id
        })
      )

    publish(delivery, step, intent)
  end

  defp merge(delivery, project, source, plan, original_review, original_check, target) do
    base = delivery.intent["base_commit"]
    approved = original_review.input["candidate_commit"]
    original = original_check.input["workspace"]

    case Workspace.git(project.root_path, ["merge-base", "--is-ancestor", base, target]) do
      {:ok, _} -> :ok
      {:error, {:git_exit, _}} -> throw({:halt, :target_rewritten})
      error -> ok!(error)
    end

    candidate = ok!(Candidate.plan(original["run_workspace"], Ecto.UUID.generate()))

    {merge, sha} =
      stage(
        delivery,
        "merge",
        %{
          "original_review_step_id" => original_review.id,
          "original_check_step_id" => original_check.id,
          "plan_step_id" => plan.id,
          "original_candidate" => approved,
          "original_base" => base,
          "target_commit" => target,
          "workspace" => candidate
        },
        fn ->
          ok!(Integration.preflight(project, delivery.id, target))
          ok!(Candidate.verify(original, approved))
          merged = ok!(Candidate.prepare_merge(candidate, target, approved))
          ok!(Integration.preflight(project, delivery.id, target))

          {%{
             "status" => "finished",
             "cleanup" => "group_empty",
             "workspace" => candidate,
             "candidate_commit" => merged.candidate_commit
           }, merged.candidate_commit}
        end
      )

    verify = fn ->
      with :ok <- Candidate.verify(original, approved),
           :ok <- Candidate.verify_merge(candidate, sha, target, approved),
           do: Integration.preflight(project, delivery.id, target)
    end

    {check, output} =
      stage(
        delivery,
        "merge_check",
        %{
          "merge_step_id" => merge.id,
          "candidate_commit" => sha,
          "target_commit" => target,
          "workspace" => candidate
        },
        fn ->
          {receipt, output} = Worker.run_check(candidate["path"], delivery.check_config, verify)
          {Map.put(receipt, "candidate_commit", sha), output}
        end
      )

    ok!(continue())

    input = %{
      "specification" => source,
      "plan" => plan.receipt["report"],
      "base_commit" => base,
      "target_commit" => target,
      "candidate_commit" => sha,
      "original_candidate" => approved,
      "original_review" => original_review.receipt["report"],
      "diff" => diff(candidate["path"], base, sha),
      "target_diff" => diff(candidate["path"], target, sha),
      "check_config" => delivery.check_config,
      "check_receipt" => check.receipt,
      "check_output" => output,
      "reviewer" => delivery.reviewer
    }

    kind = if delivery.reviewer == "claude", do: :claude_merge_review, else: :merge_review
    prompt = ok!(Protocol.prompt(kind, input))

    {review, report} =
      stage(
        delivery,
        "merge_review",
        %{
          "merge_step_id" => merge.id,
          "merge_check_step_id" => check.id,
          "original_review_step_id" => original_review.id,
          "plan_step_id" => plan.id,
          "candidate_commit" => sha,
          "target_commit" => target,
          "original_base" => base,
          "output_hash" => check.receipt["output_hash"],
          "input_hash" => Protocol.digest(input)
        },
        fn ->
          ok!(verify.())

          receipt =
            Worker.run_reviewer(
              delivery.reviewer,
              candidate["path"],
              prompt,
              &Protocol.review(&1, plan.receipt["report"])
            )

          receipt = Worker.verify_agent(receipt, verify)
          {Map.put(receipt, "candidate_commit", sha), receipt["report"]}
        end
      )

    case report["verdict"] do
      "approved" -> {candidate, sha, review}
      "needs_spec_revision" -> throw({:halt, :merge_needs_spec})
      _ -> throw({:halt, :merge_changes_requested})
    end
  end

  defp diff(path, from, to) do
    diff =
      ok!(
        Workspace.git(path, [
          "diff",
          "--no-ext-diff",
          "--no-textconv",
          "--binary",
          "--full-index",
          from,
          to,
          "--"
        ])
      )

    unless String.valid?(diff), do: throw({:halt, :invalid_input})
    diff
  end

  defp stage(delivery, kind, input, fun) do
    ok!(continue())

    input =
      Map.merge(input, %{
        "spec_revision_id" => delivery.spec_revision_id,
        "config_hash" => delivery.config_hash
      })

    step = ok!(Deliveries.begin_step(delivery.id, kind, delivery.cycle, input))
    Process.put(:integration_step, step.id)
    ok!(continue())
    {receipt, value} = fun.()
    saved = ok!(Deliveries.finish_step(step.id, receipt))
    Process.delete(:integration_step)

    case receipt do
      %{"status" => "finished"} -> {saved, value}
      %{"cleanup" => "unknown"} -> throw({:halt, :cleanup_unknown})
      %{"status" => "cancelled"} -> throw({:halt, :cancelled})
      _ -> throw({:halt, {:stage_failed, kind}})
    end
  end

  defp halt(delivery, reason) do
    if step = Process.delete(:integration_step) do
      unknown = reason in [:cleanup_unknown, :publication_unknown, :storage_error]

      ok!(
        Deliveries.finish_step(step, %{
          "status" =>
            if(unknown,
              do: "interrupted",
              else: if(reason == :cancelled, do: "cancelled", else: "failed")
            ),
          "cleanup" => if(unknown, do: "unknown", else: "group_empty"),
          "outcome" => if(is_atom(reason), do: Atom.to_string(reason), else: "stage_failed")
        })
      )
    end

    stop(delivery, reason)
  rescue
    _ -> {:error, :storage_error}
  catch
    _, _ -> {:error, :storage_error}
  end

  defp ok!(:ok), do: :ok
  defp ok!({:ok, value}), do: value
  defp ok!({:error, reason}), do: throw({:halt, reason})

  defp publish(delivery, step, intent) do
    result =
      with :ok <- continue(),
           :ok <- Integration.prepare(intent),
           :ok <- continue(),
           do:
             Integration.publish(intent,
               authorize: fn -> Deliveries.authorize_publication(delivery.id) end
             )

    case result do
      {:ok, sha} ->
        with {:ok, _} <-
               Deliveries.finish_step(step.id, %{
                 "status" => "finished",
                 "cleanup" => "group_empty",
                 "candidate_commit" => sha
               }),
             :ok <- continue(),
             {:ok, check} <-
               Deliveries.begin_step(delivery.id, "post_check", delivery.cycle, %{
                 "intent" => intent,
                 "publish_step_id" => step.id,
                 "config_hash" => delivery.config_hash
               }) do
          {receipt, _output} =
            Worker.run_check(intent["path"], delivery.check_config, fn ->
              Integration.verify_published(intent)
            end)

          receipt = Map.put(receipt, "candidate_commit", sha)

          with {:ok, _} <- Deliveries.finish_step(check.id, receipt) do
            case receipt do
              %{"status" => "finished"} ->
                with :ok <- continue(),
                     :ok <- Integration.release(intent),
                     :ok <- Integration.verify_published(intent),
                     :ok <- continue() do
                  Deliveries.complete(delivery.id, "done")
                else
                  {:error, reason} -> stop(delivery, reason)
                end

              %{"cleanup" => "unknown"} ->
                Deliveries.interrupt(delivery.id)

              _ ->
                Deliveries.complete(
                  delivery.id,
                  "blocked",
                  "The commit was published, but post-integration checks did not pass. Target was not rolled back; inspect the retained checkout."
                )
            end
          end
        else
          {:error, reason} -> stop(delivery, reason)
        end

      {:error, reason} ->
        unknown = reason in [:cleanup_unknown, :publication_unknown, :storage_error]

        status =
          if unknown,
            do: "interrupted",
            else: if(reason == :cancelled, do: "cancelled", else: "failed")

        with {:ok, _} <-
               Deliveries.finish_step(step.id, %{
                 "status" => status,
                 "cleanup" => if(unknown, do: "unknown", else: "group_empty")
               }) do
          stop(delivery, reason)
        end
    end
  end

  defp stop(d, reason) when reason in [:cleanup_unknown, :publication_unknown, :storage_error],
    do: Deliveries.interrupt(d.id)

  defp stop(d, :cancelled),
    do:
      Deliveries.complete(
        d.id,
        "cancelled",
        "Stopped. Any published commit and all workspaces are retained."
      )

  defp stop(d, :target_checked_out),
    do:
      Deliveries.complete(
        d.id,
        "blocked",
        "Target branch is checked out in another worktree. BOSS will not change that checkout. Release the target before starting another delivery."
      )

  defp stop(d, reason) when reason in [:target_changed, :target_drift],
    do:
      Deliveries.complete(
        d.id,
        "blocked",
        "Target branch changed again during integration. Retained evidence is stale; no automatic retry."
      )

  defp stop(d, :merge_needs_spec),
    do:
      Deliveries.complete(
        d.id,
        "needs_input",
        "Integration review needs specification clarification. Source and merge candidate retained."
      )

  defp stop(d, :merge_changes_requested),
    do:
      Deliveries.complete(
        d.id,
        "blocked",
        "Integration review requested changes. Merge candidate retained; no automatic retry."
      )

  defp stop(d, :merge_conflict),
    do:
      Deliveries.complete(
        d.id,
        "blocked",
        "The current target conflicts with the approved candidate. No publication occurred; resolve through a fresh workflow."
      )

  defp stop(d, :target_rewritten),
    do:
      Deliveries.complete(
        d.id,
        "blocked",
        "Target history no longer descends from the original base. No merge or publication occurred."
      )

  defp stop(d, _),
    do:
      Deliveries.complete(
        d.id,
        "blocked",
        "Integration could not verify the saved candidate, target or ownership. Workspaces retained; no automatic retry."
      )

  defp continue do
    receive do
      :stop -> {:error, :cancelled}
    after
      0 -> :ok
    end
  end
end
