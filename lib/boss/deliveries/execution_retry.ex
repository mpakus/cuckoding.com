defmodule Boss.Deliveries.ExecutionRetry do
  @moduledoc "A new, explicit recovery from a verified implementation timeout; old evidence stays immutable."
  alias Boss.{Deliveries, Projects, Repo, Tasks}
  alias Boss.Deliveries.{Delivery, Protocol, Step}

  def parent(parent) do
    all = Deliveries.steps(parent.id)
    implementation = List.last(all)
    plan = if implementation, do: Enum.find(all, &(&1.id == implementation.input["plan_step_id"]))

    terminal =
      Repo.get_by(Tasks.Event,
        task_id: parent.task_id,
        command_id: parent.id <> ":complete:failed"
      )

    project = Repo.get(Projects.Project, parent.project_id)

    with true <-
           parent.status == "failed" and parent.cleanup == "group_empty" and
             parent.autonomy_version == 1 and parent.routing_version == 2,
         true <- parent.integration_intent == %{} and is_nil(parent.integration_command_id),
         :ok <- Boss.Agents.ModelCatalog.validate(parent.model_catalog),
         %{action: "delivery_progress", to_state: "failed"} <- terminal,
         true <-
           terminal.version == parent.task_version + 1 and
             terminal.spec_revision_id == parent.spec_revision_id,
         %Step{kind: "implement", cycle: cycle} <- implementation,
         true <- cycle == parent.cycle and timeout?(implementation),
         true <- Deliveries.implementation_base?(parent, implementation),
         %Step{kind: "plan", status: "finished"} <- plan,
         {:ok, report} <- Protocol.plan(JSON.encode!(plan.receipt["report"])),
         true <- report["acceptance"] != [] and is_nil(report["clarification"]),
         true <- passed?(plan.receipt) or retained?(parent, plan),
         true <- identity?(project, parent.intent),
         true <-
           Enum.all?([plan, implementation], fn s ->
             s.input["config_hash"] == parent.config_hash and
               s.input["spec_revision_id"] == parent.spec_revision_id
           end),
         true <- workspace?(parent, implementation.input["workspace"]),
         true <- is_binary(get_in(implementation.input, ["model_profile", "model"])) do
      {:ok, %{parent: parent, implementation: implementation, plan: plan, terminal: terminal}}
    else
      _ -> {:error, :execution_retry_unavailable}
    end
  end

  def source(%Delivery{retry_implementation_id: nil}), do: {:ok, nil}

  def source(child) do
    with %Step{} = implementation <- Repo.get(Step, child.retry_implementation_id),
         %Delivery{} = parent <- Repo.get(Delivery, implementation.delivery_id),
         {:ok, source} <- parent(parent),
         true <-
           source.implementation.id == child.retry_implementation_id and
             child.execution_recovery_version == 1,
         true <- child.admitted_version == source.terminal.version,
         true <-
           Enum.all?(
             [
               :project_id,
               :task_id,
               :spec_revision_id,
               :check_config,
               :config_hash,
               :reviewer,
               :autonomy_version,
               :routing_version,
               :model_catalog
             ],
             &(Map.fetch!(child, &1) == Map.fetch!(parent, &1))
           ) do
      {:ok, source}
    else
      _ -> {:error, :execution_retry_unavailable}
    end
  end

  def verify(nil), do: :ok

  def verify(source) do
    parent = source.parent
    workspace = source.implementation.input["workspace"]

    with true <- identity?(Repo.get(Projects.Project, parent.project_id), parent.intent),
         true <- workspace?(parent, workspace),
         {:ok, info} <- Boss.Agents.Workspace.inspect(workspace),
         {:ok, _} <-
           Boss.Agents.Workspace.git(parent.intent["repo_path"], [
             "merge-base",
             "--is-ancestor",
             parent.intent["base_commit"],
             info.head_commit
           ]) do
      :ok
    else
      {:error, reason} when reason in [:cleanup_unknown, :cancelled, :unsupported_platform] ->
        {:error, reason}

      _ ->
        {:error, :candidate_changed}
    end
  end

  def timeout?(step), do: Boss.Deliveries.ModelPolicy.timeout_recoverable?(1, step)

  def seed_input?(d, i) do
    with {:ok, %{} = source} <- source(d) do
      i["workspace"] == d.intent and i["source_implementation_id"] == source.implementation.id and
        i["source_plan_id"] == source.plan.id and is_nil(i["model_profile"])
    else
      _ -> false
    end
  end

  def seed_receipt?(step, r) do
    d = Repo.get!(Delivery, step.delivery_id)

    with true <- step.number == 1 and step.cycle == 0 and seed_input?(d, step.input),
         {:ok, source} <- source(d) do
      Enum.sort(Map.keys(r)) == ~w(cleanup outcome report status workspace) and
        r["status"] == "finished" and r["cleanup"] == "group_empty" and
        r["outcome"] == "retained_plan" and
        r["report"] == source.plan.receipt["report"] and r["workspace"] == d.intent
    else
      _ -> false
    end
  end

  def valid_next?(
        %Delivery{execution_recovery_version: 1} = d,
        previous,
        "timeout_snapshot",
        cycle,
        i
      )
      when cycle in 0..4 do
    implementation = saved(i["implementation_step_id"])
    plan = saved(i["plan_step_id"])
    candidate = i["workspace"]

    with true <- timeout?(implementation),
         %Step{delivery_id: id, kind: "plan", status: "finished"} <- plan,
         true <- id == d.id and is_map(candidate) and map_size(candidate) == 4,
         {:ok, _} <- Ecto.UUID.cast(candidate["check_id"]),
         true <- candidate["run_workspace"] == implementation.input["workspace"],
         true <- candidate["ref"] == "refs/boss/checks/" <> candidate["check_id"],
         true <-
           is_binary(candidate["path"]) and
             candidate["path"] != candidate["run_workspace"]["path"] do
      if cycle == 0 do
        previous.id == plan.id and plan.number == 1 and
          implementation.id == d.retry_implementation_id and retained?(d, plan)
      else
        previous.id == implementation.id and implementation.delivery_id == d.id and
          implementation.cycle == cycle and
          i["plan_step_id"] == implementation.input["plan_step_id"]
      end
    else
      _ -> false
    end
  end

  def valid_next?(
        %Delivery{execution_recovery_version: 1} = d,
        %Step{kind: "timeout_snapshot", status: "finished"} = s,
        "timeout_check",
        cycle,
        i
      ),
      do:
        cycle == s.cycle and i["snapshot_step_id"] == s.id and
          i["implementation_step_id"] == s.input["implementation_step_id"] and
          i["plan_step_id"] == s.input["plan_step_id"] and
          i["workspace"] == s.receipt["workspace"] and
          i["candidate_commit"] == s.receipt["candidate_commit"] and
          i["config_hash"] == d.config_hash

  def valid_next?(_, _, _, _, _), do: false

  def check?(%Step{kind: "timeout_check", status: status, input: i, receipt: r}) do
    r["cleanup"] == "group_empty" and r["exit_kind"] == "exit" and is_integer(r["exit_code"]) and
      r["eof"] == %{"stdout" => true, "stderr" => true} and
      r["output_complete"] == true and hash?(r["output_hash"]) and
      r["candidate_commit"] == i["candidate_commit"] and
      ((status == "finished" and r["exit_code"] == 0) or
         (status == "failed" and r["outcome"] == "checks_failed" and is_integer(r["exit_code"]) and
            r["exit_code"] != 0))
  end

  def check?(_), do: false

  def repair_model(d, kind, steps) when kind in ["resolve", "implement"] do
    if d.execution_recovery_version == 1 do
      source =
        case List.last(steps) do
          %Step{kind: "resolve", input: i} -> saved(i["source_step_id"])
          step -> step
        end

      case implementation(source) do
        %Step{kind: "implement", input: input} -> get_in(input, ["model_profile", "model"])
        _ -> nil
      end
    end
  end

  def repair_model(_, _, _), do: nil

  defp implementation(%Step{kind: "implement"} = step), do: step

  defp implementation(%Step{kind: kind, input: i}) when kind in ["timeout_check", "snapshot"],
    do: saved(i["implementation_step_id"])

  defp implementation(%Step{kind: "check", input: i}),
    do: implementation(saved(i["snapshot_step_id"]))

  defp implementation(%Step{kind: "review", input: i}),
    do: implementation(saved(i["check_step_id"]))

  defp implementation(_), do: nil
  defp saved(id) when is_binary(id), do: Repo.get(Step, id)
  defp saved(_), do: nil

  defp retained?(d, plan),
    do:
      d.execution_recovery_version == 1 and plan.number == 1 and
        plan.receipt["outcome"] == "retained_plan" and plan.receipt["cleanup"] == "group_empty"

  defp workspace?(d, w),
    do:
      is_map(w) and map_size(w) == 8 and
        Enum.all?(~w(project_id repo_path git_common_dir base_branch), &(w[&1] == d.intent[&1])) and
        sha?(w["base_commit"]) and is_binary(w["path"]) and is_binary(w["branch"])

  defp identity?(nil, _), do: false

  defp identity?(p, i),
    do:
      i["project_id"] == to_string(p.id) and i["repo_path"] == p.root_path and
        i["git_common_dir"] == p.git_common_dir and i["base_branch"] == p.base_branch and
        sha?(i["base_commit"])

  defp passed?(r),
    do:
      r["cleanup"] == "group_empty" and r["exit_kind"] == "exit" and is_integer(r["exit_code"]) and
        r["exit_code"] == 0 and
        r["eof"] == %{"stdout" => true, "stderr" => true}

  defp sha?(s), do: is_binary(s) and Regex.match?(~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/, s)
  defp hash?(s), do: is_binary(s) and Regex.match?(~r/\A[0-9a-f]{64}\z/, s)
end
