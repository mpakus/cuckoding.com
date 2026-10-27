defmodule Boss.Deliveries do
  @moduledoc "Explicit managed delivery, with immutable stage receipts and manual publication."
  import Ecto.Query
  alias Boss.{Repo, Runs, Tasks}
  alias Boss.Deliveries.{Delivery, Step}
  alias Boss.Projects.{Project, Spec, SpecRevision}
  @active ~w(planning implementing testing reviewing integrating)
  @terminal ~w(done blocked needs_input failed cancelled interrupted)
  @stages %{
    "plan" => "planning",
    "implement" => "implementing",
    "snapshot" => "testing",
    "check" => "testing",
    "review" => "reviewing",
    "publish" => "integrating",
    "post_check" => "integrating"
  }
  @receipt_keys ~w(status cleanup exit_kind exit_code signal eof outcome reason report summary workspace head_commit candidate_commit stdout_bytes stderr_bytes output_hash output_complete input_hash)

  def active?(%Delivery{status: status}), do: status in @active

  def start(project, task, command, text, server \\ Boss.Runs.Manager),
    do: GenServer.call(server, {:delivery_start, project, task, command, text}, 10_000)

  def integrate(project, id, command, server \\ Boss.Runs.Manager),
    do: GenServer.call(server, {:delivery_integrate, project, id, command}, 10_000)

  def stop(project, id, registry \\ Boss.Runs.Active), do: Runs.stop(project, id, registry)

  def inputs(delivery),
    do:
      {Repo.get!(Project, delivery.project_id),
       Repo.get!(SpecRevision, delivery.spec_revision_id)}

  def get(project, id), do: Repo.get_by(Delivery, project_id: project, id: id)

  def steps(id),
    do: Repo.all(from s in Step, where: s.delivery_id == ^id, order_by: s.number, limit: 20)

  def list(project, task) do
    Repo.all(
      from d in Delivery,
        where: d.project_id == ^project and d.task_id == ^task,
        order_by: [desc: d.inserted_at, desc: d.id],
        limit: 3
    )
    |> Repo.preload(steps: from(s in Step, order_by: s.number))
  end

  def busy?,
    do: Repo.exists?(from d in Delivery, where: d.status in ^@active or d.cleanup == "unknown")

  defp run_busy?,
    do:
      Repo.exists?(
        from r in Runs.Run,
          where: r.status in ~w(preparing launching running stopping) or r.cleanup == "unknown"
      )

  @doc false
  def admit(project, task, command, text, replay_only \\ false) do
    with true <- valid_id?(project) and valid_id?(task),
         {:ok, _} <- Ecto.UUID.cast(command),
         {:ok, config, hash} <- Boss.Checks.Command.parse(text) do
      transaction(fn ->
        case Repo.get_by(Delivery, task_id: task, command_id: command) do
          %Delivery{project_id: ^project, check_config: ^config, config_hash: ^hash} = saved ->
            {:existing, saved}

          %Delivery{} ->
            Repo.rollback(:idempotency_conflict)

          nil ->
            {task, _} =
              Repo.one(
                from t in Tasks.Task,
                  join: s in Spec,
                  on: s.id == t.spec_id,
                  where: t.id == ^task and s.project_id == ^project,
                  select: {t, s}
              ) || Repo.rollback(:not_found)

            if replay_only or busy?() or run_busy?(), do: Repo.rollback(:busy)

            unless task.state in ~w(new failed cancelled blocked needs_input interrupted),
              do: Repo.rollback(:task_unavailable)

            case Tasks.Dependencies.check(project, task.id) do
              :ok -> :ok
              {:error, reason} -> Repo.rollback(reason)
            end

            case Repo.one(
                   from d in Delivery,
                     where: d.task_id == ^task.id and d.status == "ready_to_merge"
                 ) do
              nil ->
                :ok

              %Delivery{task_version: version} = saved when version != task.state_version ->
                save!(saved,
                  status: "cancelled",
                  reason:
                    "Task changed after approval. A fresh explicit workflow replaced this approval."
                )

              _ ->
                Repo.rollback(:task_unavailable)
            end

            delivery =
              Repo.insert!(%Delivery{
                id: Ecto.UUID.generate(),
                project_id: project,
                task_id: task.id,
                spec_revision_id: task.spec_revision_id,
                admitted_version: task.state_version,
                task_version: task.state_version,
                command_id: command,
                check_config: config,
                config_hash: hash
              })

            {:new, sync_task!(delivery, "admit")}
        end
      end)
    else
      _ -> {:error, :invalid_command}
    end
  end

  @doc false
  def admit_integration(project, id, command, replay_only \\ false) do
    with true <- valid_id?(project),
         {:ok, _} <- Ecto.UUID.cast(id),
         {:ok, _} <- Ecto.UUID.cast(command) do
      transaction(fn ->
        delivery = get(project, id) || Repo.rollback(:not_found)

        cond do
          delivery.integration_command_id == command ->
            {:existing, delivery}

          delivery.integration_command_id != nil ->
            Repo.rollback(:idempotency_conflict)

          replay_only or busy?() or run_busy?() ->
            Repo.rollback(:busy)

          delivery.status != "ready_to_merge" ->
            Repo.rollback(:not_ready)

          true ->
            current_task!(delivery)
            approved!(delivery)

            delivery =
              save!(delivery,
                status: "integrating",
                cleanup: "pending",
                integration_command_id: command
              )

            {:new, sync_task!(delivery, "integrate")}
        end
      end)
    else
      _ -> {:error, :invalid_command}
    end
  end

  def set_intent(id, intent), do: set_saved_intent(id, :intent, intent)
  def set_integration_intent(id, intent), do: set_saved_intent(id, :integration_intent, intent)

  defp set_saved_intent(id, field, value) do
    transaction(fn ->
      delivery = owned!(id)
      unless bounded_map?(value, 16_384), do: Repo.rollback(:invalid_intent)
      current = Map.fetch!(delivery, field)

      cond do
        current == value ->
          delivery

        current != %{} ->
          Repo.rollback(:immutable_intent)

        field == :intent and delivery.status == "planning" ->
          project = Repo.get!(Project, delivery.project_id)

          unless value["run_id"] == delivery.id and value["project_id"] == to_string(project.id) and
                   value["repo_path"] == project.root_path and
                   value["git_common_dir"] == project.git_common_dir and
                   value["base_branch"] == project.base_branch and sha?(value["base_commit"]),
                 do: Repo.rollback(:invalid_intent)

          save!(delivery, [{field, value}])

        field == :integration_intent and delivery.status == "integrating" ->
          review = approved!(delivery)

          unless value["delivery_id"] == delivery.id and
                   value["base_commit"] == delivery.intent["base_commit"] and
                   value["candidate_commit"] == review.input["candidate_commit"] and
                   value["repo_path"] == delivery.intent["repo_path"] and
                   value["base_branch"] == delivery.intent["base_branch"],
                 do: Repo.rollback(:invalid_intent)

          save!(delivery, [{field, value}])

        true ->
          Repo.rollback(:invalid_intent)
      end
    end)
  end

  def begin_step(id, kind, cycle, input) do
    result =
      transaction(fn ->
        delivery = owned!(id)
        current_task!(delivery)
        if delivery.cleanup == "unknown", do: Repo.rollback(:cleanup_unknown)

        unless Map.has_key?(@stages, kind) and is_integer(cycle) and cycle in 0..3 and
                 bounded_map?(input, 65_536),
               do: Repo.rollback(:invalid_step)

        previous = latest(id)

        unless valid_next?(delivery, previous, kind, cycle, input),
          do: Repo.rollback(:invalid_step)

        number = if previous, do: previous.number + 1, else: 1
        if number > 20, do: Repo.rollback(:budget_exhausted)

        step =
          Repo.insert!(%Step{
            id: Ecto.UUID.generate(),
            delivery_id: id,
            project_id: delivery.project_id,
            number: number,
            kind: kind,
            cycle: cycle,
            input: input
          })

        delivery |> save!(status: @stages[kind], cycle: cycle) |> sync_task!(step.id)
        step
      end)

    broadcast_result(result)
  end

  def finish_step(id, receipt) do
    result =
      transaction(fn ->
        step = Repo.get(Step, id) || Repo.rollback(:not_found)
        delivery = owned!(step.delivery_id)

        unless step.status == "running" and valid_receipt?(step, receipt),
          do: Repo.rollback(:invalid_receipt)

        if receipt["cleanup"] == "unknown", do: save!(delivery, cleanup: "unknown")

        save!(step, receipt: receipt, status: receipt["status"])
        |> Map.put(:project_id, delivery.project_id)
      end)

    broadcast_result(result)
  end

  def complete(id, status, reason \\ nil) do
    result =
      transaction(fn ->
        delivery = owned!(id)

        unless status in (@terminal ++ ["ready_to_merge"]) and valid_reason?(reason),
          do: Repo.rollback(:invalid_receipt)

        pending = latest(id)
        if pending && pending.status == "running", do: Repo.rollback(:step_running)

        cond do
          status == "ready_to_merge" ->
            current_task!(delivery)
            approved!(delivery)

          status == "done" ->
            current_task!(delivery)
            integrated!(delivery)

          true ->
            :ok
        end

        unknown = delivery.cleanup == "unknown" or status == "interrupted"

        delivery
        |> save!(
          status: status,
          reason: reason,
          cleanup: if(unknown, do: "unknown", else: "group_empty")
        )
        |> sync_task!("complete:#{status}", true)
      end)

    broadcast_result(result)
  end

  @doc false
  def authorize_publication(id) do
    case transaction(fn ->
           d = owned!(id)
           current_task!(d)
           approved!(d)

           unless d.status == "integrating" and d.integration_intent != %{} and
                    match?(%Step{kind: "publish", status: "running"}, latest(id)),
                  do: Repo.rollback(:missing_evidence)
         end) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc false
  def interrupt(id), do: transaction(fn -> interrupt_record(id) end) |> broadcast_result()

  defp interrupt_record(id) do
    delivery = Repo.get(Delivery, id) || Repo.rollback(:not_found)

    if active?(delivery) do
      case latest(id) do
        %Step{status: "running"} = step ->
          save!(step,
            status: "interrupted",
            receipt: %{"status" => "interrupted", "cleanup" => "unknown"}
          )

        _ ->
          :ok
      end

      delivery
      |> save!(
        status: "interrupted",
        cleanup: "unknown",
        reason:
          "Execution stopped without a final receipt. No automatic restart or publication retry."
      )
      |> sync_task!("interrupt", true)
    else
      delivery
    end
  end

  @doc false
  def reconcile do
    result =
      transaction(fn ->
        for id <- Repo.all(from d in Delivery, where: d.status in ^@active, select: d.id),
            do: interrupt_record(id)
      end)

    case result do
      {:ok, deliveries} -> Enum.each(deliveries, &broadcast/1)
      _ -> :ok
    end

    result
  end

  @doc false
  def transition_changes(task, command) do
    case Repo.get(Delivery, command[:delivery_id]) do
      %Delivery{task_id: task_id, spec_revision_id: revision, task_version: version} = delivery
      when task_id == task.id and revision == task.spec_revision_id and
             version == task.state_version ->
        if delivery.status in (@active ++ @terminal ++ ["ready_to_merge"]) and
             task.state != "done" do
          {:ok, %{state: delivery.status, recovery_state: nil, attention_reason: delivery.reason}}
        else
          {:error, :invalid_transition}
        end

      _ ->
        {:error, :stale_state}
    end
  end

  defp valid_next?(d, nil, "plan", 0, i),
    do: d.status == "planning" and d.intent != %{} and i["workspace"] == d.intent

  defp valid_next?(_, %Step{status: "running"}, _, _, _), do: false

  defp valid_next?(_, %Step{kind: "plan", status: "finished", id: id}, "implement", 1, i),
    do: i["plan_step_id"] == id

  defp valid_next?(
         _,
         %Step{kind: "implement", status: "finished", id: id, cycle: cycle},
         "snapshot",
         cycle,
         i
       ),
       do: i["implementation_step_id"] == id

  defp valid_next?(
         d,
         %Step{kind: "snapshot", status: "finished", id: id, cycle: cycle, receipt: r},
         "check",
         cycle,
         i
       ),
       do:
         i["snapshot_step_id"] == id and i["candidate_commit"] == r["candidate_commit"] and
           i["workspace"] == r["workspace"] and i["config_hash"] == d.config_hash

  defp valid_next?(
         d,
         %Step{kind: "check", status: "finished", id: id, cycle: cycle, input: prior, receipt: r},
         "review",
         cycle,
         i
       ),
       do:
         i["check_step_id"] == id and i["candidate_commit"] == prior["candidate_commit"] and
           i["config_hash"] == d.config_hash and
           i["original_base"] == d.intent["base_commit"] and r["output_complete"] == true and
           hash?(i["input_hash"])

  defp valid_next?(_, %Step{kind: kind, cycle: cycle} = previous, "implement", next, i)
       when kind in ["check", "review"] do
    next == cycle + 1 and next <= 3 and i["parent_step_id"] == previous.id and
      ((kind == "check" and previous.status == "failed" and
          previous.receipt["output_complete"] == true and
          previous.receipt["outcome"] == "checks_failed" and
          previous.receipt["exit_kind"] == "exit" and
          is_integer(previous.receipt["exit_code"]) and previous.receipt["exit_code"] != 0) or
         (kind == "review" and previous.status == "finished" and
            get_in(previous.receipt, ["report", "verdict"]) == "changes_requested")) and
      previous.receipt["cleanup"] == "group_empty"
  end

  defp valid_next?(
         d,
         %Step{kind: "review", status: "finished", cycle: cycle},
         "publish",
         cycle,
         i
       ),
       do:
         d.status == "integrating" and d.integration_intent != %{} and
           i["intent"] == d.integration_intent

  defp valid_next?(
         d,
         %Step{kind: "publish", status: "finished", cycle: cycle, id: id},
         "post_check",
         cycle,
         i
       ),
       do:
         d.status == "integrating" and i["publish_step_id"] == id and
           i["intent"] == d.integration_intent and i["config_hash"] == d.config_hash

  defp valid_next?(_, _, _, _, _), do: false

  defp valid_receipt?(step, receipt) do
    bounded_map?(receipt, 131_072) and Enum.all?(Map.keys(receipt), &(&1 in @receipt_keys)) and
      receipt["status"] in ~w(finished failed cancelled interrupted) and
      receipt["cleanup"] in ~w(group_empty not_started unknown) and
      (receipt["status"] != "finished" or receipt["cleanup"] == "group_empty") and
      (receipt["status"] != "finished" or success_receipt?(step, receipt))
  end

  defp success_receipt?(%Step{kind: "snapshot"}, r),
    do: sha?(r["candidate_commit"]) and is_map(r["workspace"])

  defp success_receipt?(%Step{kind: "publish", input: input}, r),
    do: r["candidate_commit"] == input["intent"]["candidate_commit"]

  defp success_receipt?(%Step{kind: kind}, r) do
    process_passed?(r) and
      case kind do
        "plan" ->
          valid_plan?(r["report"])

        "review" ->
          match?({:ok, _}, Boss.Reviews.Verdict.decode(JSON.encode!(r["report"])))

        k when k in ["check", "post_check"] ->
          r["output_complete"] == true and hash?(r["output_hash"])

        "implement" ->
          is_map(r["workspace"]) and sha?(r["head_commit"])
      end
  end

  defp process_passed?(r),
    do:
      r["exit_kind"] == "exit" and r["exit_code"] == 0 and
        r["eof"] == %{"stdout" => true, "stderr" => true}

  defp valid_plan?(%{"summary" => summary, "steps" => steps, "acceptance" => acceptance} = report) do
    map_size(report) == 3 and text?(summary, 2000) and is_list(steps) and length(steps) in 1..20 and
      Enum.all?(steps, &text?(&1, 2000)) and is_list(acceptance) and length(acceptance) in 1..20 and
      Enum.all?(acceptance, &text?(&1, 1000)) and
      length(Enum.uniq(acceptance)) == length(acceptance)
  end

  defp valid_plan?(_), do: false

  defp approved!(d) do
    all = steps(d.id)

    review =
      Enum.find(Enum.reverse(all), &(&1.kind == "review")) || Repo.rollback(:missing_evidence)

    check =
      Enum.find(all, &(&1.id == review.input["check_step_id"])) ||
        Repo.rollback(:missing_evidence)

    plan =
      Enum.find(all, &(&1.id == review.input["plan_step_id"])) || Repo.rollback(:missing_evidence)

    report = review.receipt["report"] || %{}
    criteria = Enum.map(report["acceptance"] || [], & &1["criterion"])

    unless review.status == "finished" and check.kind == "check" and check.status == "finished" and
             plan.kind == "plan" and plan.status == "finished" and report["verdict"] == "approved" and
             review.cycle == d.cycle and check.cycle == d.cycle and
             check.input["config_hash"] == d.config_hash and
             review.input["config_hash"] == d.config_hash and
             review.input["original_base"] == d.intent["base_commit"] and
             sha?(review.input["candidate_commit"]) and
             review.input["candidate_commit"] == check.input["candidate_commit"] and
             check.receipt["output_complete"] == true and hash?(check.receipt["output_hash"]) and
             MapSet.new(criteria) == MapSet.new(plan.receipt["report"]["acceptance"]),
           do: Repo.rollback(:missing_evidence)

    review
  end

  defp integrated!(d) do
    approved!(d)
    all = steps(d.id)
    post = List.last(all)
    publish = Enum.find(all, &(&1.kind == "publish"))

    unless d.status == "integrating" and d.integration_command_id != nil and
             match?(%Step{kind: "publish"}, publish) and match?(%Step{kind: "post_check"}, post) and
             post.status == "finished" and
             publish.status == "finished" and
             post.input["publish_step_id"] == publish.id and
             post.input["intent"] == d.integration_intent and
             publish.input["intent"] == d.integration_intent and
             post.input["config_hash"] == d.config_hash and
             post.receipt["candidate_commit"] == d.integration_intent["candidate_commit"] and
             publish.receipt["candidate_commit"] == d.integration_intent["candidate_commit"],
           do: Repo.rollback(:missing_evidence)
  end

  defp owned!(id) do
    delivery = Repo.get(Delivery, id) || Repo.rollback(:not_found)
    unless active?(delivery), do: Repo.rollback(:not_active)
    delivery
  end

  defp current_task!(d) do
    task = Repo.get!(Tasks.Task, d.task_id)

    unless task.spec_revision_id == d.spec_revision_id and task.state_version == d.task_version,
      do: Repo.rollback(:stale_state)

    task
  end

  defp latest(id),
    do:
      Repo.one(from s in Step, where: s.delivery_id == ^id, order_by: [desc: s.number], limit: 1)

  defp save!(record, attrs), do: record |> Ecto.Changeset.change(attrs) |> Repo.update!()

  defp sync_task!(d, suffix, allow_external_change \\ false) do
    task = Repo.get!(Tasks.Task, d.task_id)

    if allow_external_change and
         (task.state_version != d.task_version or task.spec_revision_id != d.spec_revision_id) do
      d
    else
      transition_task!(d, suffix)
    end
  end

  defp transition_task!(d, suffix) do
    case Tasks.transition(d.task_id, %{
           command_id: "#{d.id}:#{suffix}",
           expected_version: d.task_version,
           action: "delivery_progress",
           delivery_id: d.id
         }) do
      {:ok, _event} when d.status in @terminal -> d
      {:ok, event} -> save!(d, task_version: event.version)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp broadcast_result({:ok, %Step{} = step} = result) do
    Runs.broadcast(%{project_id: step.project_id})
    result
  end

  defp broadcast_result({:ok, %Delivery{} = d} = result),
    do:
      (
        broadcast(d)
        result
      )

  defp broadcast_result(result), do: result
  def broadcast(d), do: Runs.broadcast(d)
  defp valid_id?(n), do: is_integer(n) and n > 0 and n <= 9_223_372_036_854_775_807

  defp text?(v, n),
    do:
      is_binary(v) and byte_size(v) in 1..n and String.valid?(v) and String.trim(v) != "" and
        not String.contains?(v, <<0>>)

  defp valid_reason?(nil), do: true
  defp valid_reason?(value), do: text?(value, 1000)
  defp sha?(v), do: is_binary(v) and Regex.match?(~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/, v)
  defp hash?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{64}\z/, v)
  defp bounded_map?(v, n), do: is_map(v) and byte_size(JSON.encode!(v)) <= n

  defp transaction(fun) do
    selector = Repo.get_dynamic_repo()
    pid = if is_atom(selector), do: Process.whereis(selector), else: selector

    if is_pid(pid) and Process.alive?(pid) do
      Repo.put_dynamic_repo(pid)

      try do
        Repo.transaction(fun, mode: :immediate)
      rescue
        _ in [Exqlite.Error, Ecto.ConstraintError, DBConnection.ConnectionError] ->
          {:error, :storage_error}
      catch
        :exit, _ -> {:error, :storage_error}
      after
        Repo.put_dynamic_repo(selector)
      end
    else
      {:error, :storage_error}
    end
  end
end
