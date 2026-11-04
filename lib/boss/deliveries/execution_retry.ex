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

  def checkpoint_parent(parent) do
    case parent(parent) do
      {:ok, source} -> {:ok, Map.merge(source, %{check: nil, candidate_commit: nil})}
      _ -> checked_parent(parent)
    end
  end

  defp checked_parent(parent) do
    all = Deliveries.steps(parent.id)
    last = List.last(all)
    check = if last && last.kind == "resolve", do: saved(last.input["source_step_id"]), else: last
    snapshot = if check, do: saved(check.input["snapshot_step_id"])
    implementation = if snapshot, do: saved(snapshot.input["implementation_step_id"])
    plan = if check, do: saved(check.input["plan_step_id"])

    terminal =
      Repo.get_by(Tasks.Event,
        task_id: parent.task_id,
        command_id: parent.id <> ":complete:" <> parent.status
      )

    with true <-
           parent.status in ~w(failed blocked needs_input) and parent.cleanup == "group_empty" and
             parent.autonomy_version == 1 and parent.routing_version == 2,
         true <-
           parent.integration_intent == %{} and is_nil(parent.integration_command_id) and
             parent.failure_code not in ~w(provider_auth provider_rate_limit provider_schema provider_transport),
         :ok <- Boss.Agents.ModelCatalog.validate(parent.model_catalog),
         %{action: "delivery_progress"} <- terminal,
         true <-
           terminal.to_state == parent.status and terminal.version == parent.task_version + 1 and
             terminal.spec_revision_id == parent.spec_revision_id,
         %Step{kind: kind, status: "failed", delivery_id: delivery_id, cycle: cycle} <- check,
         true <-
           kind in ~w(check timeout_check checkpoint_check) and delivery_id == parent.id and
             cycle == parent.cycle and (complete_failed_check?(check) or check_timeout?(check)),
         true <- terminal_checkpoint?(last, check),
         %Step{status: "finished", delivery_id: ^delivery_id, cycle: ^cycle} <- snapshot,
         true <-
           snapshot.kind == snapshot_kind(kind) and snapshot.receipt["cleanup"] == "group_empty" and
             snapshot.number == check.number - 1,
         true <-
           snapshot.receipt["candidate_commit"] == check.input["candidate_commit"] and
             snapshot.receipt["workspace"] == check.input["workspace"],
         %Step{kind: "implement"} <- implementation,
         true <- checkpoint_implementation?(parent, check, snapshot, implementation),
         %Step{kind: "plan", status: "finished", delivery_id: ^delivery_id} <- plan,
         {:ok, report} <- Protocol.plan(JSON.encode!(plan.receipt["report"])),
         true <-
           report["acceptance"] != [] and is_nil(report["clarification"]) and
             (passed?(plan.receipt) or retained?(parent, plan)),
         true <-
           Enum.all?([plan, check, snapshot], fn step ->
             step.input["config_hash"] == parent.config_hash and
               step.input["spec_revision_id"] == parent.spec_revision_id
           end),
         true <- snapshot.input["plan_step_id"] == plan.id,
         true <- identity?(Repo.get(Projects.Project, parent.project_id), parent.intent),
         true <- workspace?(parent, implementation.input["workspace"]),
         true <- is_binary(get_in(implementation.input, ["model_profile", "model"])) do
      {:ok,
       %{
         parent: parent,
         implementation: implementation,
         plan: plan,
         check: check,
         terminal: terminal,
         candidate_commit: check.input["candidate_commit"]
       }}
    else
      _ -> {:error, :checkpoint_retry_unavailable}
    end
  end

  defp complete_failed_check?(s),
    do: check?(%{s | kind: "timeout_check"}) and sha?(s.input["candidate_commit"])

  defp snapshot_kind("check"), do: "snapshot"
  defp snapshot_kind("timeout_check"), do: "timeout_snapshot"
  defp snapshot_kind("checkpoint_check"), do: "checkpoint_snapshot"

  defp checkpoint_implementation?(p, c, s, i) do
    c.input["plan_step_id"] == s.input["plan_step_id"] and
      cond do
        c.kind == "check" ->
          i.delivery_id == p.id and i.cycle == c.cycle and i.status == "finished" and
            passed?(i.receipt) and i.input["plan_step_id"] == c.input["plan_step_id"] and
            Deliveries.implementation_base?(p, i)

        c.kind == "timeout_check" ->
          timeout?(i) and
            ((c.cycle == 0 and i.id == p.retry_implementation_id) or
               (i.delivery_id == p.id and i.cycle == c.cycle and
                  Deliveries.implementation_base?(p, i)))

        c.kind == "checkpoint_check" ->
          p.checkpoint_recovery_version == 1 and c.cycle == 0 and
            i.id == p.retry_implementation_id and
            c.input["source_check_id"] == p.retry_source_check_id

        true ->
          false
      end
  end

  defp terminal_checkpoint?(%Step{id: id}, %Step{id: id}), do: true

  defp terminal_checkpoint?(%Step{kind: "resolve"} = last, check) do
    r = last.receipt

    last.delivery_id == check.delivery_id and last.cycle == check.cycle and
      last.input["source_step_id"] == check.id and
      last.input["plan_step_id"] == check.input["plan_step_id"] and
      last.input["workspace"] == check.input["workspace"] and
      last.input["candidate_commit"] == check.input["candidate_commit"] and
      r["candidate_commit"] == check.input["candidate_commit"] and
      r["cleanup"] == "group_empty" and r["exit_kind"] == "exit" and is_integer(r["exit_code"]) and
      r["eof"] == %{"stdout" => true, "stderr" => true} and
      get_in(r, ["summary", "error_class"]) not in ~w(auth rate_limit schema transport) and
      ((last.status == "finished" and passed?(r) and
          match?({:ok, _}, Protocol.resolution(JSON.encode!(r["report"])))) or
         (last.status == "failed" and r["outcome"] in ~w(exited invalid_report)))
  end

  defp terminal_checkpoint?(_, _), do: false

  def source(%Delivery{retry_implementation_id: nil}), do: {:ok, nil}

  def source(child) do
    with %Step{} = implementation <- Repo.get(Step, child.retry_implementation_id),
         %Delivery{} = parent <- Repo.get(Delivery, source_parent_id(child, implementation)),
         {:ok, source} <-
           if(child.checkpoint_recovery_version == 1,
             do: checkpoint_parent(parent),
             else: parent(parent)
           ),
         true <-
           source.implementation.id == child.retry_implementation_id and
             child.execution_recovery_version == 1,
         true <- child.admitted_version == source.terminal.version,
         true <-
           child.checkpoint_recovery_version == 0 or
             (child.implementation_network_version == 1 and
                child.retry_source_check_id == if(source.check, do: source.check.id)),
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

  defp source_parent_id(%Delivery{retry_source_check_id: id}, _) when is_binary(id) do
    case saved(id) do
      %Step{delivery_id: parent} -> parent
      _ -> nil
    end
  end

  defp source_parent_id(_, implementation), do: implementation.delivery_id

  def verify(nil), do: :ok

  def verify(%{check: %Step{} = check} = source) do
    with true <-
           identity?(Repo.get(Projects.Project, source.parent.project_id), source.parent.intent),
         :ok <- Boss.Checks.Candidate.verify(check.input["workspace"], source.candidate_commit),
         {:ok, _} <-
           Boss.Agents.Workspace.git(source.parent.intent["repo_path"], [
             "merge-base",
             "--is-ancestor",
             source.parent.intent["base_commit"],
             source.candidate_commit
           ]) do
      :ok
    else
      {:error, reason} when reason in [:cleanup_unknown, :cancelled, :unsupported_platform] ->
        {:error, reason}

      _ ->
        {:error, :candidate_changed}
    end
  end

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
        i["source_plan_id"] == source.plan.id and is_nil(i["model_profile"]) and
        (d.checkpoint_recovery_version == 0 or i["source_check_id"] == d.retry_source_check_id)
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
        %Delivery{checkpoint_recovery_version: 1} = d,
        %Step{kind: "plan", number: 1, status: "finished"} = p,
        "checkpoint_snapshot",
        0,
        i
      ) do
    with {:ok, %{check: %Step{} = check} = source} <- source(d),
         true <-
           i["source_check_id"] == check.id and
             i["implementation_step_id"] == source.implementation.id and i["plan_step_id"] == p.id,
         true <- i["source_candidate_commit"] == source.candidate_commit,
         {:ok, _} <- Ecto.UUID.cast(i["check_id"]),
         {:ok, _} <- Ecto.UUID.cast(i["run_workspace"]["run_id"]),
         true <- workspace?(d, i["run_workspace"]) do
      w = i["run_workspace"]

      w["base_commit"] == source.candidate_commit and w["run_id"] != d.id and
        w["run_id"] != source.implementation.input["workspace"]["run_id"] and
        w["branch"] == "codex/boss-run-" <> w["run_id"] and
        w["path"] == Path.join(Path.dirname(d.intent["path"]), w["run_id"]) and
        i["check_id"] != check.input["workspace"]["check_id"]
    else
      _ -> false
    end
  end

  def valid_next?(
        %Delivery{checkpoint_recovery_version: 1} = d,
        %Step{kind: "checkpoint_snapshot", status: "finished", cycle: 0} = s,
        "checkpoint_check",
        0,
        i
      ),
      do:
        i["snapshot_step_id"] == s.id and i["source_check_id"] == d.retry_source_check_id and
          i["implementation_step_id"] == d.retry_implementation_id and
          i["plan_step_id"] == s.input["plan_step_id"] and
          i["workspace"] == s.receipt["workspace"] and
          i["candidate_commit"] == s.receipt["candidate_commit"] and
          i["config_hash"] == d.config_hash

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

  def checkpoint_snapshot_receipt?(i, r) do
    w = r["workspace"]

    is_map(w) and map_size(w) == 4 and w["run_workspace"] == i["run_workspace"] and
      w["check_id"] == i["check_id"] and
      w["ref"] == "refs/boss/checks/" <> i["check_id"] and is_binary(w["path"]) and
      sha?(r["candidate_commit"])
  end

  def check_timeout?(%Step{kind: kind} = step)
      when kind in ~w(check timeout_check checkpoint_check),
      do:
        check_timeout?(step.receipt) and sha?(step.input["candidate_commit"]) and
          step.receipt["candidate_commit"] == step.input["candidate_commit"]

  def check_timeout?(
        %{"status" => "failed", "output_complete" => false, "output_hash" => nil} = receipt
      ), do: timeout?(%{kind: "implement", status: "failed", receipt: receipt})

  def check_timeout?(_), do: false

  def check?(%Step{kind: kind, status: status, input: i, receipt: r})
      when kind in ["timeout_check", "checkpoint_check"] do
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

  defp implementation(%Step{kind: kind, input: i})
       when kind in ["timeout_check", "checkpoint_check", "snapshot"],
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
