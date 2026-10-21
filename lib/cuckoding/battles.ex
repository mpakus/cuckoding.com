defmodule Cuckoding.Battles do
  @moduledoc "Durable bounded Arena authority and sequential stage claims; workers own external effects."
  import Ecto.Query, except: [update: 2, update: 3]
  alias Cuckoding.Battles.{Attempt, Backoff, Battle, Capacity, ProviderClosure, Snapshot, Task}
  alias Cuckoding.{Event, Foundation, Repo, TaskTurn}

  @active ~w(running pausing paused stopping needs_attention)
  @retryable ~w(launch_failed timeout connection_lost provider_error profile_busy turn_failed)
  @envelope ~w(battle_id request_id task_id stage criteria_sha256)
  @result_fields @envelope ++
                   ~w(status reason summary feedback head candidate_sha preparation native_candidate native_battle resolved_checks checks provider cleanup_verified)
  @roles %{
    "coordinator" => "summa_rudis",
    "speculator" => "speculator",
    "implementor" => "implementor",
    "secutor" => "secutor",
    "final_secutor" => "secutor",
    "summary" => "summa_rudis"
  }
  @next %{
    "prepare_worktree" => "coordinator",
    "coordinator" => "speculator",
    "speculator" => "implementor",
    "implementor" => "capture",
    "capture" => "checks",
    "checks" => "secutor",
    "secutor" => "integrate",
    "final_checks" => "final_secutor",
    "final_secutor" => "summary"
  }

  def preview(arena_id, tabula_id) do
    Repo.transaction(fn ->
      preview = Snapshot.build(arena_id, tabula_id)

      if active?(arena_id),
        do: %{preview | blockers: preview.blockers ++ ["battle_active"]},
        else: preview
    end)
  end

  def get(id), do: if(valid_id?(id), do: Repo.get(Battle, id))

  def latest(arena_id, tabula_id),
    do:
      Repo.one(
        from b in Battle,
          where: b.arena_id == ^arena_id and b.tabula_id == ^tabula_id,
          order_by: [desc: b.inserted_at],
          limit: 1
      )

  def active, do: Repo.all(from b in Battle, where: b.state in ^@active, order_by: b.inserted_at)

  # A dated shell lease is an OS convenience, never execution or cleanup evidence.
  def idle_sleep_requested?(now \\ DateTime.utc_now()) do
    Enum.any?(active(), &idle_sleep_eligible?(&1, now))
  end

  defp idle_sleep_eligible?(battle, now) do
    if battle.snapshot["idle_sleep"] == "shell-lease-v1" and
         battle.state in ~w(running pausing stopping) and
         DateTime.compare(now, battle.inserted_at) != :lt do
      idle_sleep_work?(battle, running_attempt(battle.id), now)
    else
      false
    end
  end

  defp idle_sleep_work?(battle, attempt, now) do
    if battle.state == "stopping" or timing_blocked?(battle) do
      not is_nil(attempt) and DateTime.compare(now, battle.updated_at) != :lt and
        not expired?(DateTime.add(battle.updated_at, 5), now) and
        not expired?(DateTime.add(battle.deadline_at, 5), now) and
        not expired?(DateTime.add(attempt.deadline_at, 5), now)
    else
      not expired?(battle.deadline_at, now) and
        if(attempt, do: not expired?(attempt.deadline_at, now), else: battle.state == "running")
    end
  end

  def active?(arena_id),
    do: Repo.exists?(from b in Battle, where: b.arena_id == ^arena_id and b.state in ^@active)

  def locked?(tabula_id),
    do: Repo.exists?(from b in Battle, where: b.tabula_id == ^tabula_id and b.state in ^@active)

  def locked?(tabula_id, task_id),
    do:
      Repo.exists?(
        from t in Task,
          join: b in Battle,
          on: b.id == t.battle_id,
          where: b.tabula_id == ^tabula_id and b.state in ^@active and t.task_id == ^task_id
      )

  def tasks(id), do: Repo.all(from t in Task, where: t.battle_id == ^id, order_by: t.position)

  def attempts(id),
    do: Repo.all(from a in Attempt, where: a.battle_id == ^id, order_by: a.inserted_at)

  def evidence(id),
    do:
      Repo.all(
        from e in Event,
          where: fragment("json_extract(?, '$.battle_id')", e.data) == ^id,
          order_by: e.id
      )

  def projections(tabula_id) do
    Repo.all(
      from t in Task,
        join: b in Battle,
        on: b.id == t.battle_id,
        join: d in Cuckoding.DraftTask,
        on: d.id == t.task_id,
        where:
          b.tabula_id == ^tabula_id and
            fragment("json_extract(?, '$.revision')", t.snapshot) == d.revision,
        order_by: [asc: b.inserted_at]
    )
    |> Map.new(&{&1.task_id, &1})
  end

  def start(key, arena_id, tabula_id, fingerprint, confirmed, now \\ DateTime.utc_now()) do
    if valid_id?(key) and valid_id?(arena_id) and valid_id?(tabula_id) and confirmed == true and
         is_binary(fingerprint) do
      transaction(fn -> start_once(key, arena_id, tabula_id, fingerprint, now) end)
    else
      {:error, :confirmation_required}
    end
  end

  defp start_once(key, arena_id, tabula_id, fingerprint, now) do
    case get(key) do
      %Battle{arena_id: ^arena_id, tabula_id: ^tabula_id, fingerprint: ^fingerprint} = battle ->
        battle

      %Battle{} ->
        Repo.rollback(:key_conflict)

      nil ->
        create(key, arena_id, tabula_id, fingerprint, now)
    end
  end

  defp create(key, arena_id, tabula_id, fingerprint, now) do
    preview = Snapshot.build(arena_id, tabula_id)
    if preview.fingerprint != fingerprint, do: Repo.rollback(:stale_start)
    if active?(arena_id), do: Repo.rollback(:battle_active)
    if preview.blockers != [], do: Repo.rollback({:not_ready, preview.blockers})
    snapshot = preview.snapshot

    battle =
      Repo.insert!(%Battle{
        id: key,
        arena_id: arena_id,
        tabula_id: tabula_id,
        snapshot: snapshot,
        fingerprint: fingerprint,
        state: "running",
        stage: "admission",
        deadline_at: DateTime.add(now, snapshot["limits"]["wall_seconds"]),
        inserted_at: now,
        updated_at: now
      })

    for {task, position} <- Enum.with_index(snapshot["tasks"]) do
      Repo.insert!(%Task{
        id: Ecto.UUID.generate(),
        battle_id: key,
        task_id: task["id"],
        position: position,
        snapshot: task,
        inserted_at: now,
        updated_at: now
      })
    end

    record(battle, "started", %{
      "task_count" => length(snapshot["tasks"]),
      "snapshot_version" => snapshot["version"],
      "recovery" => snapshot["recovery"],
      "command_check_count" => length(snapshot["checks"])
    })

    battle
  end

  def claim_next(id, now \\ DateTime.utc_now()) do
    transaction(fn ->
      battle = get(id) || Repo.rollback(:not_found)

      cond do
        Backoff.pending?(battle) -> claim_backoff(battle, now)
        battle.state != "running" -> Repo.rollback(:not_running)
        timing_blocked?(battle) -> attention(battle, "timing_gap")
        running_attempt(battle.id) -> Repo.rollback(:busy)
        expired?(battle.deadline_at, now) -> attention(battle, "deadline_exceeded")
        battle.turns_used >= battle.snapshot["limits"]["turns"] -> attention(battle, "turn_limit")
        true -> claim(battle, now)
      end
    end)
  end

  defp claim(battle, now) do
    task = current_task(battle)
    role_id = @roles[battle.stage]
    role = Enum.find(battle.snapshot["team"], &(&1["id"] == role_id))
    unless Capacity.available?(battle.snapshot, role), do: Repo.rollback(:capacity)
    key = Ecto.UUID.generate()

    request = %{
      "request_id" => key,
      "battle_id" => battle.id,
      "task_id" => battle.current_task_id,
      "stage" => battle.stage,
      "snapshot" => battle.snapshot,
      "context" => battle.context,
      "task" => if(task, do: task.snapshot),
      "task_context" => if(task, do: task.context, else: %{}),
      "review_round" => if(task, do: task.review_round, else: 0),
      "role" => role,
      "criteria_sha256" =>
        if(task,
          do: task.snapshot["criteria_sha256"],
          else: Snapshot.final_criteria_digest(battle.snapshot, battle.context)
        )
    }

    deadline =
      min_time(battle.deadline_at, DateTime.add(now, battle.snapshot["limits"]["stage_seconds"]))

    attempt =
      Repo.insert!(%Attempt{
        id: key,
        battle_id: battle.id,
        task_id: battle.current_task_id,
        stage: battle.stage,
        role: role_id,
        request: request,
        claim_token: Ecto.UUID.generate(),
        state: "running",
        deadline_at: deadline,
        inserted_at: now,
        updated_at: now
      })

    if role_id, do: update(battle, turns_used: battle.turns_used + 1)

    record(battle, "stage_claimed", %{
      "attempt_id" => key,
      "stage" => battle.stage,
      "role" => role_id,
      "task_id" => battle.current_task_id
    })

    attempt
  end

  def finish(id, token, result, now \\ DateTime.utc_now()) do
    transaction(fn -> finish_claim(id, token, result, now) end)
  end

  def stage_cleanup_verified?(%Attempt{} = attempt, result),
    do:
      bound?(attempt, result) and result["cleanup_verified"] == true and
        valid_result?(attempt, result)

  defp finish_claim(id, token, result, now) do
    attempt = if(valid_id?(id), do: Repo.get(Attempt, id))

    if is_nil(attempt) or attempt.claim_token != token or attempt.state != "running",
      do: Repo.rollback(:stale_attempt)

    if not bound?(attempt, result), do: Repo.rollback(:foreign_result)
    finish_current(get(attempt.battle_id), attempt, result, now)
  end

  defp finish_current(battle, attempt, result, now) do
    if timing_fenced?(battle, attempt),
      do: finish_timing_gap(battle, attempt, result),
      else: finish_unfenced(battle, attempt, result, now)
  end

  defp finish_unfenced(battle, attempt, result, now) do
    cond do
      battle.state == "stopping" ->
        finish_stop(battle, attempt, result)

      battle.state not in ~w(running pausing) ->
        Repo.rollback(:not_running)

      expired?(attempt.deadline_at, now) or expired?(battle.deadline_at, now) ->
        expire_attempt(battle, attempt, result)

      not valid_result?(attempt, result) ->
        Repo.rollback(:invalid_result)

      battle.state == "pausing" and result["cleanup_verified"] != true ->
        update(attempt, state: "interrupted", result: result)
        needs_attention(battle, "cleanup_uncertain")

      true ->
        complete_attempt(battle, attempt, result)
        |> finish_pause()
        |> schedule_backoff(battle.state, now)
    end
  end

  defp expire_attempt(battle, attempt, result) do
    unless valid_expired_result?(attempt, result), do: Repo.rollback(:invalid_result)
    update(attempt, state: "expired", result: result)

    record(battle, "stage_expired", %{
      "attempt_id" => attempt.id,
      "stage" => attempt.stage,
      "task_id" => attempt.task_id,
      "reported_status" => result["status"],
      "cleanup_verified" => result["cleanup_verified"] == true
    })

    attention(battle, "late_result_rejected")
  end

  # The executor also cancels on expiry; this receipt can close work, never advance it.
  defp valid_expired_result?(_, %{"status" => "cancelled", "cleanup_verified" => cleanup}),
    do: is_boolean(cleanup)

  defp valid_expired_result?(attempt, result), do: valid_result?(attempt, result)

  def observe_timing_gap(observation) do
    if valid_timing_gap?(observation) do
      transaction(fn ->
        active()
        |> Enum.filter(
          &(&1.snapshot["timing_guard"] == "elapsed-gap-v1" and not timing_blocked?(&1) and
              Map.take(&1.context["timing_gap"] || %{}, Map.keys(observation)) != observation)
        )
        |> Enum.map(&fence_timing_gap(&1, observation))
      end)
    else
      {:error, :invalid_timing_gap}
    end
  end

  defp valid_timing_gap?(
         %{"previous_at" => previous, "observed_at" => current, "monotonic_elapsed_ms" => elapsed} =
           observation
       )
       when is_binary(previous) and byte_size(previous) <= 40 and
              is_binary(current) and byte_size(current) <= 40 and
              is_integer(elapsed) and elapsed in 0..315_360_000_000 do
    with {:ok, previous, 0} <- DateTime.from_iso8601(previous),
         {:ok, current, 0} <- DateTime.from_iso8601(current) do
      Cuckoding.BattleClock.gap({previous, 0}, {current, elapsed}) == observation
    else
      _ -> false
    end
  end

  defp valid_timing_gap?(_), do: false

  defp fence_timing_gap(battle, observation) do
    battle = clear_backoff(battle, "timing_gap")
    attempt = running_attempt(battle.id)

    blocked =
      observation["kind"] == "clock_backward" or not is_nil(attempt) or not quiescent?(battle)

    observation =
      Map.merge(observation, %{
        "attempt_id" => if(attempt, do: attempt.id),
        "recovery_attempt_id" => battle.context["integration_recovery_pending"],
        "blocks_continuation" => blocked
      })

    state =
      cond do
        battle.state == "stopping" -> "stopping"
        not is_nil(attempt) -> "pausing"
        blocked -> "needs_attention"
        true -> "paused"
      end

    battle =
      update(battle,
        state: state,
        reason: "timing_gap",
        context:
          battle.context
          |> Map.delete("integration_recovery_pending")
          |> Map.put("timing_gap", observation),
        control_revision: battle.control_revision + 1
      )

    record(
      battle,
      "timing_gap",
      Map.merge(observation, %{
        "stage" => battle.stage,
        "task_id" => battle.current_task_id,
        "control_revision" => battle.control_revision
      })
    )

    if state == "paused", do: record(battle, "paused")
    battle
  end

  defp timing_blocked?(battle),
    do: get_in(battle.context, ["timing_gap", "blocks_continuation"]) == true

  defp timing_fenced?(battle, attempt),
    do: get_in(battle.context, ["timing_gap", "attempt_id"]) == attempt.id

  defp timing_closed?(battle, attempt),
    do:
      attempt.state == "interrupted" and attempt.result["cleanup_verified"] == true and
        attempt.id in (battle.context["timing_closed_attempts"] || [])

  defp finish_timing_gap(battle, attempt, result) do
    unless valid_expired_result?(attempt, result), do: Repo.rollback(:invalid_result)
    update(attempt, state: "interrupted", result: result)
    cleanup = result["cleanup_verified"] == true

    context =
      if cleanup do
        Map.update(battle.context, "timing_closed_attempts", [attempt.id], &(&1 ++ [attempt.id]))
      else
        battle.context
      end

    battle = update(battle, context: context)

    record(battle, "timing_stage_closed", %{
      "attempt_id" => attempt.id,
      "reported_status" => result["status"],
      "cleanup_verified" => cleanup
    })

    if battle.state == "stopping" and cleanup and safe_to_stop?(battle) do
      battle = update(battle, state: "stopped", reason: "user_stop")
      record(battle, "stopped", %{"attempt_id" => attempt.id})
      battle
    else
      needs_attention(battle, if(cleanup, do: "timing_gap", else: "cleanup_uncertain"))
    end
  end

  def pause(id, revision) do
    transaction(fn -> control_battle(id, revision, "running") |> pause_current() end)
  end

  defp pause_current(battle) do
    state = if(running_attempt(battle.id), do: "pausing", else: "paused")

    if state == "paused" and not quiescent?(battle) do
      attention(battle, "cleanup_uncertain")
    else
      battle = update(battle, state: state, control_revision: battle.control_revision + 1)
      record(battle, "pause_requested", %{"control_revision" => battle.control_revision})
      if state == "paused", do: record(battle, "paused")
      battle
    end
  end

  def resume(id, revision, now \\ DateTime.utc_now()) do
    transaction(fn ->
      battle = control_battle(id, revision, "paused")

      cond do
        timing_blocked?(battle) -> attention(battle, "timing_gap")
        not quiescent?(battle) -> attention(battle, "cleanup_uncertain")
        expired?(battle.deadline_at, now) -> attention(battle, "deadline_exceeded")
        battle.turns_used >= battle.snapshot["limits"]["turns"] -> attention(battle, "turn_limit")
        not current_team?(battle) -> Repo.rollback(:resume_binding_changed)
        true -> resume_current(battle)
      end
    end)
  end

  defp control_battle(id, revision, state) do
    battle = get(id) || Repo.rollback(:not_found)

    if battle.control_revision != revision or battle.state != state,
      do: Repo.rollback(:stale_control)

    battle
  end

  defp current_team?(battle) do
    Enum.all?(battle.snapshot["team"], fn role ->
      Foundation.verified_executable(role["agent_id"]) == {:ok, role["identity"]} and
        Foundation.task_binding_current?(role)
    end)
  end

  defp resume_current(battle) do
    battle =
      update(battle, state: "running", reason: nil, control_revision: battle.control_revision + 1)

    record(battle, "resumed", %{"control_revision" => battle.control_revision})
    battle
  end

  defp finish_pause(%Battle{state: "pausing"} = battle) do
    if quiescent?(battle) do
      battle = update(battle, state: "paused")
      record(battle, "paused")
      battle
    else
      needs_attention(battle, "cleanup_uncertain")
    end
  end

  defp finish_pause(battle), do: battle

  defp quiescent?(battle) do
    Enum.all?(attempts(battle.id), fn attempt ->
      settled?(battle, attempt)
    end)
  end

  defp settled?(battle, attempt) do
    reconciled?(battle, attempt) or
      (attempt.result["cleanup_verified"] == true and
         (attempt.state == "completed" or
            (attempt.state == "failed" and
               attempt.id in (retried(battle) ++ (battle.context["skipped_attempts"] || [])))))
  end

  defp reconciled?(battle, attempt),
    do:
      attempt.state == "interrupted" and
        get_in(battle.context, ["integration_reconciliations", attempt.id, "status"]) ==
          "integrated"

  defp retried(battle), do: battle.context["provider_retries"] || []

  defp schedule_backoff(battle, "running", now) do
    attempt = if Backoff.enabled?(battle), do: retry_candidate(battle, now)

    if attempt && Backoff.transient?(attempt) do
      used =
        Enum.count(
          attempts(battle.id),
          &(&1.id in retried(battle) and &1.task_id == attempt.task_id)
        )

      wait = Backoff.schedule(attempt, used, now)
      {:ok, due, 0} = DateTime.from_iso8601(wait["due_at"])

      if expired?(battle.deadline_at, due) do
        battle
      else
        battle = update(battle, context: Map.put(battle.context, "provider_backoff", wait))
        record(battle, "provider_backoff_scheduled", wait)
        battle
      end
    else
      battle
    end
  end

  defp schedule_backoff(battle, _, _), do: battle

  defp claim_backoff(battle, now) do
    {:ok, due, 0} = Backoff.due_at(battle)

    cond do
      Backoff.before_wait?(battle, now) ->
        cancel_wait(battle, "clock_backward") |> attention("clock_backward")

      expired?(battle.deadline_at, now) ->
        cancel_wait(battle, "deadline_exceeded") |> attention("deadline_exceeded")

      DateTime.compare(now, due) == :lt ->
        Repo.rollback(:backoff)

      not current_team?(battle) ->
        cancel_wait(battle, "resume_binding_changed") |> attention("resume_binding_changed")

      true ->
        claim_retry(battle, now)
    end
  end

  defp claim_retry(battle, now) do
    expected = battle.context["provider_backoff"]["attempt_id"]

    case retry_candidate(battle, now) do
      %Attempt{id: ^expected} = attempt ->
        battle |> retry_current(attempt) |> claim(now)

      _ ->
        cancel_wait(battle, "retry_unavailable") |> attention("retry_unavailable")
    end
  end

  def cancel_backoff(id, revision) do
    transaction(fn ->
      battle = control_battle(id, revision, "needs_attention")
      if not Backoff.pending?(battle), do: Repo.rollback(:stale_control)
      cancel_wait(battle, "user_cancelled")
    end)
  end

  defp cancel_wait(battle, reason) do
    wait = battle.context["provider_backoff"]

    battle =
      update(battle,
        context: Map.delete(battle.context, "provider_backoff"),
        control_revision: battle.control_revision + 1
      )

    record(battle, "provider_backoff_cancelled", Map.put(wait, "reason", reason))
    battle
  end

  defp clear_backoff(battle, reason),
    do: if(Backoff.pending?(battle), do: cancel_wait(battle, reason), else: battle)

  def retry_available?(battle, now \\ DateTime.utc_now()) do
    retry_candidate(battle, now) != nil
  end

  def retry(id, revision, now \\ DateTime.utc_now()) do
    transaction(fn ->
      battle = control_battle(id, revision, "needs_attention")
      attempt = retry_candidate(battle, now) || Repo.rollback(:retry_unavailable)
      if not current_team?(battle), do: Repo.rollback(:resume_binding_changed)
      retry_current(battle, attempt)
    end)
  end

  defp retry_candidate(%Battle{state: "needs_attention"} = battle, now) do
    history = attempts(battle.id)
    attempt = List.last(history)

    used =
      Enum.count(history, &(&1.id in retried(battle) and &1.task_id == battle.current_task_id))

    if retry_scope?(battle, now) and used < 2 and
         retryable_attempt?(battle, attempt) and
         Enum.all?(history, &(&1.id == attempt.id or settled?(battle, &1))) do
      attempt
    end
  end

  defp retry_candidate(_, _), do: nil

  defp retry_scope?(battle, now) do
    not timing_blocked?(battle) and battle.snapshot["recovery"] == "provider-retry-v1" and
      battle.snapshot["limits"]["provider_retries"] == 2 and
      not expired?(battle.deadline_at, now) and
      battle.turns_used < battle.snapshot["limits"]["turns"]
  end

  defp retryable_attempt?(
         battle,
         %Attempt{
           state: "failed",
           result: %{
             "status" => "failed",
             "reason" => reason,
             "cleanup_verified" => true,
             "provider" => %{"status" => reason} = provider
           }
         } = attempt
       )
       when reason in @retryable do
    attempt.stage == battle.stage and attempt.task_id == battle.current_task_id and
      not is_nil(@roles[attempt.stage]) and attempt.id not in retried(battle) and
      reason == battle.reason and
      TaskTurn.normalize(Jason.encode!(provider)) == provider
  end

  defp retryable_attempt?(_, _), do: false

  defp retry_current(battle, attempt) do
    stage = if attempt.stage == "implementor", do: "prepare_worktree", else: battle.stage

    if task = current_task(battle) do
      update(task, state: projection(stage), context: Map.delete(task.context, "column"))
    end

    battle =
      update(battle,
        state: "running",
        stage: stage,
        reason: nil,
        control_revision: battle.control_revision + 1,
        context:
          battle.context
          |> Map.delete("provider_backoff")
          |> Map.put("provider_retries", retried(battle) ++ [attempt.id])
      )

    record(battle, "retry_requested", %{
      "attempt_id" => attempt.id,
      "task_id" => attempt.task_id,
      "failed_stage" => attempt.stage,
      "next_stage" => stage,
      "control_revision" => battle.control_revision
    })

    battle
  end

  # This preview reads only the frozen graph. Skip rechecks it under the write lock.
  def skip_preview(battle, now \\ DateTime.utc_now()) do
    if skip_scope?(battle, now) and skippable_boundary?(battle) do
      affected_tasks(battle)
    else
      []
    end
  end

  defp affected_tasks(battle) do
    Enum.reduce(tasks(battle.id), [], fn task, affected ->
      ids = Enum.map(affected, & &1.task_id)

      if task.state not in ~w(completed skipped deferred) and
           (task.task_id == battle.current_task_id or
              Enum.any?(task.snapshot["depends_on"], &(&1 in ids))),
         do: affected ++ [task],
         else: affected
    end)
  end

  def skip(id, revision, task_id, confirmed, now \\ DateTime.utc_now()) do
    transaction(fn ->
      battle = get(id) || Repo.rollback(:not_found)

      if confirmed != true or battle.control_revision != revision or
           battle.current_task_id != task_id,
         do: Repo.rollback(:stale_control)

      affected = skip_preview(battle, now)
      if affected == [], do: Repo.rollback(:skip_unavailable)
      if not current_team?(battle), do: Repo.rollback(:resume_binding_changed)
      skip_current(battle, affected)
    end)
  end

  defp skip_scope?(battle, now) do
    not timing_blocked?(battle) and battle.snapshot["task_selection"] == "skip-task-v1" and
      battle.state in ~w(paused needs_attention) and not is_nil(battle.current_task_id) and
      not expired?(battle.deadline_at, now) and
      battle.turns_used < battle.snapshot["limits"]["turns"]
  end

  defp skippable_boundary?(%Battle{state: "paused"} = battle), do: quiescent?(battle)

  defp skippable_boundary?(battle) do
    history = attempts(battle.id)
    attempt = List.last(history)

    task_failure?(battle, attempt) and
      Enum.all?(history, &(&1.id == attempt.id or settled?(battle, &1)))
  end

  defp task_failure?(_, nil), do: false

  defp task_failure?(battle, attempt) do
    local? =
      attempt.task_id == battle.current_task_id and attempt.stage == battle.stage and
        attempt.result["cleanup_verified"] == true and not is_nil(attempt.role)

    local? and
      (retryable_attempt?(battle, attempt) or
         (review_failure?(battle, attempt) and provider_result?(attempt, attempt.result)))
  end

  defp review_failure?(%Battle{reason: "blocked"}, %Attempt{
         state: "failed",
         result: %{"status" => "blocked"}
       }),
       do: true

  defp review_failure?(%Battle{reason: "review_limit"}, %Attempt{
         state: "completed",
         stage: "secutor",
         result: %{"status" => "changes_requested"}
       }),
       do: true

  defp review_failure?(_, _), do: false

  defp skip_current(battle, affected) do
    battle = clear_backoff(battle, "task_skipped")

    omitted =
      Enum.map(affected, fn task ->
        state = if(task.task_id == battle.current_task_id, do: "skipped", else: "deferred")
        column = if(task.state == "pending", do: "todo", else: task.state)
        update(task, state: state, context: Map.put_new(task.context, "column", column))
        %{"id" => task.task_id, "state" => state}
      end)

    failed =
      attempts(battle.id)
      |> Enum.filter(&(&1.task_id == battle.current_task_id and &1.state == "failed"))
      |> Enum.map(& &1.id)

    context =
      battle.context
      |> Map.put("omitted_tasks", (battle.context["omitted_tasks"] || []) ++ omitted)
      |> Map.put(
        "skipped_attempts",
        Enum.uniq((battle.context["skipped_attempts"] || []) ++ failed)
      )

    battle =
      update(battle,
        context: context,
        state: if(battle.state == "paused", do: "paused", else: "running"),
        reason: nil,
        control_revision: battle.control_revision + 1
      )

    record(battle, "task_skipped", %{
      "task_id" => battle.current_task_id,
      "omitted_tasks" => omitted,
      "control_revision" => battle.control_revision
    })

    next_task(battle)
  end

  defp next_task(battle) do
    all = tasks(battle.id)
    next = Enum.find(all, &(&1.state not in ~w(completed skipped deferred)))

    if is_nil(next) and not Enum.any?(all, &(&1.state == "completed")) do
      battle = update(battle, state: "stopped", current_task_id: nil, reason: "all_tasks_skipped")
      record(battle, "stopped", %{"reason" => battle.reason})
      battle
    else
      update(battle,
        current_task_id: if(next, do: next.task_id),
        stage: if(next, do: "prepare_worktree", else: review_stage(battle, "final_checks"))
      )
    end
  end

  def stop(id) do
    transaction(fn -> stop_current(get(id) || Repo.rollback(:not_found)) end)
  end

  defp stop_current(battle) do
    cond do
      battle.state in ~w(stopped completed partial stopping) ->
        battle

      battle.state == "needs_attention" and not safe_to_stop?(battle) ->
        Repo.rollback(:cleanup_required)

      true ->
        battle = clear_backoff(battle, "user_stop")
        state = if(running_attempt(battle.id), do: "stopping", else: "stopped")
        battle = update(battle, state: state, reason: "user_stop")
        record(battle, "stop_requested")
        battle
    end
  end

  defp safe_to_stop?(battle) do
    Enum.all?(attempts(battle.id), fn attempt ->
      provider_closed?(battle, attempt) or timing_closed?(battle, attempt) or
        reconciled?(battle, attempt) or
        (attempt.state in ~w(completed failed cancelled expired) and
           attempt.result["cleanup_verified"] == true)
    end)
  end

  def active_attempt?(id, token, now \\ DateTime.utc_now()) do
    case Repo.get(Attempt, id) do
      %Attempt{state: "running", claim_token: ^token} = attempt ->
        battle = get(attempt.battle_id)

        battle.state in ~w(running pausing) and not expired?(attempt.deadline_at, now) and
          not expired?(battle.deadline_at, now) and not timing_fenced?(battle, attempt)

      _ ->
        false
    end
  end

  # The startup owner calls this once before dispatch. Uncertain effects are retained, never replayed.
  def recover do
    transaction(fn ->
      Repo.all(
        from b in Battle, where: b.state in ~w(running pausing paused stopping needs_attention)
      )
      |> Enum.filter(&(&1.state != "needs_attention" or Backoff.pending?(&1)))
      |> Enum.map(&recover_battle/1)
    end)
  end

  defp recover_battle(%Battle{state: "needs_attention"} = battle) do
    if Backoff.pending?(battle),
      do: cancel_wait(battle, "restart_requires_confirmation"),
      else: battle
  end

  defp recover_battle(%Battle{state: "paused"} = battle) do
    if quiescent?(battle), do: battle, else: interrupt_battle(battle)
  end

  defp recover_battle(%Battle{state: state} = battle) when state in ~w(running pausing) do
    if quiescent?(battle) do
      battle =
        update(battle,
          state: "paused",
          reason: "restart_checkpoint",
          control_revision: battle.control_revision + 1
        )

      record(battle, "recovery_paused", %{
        "stage" => battle.stage,
        "task_id" => battle.current_task_id,
        "control_revision" => battle.control_revision
      })

      battle
    else
      interrupt_battle(battle)
    end
  end

  defp recover_battle(battle), do: interrupt_battle(battle)

  defp interrupt_battle(battle) do
    battle =
      if attempt = running_attempt(battle.id) do
        update(attempt, state: "interrupted", result: %{"status" => "interrupted"})

        arm_recovery(battle, attempt)
      else
        battle
      end

    needs_attention(battle, "restart_requires_inspection")
  end

  defp arm_recovery(battle, attempt) do
    if Enum.all?(attempts(battle.id), &(&1.id == attempt.id or settled?(battle, &1))) do
      key =
        cond do
          provider_recoverable?(battle, attempt) -> "provider_closure_pending"
          integration_recoverable?(battle, attempt) -> "integration_recovery_pending"
          true -> nil
        end

      if key, do: update(battle, context: Map.put(battle.context, key, attempt.id)), else: battle
    else
      battle
    end
  end

  defp provider_recoverable?(battle, attempt),
    do:
      battle.state in ~w(running pausing stopping) and not is_nil(attempt.role) and
        ProviderClosure.enabled?(battle.snapshot)

  defp integration_recoverable?(battle, attempt),
    do:
      battle.state in ~w(running pausing) and attempt.stage == "integrate" and
        not timing_fenced?(battle, attempt) and
        battle.snapshot["native_recovery"] == "retained-integration-v1"

  # Only a durable restart marker can authorize this read-only inspection. It is
  # separate from the interrupted claim, which must never be replayed or rewritten.
  def recovery_attempt, do: Enum.find_value(active(), &pending_reconciliation/1)

  defp pending_reconciliation(battle) do
    with id when is_binary(id) <-
           battle.context["provider_closure_pending"] ||
             battle.context["integration_recovery_pending"],
         %Attempt{} = attempt <- Repo.get(Attempt, id),
         true <- provider_reconciliation_current?(attempt) or reconciliation_current?(attempt) do
      attempt
    else
      _ -> nil
    end
  end

  def provider_reconciliation_current?(%Attempt{} = attempt) do
    case get(attempt.battle_id) do
      %Battle{state: "needs_attention", reason: "restart_requires_inspection"} = battle ->
        ProviderClosure.enabled?(battle.snapshot) and not is_nil(attempt.role) and
          battle.context["provider_closure_pending"] == attempt.id and
          battle.current_task_id == attempt.task_id and battle.stage == attempt.stage and
          interrupted_current?(attempt)

      _ ->
        false
    end
  end

  def reconcile_recovery(attempt, result),
    do:
      if(is_nil(attempt.role),
        do: reconcile_integration(attempt, result),
        else: reconcile_provider(attempt, result)
      )

  defp interrupted_current?(attempt),
    do:
      attempt.state == "interrupted" and attempt.result == %{"status" => "interrupted"} and
        Repo.get(Attempt, attempt.id) == attempt

  def reconcile_provider(attempt, result) do
    transaction(fn ->
      unless provider_reconciliation_current?(attempt), do: Repo.rollback(:stale_reconciliation)
      unless bound?(attempt, result, ["provider_closure"]), do: Repo.rollback(:foreign_result)

      verified = verified_provider_closure?(attempt, result)

      unless verified or failed_provider_closure?(attempt, result),
        do: Repo.rollback(:invalid_result)

      battle = get(attempt.battle_id)

      context =
        battle.context
        |> Map.delete("provider_closure_pending")
        |> Map.update(
          "provider_closures",
          %{attempt.id => result},
          &Map.put(&1, attempt.id, result)
        )

      battle = update(battle, context: context, control_revision: battle.control_revision + 1)

      record(battle, "provider_closure_observed", %{
        "attempt_id" => attempt.id,
        "cleanup_verified" => verified
      })

      battle
    end)
  end

  defp verified_provider_closure?(attempt, result),
    do:
      result["status"] == "closed" and result["cleanup_verified"] == true and
        Map.keys(result) -- (@envelope ++ ~w(status cleanup_verified provider_closure)) == [] and
        ProviderClosure.verified?(attempt, result["provider_closure"])

  defp failed_provider_closure?(attempt, result),
    do:
      result["status"] == "failed" and result["cleanup_verified"] == false and
        Map.keys(result) -- (@envelope ++ ~w(status reason cleanup_verified)) == [] and
        valid_result?(attempt, result)

  defp provider_closed?(battle, attempt),
    do:
      ProviderClosure.enabled?(battle.snapshot) and attempt.state == "interrupted" and
        get_in(battle.context, ["provider_closures", attempt.id, "status"]) == "closed" and
        get_in(battle.context, ["provider_closures", attempt.id, "cleanup_verified"]) == true

  def reconciliation_current?(%Attempt{} = attempt) do
    case get(attempt.battle_id) do
      %Battle{state: "needs_attention", reason: "restart_requires_inspection", stage: "integrate"} =
          battle ->
        battle.snapshot["native_recovery"] == "retained-integration-v1" and
          battle.context["integration_recovery_pending"] == attempt.id and
          battle.current_task_id == attempt.task_id and
          attempt.state == "interrupted" and attempt.result == %{"status" => "interrupted"} and
          Repo.get(Attempt, attempt.id) == attempt

      _ ->
        false
    end
  end

  def reconcile_integration(attempt, result, now \\ DateTime.utc_now()) do
    transaction(fn ->
      unless reconciliation_current?(attempt), do: Repo.rollback(:stale_reconciliation)
      unless bound?(attempt, result), do: Repo.rollback(:foreign_result)
      verified = verified_integration?(attempt, result)

      unless verified or failed_reconciliation?(attempt, result),
        do: Repo.rollback(:invalid_result)

      battle = retain_reconciliation(get(attempt.battle_id), attempt, result, verified)
      finish_reconciliation(battle, attempt, result, verified, now)
    end)
  end

  defp verified_integration?(attempt, result) do
    native = result["native_battle"]

    expected = %{
      "status" => "battle_integrated",
      "key" => attempt.id,
      "battle_key" => attempt.battle_id,
      "head" => result["head"],
      "previous_head" => attempt.request["context"]["head"],
      "candidate_key" => attempt.request["task_context"]["native_candidate"]["key"]
    }

    result["status"] == "integrated" and stage_cleanup_verified?(attempt, result) and
      is_map(native) and Cuckoding.LocalGit.normalize(native) == native and
      Map.take(native, Map.keys(expected)) == expected
  end

  defp failed_reconciliation?(attempt, result),
    do:
      result["status"] == "failed" and result["cleanup_verified"] == false and
        valid_result?(attempt, result)

  defp retain_reconciliation(battle, attempt, result, verified) do
    observations =
      Map.put(battle.context["integration_reconciliations"] || %{}, attempt.id, result)

    context =
      battle.context
      |> Map.delete("integration_recovery_pending")
      |> Map.put("integration_reconciliations", observations)

    battle = update(battle, context: context)

    record(battle, "integration_reconciled", %{
      "attempt_id" => attempt.id,
      "status" => result["status"],
      "cleanup_verified" => verified
    })

    battle
  end

  defp finish_reconciliation(battle, _attempt, _result, false, _now), do: battle

  defp finish_reconciliation(battle, attempt, result, true, now) do
    if timing_blocked?(battle) or expired?(attempt.deadline_at, now) or
         expired?(battle.deadline_at, now) do
      needs_attention(
        battle,
        if(timing_blocked?(battle), do: "timing_gap", else: "late_result_rejected")
      )
    else
      battle = advance(battle, attempt, result)

      battle =
        update(battle,
          state: "paused",
          reason: "restart_checkpoint",
          control_revision: battle.control_revision + 1
        )

      record(battle, "recovery_paused", %{
        "stage" => battle.stage,
        "task_id" => battle.current_task_id,
        "control_revision" => battle.control_revision
      })

      battle
    end
  end

  defp finish_stop(
         battle,
         attempt,
         %{"status" => "cancelled", "cleanup_verified" => true} = result
       ) do
    update(attempt, state: "cancelled", result: result)
    battle = update(battle, state: "stopped", reason: "user_stop")
    record(battle, "stopped", %{"attempt_id" => attempt.id})
    battle
  end

  defp finish_stop(battle, attempt, %{"status" => "cancelled"} = result) do
    update(attempt, state: "interrupted", result: result)
    needs_attention(battle, "cleanup_uncertain")
  end

  defp finish_stop(_, _, _), do: Repo.rollback(:stop_pending)

  defp complete_attempt(battle, attempt, result) do
    status = result["status"]

    update(attempt,
      state: if(status in ~w(failed blocked), do: "failed", else: "completed"),
      result: result
    )

    record(battle, "stage_finished", %{
      "attempt_id" => attempt.id,
      "stage" => attempt.stage,
      "task_id" => attempt.task_id,
      "status" => status
    })

    cond do
      status in ~w(failed blocked) -> needs_attention(battle, result["reason"] || status)
      status == "changes_requested" -> review_return(battle, attempt, result)
      true -> advance(battle, attempt, result)
    end
  end

  defp advance(battle, %Attempt{stage: "admission"}, result) do
    task = hd(tasks(battle.id))

    update(battle,
      context: result_context(result),
      current_task_id: task.task_id,
      stage: "prepare_worktree"
    )
  end

  defp advance(battle, %Attempt{stage: "integrate"}, result) do
    task = current_task(battle)
    update(task, state: "completed", context: Map.merge(task.context, result_context(result)))
    context = Map.merge(battle.context, Map.take(result, ~w(head native_battle)))
    battle |> update(context: context) |> next_task()
  end

  defp advance(battle, %Attempt{stage: "summary"}, result) do
    battle =
      update(battle,
        state:
          if((battle.context["omitted_tasks"] || []) == [], do: "completed", else: "partial"),
        context: Map.merge(battle.context, result_context(result))
      )

    record(battle, battle.state)
    battle
  end

  defp advance(battle, attempt, result) do
    next_stage = review_stage(battle, Map.fetch!(@next, attempt.stage))

    if task = current_task(battle) do
      context = Map.merge(task.context, result_context(result))

      context =
        if(attempt.stage == "prepare_worktree",
          do: Map.drop(context, ~w(candidate_sha native_candidate checks)),
          else: context
        )

      state = projection(next_stage)
      update(task, state: state, context: context)
    end

    context =
      if(is_nil(attempt.task_id),
        do: Map.merge(battle.context, result_context(result)),
        else: battle.context
      )

    update(battle, stage: next_stage, context: context)
  end

  defp review_stage(battle, stage) when stage in ~w(checks final_checks) do
    if Snapshot.task_review_only?(battle.snapshot), do: Map.fetch!(@next, stage), else: stage
  end

  defp review_stage(_, stage), do: stage

  defp review_return(battle, %Attempt{stage: "secutor"}, result) do
    task = current_task(battle)
    round = task.review_round + 1

    update(task,
      state: "specs",
      review_round: round,
      context:
        Map.merge(task.context, %{
          "feedback" => result["feedback"] || result["provider"]["report"]["summary"],
          "previous_implementation" => get_in(task.context, ["provider", "report", "summary"])
        })
    )

    if round >= battle.snapshot["limits"]["review_rounds"],
      do: needs_attention(battle, "review_limit"),
      else: update(battle, stage: "prepare_worktree")
  end

  defp review_return(battle, _, _), do: needs_attention(battle, "final_review_changes_requested")

  defp projection(stage) when stage in ~w(prepare_worktree coordinator speculator), do: "specs"
  defp projection(stage) when stage in ~w(checks secutor integrate), do: "review"
  defp projection(_), do: "in_process"

  defp valid_result?(_, %{"status" => "failed", "reason" => reason}),
    do: is_binary(reason) and byte_size(reason) in 1..200

  defp valid_result?(%Attempt{role: role} = attempt, result) when not is_nil(role),
    do: provider_result?(attempt, result)

  defp valid_result?(%Attempt{stage: "admission"} = attempt, %{"status" => "admitted"} = result),
    do:
      sha?(result["head"]) and is_map(result["native_battle"]) and
        resolved_checks?(attempt, result["resolved_checks"])

  defp valid_result?(%Attempt{stage: "prepare_worktree"}, %{"status" => "prepared"} = result),
    do: is_map(result["preparation"])

  defp valid_result?(%Attempt{stage: "capture"}, %{"status" => "captured"} = result),
    do: sha?(result["candidate_sha"]) and is_map(result["native_candidate"])

  defp valid_result?(%Attempt{stage: stage} = attempt, %{"status" => "passed"} = result)
       when stage in ~w(checks final_checks),
       do: candidate?(attempt, result) and checks?(attempt, result["checks"])

  defp valid_result?(
         %Attempt{stage: stage} = attempt,
         %{"status" => "checks_failed", "cleanup_verified" => true} = result
       )
       when stage in ~w(checks final_checks),
       do: candidate?(attempt, result) and failed_checks?(attempt, result["checks"])

  defp valid_result?(
         %Attempt{stage: "integrate"} = attempt,
         %{"status" => "integrated"} = result
       ),
       do:
         candidate?(attempt, result) and result["head"] == result["candidate_sha"] and
           is_map(result["native_battle"])

  defp valid_result?(_, _), do: false

  defp provider_result?(attempt, result) do
    provider = result["provider"] || %{}
    normalized = TaskTurn.normalize(Jason.encode!(provider))

    allowed =
      if(attempt.stage in ~w(secutor final_secutor),
        do: ~w(completed changes_requested blocked),
        else: ~w(completed blocked)
      )

    normalized["status"] == "task_finished" and normalized == provider and
      result["status"] in allowed and
      provider_identity?(attempt, provider) and
      provider["report"]["outcome"] == result["status"] and fresh_session?(attempt, provider) and
      review_candidate?(attempt, result)
  end

  defp review_candidate?(%Attempt{stage: stage} = attempt, result)
       when stage in ~w(secutor final_secutor),
       do: candidate?(attempt, result) and review_verdict?(attempt, result)

  defp review_candidate?(_, _), do: true

  defp review_verdict?(attempt, %{"status" => "completed"} = result) do
    context =
      if(attempt.task_id, do: attempt.request["task_context"], else: attempt.request["context"])

    if Snapshot.task_review_only?(attempt.request["snapshot"]),
      do: is_nil(context["checks"]) and inspected?(result["provider"]["tools"]),
      else: checks?(attempt, context["checks"])
  end

  defp review_verdict?(_, _), do: true

  defp inspected?(tools) when is_list(tools),
    do:
      Enum.any?(tools, &(&1["tool"] in ~w(list_files read_file) and &1["status"] == "completed"))

  defp inspected?(_), do: false

  defp provider_identity?(attempt, provider) do
    role = attempt.request["role"]

    expected = %{
      "request_id" => attempt.id,
      "requested_model" => role["model"],
      "observed_model" => role["model"],
      "effort" => role["effort"],
      "access" => if(attempt.stage == "implementor", do: "write", else: "read")
    }

    Map.take(provider, Map.keys(expected)) == expected and
      provider["transport"] == if(role["kind"] == "cursor", do: "cursor-acp-v1", else: nil)
  end

  defp fresh_session?(attempt, provider) do
    not Repo.exists?(
      from a in Attempt,
        where:
          a.battle_id == ^attempt.battle_id and a.id != ^attempt.id and
            (fragment("json_extract(?, '$.provider.thread_id')", a.result) ==
               ^provider["thread_id"] or
               fragment("json_extract(?, '$.provider.turn_id')", a.result) == ^provider["turn_id"])
    )
  end

  defp checks?(attempt, checks) when is_list(checks) do
    declared = attempt.request["snapshot"]["checks"]

    declared != [] and length(checks) == length(declared) and Enum.all?(checks, &is_map/1) and
      Enum.sort(Enum.map(checks, & &1["id"])) == Enum.sort(Enum.map(declared, & &1["id"])) and
      Enum.all?(checks, &(&1["status"] == "passed" and &1["exit_code"] == 0))
  end

  defp checks?(_, _), do: false

  defp failed_checks?(attempt, checks) when is_list(checks) and checks != [] do
    declared = attempt.request["snapshot"]["checks"]

    Enum.all?(checks, &is_map/1) and length(checks) <= length(declared) and
      Enum.map(checks, & &1["id"]) ==
        declared |> Enum.take(length(checks)) |> Enum.map(& &1["id"]) and
      Enum.all?(Enum.drop(checks, -1), &(&1["status"] == "passed" and &1["exit_code"] == 0)) and
      failed_check?(List.last(checks))
  end

  defp failed_checks?(_, _), do: false

  defp failed_check?(%{"status" => "failed", "exit_code" => code}),
    do: is_integer(code) and code in 1..255

  defp failed_check?(_), do: false

  defp resolved_checks?(attempt, resolved) when is_list(resolved) do
    declared = attempt.request["snapshot"]["checks"]

    (declared != [] or Snapshot.task_review_only?(attempt.request["snapshot"])) and
      length(declared) == length(resolved) and Enum.all?(resolved, &is_map/1) and
      Enum.map(
        resolved,
        &Map.take(&1, ~w(id name executable arguments directory timeout_seconds))
      ) == declared
  end

  defp resolved_checks?(_, _), do: false

  defp candidate?(attempt, result) do
    expected =
      if(attempt.task_id,
        do: attempt.request["task_context"]["candidate_sha"],
        else: attempt.request["context"]["head"]
      )

    sha?(expected) and result["candidate_sha"] == expected
  end

  defp bound?(attempt, result, extra \\ [])

  defp bound?(attempt, result, extra) when is_map(result) do
    Map.keys(result) -- (@result_fields ++ extra) == [] and
      Map.take(result, @envelope) == Map.take(attempt.request, @envelope) and
      match?({:ok, _}, Jason.encode(result)) and byte_size(Jason.encode!(result)) <= 131_072
  end

  defp bound?(_, _, _), do: false
  defp result_context(result), do: Map.drop(result, @envelope ++ ["status", "reason"])
  defp current_task(%Battle{current_task_id: nil}), do: nil

  defp current_task(battle),
    do: Repo.get_by!(Task, battle_id: battle.id, task_id: battle.current_task_id)

  defp running_attempt(id),
    do: Repo.one(from a in Attempt, where: a.battle_id == ^id and a.state == "running")

  defp attention(battle, reason) do
    needs_attention(battle, reason)
    {:error, reason}
  end

  defp needs_attention(battle, reason) do
    if task = current_task(battle) do
      column = if(task.state == "pending", do: "todo", else: task.state)
      context = Map.put_new(task.context, "column", column)
      update(task, state: "needs_attention", context: context)
    end

    battle = update(battle, state: "needs_attention", reason: reason)
    record(battle, "needs_attention", %{"reason" => reason})
    battle
  end

  defp update(record, fields), do: Repo.update!(Ecto.Changeset.change(record, fields))

  defp record(battle, kind, fields \\ %{}),
    do:
      Foundation.record(
        "battle." <> kind,
        Map.merge(fields, %{
          "battle_id" => battle.id,
          "arena_id" => battle.arena_id,
          "tabula_id" => battle.tabula_id
        })
      )

  defp expired?(deadline, now), do: DateTime.compare(now, deadline) != :lt
  defp min_time(a, b), do: if(DateTime.compare(a, b) == :gt, do: b, else: a)
  defp sha?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{40}\z/, value)
  defp valid_id?(id), do: match?({:ok, _}, Ecto.UUID.cast(id))

  defp transaction(fun) do
    case Repo.transaction(fun, mode: :immediate) do
      {:ok, {:error, _} = error} ->
        Foundation.broadcast()
        error

      {:ok, _} = result ->
        Foundation.broadcast()
        result

      error ->
        error
    end
  end
end
