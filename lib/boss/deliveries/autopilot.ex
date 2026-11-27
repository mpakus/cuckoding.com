defmodule Boss.Deliveries.Autopilot do
  @moduledoc "Explicit frozen task selection, advanced through existing delivery evidence one task at a time."
  import Ecto.Query
  alias Boss.{Deliveries, Repo, Runs, Tasks}

  alias Boss.Deliveries.{
    AutopilotBatch,
    AutopilotItem,
    AutopilotLoopConfig,
    Delivery,
    Queue,
    Request,
    SpecRework,
    Step
  }

  @shared_failures ~w(catalog_unavailable catalog_invalid catalog_insufficient_models codex_unavailable models_exhausted provider_auth provider_rate_limit provider_schema provider_transport)

  def start(project, command, tasks, text, reviewer, server \\ Boss.Runs.Manager),
    do:
      GenServer.call(server, {:autopilot_start, project, command, tasks, text, reviewer}, 10_000)

  def start_loop(
        project,
        command,
        tasks,
        text,
        reviewer,
        opts \\ [parallel: true, spec_loop: true],
        server \\ Boss.Runs.Manager
      ),
      do:
        GenServer.call(
          server,
          {:autopilot_start_loop, project, command, tasks, text, reviewer, opts},
          10_000
        )

  def resume(project, id, version, server \\ Boss.Runs.Manager),
    do: GenServer.call(server, {:autopilot_resume, project, id, version}, 10_000)

  def pause(project, id, version), do: change(project, id, :pause, version)

  def cancel(project, id, version, registry \\ Boss.Runs.Active) do
    with true <- is_integer(project) and project > 0 and is_integer(version) and version >= 0,
         {:ok, _} <- Ecto.UUID.cast(id) do
      # Stop is terminal for this immutable batch, even when the browser's version is stale.
      # Mark in-flight cancellation in ETS before signaling the worker so Manager cannot
      # turn the raced worker exit into a blocked batch before change/4 commits, while
      # still signaling the live worker immediately even if SQLite is stalled.
      token = {id, make_ref()}
      :ets.insert(cancelling_table(), token)

      try do
        Runs.stop(project, {:autopilot, id}, registry)
        result = change(project, id, :cancel, version)
        Runs.stop(project, {:autopilot, id}, registry)
        result
      after
        :ets.delete_object(cancelling_table(), token)
      end
    else
      _ -> {:error, :invalid_command}
    end
  end

  def current(project) do
    transaction(fn ->
      case Repo.one(
             from b in AutopilotBatch,
               where: b.project_id == ^project,
               order_by: [desc: b.inserted_at, desc: b.id],
               limit: 1
           ) do
        nil -> nil
        batch -> view(batch)
      end
    end)
  end

  def selection(project) when is_integer(project) and project > 0,
    do:
      transaction(fn ->
        Queue.autopilot_candidates(project, Boss.Deliveries.ModelPolicy.current_routing())
      end)

  def selection(_), do: {:error, :invalid_command}

  def running?, do: Repo.exists?(from b in AutopilotBatch, where: b.status == "running")

  def parallel_running? do
    if loop_table_ready?() do
      Repo.exists?(
        from b in AutopilotBatch,
          join: lc in AutopilotLoopConfig,
          on: lc.autopilot_id == b.id,
          where: b.status == "running" and lc.parallel_enabled == 1
      )
    else
      false
    end
  rescue
    _ -> false
  end

  def loop_info(nil), do: nil

  def loop_info(batch_id) when is_binary(batch_id) do
    if loop_table_ready?() do
      Repo.get(AutopilotLoopConfig, batch_id)
    end
  rescue
    _ -> nil
  end

  def owns_request?(id), do: Repo.get(AutopilotItem, id) != nil

  @doc false
  def awaiting_request?(project, task, config, hash, reviewer) do
    Repo.exists?(
      from b in AutopilotBatch,
        where:
          b.status == "running" and b.project_id == ^project and b.check_config == ^config and
            b.config_hash == ^hash and b.reviewer == ^reviewer and
            fragment("EXISTS (SELECT 1 FROM json_each(?) WHERE value=?)", b.task_ids, ^task) and
            fragment(
              "NOT EXISTS (SELECT 1 FROM autopilot_items i JOIN delivery_requests r ON r.id=i.request_id WHERE i.autopilot_id=? AND r.task_id=?)",
              b.id,
              ^task
            )
    )
  end

  def owner(delivery) do
    Repo.one(
      from i in AutopilotItem,
        join: r in Request,
        on: r.id == i.request_id,
        where: r.delivery_id == ^delivery.id,
        select: i.autopilot_id
    )
  end

  def cancelled?(id), do: Repo.get!(AutopilotBatch, id).status in ~w(cancelled blocked)

  def admission_allowed?(task, command) do
    item =
      Repo.one(
        from i in AutopilotItem,
          join: r in Request,
          on: r.id == i.request_id,
          join: b in AutopilotBatch,
          on: b.id == i.autopilot_id,
          where: r.task_id == ^task and r.command_id == ^command,
          select: b
      )

    case item do
      nil ->
        not running?()

      %{status: "running"} = batch ->
        complete?(batch) and
          if parallel_batch?(batch.id) do
            not Enum.any?(rows(batch.id), fn {_, r, d, _} ->
              r.status == "started" and not is_nil(d) and
                (d.status in ~w(integrating interrupted) or d.cleanup == "unknown" or
                   not is_nil(shared_failure_code(d)))
            end)
          else
            not Enum.any?(rows(batch.id), fn {_, r, d, _} ->
              r.status == "started" and not settled?(d)
            end)
          end

      _ ->
        false
    end
  end

  def integration_allowed?(delivery, command) do
    case Repo.one(
           from i in AutopilotItem,
             join: r in Request,
             on: r.id == i.request_id,
             join: b in AutopilotBatch,
             on: b.id == i.autopilot_id,
             where: r.delivery_id == ^delivery.id,
             select: {b, i.integration_command_id}
         ) do
      {%{status: "running"} = batch, ^command} -> complete?(batch)
      {%{status: status}, _} when status in ~w(running paused) -> false
      _ -> not running?()
    end
  end

  @doc false
  def admit(project, command, tasks, text, reviewer, owned \\ false, intake \\ nil, opts \\ []) do
    with true <-
           is_integer(project) and project > 0 and Boss.Agents.Metadata.review_runner?(reviewer),
         {:ok, _} <- Ecto.UUID.cast(command),
         true <-
           is_list(tasks) and length(tasks) in 1..256 and
             Enum.all?(tasks, &(is_integer(&1) and &1 > 0)) and Enum.uniq(tasks) == tasks,
         {:ok, config, hash} <- Boss.Checks.Command.parse_workflow(text) do
      transaction(fn ->
        case Repo.get_by(AutopilotBatch, project_id: project, command_id: command) do
          %{task_ids: ^tasks, check_config: ^config, config_hash: ^hash, reviewer: ^reviewer} =
              batch ->
            view(batch)

          %AutopilotBatch{} ->
            Repo.rollback(:idempotency_conflict)

          nil ->
            routing_version = intake_routing(intake)
            backlog = Queue.autopilot_candidates(project, routing_version)

            if length(backlog) > 256, do: Repo.rollback(:backlog_too_large)
            if Enum.sort(backlog) != Enum.sort(tasks), do: Repo.rollback(:backlog_changed)

            Boss.Projects.Intake.ensure_brief_selection!(project, tasks, hash, reviewer)
            release_unknown_cleanups!()

            if owned or Deliveries.busy?() or
                 not Boss.Projects.Intake.batch_allowed?(
                   intake,
                   project,
                   command,
                   config,
                   hash,
                   reviewer,
                   opts
                 ) or
                 Repo.exists?(from b in AutopilotBatch, where: b.status in ~w(running paused)) or
                 Repo.exists?(
                   from r in Runs.Run,
                     where:
                       r.status in ~w(preparing launching running stopping) or
                         r.cleanup == "unknown"
                 ),
               do: Repo.rollback(:busy)

            batch =
              Repo.insert!(%AutopilotBatch{
                id: Ecto.UUID.generate(),
                project_id: project,
                command_id: command,
                task_ids: tasks,
                check_config: config,
                config_hash: hash,
                reviewer: reviewer,
                autonomy_version: intake_autonomy(intake),
                routing_version: routing_version
              })

            maybe_insert_loop_config!(batch, opts)

            Queue.admit_autopilot_items!(batch.id)
            view(batch)
        end
      end)
      |> broadcast()
    else
      _ -> {:error, :invalid_command}
    end
  end

  @doc false
  def resume_saved(project, id, version), do: change(project, id, :resume, version)

  defp intake_autonomy(nil), do: Boss.Deliveries.ModelPolicy.current()
  defp intake_autonomy(id), do: Repo.get!(Boss.Projects.Intake.Request, id).autonomy_version
  defp intake_routing(nil), do: Boss.Deliveries.ModelPolicy.current_routing()
  defp intake_routing(id), do: Repo.get!(Boss.Projects.Intake.Request, id).routing_version

  defp change(project, id, action, version) do
    with true <- is_integer(project) and is_integer(version) and version >= 0,
         {:ok, _} <- Ecto.UUID.cast(id) do
      transaction(fn ->
        batch =
          Repo.get_by(AutopilotBatch, project_id: project, id: id) || Repo.rollback(:not_found)

        replay = batch.version == version + 1 and batch.last_action == Atom.to_string(action)

        if action != :cancel and batch.version != version and not replay,
          do: Repo.rollback(:stale_version)

        batch =
          if replay do
            batch
          else
            case {action, batch.status} do
              {:pause, "running"} ->
                save(
                  batch,
                  "paused",
                  "Autopilot paused. The current workflow may finish; no next task or integration starts.",
                  "pause"
                )

              {:pause, "paused"} ->
                batch

              {:resume, "paused"} ->
                for {_, request, _, _} <- rows(batch.id),
                    request.status == "paused",
                    do: Queue.save!(request, status: "queued", reason: nil)

                save(batch, "running", nil, "resume")

              {:resume, "running"} ->
                batch

              {:cancel, status} when status in ~w(running paused) ->
                cancel_pending(batch.id)

                save(
                  batch,
                  "cancelled",
                  "Autopilot stopped. Completed work and retained evidence remain available.",
                  "cancel"
                )

              {:cancel, "cancelled"} ->
                batch

              _ ->
                Repo.rollback(:request_finished)
            end
          end

        view(batch)
      end)
      |> broadcast()
    else
      _ -> {:error, :invalid_command}
    end
  end

  @doc false
  def pause_on_restart do
    transaction(fn ->
      for batch <- Repo.all(from b in AutopilotBatch, where: b.status == "running") do
        for {_, request, _, _} <- rows(batch.id),
            request.status == "queued",
            do:
              Queue.save!(request,
                status: "paused",
                reason: "BOSS restarted. Resume the saved Autopilot selection explicitly."
              )

        save(batch, "paused", "BOSS restarted. Resume this saved Autopilot selection explicitly.")
      end
    end)
    |> broadcast()
  end

  @doc false
  def advance(cursor \\ nil) do
    pinned(fn ->
      preflight = preflight()

      Repo.transaction(
        fn ->
          case Repo.one(from b in AutopilotBatch, where: b.status == "running") do
            nil -> :idle
            batch -> advance_batch(batch, preflight, cursor)
          end
        end,
        mode: :immediate
      )
    end)
    |> broadcast()
  end

  defp preflight do
    batch = Repo.one(from b in AutopilotBatch, where: b.status == "running")

    entries = if batch, do: rows(batch.id), else: []

    can_preflight? =
      batch &&
        (not Enum.any?(entries, fn {_, r, d, _} ->
           r.status == "started" and not settled?(d)
         end) or
           (parallel_batch?(batch.id) and
              Enum.any?(entries, fn {_, r, _, _} -> r.status == "queued" end)))

    if can_preflight? do
      project = Repo.get!(Boss.Projects.Project, batch.project_id)

      published? = Enum.any?(entries, fn {_, _, d, _} -> match?(%Delivery{status: "done"}, d) end)

      result =
        with {:ok, workspace} <- Boss.Agents.Workspace.plan(project, batch.id) do
          expected =
            if published?,
              do: workspace.base_commit,
              else: Boss.Projects.Intake.initial_base(batch.id) || workspace.base_commit

          Boss.Deliveries.Integration.preflight_target(workspace, expected)
        end

      {batch.id, result}
    else
      nil
    end
  end

  defp advance_batch(batch, preflight, cursor) do
    unless complete?(batch), do: Repo.rollback(:incomplete_autopilot)

    if cancelling?(batch.id) do
      :waiting
    else
      case loop_info(batch.id) do
        %AutopilotLoopConfig{} = cfg
        when cfg.parallel_enabled == 1 or cfg.spec_loop_enabled == 1 ->
          advance_loop_batch(batch, cfg, preflight, cursor)

        _ ->
          advance_active_batch(batch, preflight, cursor)
      end
    end
  end

  defp advance_loop_batch(batch, %AutopilotLoopConfig{} = cfg, preflight, cursor) do
    entries = rows(batch.id)
    unfinished = Enum.reject(entries, fn {_, _, d, _} -> settled?(d) end)

    started_unfinished =
      Enum.filter(unfinished, fn {_, r, _, _} -> r.status == "started" end)

    active_count =
      Enum.count(started_unfinished, fn {_, _, d, _} ->
        not is_nil(d) and Deliveries.active?(d)
      end)

    any_active? = active_count > 0

    parallel_limit =
      if cfg.parallel_enabled == 1 do
        max(
          min(
            Boss.Projects.RoleBindings.implementer_pool_size(batch.project_id),
            Boss.Deliveries.Scheduling.capacity!()
          ),
          1
        )
      else
        1
      end

    shared_code =
      Enum.find_value(entries, fn {_, _, d, _} -> shared_failure_code(d) end)

    halted_entry =
      Enum.find(started_unfinished, fn {_, _, d, _} ->
        not is_nil(d) and not Deliveries.active?(d) and d.status != "ready_to_merge"
      end)

    ready_entry =
      Enum.find(started_unfinished, fn {_, _, d, _} ->
        match?(%Delivery{status: "ready_to_merge"}, d)
      end)

    cond do
      not is_nil(shared_code) ->
        if any_active?, do: :waiting, else: block(batch, shared_failure_reason(shared_code))

      not is_nil(halted_entry) ->
        if any_active? do
          :waiting
        else
          {_, _, delivery, _} = halted_entry

          block(
            batch,
            "Task stopped: " <>
              (delivery.reason || delivery.status) <>
              " Autopilot did not start another task."
          )
        end

      not is_nil(ready_entry) ->
        if any_active? do
          :waiting
        else
          {item, _, delivery, _} = ready_entry

          case Deliveries.admit_integration(
                 batch.project_id,
                 delivery.id,
                 item.integration_command_id
               ) do
            {:ok, {:new, saved}} ->
              {:launch, :integrate, saved, batch.id}

            {:error, :busy} ->
              :waiting

            {:error, :storage_error} ->
              Repo.rollback(:storage_error)

            _ ->
              block(
                batch,
                "The saved approval cannot be integrated. Inspect its retained evidence."
              )
          end
        end

      unfinished == [] ->
        if Enum.all?(entries, fn {_, _, d, _} -> d.status == "done" end) do
          {:changed, view(save(batch, "completed", nil))}
        else
          maybe_restart_spec_loop(batch, cfg, entries)
        end

      active_count >= parallel_limit ->
        :waiting

      Deliveries.managed_busy?() ->
        :waiting

      true ->
        queued_entries = Enum.filter(unfinished, fn {_, r, _, _} -> r.status == "queued" end)

        if queued_entries == [] do
          if any_active? do
            :waiting
          else
            block(
              batch,
              "A selected task changed or its request was cancelled. Start a fresh selection after inspection."
            )
          end
        else
          start_next_loop_entry(
            batch,
            cfg,
            entries,
            queued_entries,
            any_active?,
            preflight,
            cursor
          )
        end
    end
  end

  defp start_next_loop_entry(batch, cfg, entries, queued_entries, any_active?, preflight, cursor) do
    release_unknown_cleanups!()

    cond do
      Boss.Deliveries.Scheduling.quarantined?() ->
        if any_active? do
          :waiting
        else
          block(
            batch,
            "Another execution has unknown cleanup. Inspect it before a fresh Autopilot start."
          )
        end

      Deliveries.managed_busy?() ->
        :waiting

      preflight != {batch.id, :ok} ->
        if any_active? do
          :waiting
        else
          reason =
            if preflight == {batch.id, {:error, :target_checked_out}},
              do:
                "The integration target branch is checked out. Switch that checkout to another branch, then start Autopilot again.",
              else:
                "The integration target is unavailable or changed. Inspect the repository before starting Autopilot again."

          block(batch, reason)
        end

      true ->
        offset =
          case cursor do
            {id, version, offset}
            when id == batch.id and version == batch.version and is_integer(offset) ->
              offset

            _ ->
              0
          end

        deadline = System.monotonic_time(:millisecond) + 1_000

        selected =
          queued_entries
          |> Enum.drop(offset)
          |> Enum.reduce_while({:scanned, offset}, fn entry, {:scanned, index} ->
            if System.monotonic_time(:millisecond) >= deadline do
              {:halt, {:scanned, index}}
            else
              {_, request, _, _} = entry

              if Tasks.Dependencies.check(batch.project_id, request.task_id) == :ok,
                do: {:halt, entry},
                else: {:cont, {:scanned, index + 1}}
            end
          end)

        case selected do
          {:scanned, count} when count < length(queued_entries) ->
            {:waiting, {batch.id, batch.version, count}}

          {:scanned, _} ->
            if any_active? do
              :waiting
            else
              maybe_restart_spec_loop(
                batch,
                cfg,
                entries,
                "No remaining task is ready. Open tasks that need attention and resolve missing, unfinished or cyclic prerequisites, then start Autopilot again."
              )
            end

          {_, request, _, _} ->
            case Queue.claim(request.id) do
              {:ok, {:started, _, delivery}} ->
                {:launch, :deliver, delivery, batch.id}

              {:error, :busy} ->
                :waiting

              {:error, :storage_error} ->
                Repo.rollback(:storage_error)

              _ ->
                if any_active? do
                  :waiting
                else
                  block(
                    batch,
                    "A selected task changed before launch. Start a fresh selection after inspection."
                  )
                end
            end
        end
    end
  end

  defp maybe_restart_spec_loop(
         batch,
         %AutopilotLoopConfig{} = cfg,
         entries,
         blocked_reason \\ "All runnable tasks finished. Open the tasks that need attention for details."
       ) do
    if cfg.spec_loop_enabled == 1 and cfg.loop_pass < cfg.max_passes do
      reworked = SpecRework.refine_settled_deliveries(batch.project_id, entries, cfg.loop_pass)

      if reworked == [] do
        block(batch, blocked_reason)
      else
        next_pass = cfg.loop_pass + 1

        reason =
          "Reviewer refined #{length(reworked)} task specification(s) and returned them to Backlog — continuing Autopilot loop (pass #{next_pass}/#{cfg.max_passes})."

        cancel_pending(batch.id)
        candidates = Queue.autopilot_candidates(batch.project_id, batch.routing_version)
        waiting = for {_, %{status: "queued", task_id: task_id}, nil, _} <- entries, do: task_id

        if Enum.sort(candidates) == Enum.sort(reworked ++ waiting) do
          save(batch, "blocked", reason)

          next_batch =
            Repo.insert!(%AutopilotBatch{
              id: Ecto.UUID.generate(),
              project_id: batch.project_id,
              command_id: Ecto.UUID.generate(),
              task_ids: candidates,
              check_config: batch.check_config,
              config_hash: batch.config_hash,
              reviewer: batch.reviewer,
              autonomy_version: batch.autonomy_version,
              routing_version: batch.routing_version
            })

          maybe_insert_loop_config!(next_batch,
            parallel: cfg.parallel_enabled == 1,
            spec_loop: true,
            loop_pass: next_pass,
            max_passes: cfg.max_passes,
            parent_autopilot_id: batch.id
          )

          cfg
          |> AutopilotLoopConfig.changeset(%{
            reworked_task_ids: JSON.encode!(reworked),
            next_autopilot_id: next_batch.id
          })
          |> Repo.update!()

          Queue.admit_autopilot_items!(next_batch.id)

          if cancelling?(batch.id), do: Repo.rollback(:cancelled)
          Tasks.broadcast(batch.project_id)
          {:restarted_loop, view(next_batch)}
        else
          block(
            batch,
            "The remaining Backlog differs from the authorized loop tasks. Inspect the tasks before starting a fresh selection."
          )
        end
      end
    else
      block(batch, blocked_reason)
    end
  end

  defp advance_active_batch(batch, preflight, cursor) do
    entries = rows(batch.id)
    unfinished = Enum.reject(entries, fn {_, _, d, _} -> settled?(d) end)

    case unfinished do
      [] ->
        if Enum.all?(entries, fn {_, _, d, _} -> d.status == "done" end) do
          {:changed, view(save(batch, "completed", nil))}
        else
          block(
            batch,
            "All runnable tasks finished. Open the tasks that need attention for details."
          )
        end

      _ ->
        case Enum.find(unfinished, fn {_, r, _, _} -> r.status == "started" end) do
          {item, _, %{status: "ready_to_merge"} = delivery, _} ->
            case Deliveries.admit_integration(
                   batch.project_id,
                   delivery.id,
                   item.integration_command_id
                 ) do
              {:ok, {:new, saved}} ->
                {:launch, :integrate, saved, batch.id}

              {:error, :busy} ->
                :waiting

              {:error, :storage_error} ->
                Repo.rollback(:storage_error)

              _ ->
                block(
                  batch,
                  "The saved approval cannot be integrated. Inspect its retained evidence."
                )
            end

          {_, _, delivery, _} ->
            cond do
              Deliveries.active?(delivery) ->
                :waiting

              code = shared_failure_code(delivery) ->
                block(batch, shared_failure_reason(code))

              true ->
                block(
                  batch,
                  "Task stopped: " <>
                    (delivery.reason || delivery.status) <>
                    " Autopilot did not start another task."
                )
            end

          nil ->
            start_next(batch, unfinished, preflight, cursor)
        end
    end
  end

  defp settled?(%Delivery{status: "done"}), do: true

  defp settled?(
         %Delivery{
           status: status,
           cleanup: "group_empty",
           integration_command_id: nil
         } = delivery
       ),
       do: status in ~w(failed blocked needs_input) and is_nil(shared_failure_code(delivery))

  defp settled?(_), do: false

  defp shared_failure_code(
         %Delivery{
           status: status,
           cleanup: "group_empty",
           integration_command_id: nil
         } = delivery
       )
       when status in ~w(failed blocked needs_input) do
    code = Map.get(delivery, :failure_code)

    cond do
      code in @shared_failures ->
        code

      Map.get(delivery, :routing_version, 1) == 1 and delivery.autonomy_version == 1 and
          Deliveries.model_profile(delivery, :plan, 0) == {:error, :models_exhausted} ->
        "models_exhausted"

      shared_startup_failure?(delivery) ->
        "provider_startup"

      true ->
        nil
    end
  end

  defp shared_failure_code(_), do: nil

  defp shared_startup_failure?(%Delivery{routing_version: 2, model_catalog: catalog} = delivery) do
    if Boss.Agents.ModelCatalog.validate(catalog) == :ok do
      steps = Deliveries.steps(delivery.id)
      strong_models = MapSet.new(catalog["fallbacks"], & &1["model"])

      not Enum.any?(steps, &(&1.kind in ~w(plan implement) and &1.status == "finished")) and
        steps
        |> Enum.filter(&failed_startup?/1)
        |> Enum.map(&get_in(&1.input, ["model_profile", "model"]))
        |> Enum.filter(&MapSet.member?(strong_models, &1))
        |> Enum.uniq()
        |> length() >= 2
    else
      if Map.get(delivery, :implementer, "codex") in ["claude", "cursor", "opencode"] do
        steps = Deliveries.steps(delivery.id)

        not Enum.any?(steps, &(&1.kind in ~w(plan implement) and &1.status == "finished")) and
          Enum.any?(steps, fn s ->
            s.kind == "plan" and s.status == "failed" and
              get_in(s.receipt, ["summary", "error_class"]) == "model_unavailable"
          end)
      else
        false
      end
    end
  end

  defp shared_startup_failure?(_), do: false

  defp failed_startup?(%{kind: kind, status: "failed", receipt: receipt})
       when kind in ~w(plan resolve),
       do:
         receipt["outcome"] == "exited" and receipt["cleanup"] == "group_empty" and
           receipt["exit_kind"] == "exit" and is_integer(receipt["exit_code"]) and
           receipt["eof"] == %{"stdout" => true, "stderr" => true} and
           (receipt["exit_code"] != 0 or
              get_in(receipt, ["summary", "error_class"]) == "unknown")

  defp failed_startup?(_), do: false

  defp shared_failure_reason(code) do
    detail =
      case code do
        "catalog_unavailable" -> "The local model catalog could not be read."
        "catalog_invalid" -> "The local model catalog is invalid."
        "catalog_insufficient_models" -> "The local model catalog has too few eligible models."
        "codex_unavailable" -> "The Codex CLI is unavailable."
        "models_exhausted" -> "The saved model routes are exhausted."
        "provider_auth" -> "The provider rejected authentication."
        "provider_rate_limit" -> "The provider reported a rate limit."
        "provider_schema" -> "The provider rejected the response format."
        "provider_startup" -> "Two catalogued models could not start a valid planning session."
        "provider_transport" -> "The selected agent's transport or protocol failed."
      end

    detail <>
      " Autopilot did not start another task. Correct the shared agent setup, then use a new Start to retry unfinished tasks."
  end

  defp start_next(batch, entries, preflight, cursor) do
    release_unknown_cleanups!()

    cond do
      Boss.Deliveries.Scheduling.quarantined?() ->
        block(
          batch,
          "Another execution has unknown cleanup. Inspect it before a fresh Autopilot start."
        )

      Deliveries.busy?() ->
        :waiting

      preflight != {batch.id, :ok} ->
        reason =
          if preflight == {batch.id, {:error, :target_checked_out}},
            do:
              "The integration target branch is checked out. Switch that checkout to another branch, then start Autopilot again.",
            else:
              "The integration target is unavailable or changed. Inspect the repository before starting Autopilot again."

        block(batch, reason)

      Enum.any?(entries, fn {_, r, _, _} -> r.status not in ~w(queued paused) end) ->
        block(
          batch,
          "A selected task changed or its request was cancelled. Start a fresh selection after inspection."
        )

      true ->
        offset =
          case cursor do
            {id, version, offset}
            when id == batch.id and version == batch.version and is_integer(offset) ->
              offset

            _ ->
              0
          end

        deadline = System.monotonic_time(:millisecond) + 1_000

        selected =
          entries
          |> Enum.drop(offset)
          |> Enum.reduce_while({:scanned, offset}, fn entry, {:scanned, index} ->
            if System.monotonic_time(:millisecond) >= deadline do
              {:halt, {:scanned, index}}
            else
              {_, request, _, _} = entry

              if Tasks.Dependencies.check(batch.project_id, request.task_id) == :ok,
                do: {:halt, entry},
                else: {:cont, {:scanned, index + 1}}
            end
          end)

        case selected do
          {:scanned, count} when count < length(entries) ->
            {:waiting, {batch.id, batch.version, count}}

          {:scanned, _} ->
            block(
              batch,
              "No remaining task is ready. Open tasks that need attention and resolve missing, unfinished or cyclic prerequisites, then start Autopilot again."
            )

          {_, request, _, _} ->
            case Queue.claim(request.id) do
              {:ok, {:started, _, delivery}} ->
                {:launch, :deliver, delivery, batch.id}

              {:error, :busy} ->
                :waiting

              {:error, :storage_error} ->
                Repo.rollback(:storage_error)

              _ ->
                block(
                  batch,
                  "A selected task changed before launch. Start a fresh selection after inspection."
                )
            end
        end
    end
  end

  defp release_unknown_cleanups! do
    case Deliveries.release_unknown_cleanups() do
      {:ok, _} -> :ok
      {:error, :storage_error} -> Repo.rollback(:storage_error)
      _ -> :ok
    end
  end

  defp block(batch, reason) do
    cancel_pending(batch.id)
    {:changed, view(save(batch, "blocked", reason))}
  end

  defp cancel_pending(id) do
    for {_, request, _, _} <- rows(id),
        request.status in ~w(queued paused),
        do:
          Queue.save!(request,
            status: "cancelled",
            reason: "Autopilot stopped before this request launched."
          )
  end

  defp rows(id) do
    Repo.all(
      from i in AutopilotItem,
        join: r in Request,
        on: r.id == i.request_id,
        join: t in Tasks.Task,
        on: t.id == r.task_id,
        left_join: d in Delivery,
        on: d.id == r.delivery_id,
        where: i.autopilot_id == ^id,
        order_by: i.position,
        limit: 256,
        select: {i, r, d, t.title}
    )
  end

  defp view(batch) do
    loaded = rows(batch.id)

    notes =
      loaded
      |> Enum.map(fn {_, request, _, _} -> request.delivery_id end)
      |> Enum.reject(&is_nil/1)
      |> stage_notes()

    items =
      for {item, request, delivery, title} <- loaded,
          do: %{
            position: item.position,
            task_id: request.task_id,
            title: title,
            request_id: request.id,
            request_status: request.status,
            delivery_id: request.delivery_id,
            delivery_status: if(delivery, do: delivery.status),
            spec_revision_id: request.spec_revision_id,
            stages: Map.get(notes, request.delivery_id, [])
          }

    batch |> Map.from_struct() |> Map.drop([:__meta__]) |> Map.put(:items, items)
  end

  defp stage_notes([]), do: %{}

  defp stage_notes(ids) do
    Step
    |> where([s], s.delivery_id in ^ids)
    |> order_by([s], asc: s.number)
    |> select([s], %{
      delivery_id: s.delivery_id,
      kind: s.kind,
      status: s.status,
      exit_code: fragment("json_extract(?, '$.exit_code')", s.receipt),
      note: fragment("substr(coalesce(json_extract(?, '$.reason'), ''), 1, 240)", s.receipt),
      error_class: fragment("json_extract(?, '$.summary.error_class')", s.receipt)
    })
    |> Repo.all()
    |> Enum.group_by(& &1.delivery_id, &Map.delete(&1, :delivery_id))
  end

  defp save(batch, status, reason, action \\ nil),
    do:
      batch
      |> Ecto.Changeset.change(
        status: status,
        reason: reason,
        version: batch.version + 1,
        last_action: action
      )
      |> Repo.update!()

  defp broadcast({:ok, batches} = result) when is_list(batches) do
    unless Repo.in_transaction?(), do: Enum.each(batches, &Runs.broadcast/1)
    result
  end

  defp broadcast({:ok, %{project_id: _} = batch} = result) do
    unless Repo.in_transaction?(), do: Runs.broadcast(batch)
    result
  end

  defp broadcast({:ok, {:changed, batch}} = result) do
    Runs.broadcast(batch)
    result
  end

  defp broadcast({:ok, {:restarted_loop, batch}} = result) do
    Runs.broadcast(batch)
    result
  end

  defp broadcast(result), do: result

  defp loop_table_ready? do
    Repo.query!(
      "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE type='table' AND name='autopilot_loop_configs')"
    ).rows == [[1]]
  rescue
    _ -> false
  end

  defp parallel_batch?(batch_id) do
    case loop_info(batch_id) do
      %AutopilotLoopConfig{parallel_enabled: 1} -> true
      _ -> false
    end
  end

  defp maybe_insert_loop_config!(batch, opts) when is_list(opts) do
    parallel? = Keyword.get(opts, :parallel, false)
    spec_loop? = Keyword.get(opts, :spec_loop, false)

    if (parallel? or spec_loop?) and loop_table_ready?() do
      %AutopilotLoopConfig{}
      |> AutopilotLoopConfig.changeset(%{
        autopilot_id: batch.id,
        project_id: batch.project_id,
        parallel_enabled: if(parallel?, do: 1, else: 0),
        spec_loop_enabled: if(spec_loop?, do: 1, else: 0),
        loop_pass: Keyword.get(opts, :loop_pass, 1),
        max_passes: Keyword.get(opts, :max_passes, 2),
        parent_autopilot_id: Keyword.get(opts, :parent_autopilot_id)
      })
      |> Repo.insert!()
    end
  end

  defp maybe_insert_loop_config!(_, _), do: :ok

  defp complete?(batch),
    do:
      Repo.aggregate(from(i in AutopilotItem, where: i.autopilot_id == ^batch.id), :count) ==
        length(batch.task_ids)

  defp transaction(fun), do: pinned(fn -> Repo.transaction(fun, mode: :immediate) end)

  defp pinned(fun) do
    selector = Repo.get_dynamic_repo()
    pid = if is_atom(selector), do: Process.whereis(selector), else: selector

    if is_pid(pid) and Process.alive?(pid) do
      Repo.put_dynamic_repo(pid)

      try do
        fun.()
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

  defp cancelling?(id) do
    :ets.lookup(cancelling_table(), id) != []
  end

  defp cancelling_table do
    case :ets.whereis(:boss_autopilot_cancelling) do
      :undefined ->
        try do
          :ets.new(:boss_autopilot_cancelling, [
            :named_table,
            :public,
            :bag,
            {:read_concurrency, true},
            {:heir, Process.whereis(:init), :none}
          ])
        rescue
          ArgumentError -> :boss_autopilot_cancelling
        end

      _ ->
        :boss_autopilot_cancelling
    end
  end
end
