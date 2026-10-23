defmodule Cuckoding.Battles do
  @moduledoc "Durable bounded Arena authority and attempt claims; workers own external effects."
  import Ecto.Query, except: [update: 2, update: 3]

  alias Cuckoding.Battles.{
    Attempt,
    Backoff,
    Battle,
    Capacity,
    PreparationRecovery,
    ProviderClosure,
    Receipts,
    Slots,
    Snapshot,
    Stages,
    Task,
    Waves
  }

  alias Cuckoding.{Event, Foundation, Repo, TaskTurn}

  @active ~w(running pausing paused stopping needs_attention)
  @retryable ~w(launch_failed timeout connection_lost provider_error profile_busy turn_failed)
  @envelope ~w(battle_id request_id task_id stage criteria_sha256)

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
    battle.snapshot["idle_sleep"] == "shell-lease-v1" and
      battle.state in ~w(running pausing stopping) and
      DateTime.compare(now, battle.inserted_at) != :lt and idle_sleep_workers?(battle, now)
  end

  defp idle_sleep_workers?(battle, now) do
    workers =
      if Waves.enabled?(battle.snapshot),
        do:
          Repo.all(
            from a in Attempt, where: a.battle_id == ^battle.id and a.state == "running", limit: 2
          ),
        else: [running_attempt(battle.id)]

    workers = if workers == [], do: [nil], else: workers
    Enum.any?(workers, &idle_sleep_work?(battle, &1, now))
  end

  defp idle_sleep_work?(battle, attempt, now) do
    if battle.state == "stopping" or timing_blocked?(battle) do
      cleanup_sleep_window?(battle, attempt, now)
    else
      not expired?(battle.deadline_at, now) and
        if(attempt, do: not expired?(attempt.deadline_at, now), else: battle.state == "running")
    end
  end

  defp cleanup_sleep_window?(_, nil, _), do: false

  defp cleanup_sleep_window?(battle, attempt, now) do
    case cancellation_started_at(battle) do
      %DateTime{} = time ->
        DateTime.compare(now, time) != :lt and not expired?(DateTime.add(time, 5), now) and
          not expired?(DateTime.add(min_time(battle.deadline_at, attempt.deadline_at), 5), now)

      _ ->
        false
    end
  end

  defp cancellation_started_at(battle),
    do:
      if(Waves.enabled?(battle.snapshot),
        do: parse_cancellation(battle.context["cancellation_started_at"]),
        else: battle.updated_at
      )

  defp parse_cancellation(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, 0} -> time
      _ -> nil
    end
  end

  defp parse_cancellation(_), do: nil

  defp mark_cancellation(battle) do
    if Waves.enabled?(battle.snapshot),
      do:
        update(battle,
          context:
            Map.put_new(
              battle.context,
              "cancellation_started_at",
              DateTime.to_iso8601(DateTime.utc_now())
            )
        ),
      else: battle
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
        Backoff.pending?(battle) ->
          claim_backoff(battle, now)

        battle.state != "running" ->
          Repo.rollback(:not_running)

        timing_blocked?(battle) ->
          attention(battle, "timing_gap")

        stage_busy?(battle) ->
          Repo.rollback(:busy)

        expired?(battle.deadline_at, now) ->
          attention(battle, "deadline_exceeded")

        battle.turns_used >= battle.snapshot["limits"]["turns"] ->
          attention(battle, "turn_limit")

        true ->
          claim_work(battle, now)
      end
    end)
  end

  defp stage_busy?(battle),
    do:
      (not Waves.enabled?(battle.snapshot) or is_nil(battle.current_task_id)) and
        running_attempt(battle.id)

  defp claim_work(battle, now) do
    if Waves.enabled?(battle.snapshot) and battle.current_task_id,
      do: claim_wave(battle, now),
      else: claim(battle, now)
  end

  defp claim_wave(battle, now) do
    running =
      Repo.all(from a in Attempt, where: a.battle_id == ^battle.id and a.state == "running")

    candidates = Waves.candidates(battle, tasks(battle.id), running)
    selected = Enum.find(candidates, &claimable_wave?/1)
    if is_nil(selected), do: Repo.rollback(if(candidates == [], do: :busy, else: :capacity))
    task = current_task(selected)
    update(task, context: Waves.put_stage(task.context, selected, selected.stage))
    claim(selected, now)
  end

  defp claimable_wave?(view) do
    role =
      Slots.task_binding(
        view.snapshot,
        Stages.role(view.snapshot, view.stage),
        current_task(view)
      )

    Capacity.available?(view.snapshot, role)
  end

  defp claim(battle, now) do
    task = current_task(battle)
    role_id = Stages.role(battle.snapshot, battle.stage)
    role = claimed_binding(battle.snapshot, role_id, task)
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

  defp claimed_binding(snapshot, role_id, task) do
    unless Slots.valid_task?(snapshot, task), do: Repo.rollback(:invalid_binding)
    role = Slots.task_binding(snapshot, role_id, task)
    if role_id && is_nil(role), do: Repo.rollback(:invalid_binding)
    role
  end

  def finish(id, token, result, now \\ DateTime.utc_now()) do
    transaction(fn -> finish_claim(id, token, result, now) end)
  end

  def stage_cleanup_verified?(%Attempt{} = attempt, result),
    do:
      Receipts.bound?(attempt, result) and result["cleanup_verified"] == true and
        Receipts.payload_valid?(attempt, result)

  defp finish_claim(id, token, result, now) do
    attempt = if(valid_id?(id), do: Repo.get(Attempt, id))

    if is_nil(attempt) or attempt.claim_token != token or attempt.state != "running",
      do: Repo.rollback(:stale_attempt)

    if not Receipts.bound?(attempt, result), do: Repo.rollback(:foreign_result)
    finish_current(get(attempt.battle_id), attempt, result, now)
  end

  defp finish_current(battle, attempt, result, now) do
    if Waves.enabled?(battle.snapshot) and battle.state == "needs_attention" and
         battle.reason == "late_result_rejected" do
      Waves.reject_receipt(battle, attempt, result)
    else
      finish_selected(battle, attempt, result, now)
    end
  end

  defp finish_selected(battle, attempt, result, now) do
    battle = if Waves.enabled?(battle.snapshot), do: Waves.view(battle, attempt), else: battle

    updated =
      if timing_fenced?(battle, attempt),
        do: finish_timing_gap(battle, attempt, result),
        else: finish_unfenced(battle, attempt, result, now)

    focus_wave(updated)
  end

  defp focus_wave(%Battle{} = battle),
    do: if(Waves.enabled?(battle.snapshot), do: Waves.focus(battle), else: battle)

  defp focus_wave(other), do: other

  defp finish_unfenced(battle, attempt, result, now) do
    cond do
      battle.state == "stopping" ->
        finish_stop(battle, attempt, result)

      battle.state not in ~w(running pausing) ->
        Repo.rollback(:not_running)

      expired?(attempt.deadline_at, now) or expired?(battle.deadline_at, now) ->
        expire_attempt(battle, attempt, result)

      not Receipts.payload_valid?(attempt, result) ->
        Repo.rollback(:invalid_result)

      battle.state == "pausing" and result["cleanup_verified"] != true ->
        update(attempt, state: "interrupted", result: result)
        needs_attention(battle, "cleanup_uncertain")

      true ->
        complete_attempt(battle, attempt, result)
        |> finish_pause()
        |> focus_wave()
        |> schedule_backoff(Waves.backoff_origin(battle), now)
    end
  end

  defp expire_attempt(battle, attempt, result) do
    unless Receipts.rejected_payload_valid?(attempt, result), do: Repo.rollback(:invalid_result)
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
    battle = mark_active_cancellation(battle, attempt)

    blocked =
      observation["kind"] == "clock_backward" or not is_nil(attempt) or not quiescent?(battle)

    observation = bind_timing_observation(battle, observation, attempt, blocked)

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

  defp mark_active_cancellation(battle, nil), do: battle
  defp mark_active_cancellation(battle, _), do: mark_cancellation(battle)

  defp bind_timing_observation(battle, observation, attempt, blocked) do
    observation =
      Map.merge(observation, %{
        "attempt_id" => if(attempt, do: attempt.id),
        "recovery_attempt_id" =>
          battle.context["integration_recovery_pending"] ||
            battle.context["preparation_recovery_pending"],
        "blocks_continuation" => blocked
      })

    observation =
      if Waves.enabled?(battle.snapshot) do
        ids =
          Repo.all(
            from a in Attempt,
              where: a.battle_id == ^battle.id and a.state == "running",
              select: a.id
          )

        Map.put(observation, "attempt_ids", ids)
      else
        observation
      end

    observation
  end

  defp timing_blocked?(battle),
    do: get_in(battle.context, ["timing_gap", "blocks_continuation"]) == true

  defp timing_fenced?(battle, attempt),
    do:
      get_in(battle.context, ["timing_gap", "attempt_id"]) == attempt.id or
        (Waves.enabled?(battle.snapshot) and
           attempt.id in (get_in(battle.context, ["timing_gap", "attempt_ids"]) || []))

  defp timing_closed?(battle, attempt),
    do:
      attempt.state == "interrupted" and attempt.result["cleanup_verified"] == true and
        attempt.id in (battle.context["timing_closed_attempts"] || [])

  defp finish_timing_gap(battle, attempt, result) do
    unless Receipts.rejected_payload_valid?(attempt, result), do: Repo.rollback(:invalid_result)
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

    finish_timing_boundary(battle, attempt, cleanup)
  end

  defp finish_timing_boundary(%Battle{state: "stopping"} = battle, attempt, cleanup) do
    cond do
      cleanup and safe_to_stop?(battle) ->
        battle = update(battle, state: "stopped", reason: "user_stop")
        record(battle, "stopped", %{"attempt_id" => attempt.id})
        battle

      Waves.enabled?(battle.snapshot) and running_attempt(battle.id) ->
        battle

      true ->
        needs_attention(battle, "cleanup_uncertain")
    end
  end

  defp finish_timing_boundary(battle, _, cleanup),
    do: needs_attention(battle, if(cleanup, do: "timing_gap", else: "cleanup_uncertain"))

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
    Enum.all?(Slots.bindings(battle.snapshot), fn role ->
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
    cond do
      running_attempt(battle.id) ->
        battle

      Waves.enabled?(battle.snapshot) and Waves.blocked?(battle) ->
        update(battle, state: "needs_attention")

      quiescent?(battle) ->
        battle = update(battle, state: "paused")
        record(battle, "paused")
        battle

      true ->
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
    reconciled?(battle, attempt) or Waves.conflict_settled?(battle, attempt) or
      (attempt.result["cleanup_verified"] == true and
         (attempt.state == "completed" or
            (attempt.state == "failed" and
               attempt.id in (retried(battle) ++ (battle.context["skipped_attempts"] || [])))))
  end

  defp reconciled?(battle, attempt),
    do:
      PreparationRecovery.reconciled?(battle, attempt) or
        (attempt.state == "interrupted" and
           get_in(battle.context, ["integration_reconciliations", attempt.id, "status"]) ==
             "integrated")

  defp retried(battle), do: battle.context["provider_retries"] || []

  defp schedule_backoff(battle, "running", now) do
    multiple =
      Waves.enabled?(battle.snapshot) and map_size(battle.context["lane_blockers"] || %{}) > 1

    attempt = if Backoff.enabled?(battle) and not multiple, do: retry_candidate(battle, now)

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
        battle |> retry_current(attempt) |> claim_work(now)

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
    attempt = Waves.control_attempt(battle, history)

    used =
      Enum.count(history, &(&1.id in retried(battle) and &1.task_id == battle.current_task_id))

    if retry_scope?(battle, now) and used < 2 and
         retryable_attempt?(battle, attempt) and
         Enum.all?(history, &(&1.id == attempt.id or control_settled?(battle, &1))) do
      attempt
    end
  end

  defp retry_candidate(_, _), do: nil

  defp control_settled?(battle, attempt),
    do: settled?(battle, attempt) or Waves.other_blocked?(battle, attempt)

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
      not is_nil(Stages.role(battle.snapshot, attempt.stage)) and
      attempt.id not in retried(battle) and
      reason == battle.reason and
      TaskTurn.normalize(Jason.encode!(provider)) == provider
  end

  defp retryable_attempt?(_, _), do: false

  defp retry_current(battle, attempt) do
    stage =
      if Stages.access(battle.snapshot, attempt.stage) == "write",
        do: "prepare_worktree",
        else: battle.stage

    if task = current_task(battle) do
      update(task,
        state: projection(stage),
        context: task.context |> Map.delete("column") |> Waves.put_stage(battle, stage)
      )
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

    if Waves.enabled?(battle.snapshot),
      do: Waves.clear_block(battle, attempt.task_id),
      else: battle
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
    attempt = Waves.control_attempt(battle, history)

    task_failure?(battle, attempt) and
      Enum.all?(history, &(&1.id == attempt.id or control_settled?(battle, &1)))
  end

  defp task_failure?(_, nil), do: false

  defp task_failure?(battle, attempt) do
    local? =
      attempt.task_id == battle.current_task_id and attempt.stage == battle.stage and
        attempt.result["cleanup_verified"] == true and not is_nil(attempt.role)

    local? and
      (retryable_attempt?(battle, attempt) or
         (review_failure?(battle, attempt) and Receipts.provider_valid?(attempt, attempt.result)))
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

    battle =
      if Waves.enabled?(battle.snapshot),
        do: Waves.clear_blocks(battle, Enum.map(affected, & &1.task_id)),
        else: battle

    next_task(battle)
  end

  defp next_task(battle) do
    if Waves.enabled?(battle.snapshot),
      do: Waves.activate(battle, review_stage(battle, "final_checks")),
      else: next_sequential_task(battle)
  end

  defp next_sequential_task(battle) do
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
        attempt = running_attempt(battle.id)
        battle = mark_active_cancellation(battle, attempt)
        state = if(attempt, do: "stopping", else: "stopped")
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
      |> Enum.filter(
        &(&1.state != "needs_attention" or Backoff.pending?(&1) or
            (Waves.enabled?(&1.snapshot) and not is_nil(running_attempt(&1.id))))
      )
      |> Enum.map(&recover_battle/1)
    end)
  end

  defp recover_battle(%Battle{state: "needs_attention"} = battle) do
    cond do
      Backoff.pending?(battle) -> cancel_wait(battle, "restart_requires_confirmation")
      Waves.enabled?(battle.snapshot) and running_attempt(battle.id) -> interrupt_battle(battle)
      true -> battle
    end
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
    if Waves.enabled?(battle.snapshot),
      do: interrupt_wave(battle),
      else: interrupt_sequential(battle)
  end

  defp interrupt_wave(battle) do
    {battle, selected} = Waves.interrupt(battle)

    battle =
      if selected && is_nil(battle.context["provider_closure_pending"]),
        do: arm_recovery(battle, selected),
        else: battle

    needs_attention(battle, "restart_requires_inspection")
  end

  defp interrupt_sequential(battle) do
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
          provider_recoverable?(battle, attempt) ->
            "provider_closure_pending"

          integration_recoverable?(battle, attempt) ->
            "integration_recovery_pending"

          PreparationRecovery.eligible?(battle, attempt) and not timing_fenced?(battle, attempt) ->
            "preparation_recovery_pending"

          true ->
            nil
        end

      if key, do: update(battle, context: Map.put(battle.context, key, attempt.id)), else: battle
    else
      arm_preparation_wave(battle, attempt)
    end
  end

  defp arm_preparation_wave(battle, selected) do
    unsettled = Enum.reject(attempts(battle.id), &settled?(battle, &1))

    if PreparationRecovery.wave_eligible?(battle, unsettled) and
         Enum.all?(unsettled, &(interrupted_current?(&1) and not timing_fenced?(battle, &1))) do
      ids = [selected.id | Enum.map(unsettled, & &1.id) -- [selected.id]]

      context =
        Map.merge(battle.context, %{
          "preparation_recovery_pending" => selected.id,
          "preparation_recovery_wave" => %{"attempt_ids" => ids, "remaining_ids" => ids}
        })

      battle = update(battle, context: context)
      record(battle, "preparation_recovery_queued", %{"attempt_ids" => ids})
      battle
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
             battle.context["integration_recovery_pending"] ||
             battle.context["preparation_recovery_pending"],
         %Attempt{} = attempt <- Repo.get(Attempt, id),
         true <-
           provider_reconciliation_current?(attempt) or reconciliation_current?(attempt) or
             preparation_reconciliation_current?(attempt) do
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

  def reconcile_recovery(%Attempt{stage: "prepare_worktree", role: nil} = attempt, result),
    do: reconcile_preparation(attempt, result)

  def reconcile_recovery(attempt, result),
    do:
      if(is_nil(attempt.role),
        do: reconcile_integration(attempt, result),
        else: reconcile_provider(attempt, result)
      )

  def preparation_reconciliation_current?(%Attempt{} = attempt) do
    case get(attempt.battle_id) do
      %Battle{reason: "restart_requires_inspection"} = battle ->
        PreparationRecovery.pending?(battle, attempt) and interrupted_current?(attempt)

      _ ->
        false
    end
  end

  def reconcile_preparation(attempt, result, now \\ DateTime.utc_now()) do
    transaction(fn ->
      battle = get(attempt.battle_id)

      unless battle && PreparationRecovery.pending?(battle, attempt) &&
               interrupted_current?(attempt),
             do: Repo.rollback(:stale_reconciliation)

      unless Receipts.bound?(attempt, result), do: Repo.rollback(:foreign_result)
      verified = PreparationRecovery.verified?(attempt, result)

      unless verified or PreparationRecovery.failed?(attempt, result),
        do: Repo.rollback(:invalid_result)

      observation = %{"receipt" => result, "observed_at" => DateTime.to_iso8601(now)}

      context =
        battle.context
        |> Map.delete("preparation_recovery_pending")
        |> Map.update(
          "preparation_reconciliations",
          %{attempt.id => observation},
          &Map.put(&1, attempt.id, observation)
        )

      battle = update(battle, context: context)

      record(battle, "preparation_reconciled", %{
        "attempt_id" => attempt.id,
        "status" => result["status"],
        "cleanup_verified" => verified
      })

      finish_preparation_recovery(battle, attempt, result, verified, now)
    end)
  end

  defp finish_preparation_recovery(battle, attempt, result, verified, now) do
    if wave = battle.context["preparation_recovery_wave"] do
      members = preparation_wave_members!(battle, wave)

      case tl(wave["remaining_ids"]) do
        [] ->
          battle =
            update(battle, context: Map.delete(battle.context, "preparation_recovery_wave"))

          finish_preparation_wave(battle, members, now)

        [next | _] = remaining ->
          member = Enum.find(members, &(&1.id == next))

          context =
            battle.context
            |> Map.put("preparation_recovery_pending", next)
            |> put_in(["preparation_recovery_wave", "remaining_ids"], remaining)

          update(battle, context: context, current_task_id: member.task_id, stage: member.stage)
      end
    else
      finish_reconciliation(battle, attempt, result, verified, now)
    end
  end

  defp preparation_wave_members!(battle, wave) do
    Enum.map(wave["attempt_ids"], fn id ->
      member = Repo.get(Attempt, id)

      unless member && PreparationRecovery.member?(battle, member) && interrupted_current?(member),
        do: Repo.rollback(:stale_reconciliation)

      member
    end)
  end

  defp finish_preparation_wave(battle, members, now) do
    cond do
      timing_blocked?(battle) ->
        update(battle, state: "needs_attention", reason: "timing_gap")

      not Enum.all?(members, &PreparationRecovery.reconciled?(battle, &1)) ->
        battle

      expired?(battle.deadline_at, now) or Enum.any?(members, &expired?(&1.deadline_at, now)) ->
        needs_attention(battle, "late_result_rejected")

      true ->
        Enum.reduce(members, battle, fn member, current ->
          current = update(current, current_task_id: member.task_id, stage: member.stage)
          current = Waves.clear_block(current, member.task_id)
          receipt = current.context["preparation_reconciliations"][member.id]["receipt"]
          advance(current, member, receipt)
        end)
        |> Waves.focus()
        |> pause_reconciled()
    end
  end

  defp interrupted_current?(attempt),
    do:
      attempt.state == "interrupted" and attempt.result == %{"status" => "interrupted"} and
        Repo.get(Attempt, attempt.id) == attempt

  def reconcile_provider(attempt, result) do
    transaction(fn ->
      unless provider_reconciliation_current?(attempt), do: Repo.rollback(:stale_reconciliation)

      unless Receipts.bound?(attempt, result, ["provider_closure"]),
        do: Repo.rollback(:foreign_result)

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

      Waves.advance_provider_queue(battle, attempt.id)
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
        Receipts.payload_valid?(attempt, result)

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
      unless Receipts.bound?(attempt, result), do: Repo.rollback(:foreign_result)
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
        Receipts.payload_valid?(attempt, result)

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
      battle =
        if Waves.enabled?(battle.snapshot),
          do: Waves.clear_block(battle, attempt.task_id),
          else: battle

      battle |> advance(attempt, result) |> pause_reconciled()
    end
  end

  defp pause_reconciled(battle) do
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

  defp finish_stop(
         battle,
         attempt,
         %{"status" => "cancelled", "cleanup_verified" => true} = result
       ) do
    update(attempt, state: "cancelled", result: result)

    cond do
      Waves.enabled?(battle.snapshot) and running_attempt(battle.id) ->
        update(battle, state: "stopping")

      Waves.enabled?(battle.snapshot) and not safe_to_stop?(battle) ->
        battle = update(battle, state: "needs_attention", reason: "cleanup_uncertain")
        record(battle, "needs_attention", %{"reason" => "cleanup_uncertain"})
        battle

      true ->
        battle = update(battle, state: "stopped", reason: "user_stop")
        record(battle, "stopped", %{"attempt_id" => attempt.id})
        battle
    end
  end

  defp finish_stop(battle, attempt, %{"status" => "cancelled"} = result) do
    update(attempt, state: "interrupted", result: result)
    battle = needs_attention(battle, "cleanup_uncertain")

    if Waves.enabled?(battle.snapshot) and running_attempt(battle.id),
      do: update(battle, state: "stopping"),
      else: battle
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
      Waves.conflict?(attempt, result) ->
        context =
          Map.update(battle.context, "combination_conflicts", [attempt.id], &(&1 ++ [attempt.id]))

        battle = update(battle, context: context)

        record(battle, "combination_conflict", %{
          "attempt_id" => attempt.id,
          "task_id" => attempt.task_id
        })

        review_return(battle, attempt, %{
          "feedback" =>
            "A combination conflict prevents preserving both task results. Inspect the current reviewed head and reimplement this task in the fresh checkout, preserving all frozen criteria and the other task's work."
        })

      status in ~w(failed blocked) ->
        needs_attention(battle, result["reason"] || status)

      status == "changes_requested" ->
        review_return(battle, attempt, result)

      true ->
        advance(battle, attempt, result)
    end
  end

  defp advance(battle, %Attempt{stage: "admission"}, result) do
    task = hd(tasks(battle.id))

    battle =
      update(battle,
        context: result_context(result),
        current_task_id: task.task_id,
        stage: "prepare_worktree"
      )

    if Waves.enabled?(battle.snapshot),
      do: Waves.activate(battle, review_stage(battle, "final_checks")),
      else: battle
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
    next_stage =
      review_stage(
        battle,
        Stages.next(battle.snapshot, attempt.stage, attempt.request["task_context"])
      )

    if task = current_task(battle) do
      context =
        Stages.merge_context(battle.snapshot, attempt.stage, task.context, result_context(result))
        |> Waves.put_stage(battle, next_stage)

      context =
        case attempt.stage do
          "prepare_worktree" ->
            Map.drop(
              context,
              ~w(candidate_sha native_candidate checks read_stage_summaries speculator_plan writer_stage)
            )

          "combine" ->
            Map.drop(context, ~w(checks provider))

          _ ->
            context
        end

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
    if Snapshot.task_review_only?(battle.snapshot),
      do: Stages.next(battle.snapshot, stage),
      else: stage
  end

  defp review_stage(_, stage), do: stage

  defp review_return(battle, %Attempt{stage: stage}, result) when stage in ~w(secutor combine) do
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
        |> Waves.put_stage(
          battle,
          if(round >= battle.snapshot["limits"]["review_rounds"],
            do: stage,
            else: "prepare_worktree"
          )
        )
    )

    if round >= battle.snapshot["limits"]["review_rounds"],
      do: needs_attention(battle, "review_limit"),
      else: update(battle, stage: "prepare_worktree")
  end

  defp review_return(battle, _, _), do: needs_attention(battle, "final_review_changes_requested")

  defp projection(stage) when stage in ~w(prepare_worktree coordinator speculator), do: "specs"
  defp projection(stage) when stage in ~w(combine checks secutor integrate), do: "review"
  defp projection(_), do: "in_process"

  defp result_context(result), do: Map.drop(result, @envelope ++ ["status", "reason"])
  defp current_task(%Battle{current_task_id: nil}), do: nil

  defp current_task(battle),
    do: Repo.get_by!(Task, battle_id: battle.id, task_id: battle.current_task_id)

  defp running_attempt(id),
    do:
      Repo.one(
        from a in Attempt,
          where: a.battle_id == ^id and a.state == "running",
          order_by: a.inserted_at,
          limit: 1
      )

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

    context = Waves.failure_context(battle, reason)

    battle = update(battle, state: "needs_attention", reason: reason, context: context)

    battle =
      if Waves.enabled?(battle.snapshot) and reason != "late_result_rejected",
        do: Waves.block(battle, reason),
        else: battle

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
