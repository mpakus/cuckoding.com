defmodule Boss.Deliveries.Retry do
  @moduledoc "Explicit new delivery from a retained rejected review; no old approval is inherited."
  alias Boss.{Deliveries, Projects, Repo}
  alias Boss.Deliveries.{Delivery, Protocol, Step}
  alias Boss.Agents.Workspace
  alias Boss.Checks.Candidate

  def start(project, parent, command, server \\ Boss.Runs.Manager),
    do: GenServer.call(server, {:delivery_retry, project, parent, command}, 10_000)

  def start_timeout(project, parent, command, server \\ Boss.Runs.Manager),
    do: GenServer.call(server, {:delivery_timeout_retry, project, parent, command}, 10_000)

  def start_checkpoint(project, parent, command, server \\ Boss.Runs.Manager),
    do: GenServer.call(server, {:delivery_checkpoint_retry, project, parent, command}, 10_000)

  def start_candidate(project, parent, command, candidate, server \\ Boss.Runs.Manager),
    do:
      GenServer.call(
        server,
        {:delivery_candidate_retry, project, parent, command, candidate},
        10_000
      )

  @doc false
  def valid_candidate?(nil), do: true
  def valid_candidate?(candidate), do: sha?(candidate)

  @doc false
  def parent(parent, candidate \\ nil) do
    steps = Deliveries.steps(parent.id)
    last = List.last(steps)
    review = if candidate, do: Enum.find(Enum.reverse(steps), &(&1.kind == "review")), else: last
    status = if candidate, do: "failed", else: "blocked"
    check = if review, do: Enum.find(steps, &(&1.id == review.input["check_step_id"]))
    plan = if review, do: Enum.find(steps, &(&1.id == review.input["plan_step_id"]))
    project = Repo.get(Projects.Project, parent.project_id)

    terminal =
      Repo.get_by(Boss.Tasks.Event,
        task_id: parent.task_id,
        command_id: parent.id <> ":complete:" <> status
      )

    with true <- parent.execution_recovery_version == 0,
         true <- parent.status == status and parent.cleanup == "group_empty",
         true <- parent.integration_intent == %{} and is_nil(parent.integration_command_id),
         %{version: version, action: "delivery_progress", to_state: ^status} <- terminal,
         true <-
           version == parent.task_version + 1 and
             terminal.spec_revision_id == parent.spec_revision_id,
         %Step{kind: "review", status: "finished"} <- review,
         %Step{kind: "check", status: "finished"} <- check,
         %Step{kind: "plan", status: "finished"} <- plan,
         true <- Enum.all?([plan, check, review], &passed?/1),
         {:ok, typed_plan} <- Protocol.plan(JSON.encode!(plan.receipt["report"])),
         {:ok, report} <- Protocol.review(JSON.encode!(review.receipt["report"]), typed_plan),
         true <- report["verdict"] == "changes_requested",
         true <- check.receipt["output_complete"] == true,
         true <- check.cycle == review.cycle and terminal_stage?(parent, last, review, candidate),
         true <- check.input["candidate_commit"] == review.input["candidate_commit"],
         true <- review.input["original_base"] == parent.intent["base_commit"],
         true <- is_map(check.input["workspace"]) and sha?(review.input["candidate_commit"]),
         true <-
           Enum.all?([plan, check, review], fn step ->
             step.input["config_hash"] == parent.config_hash and
               step.input["spec_revision_id"] == parent.spec_revision_id
           end),
         true <- identity?(project, parent.intent) do
      {:ok,
       %{
         parent: parent,
         plan: plan,
         check: check,
         review: review,
         terminal: terminal,
         candidate_commit: candidate || review.input["candidate_commit"]
       }}
    else
      _ -> {:error, :retry_unavailable}
    end
  end

  @doc false
  def source(%Delivery{retry_review_id: nil}), do: {:ok, nil}

  def source(%Delivery{} = child) do
    with %Step{} = review <- Repo.get(Step, child.retry_review_id),
         %Delivery{} = parent <- Repo.get(Delivery, review.delivery_id),
         {:ok, source} <- parent(parent, child.retry_candidate_commit),
         true <- source.review.id == child.retry_review_id,
         true <-
           Enum.all?(
             [
               :project_id,
               :task_id,
               :spec_revision_id,
               :check_config,
               :config_hash,
               :reviewer,
               :implementer,
               :analytic,
               :autonomy_version,
               :routing_version,
               :model_catalog
             ],
             &(Map.fetch!(child, &1) == Map.fetch!(parent, &1))
           ),
         true <- child.admitted_version == source.terminal.version do
      {:ok, source}
    else
      _ -> {:error, :retry_unavailable}
    end
  end

  @doc false
  def verify(nil), do: :ok

  def verify(source) do
    parent = source.parent
    sha = source.review.input["candidate_commit"]

    with true <- identity?(Repo.get(Projects.Project, parent.project_id), parent.intent),
         :ok <- Candidate.verify(source.check.input["workspace"], sha),
         :ok <- verify_seed(parent.intent["repo_path"], sha, source.candidate_commit),
         {:ok, _} <-
           Workspace.git(parent.intent["repo_path"], [
             "merge-base",
             "--is-ancestor",
             parent.intent["base_commit"],
             sha
           ]) do
      :ok
    else
      {:error, :cleanup_unknown} = error -> error
      {:error, :cancelled} = error -> error
      _ -> {:error, :candidate_changed}
    end
  end

  @doc false
  def preserved_plan?(id, report) do
    with %Delivery{} = delivery <- Repo.get(Delivery, id),
         {:ok, source} <- source(delivery) do
      is_nil(source) or
        MapSet.new(report["acceptance"]) ==
          MapSet.new(source.plan.receipt["report"]["acceptance"])
    else
      _ -> false
    end
  end

  @doc false
  def valid_next?(%Delivery{retry_review_id: nil}, _, _, _, _), do: false

  def valid_next?(d, %Step{kind: "plan", status: "finished"} = plan, "retry_snapshot", 0, i) do
    with {:ok, source} <- source(d),
         true <- i["source_review_id"] == d.retry_review_id and i["plan_step_id"] == plan.id,
         true <- i["source_candidate_commit"] == source.candidate_commit,
         {:ok, _} <- Ecto.UUID.cast(i["check_id"]),
         workspace when is_map(workspace) <- i["run_workspace"] do
      workspace["base_commit"] == i["source_candidate_commit"] and
        workspace["repo_path"] == d.intent["repo_path"] and
        workspace["git_common_dir"] == d.intent["git_common_dir"] and
        workspace["base_branch"] == d.intent["base_branch"] and
        workspace["project_id"] == to_string(d.project_id) and workspace["run_id"] != d.id and
        i["check_id"] != source.check.input["workspace"]["check_id"]
    else
      _ -> false
    end
  end

  def valid_next?(
        d,
        %Step{kind: "retry_snapshot", status: "finished"} = snapshot,
        "retry_check",
        0,
        i
      ),
      do:
        i["snapshot_step_id"] == snapshot.id and
          i["plan_step_id"] == snapshot.input["plan_step_id"] and
          i["source_review_id"] == d.retry_review_id and
          i["workspace"] == snapshot.receipt["workspace"] and
          i["candidate_commit"] == snapshot.receipt["candidate_commit"] and
          i["config_hash"] == d.config_hash

  def valid_next?(d, %Step{kind: "retry_check"} = check, "implement", 1, i),
    do:
      repairable?(check) and i["parent_step_id"] == check.id and
        i["plan_step_id"] == check.input["plan_step_id"] and
        i["source_review_id"] == d.retry_review_id and
        get_in(i, ["workspace", "base_commit"]) == check.input["candidate_commit"]

  def valid_next?(_, _, _, _, _), do: false

  @doc false
  def snapshot_receipt?(input, receipt) do
    workspace = receipt["workspace"]

    is_map(workspace) and workspace["check_id"] == input["check_id"] and
      workspace["run_workspace"] == input["run_workspace"] and
      workspace["ref"] == "refs/boss/checks/#{input["check_id"]}" and
      sha?(receipt["candidate_commit"])
  end

  defp terminal_stage?(parent, review, review, nil), do: review.cycle == parent.cycle

  defp terminal_stage?(parent, %Step{kind: "check", status: "finished"} = last, review, candidate)
       when is_binary(candidate) do
    last.cycle == parent.cycle and last.cycle > review.cycle and last.number > review.number and
      passed?(last) and last.receipt["output_complete"] == true and
      sha?(last.input["candidate_commit"]) and
      last.input["candidate_commit"] == last.receipt["candidate_commit"] and
      last.input["plan_step_id"] == review.input["plan_step_id"] and
      last.input["config_hash"] == parent.config_hash and
      last.input["spec_revision_id"] == parent.spec_revision_id
  end

  defp terminal_stage?(_, _, _, _), do: false

  defp verify_seed(_, sha, sha), do: :ok

  defp verify_seed(repo, reviewed, candidate) do
    with {:ok, "commit"} <- Workspace.git(repo, ["cat-file", "-t", candidate]),
         {:ok, _} <- Workspace.git(repo, ["merge-base", "--is-ancestor", reviewed, candidate]) do
      :ok
    else
      {:error, reason} when reason in [:cleanup_unknown, :cancelled] -> {:error, reason}
      _ -> {:error, :candidate_changed}
    end
  end

  defp repairable?(step) do
    r = step.receipt

    r["cleanup"] == "group_empty" and r["exit_kind"] == "exit" and
      r["eof"] == %{"stdout" => true, "stderr" => true} and r["output_complete"] == true and
      r["candidate_commit"] == step.input["candidate_commit"] and
      ((step.status == "finished" and r["exit_code"] == 0) or
         (step.status == "failed" and r["outcome"] == "checks_failed" and
            is_integer(r["exit_code"]) and r["exit_code"] != 0))
  end

  defp passed?(step),
    do:
      step.receipt["cleanup"] == "group_empty" and
        step.receipt["exit_kind"] == "exit" and step.receipt["exit_code"] == 0 and
        step.receipt["eof"] == %{"stdout" => true, "stderr" => true}

  defp identity?(nil, _), do: false

  defp identity?(project, intent),
    do:
      intent["project_id"] == to_string(project.id) and
        intent["repo_path"] == project.root_path and
        intent["git_common_dir"] == project.git_common_dir and
        intent["base_branch"] == project.base_branch and sha?(intent["base_commit"])

  defp sha?(value),
    do: is_binary(value) and Regex.match?(~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/, value)
end
