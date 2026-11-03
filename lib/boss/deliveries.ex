defmodule Boss.Deliveries do
  @moduledoc "Explicit managed delivery, with immutable stage receipts and manual publication."
  import Ecto.Query
  alias Boss.{Repo, Runs, Tasks}
  alias Boss.Deliveries.{Delivery, ModelPolicy, Scheduling, Step}
  alias Boss.Agents.ModelCatalog
  alias Boss.Projects.{Project, Spec, SpecRevision}
  @active ~w(planning implementing testing reviewing integrating)
  @terminal ~w(done blocked needs_input failed cancelled interrupted)
  @failure_codes ~w(catalog_unavailable catalog_invalid catalog_insufficient_models codex_unavailable models_exhausted provider_auth provider_rate_limit provider_schema provider_transport)
  @stages %{
    "plan" => "planning",
    "resolve" => "planning",
    "retry_snapshot" => "planning",
    "retry_check" => "planning",
    "implement" => "implementing",
    "snapshot" => "testing",
    "check" => "testing",
    "review" => "reviewing",
    "merge" => "integrating",
    "merge_check" => "integrating",
    "merge_review" => "integrating",
    "publish" => "integrating",
    "post_check" => "integrating"
  }
  @receipt_keys ~w(status cleanup exit_kind exit_code signal eof outcome reason report summary workspace head_commit candidate_commit stdout_bytes stderr_bytes output_hash output_complete input_hash)

  def active?(%Delivery{status: status}), do: status in @active

  def start(project, task, command, text, server \\ Boss.Runs.Manager),
    do: start(project, task, command, text, "codex", server)

  def start(project, task, command, text, reviewer, server),
    do: GenServer.call(server, {:delivery_start, project, task, command, text, reviewer}, 10_000)

  def integrate(project, id, command, server \\ Boss.Runs.Manager),
    do: GenServer.call(server, {:delivery_integrate, project, id, command}, 10_000)

  def stop(project, id, registry \\ Boss.Runs.Active), do: Runs.stop(project, id, registry)

  def inputs(delivery),
    do:
      {Repo.get!(Project, delivery.project_id),
       Repo.get!(SpecRevision, delivery.spec_revision_id)}

  def get(project, id), do: Repo.get_by(Delivery, project_id: project, id: id)

  def steps(id),
    do: Repo.all(from s in Step, where: s.delivery_id == ^id, order_by: s.number, limit: 48)

  @doc false
  def model_profile(delivery, kind, cycle, plan_step_id \\ nil) do
    d = Repo.get!(Delivery, delivery.id)
    kind = to_string(kind)

    if d.autonomy_version == 0 or (d.reviewer == "claude" and kind in ~w(review merge_review)) do
      {:ok, nil}
    else
      saved_plan =
        case saved_step(plan_step_id) do
          %Step{delivery_id: id, kind: "plan"} = p when id == d.id -> p
          _ -> nil
        end

      if d.routing_version == 2 and ModelCatalog.validate(d.model_catalog) != :ok do
        {:error, :catalog_invalid}
      else
        preferred =
          if kind == "plan" and not is_nil(saved_plan) and saved_plan.status == "failed" and
               known_model_failure?(saved_plan.receipt) do
            attempt =
              if get_in(saved_plan.input, ["model_profile", "model"]) == resolver_model(d),
                do: 2,
                else: 1

            route(d, :resolve, attempt, nil)
          else
            route(
              d,
              kind,
              cycle,
              if(saved_plan, do: saved_plan.receipt["report"])
            )
          end

        saved_steps = steps(d.id)

        excluded =
          saved_steps
          |> Enum.filter(&excluded_model?(d, &1))
          |> Enum.map(&get_in(&1.input, ["model_profile", "model"]))
          |> Enum.reject(&is_nil/1)

        excluded =
          case {kind, cycle, List.last(saved_steps)} do
            {"resolve", 2, %Step{kind: "resolve", input: input}} ->
              [get_in(input, ["model_profile", "model"]) | excluded]

            _ ->
              excluded
          end

        if d.routing_version == 1,
          do: ModelPolicy.select(preferred, excluded),
          else: ModelPolicy.select(preferred, excluded, d.model_catalog)
      end
    end
  end

  defp resolver_model(%Delivery{routing_version: 1}), do: "gpt-6-astra"
  defp resolver_model(d), do: d.model_catalog["resolver"]["model"]

  defp route(%Delivery{routing_version: 1}, kind, cycle, plan),
    do: ModelPolicy.route(1, kind, cycle, plan)

  defp route(d, kind, cycle, plan), do: ModelPolicy.route(2, kind, cycle, plan, d.model_catalog)

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
    do:
      Boss.Projects.Intake.quarantined?() or
        Repo.exists?(from d in Delivery, where: d.status in ^@active or d.cleanup == "unknown")

  defp run_busy?,
    do:
      Repo.exists?(
        from r in Runs.Run,
          where: r.status in ~w(preparing launching running stopping) or r.cleanup == "unknown"
      )

  @doc false
  def admit(project, task, command, text, replay_only \\ false),
    do: admit(project, task, command, text, "codex", replay_only)

  def admit(project, task, command, text, reviewer, replay_only),
    do:
      admit(
        project,
        task,
        command,
        text,
        reviewer,
        replay_only,
        ModelPolicy.current(),
        ModelPolicy.current_routing()
      )

  @doc false
  def admit(project, task, command, text, reviewer, replay_only, autonomy_version),
    do: admit(project, task, command, text, reviewer, replay_only, autonomy_version, 1)

  def admit(
        project,
        task,
        command,
        text,
        reviewer,
        replay_only,
        autonomy_version,
        routing_version
      ) do
    with true <- valid_id?(project) and valid_id?(task),
         true <- reviewer in ["codex", "claude"] and is_boolean(replay_only),
         true <- autonomy_version in [0, 1],
         true <- routing_version in [1, 2] and (routing_version == 1 or autonomy_version == 1),
         {:ok, _} <- Ecto.UUID.cast(command),
         {:ok, config, hash} <- Boss.Checks.Command.parse(text) do
      transaction(fn ->
        case Repo.get_by(Delivery, task_id: task, command_id: command) do
          %Delivery{
            project_id: ^project,
            check_config: ^config,
            config_hash: ^hash,
            reviewer: ^reviewer,
            retry_review_id: nil
          } = saved ->
            {:existing, saved}

          %Delivery{} ->
            Repo.rollback(:idempotency_conflict)

          nil ->
            if Repo.exists?(
                 from r in Boss.Deliveries.Request,
                   where: r.task_id == ^task and r.command_id == ^command
               ),
               do: Repo.rollback(:idempotency_conflict)

            if Boss.Deliveries.Queue.pending?(task), do: Repo.rollback(:task_queued)
            task = queued_task!(project, task)

            {:new,
             admit_new!(
               project,
               task,
               command,
               config,
               hash,
               reviewer,
               replay_only,
               nil,
               nil,
               autonomy_version,
               routing_version
             )}
        end
      end)
    else
      _ -> {:error, :invalid_command}
    end
  end

  @doc false
  def admit_retry(project, parent_id, command, replay_only \\ false, candidate \\ nil) do
    with true <- valid_id?(project) and is_boolean(replay_only),
         true <- Boss.Deliveries.Retry.valid_candidate?(candidate),
         {:ok, _} <- Ecto.UUID.cast(parent_id),
         {:ok, _} <- Ecto.UUID.cast(command) do
      transaction(fn ->
        parent = get(project, parent_id) || Repo.rollback(:not_found)

        case Repo.get_by(Delivery, task_id: parent.task_id, command_id: command) do
          %Delivery{retry_review_id: review_id} = saved when is_binary(review_id) ->
            case Repo.get(Step, review_id) do
              %Step{delivery_id: ^parent_id} when saved.retry_candidate_commit == candidate ->
                {:existing, saved}

              _ ->
                Repo.rollback(:idempotency_conflict)
            end

          %Delivery{} ->
            Repo.rollback(:idempotency_conflict)

          nil ->
            task = queued_task!(project, parent.task_id)
            {:ok, source} = retry_source!(parent, candidate)

            unless task.state == source.terminal.to_state and
                     task.state_version == source.terminal.version,
                   do: Repo.rollback(:retry_unavailable)

            if Boss.Deliveries.Queue.pending?(task.id), do: Repo.rollback(:task_queued)

            if Repo.exists?(
                 from r in Boss.Deliveries.Request,
                   where: r.task_id == ^task.id and r.command_id == ^command
               ),
               do: Repo.rollback(:idempotency_conflict)

            delivery =
              admit_new!(
                project,
                task,
                command,
                parent.check_config,
                parent.config_hash,
                parent.reviewer,
                replay_only,
                source.review.id,
                candidate,
                parent.autonomy_version,
                parent.routing_version,
                parent.model_catalog
              )

            {:new, delivery}
        end
      end)
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp retry_source!(parent, candidate) do
    case Boss.Deliveries.Retry.parent(parent, candidate) do
      {:ok, _} = result -> result
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc false
  def claim(request_id) do
    alias Boss.Deliveries.{Queue, Request}

    transaction(fn ->
      request = Repo.get(Request, request_id) || Repo.rollback(:not_found)
      task = queued_task!(request.project_id, request.task_id)

      cond do
        request.status == "started" ->
          {:existing, request, Repo.get!(Delivery, request.delivery_id)}

        request.status != "queued" ->
          Repo.rollback(:request_unavailable)

        task.spec_revision_id != request.spec_revision_id or
          task.state_version != request.admitted_version or
            task.state not in ~w(new failed cancelled blocked needs_input interrupted) ->
          saved =
            Queue.save!(request,
              status: "stale",
              reason: "Task changed after this request was queued."
            )

          {:stale, saved}

        true ->
          delivery =
            admit_new!(
              request.project_id,
              task,
              request.command_id,
              request.check_config,
              request.config_hash,
              request.reviewer,
              false,
              nil,
              nil,
              request.autonomy_version,
              request.routing_version
            )

          saved = Queue.save!(request, status: "started", delivery_id: delivery.id)
          {:started, saved, delivery}
      end
    end)
  end

  defp queued_task!(project, id) do
    Repo.one(
      from t in Tasks.Task,
        join: s in Spec,
        on: s.id == t.spec_id,
        where: t.id == ^id and s.project_id == ^project,
        select: t
    ) || Repo.rollback(:not_found)
  end

  defp admit_new!(
         project,
         task,
         command,
         config,
         hash,
         reviewer,
         replay_only,
         retry_review_id,
         retry_candidate_commit,
         autonomy_version,
         routing_version,
         model_catalog \\ %{}
       ) do
    if replay_only or managed_busy?() or run_busy?() or
         not Boss.Deliveries.Autopilot.admission_allowed?(task.id, command),
       do: Repo.rollback(:busy)

    unless task.state in ~w(new failed cancelled blocked needs_input interrupted),
      do: Repo.rollback(:task_unavailable)

    case Tasks.Dependencies.check(project, task.id) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end

    case Repo.one(
           from d in Delivery, where: d.task_id == ^task.id and d.status == "ready_to_merge"
         ) do
      nil ->
        :ok

      %Delivery{task_version: version} = saved when version != task.state_version ->
        save!(saved,
          status: "cancelled",
          reason: "Task changed after approval. A fresh explicit workflow replaced this approval."
        )

      _ ->
        Repo.rollback(:task_unavailable)
    end

    Repo.insert!(%Delivery{
      id: Ecto.UUID.generate(),
      project_id: project,
      task_id: task.id,
      spec_revision_id: task.spec_revision_id,
      admitted_version: task.state_version,
      task_version: task.state_version,
      command_id: command,
      retry_review_id: retry_review_id,
      retry_candidate_commit: retry_candidate_commit,
      reviewer: reviewer,
      autonomy_version: autonomy_version,
      routing_version: routing_version,
      model_catalog: model_catalog,
      check_config: config,
      config_hash: hash
    })
    |> sync_task!("admit")
  end

  @doc false
  def managed_busy? do
    Boss.Projects.Intake.busy?() or
      Repo.exists?(from d in Delivery, where: d.status == "integrating" or d.cleanup == "unknown") or
      Repo.aggregate(from(d in Delivery, where: d.status in ^@active), :count) >=
        Scheduling.capacity!()
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

          replay_only or busy?() or run_busy?() or
              not Boss.Deliveries.Autopilot.integration_allowed?(delivery, command) ->
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

  def set_model_catalog(id, snapshot) do
    transaction(fn ->
      d = owned!(id)

      unless d.routing_version == 2 and ModelCatalog.validate(snapshot) == :ok,
        do: Repo.rollback(:catalog_invalid)

      cond do
        d.model_catalog == snapshot -> d
        d.model_catalog != %{} -> Repo.rollback(:immutable_model_catalog)
        d.status != "planning" or not is_nil(latest(d.id)) -> Repo.rollback(:invalid_intent)
        true -> save!(d, model_catalog: snapshot)
      end
    end)
  end

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

          if delivery.retry_review_id do
            source =
              case Boss.Deliveries.Retry.source(delivery) do
                {:ok, source} -> source
                {:error, reason} -> Repo.rollback(reason)
              end

            unless value["base_commit"] == source.parent.intent["base_commit"],
              do: Repo.rollback(:invalid_intent)
          end

          save!(delivery, [{field, value}])

        field == :integration_intent and delivery.status == "integrating" ->
          review = publication_approved!(delivery)

          unless value["delivery_id"] == delivery.id and
                   value["base_commit"] == publication_base(delivery, review) and
                   value["candidate_commit"] == review.input["candidate_commit"] and
                   value["candidate"] == publication_candidate(review) and
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

        unless Map.has_key?(@stages, kind) and is_integer(cycle) and
                 cycle in 0..ModelPolicy.max_cycles(delivery.autonomy_version) and
                 bounded_map?(input, 65_536),
               do: Repo.rollback(:invalid_step)

        input = pin_model!(delivery, kind, cycle, input)

        previous = latest(id)

        unless valid_next?(delivery, previous, kind, cycle, input),
          do: Repo.rollback(:invalid_step)

        if kind == "implement" and Scheduling.quarantined?(),
          do: Repo.rollback(:execution_quarantined)

        if kind == "implement" and Scheduling.blockers(delivery) != [],
          do: Repo.rollback(:scope_conflict)

        number = if previous, do: previous.number + 1, else: 1

        if number > ModelPolicy.max_steps(delivery.autonomy_version),
          do: Repo.rollback(:budget_exhausted)

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

  def complete(id, status, reason \\ nil, failure_code \\ nil) do
    result =
      transaction(fn ->
        delivery = owned!(id)

        unless status in (@terminal ++ ["ready_to_merge"]) and valid_reason?(reason) and
                 (is_nil(failure_code) or
                    (status in ~w(failed blocked needs_input) and failure_code in @failure_codes)),
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
          failure_code: failure_code,
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
           review = publication_approved!(d)
           publish = latest(id)

           unless d.status == "integrating" and d.integration_intent != %{} and
                    match?(%Step{kind: "publish", status: "running"}, publish) and
                    publish.input["review_step_id"] == review.id and
                    publish.input["intent"] == d.integration_intent,
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
      {:ok, deliveries} ->
        unless Repo.in_transaction?(),
          do: deliveries |> Enum.uniq_by(& &1.project_id) |> Enum.each(&broadcast/1)

      _ ->
        :ok
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
    do:
      d.status == "planning" and d.intent != %{} and i["workspace"] == d.intent and
        (is_nil(d.retry_review_id) or i["source_review_id"] == d.retry_review_id)

  defp valid_next?(_, %Step{status: "running"}, _, _, _), do: false

  defp valid_next?(%Delivery{autonomy_version: 1} = d, previous, "resolve", cycle, i),
    do: resolution_input?(d, previous, cycle, i)

  defp valid_next?(
         %Delivery{autonomy_version: 1} = d,
         %Step{kind: "resolve"} = previous,
         "plan",
         0,
         i
       ) do
    resolution_passed?(previous) and previous.cycle == 0 and
      i["parent_step_id"] == previous.id and i["plan_step_id"] == previous.input["plan_step_id"] and
      i["workspace"] == d.intent and
      Repo.aggregate(from(s in Step, where: s.delivery_id == ^d.id and s.kind == "plan"), :count) <
        3
  end

  defp valid_next?(
         %Delivery{autonomy_version: 1} = d,
         %Step{kind: "resolve"} = previous,
         "implement",
         cycle,
         i
       ) do
    resolution_passed?(previous) and previous.cycle > 0 and cycle == previous.cycle + 1 and
      cycle <= ModelPolicy.max_cycles(d.autonomy_version) and
      i["parent_step_id"] == previous.id and i["resolution_step_id"] == previous.id and
      i["source_step_id"] == previous.input["source_step_id"] and
      i["plan_step_id"] == previous.input["plan_step_id"] and
      get_in(i, ["workspace", "base_commit"]) == previous.input["candidate_commit"]
  end

  defp valid_next?(
         d,
         %Step{kind: "plan", status: "finished", id: id, receipt: r},
         "implement",
         1,
         i
       ),
       do:
         is_nil(d.retry_review_id) and i["plan_step_id"] == id and
           (d.autonomy_version == 0 or
              (is_nil(r["report"]["clarification"]) and r["report"]["acceptance"] != []))

  defp valid_next?(d, previous, kind, cycle, input)
       when kind in ["retry_snapshot", "retry_check"] or
              (kind == "implement" and cycle == 1),
       do: Boss.Deliveries.Retry.valid_next?(d, previous, kind, cycle, input)

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

  defp valid_next?(d, %Step{kind: kind, cycle: cycle} = previous, "implement", next, i)
       when kind in ["check", "review"] do
    d.autonomy_version == 0 and next == cycle + 1 and
      next <= ModelPolicy.max_cycles(d.autonomy_version) and
      i["parent_step_id"] == previous.id and
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
         %Step{kind: "review", status: "finished", cycle: cycle} = review,
         "merge",
         cycle,
         i
       ) do
    check = Repo.get(Step, review.input["check_step_id"])

    d.status == "integrating" and d.integration_intent == %{} and
      approved!(d).id == review.id and merge_input?(d, review, check, i)
  end

  defp valid_next?(
         d,
         %Step{kind: "merge", status: "finished", cycle: cycle} = merge,
         "merge_check",
         cycle,
         i
       ),
       do: merge_check_input?(d, merge, i)

  defp valid_next?(
         d,
         %Step{kind: "merge_check", status: "finished", cycle: cycle} = check,
         "merge_review",
         cycle,
         i
       ) do
    merge = Repo.get(Step, check.input["merge_step_id"])
    merge_review_input?(d, merge, check, i)
  end

  defp valid_next?(
         d,
         %Step{kind: kind, status: "finished", cycle: cycle, id: id},
         "publish",
         cycle,
         i
       )
       when kind in ["review", "merge_review"],
       do:
         d.status == "integrating" and d.integration_intent != %{} and
           i["intent"] == d.integration_intent and i["review_step_id"] == id and
           publication_approved!(d).id == id

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

  defp success_receipt?(%Step{kind: "merge", input: input}, r),
    do:
      sha?(r["candidate_commit"]) and
        r["candidate_commit"] not in [input["target_commit"], input["original_candidate"]] and
        r["workspace"] == input["workspace"]

  defp success_receipt?(%Step{kind: kind, input: input}, r)
       when kind in ["merge_check", "merge_review"] do
    r["candidate_commit"] == input["candidate_commit"] and process_passed?(r) and
      case kind do
        "merge_check" -> r["output_complete"] == true and hash?(r["output_hash"])
        "merge_review" -> match?({:ok, _}, Boss.Reviews.Verdict.decode(JSON.encode!(r["report"])))
      end
  end

  defp success_receipt?(%Step{kind: "publish", input: input}, r),
    do: r["candidate_commit"] == input["intent"]["candidate_commit"]

  defp success_receipt?(%Step{kind: "retry_snapshot", input: input}, r),
    do: Boss.Deliveries.Retry.snapshot_receipt?(input, r)

  defp success_receipt?(%Step{kind: "retry_check", input: input}, r),
    do:
      process_passed?(r) and r["candidate_commit"] == input["candidate_commit"] and
        r["output_complete"] == true and hash?(r["output_hash"])

  defp success_receipt?(%Step{kind: "plan"} = step, r),
    do:
      process_passed?(r) and valid_plan?(r["report"]) and
        Boss.Deliveries.Retry.preserved_plan?(step.delivery_id, r["report"]) and
        preserved_replan?(step, r["report"])

  defp success_receipt?(%Step{kind: "resolve", input: input}, r),
    do:
      process_passed?(r) and sha?(r["candidate_commit"]) and
        r["candidate_commit"] == input["candidate_commit"] and
        match?({:ok, _}, Boss.Deliveries.Protocol.resolution(JSON.encode!(r["report"])))

  defp success_receipt?(%Step{kind: kind}, r) do
    process_passed?(r) and
      case kind do
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

  defp pin_model!(d, kind, cycle, input) do
    if d.autonomy_version == 1 and kind in ~w(plan implement review merge_review resolve) and
         not (d.reviewer == "claude" and kind in ~w(review merge_review)) do
      route_cycle = if kind == "resolve", do: input["resolution_attempt"], else: cycle
      unless is_integer(route_cycle), do: Repo.rollback(:invalid_step)

      if (kind == "resolve" and route_cycle not in [1, 2]) or
           (kind == "implement" and route_cycle not in 1..5),
         do: Repo.rollback(:invalid_step)

      profile =
        case model_profile(d, kind, route_cycle, input["plan_step_id"]) do
          {:ok, profile} -> profile
          {:error, reason} -> Repo.rollback(reason)
        end

      unless is_map(profile) and Map.get(input, "model_profile", profile) == profile,
        do: Repo.rollback(:invalid_step)

      Map.put(input, "model_profile", profile)
    else
      input
    end
  end

  defp saved_step(id) when is_binary(id), do: Repo.get(Step, id)
  defp saved_step(_), do: nil

  defp resolution_input?(_, nil, _, _), do: false

  defp resolution_input?(d, previous, cycle, i) do
    source = saved_step(i["source_step_id"])
    attempt = i["resolution_attempt"]

    with %Step{delivery_id: id} <- source,
         true <- id == d.id and source.cycle == cycle and cycle < ModelPolicy.max_cycles(1),
         true <- i["parent_step_id"] == previous.id and i["config_hash"] == d.config_hash,
         true <- hash?(i["input_hash"]) and hash?(i["feedback_hash"]),
         true <- not shared_provider_failure?(d, source) and recoverable_source?(d, source),
         true <-
           (attempt == 1 and previous.id == source.id) or
             (attempt == 2 and previous.kind == "resolve" and previous.cycle == cycle and
                previous.input["resolution_attempt"] == 1 and
                previous.input["source_step_id"] == source.id and
                not shared_provider_failure?(d, previous) and second_opinion?(previous)) do
      case source.kind do
        "plan" ->
          i["plan_step_id"] == source.id and i["workspace"] == d.intent and
            i["candidate_commit"] == d.intent["base_commit"] and
            Repo.aggregate(
              from(s in Step, where: s.delivery_id == ^d.id and s.kind == "plan"),
              :count
            ) < 3

        "implement" ->
          i["plan_step_id"] == source.input["plan_step_id"] and
            implementation_base?(d, source) and
            fresh_resolution_workspace?(d, source, previous, i)

        _ ->
          i["plan_step_id"] == source.input["plan_step_id"] and
            i["workspace"] == source.input["workspace"] and
            i["candidate_commit"] == source.input["candidate_commit"]
      end
    else
      _ -> false
    end
  end

  defp recoverable_source?(%Delivery{routing_version: 2}, %Step{kind: "implement"} = source),
    do:
      clean_model_exit?(source) and
        (source.receipt["exit_code"] != 0 or
           get_in(source.receipt, ["summary", "error_class"]) in ~w(model_unavailable unknown))

  defp recoverable_source?(_, %Step{kind: "implement"} = source), do: unavailable_model?(source)

  defp recoverable_source?(_, %Step{kind: kind, status: status, receipt: r}) do
    r["cleanup"] == "group_empty" and r["exit_kind"] == "exit" and
      r["eof"] == %{"stdout" => true, "stderr" => true} and
      case {kind, status} do
        {"plan", "finished"} ->
          is_binary(get_in(r, ["report", "clarification"])) and r["exit_code"] == 0

        {"review", "finished"} ->
          get_in(r, ["report", "verdict"]) in ~w(changes_requested needs_spec_revision) and
            r["exit_code"] == 0

        {"check", "failed"} ->
          r["outcome"] == "checks_failed" and r["output_complete"] == true and
            is_integer(r["exit_code"]) and r["exit_code"] != 0

        {kind, "failed"} when kind in ["plan", "review"] ->
          known_model_failure?(r)

        _ ->
          false
      end
  end

  defp second_opinion?(%Step{status: "finished", receipt: r}),
    do:
      r["cleanup"] == "group_empty" and process_passed?(r) and
        is_binary(get_in(r, ["report", "external_action"]))

  defp second_opinion?(%Step{status: "failed", receipt: r}),
    do:
      r["cleanup"] == "group_empty" and r["exit_kind"] == "exit" and
        r["eof"] == %{"stdout" => true, "stderr" => true} and known_model_failure?(r)

  defp second_opinion?(_), do: false

  defp known_model_failure?(r),
    do: r["outcome"] in ["invalid_report", "exited"] and is_integer(r["exit_code"])

  defp unavailable_model?(%Step{kind: kind, status: "failed", receipt: r})
       when kind in ~w(plan implement review merge_review resolve),
       do:
         r["cleanup"] == "group_empty" and r["exit_kind"] == "exit" and
           r["eof"] == %{"stdout" => true, "stderr" => true} and r["outcome"] == "exited" and
           is_integer(r["exit_code"]) and r["exit_code"] != 0

  defp unavailable_model?(_), do: false

  defp clean_model_exit?(%Step{status: "failed", receipt: r}),
    do:
      r["outcome"] == "exited" and r["cleanup"] == "group_empty" and
        r["exit_kind"] == "exit" and is_integer(r["exit_code"]) and
        r["eof"] == %{"stdout" => true, "stderr" => true}

  defp clean_model_exit?(_), do: false

  defp excluded_model?(%Delivery{routing_version: 1}, step), do: unavailable_model?(step)

  defp excluded_model?(_, %Step{kind: kind} = step),
    do:
      kind in ~w(plan implement review merge_review resolve) and clean_model_exit?(step) and
        get_in(step.receipt, ["summary", "error_class"]) == "model_unavailable"

  defp shared_provider_failure?(%Delivery{routing_version: 2}, step),
    do: get_in(step.receipt, ["summary", "error_class"]) in ~w(auth rate_limit schema transport)

  defp shared_provider_failure?(_, _), do: false

  defp implementation_base?(d, source) do
    base = get_in(source.input, ["workspace", "base_commit"])

    with %Step{delivery_id: id} = parent <- saved_step(source.input["parent_step_id"]),
         true <- id == d.id and parent.number == source.number - 1 do
      case {source.cycle, d.retry_review_id, parent.kind} do
        {1, nil, "plan"} ->
          parent.id == source.input["plan_step_id"] and parent.status == "finished" and
            base == d.intent["base_commit"]

        {1, retry, "retry_check"} when not is_nil(retry) ->
          parent.input["plan_step_id"] == source.input["plan_step_id"] and
            base == parent.input["candidate_commit"] and
            Boss.Deliveries.Retry.valid_next?(d, parent, "implement", 1, source.input)

        {cycle, _, "resolve"} when cycle > 1 ->
          parent.cycle == cycle - 1 and resolution_passed?(parent) and
            parent.input["plan_step_id"] == source.input["plan_step_id"] and
            base == parent.input["candidate_commit"]

        _ ->
          false
      end
    else
      _ -> false
    end
  end

  defp fresh_resolution_workspace?(d, source, previous, input) do
    workspace = input["workspace"]
    old = source.input["workspace"]

    with true <- is_map(workspace) and map_size(workspace) == 8 and is_map(old),
         {:ok, _} <- Ecto.UUID.cast(workspace["run_id"]),
         true <- is_binary(old["path"]),
         true <-
           Enum.all?(
             ~w(project_id repo_path git_common_dir base_branch),
             &(workspace[&1] == d.intent[&1])
           ),
         true <- sha?(old["base_commit"]) and workspace["base_commit"] == old["base_commit"],
         true <- input["candidate_commit"] == old["base_commit"],
         true <- workspace["branch"] == "codex/boss-run-#{workspace["run_id"]}",
         true <- workspace["path"] == Path.join(Path.dirname(old["path"]), workspace["run_id"]),
         true <- workspace["path"] != old["path"] and workspace["path"] != d.intent["path"] do
      if input["resolution_attempt"] == 2 do
        workspace == previous.input["workspace"]
      else
        Enum.all?(steps(d.id), fn step ->
          Enum.all?([step.input["workspace"], step.receipt["workspace"]], fn
            saved when is_map(saved) ->
              saved["path"] != workspace["path"] and saved["branch"] != workspace["branch"]

            _ ->
              true
          end)
        end)
      end
    else
      _ -> false
    end
  end

  defp resolution_passed?(%Step{status: "finished", receipt: r}),
    do:
      r["cleanup"] == "group_empty" and process_passed?(r) and
        is_nil(get_in(r, ["report", "external_action"]))

  defp resolution_passed?(_), do: false

  defp preserved_replan?(step, report) do
    Repo.all(
      from s in Step,
        where:
          s.delivery_id == ^step.delivery_id and s.kind == "plan" and s.status == "finished" and
            s.number < ^step.number
    )
    |> Enum.all?(fn previous ->
      acceptance = previous.receipt["report"]["acceptance"]
      acceptance == [] or MapSet.new(acceptance) == MapSet.new(report["acceptance"])
    end)
  end

  defp valid_plan?(report) when is_map(report),
    do: match?({:ok, _}, Boss.Deliveries.Protocol.plan(JSON.encode!(report)))

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

    report = decoded_review!(review.receipt["report"])
    criteria = Enum.map(report["acceptance"], & &1["criterion"])

    unless review.status == "finished" and check.kind == "check" and check.status == "finished" and
             plan.kind == "plan" and plan.status == "finished" and
             valid_plan?(plan.receipt["report"]) and
             process_passed?(review.receipt) and process_passed?(check.receipt) and
             process_passed?(plan.receipt) and
             review.receipt["cleanup"] == "group_empty" and
             check.receipt["cleanup"] == "group_empty" and
             report["verdict"] == "approved" and
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

  defp merge_input?(d, review, check, i) do
    match?(%Step{kind: "check", status: "finished"}, check) and
      i["original_review_step_id"] == review.id and i["original_check_step_id"] == check.id and
      i["plan_step_id"] == review.input["plan_step_id"] and
      i["original_candidate"] == review.input["candidate_commit"] and
      i["original_base"] == d.intent["base_commit"] and i["config_hash"] == d.config_hash and
      i["spec_revision_id"] == d.spec_revision_id and sha?(i["target_commit"]) and
      i["target_commit"] not in [i["original_base"], i["original_candidate"]] and
      is_map(i["workspace"]) and is_map(get_in(i, ["workspace", "run_workspace"])) and
      match?({:ok, _}, Ecto.UUID.cast(get_in(i, ["workspace", "check_id"]))) and
      get_in(i, ["workspace", "check_id"]) != get_in(check.input, ["workspace", "check_id"]) and
      get_in(i, ["workspace", "path"]) != get_in(check.input, ["workspace", "path"]) and
      get_in(i, ["workspace", "ref"]) != get_in(check.input, ["workspace", "ref"]) and
      get_in(i, ["workspace", "run_workspace"]) ==
        get_in(check.input, ["workspace", "run_workspace"])
  end

  defp merge_check_input?(d, merge, i),
    do:
      d.status == "integrating" and merge.kind == "merge" and merge.status == "finished" and
        i["merge_step_id"] == merge.id and
        i["candidate_commit"] == merge.receipt["candidate_commit"] and
        i["workspace"] == merge.receipt["workspace"] and
        i["target_commit"] == merge.input["target_commit"] and
        i["config_hash"] == d.config_hash and i["spec_revision_id"] == d.spec_revision_id

  defp merge_review_input?(d, %Step{} = merge, check, i),
    do:
      merge_check_input?(d, merge, check.input) and i["merge_step_id"] == merge.id and
        i["merge_check_step_id"] == check.id and
        i["candidate_commit"] == check.input["candidate_commit"] and
        i["target_commit"] == merge.input["target_commit"] and
        i["original_base"] == d.intent["base_commit"] and
        i["original_review_step_id"] == merge.input["original_review_step_id"] and
        i["plan_step_id"] == merge.input["plan_step_id"] and i["config_hash"] == d.config_hash and
        i["spec_revision_id"] == d.spec_revision_id and check.receipt["output_complete"] == true and
        hash?(check.receipt["output_hash"]) and i["output_hash"] == check.receipt["output_hash"] and
        hash?(i["input_hash"])

  defp merge_review_input?(_, _, _, _), do: false

  defp publication_approved!(d) do
    original = approved!(d)
    all = steps(d.id)

    if Enum.any?(all, &(&1.kind == "merge")) do
      merge = Enum.find(all, &(&1.kind == "merge"))
      check = Enum.find(all, &(&1.kind == "merge_check"))
      review = Enum.find(all, &(&1.kind == "merge_review"))
      original_check = Enum.find(all, &(&1.id == original.input["check_step_id"]))
      plan = Enum.find(all, &(&1.id == original.input["plan_step_id"]))

      report =
        if review,
          do: decoded_review!(review.receipt["report"]),
          else: Repo.rollback(:missing_evidence)

      criteria = Enum.map(report["acceptance"], & &1["criterion"])

      unless match?(%Step{status: "finished"}, merge) and match?(%Step{status: "finished"}, check) and
               match?(%Step{status: "finished"}, review) and
               merge_input?(d, original, original_check, merge.input) and
               merge_review_input?(d, merge, check, review.input) and
               report["verdict"] == "approved" and
               review.receipt["candidate_commit"] == merge.receipt["candidate_commit"] and
               check.receipt["candidate_commit"] == merge.receipt["candidate_commit"] and
               merge.number == original.number + 1 and check.number == merge.number + 1 and
               review.number == check.number + 1 and
               Enum.all?(
                 [merge, check, review],
                 &(&1.cycle == d.cycle and &1.receipt["cleanup"] == "group_empty")
               ) and
               MapSet.new(criteria) == MapSet.new(plan.receipt["report"]["acceptance"]),
             do: Repo.rollback(:missing_evidence)

      review
    else
      original
    end
  end

  defp decoded_review!(report) do
    case Boss.Reviews.Verdict.decode(JSON.encode!(report)) do
      {:ok, decoded} -> decoded
      _ -> Repo.rollback(:missing_evidence)
    end
  end

  defp publication_base(_d, %Step{kind: "merge_review", input: input}), do: input["target_commit"]
  defp publication_base(d, _review), do: d.intent["base_commit"]

  defp publication_candidate(%Step{kind: "merge_review", input: input}),
    do: Repo.get!(Step, input["merge_step_id"]).receipt["workspace"]

  defp publication_candidate(%Step{input: input}),
    do: Repo.get!(Step, input["check_step_id"]).input["workspace"]

  defp integrated!(d) do
    review = publication_approved!(d)
    all = steps(d.id)
    post = List.last(all)
    publish = Enum.find(all, &(&1.kind == "publish"))

    unless d.status == "integrating" and d.integration_command_id != nil and
             match?(%Step{kind: "publish"}, publish) and match?(%Step{kind: "post_check"}, post) and
             post.status == "finished" and
             publish.status == "finished" and
             publish.input["review_step_id"] == review.id and
             d.integration_intent["base_commit"] == publication_base(d, review) and
             d.integration_intent["candidate_commit"] == review.input["candidate_commit"] and
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
    Scheduling.claims_changed()
    result
  end

  defp broadcast_result({:ok, %Delivery{} = d} = result),
    do:
      (
        broadcast(d)
        Scheduling.claims_changed()
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
