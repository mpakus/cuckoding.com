defmodule Cuckoding.Battles do
  @moduledoc "Durable bounded Arena authority and sequential stage claims; workers own external effects."
  import Ecto.Query, except: [update: 2, update: 3]
  alias Cuckoding.Battles.{Attempt, Battle, Snapshot, Task}
  alias Cuckoding.{Event, Foundation, Repo, TaskTurn}

  @active ~w(running stopping needs_attention)
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
        where: b.tabula_id == ^tabula_id,
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

    record(battle, "started", %{"task_count" => length(snapshot["tasks"])})
    battle
  end

  def claim_next(id, now \\ DateTime.utc_now()) do
    transaction(fn ->
      battle = get(id) || Repo.rollback(:not_found)

      cond do
        battle.state != "running" -> Repo.rollback(:not_running)
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
          else: Snapshot.digest(Enum.map(battle.snapshot["tasks"], & &1["criteria_sha256"]))
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

  defp finish_claim(id, token, result, now) do
    attempt = if(valid_id?(id), do: Repo.get(Attempt, id))

    if is_nil(attempt) or attempt.claim_token != token or attempt.state != "running",
      do: Repo.rollback(:stale_attempt)

    if not bound?(attempt, result), do: Repo.rollback(:foreign_result)
    finish_current(get(attempt.battle_id), attempt, result, now)
  end

  defp finish_current(battle, attempt, result, now) do
    cond do
      battle.state == "stopping" ->
        finish_stop(battle, attempt, result)

      battle.state != "running" ->
        Repo.rollback(:not_running)

      expired?(attempt.deadline_at, now) or expired?(battle.deadline_at, now) ->
        update(attempt, state: "interrupted", result: %{"status" => "late_result_rejected"})
        attention(battle, "late_result_rejected")

      not valid_result?(attempt, result) ->
        Repo.rollback(:invalid_result)

      true ->
        complete_attempt(battle, attempt, result)
    end
  end

  def stop(id) do
    transaction(fn -> stop_current(get(id) || Repo.rollback(:not_found)) end)
  end

  defp stop_current(battle) do
    cond do
      battle.state in ~w(stopped completed stopping) ->
        battle

      battle.state == "needs_attention" and not safe_to_stop?(battle) ->
        Repo.rollback(:cleanup_required)

      true ->
        state = if(running_attempt(battle.id), do: "stopping", else: "stopped")
        battle = update(battle, state: state, reason: "user_stop")
        record(battle, "stop_requested")
        battle
    end
  end

  defp safe_to_stop?(battle) do
    Enum.all?(attempts(battle.id), fn attempt ->
      attempt.state == "completed" or
        (attempt.state in ~w(failed cancelled) and attempt.result["cleanup_verified"] == true)
    end)
  end

  def active_attempt?(id, token, now \\ DateTime.utc_now()) do
    case Repo.get(Attempt, id) do
      %Attempt{state: "running", claim_token: ^token} = attempt ->
        battle = get(attempt.battle_id)

        battle.state == "running" and not expired?(attempt.deadline_at, now) and
          not expired?(battle.deadline_at, now)

      _ ->
        false
    end
  end

  # The startup owner calls this once before dispatch. Uncertain effects are retained, never replayed.
  def recover do
    transaction(fn ->
      Enum.map(
        Repo.all(from b in Battle, where: b.state in ~w(running stopping)),
        &recover_battle/1
      )
    end)
  end

  defp recover_battle(battle) do
    if attempt = running_attempt(battle.id),
      do: update(attempt, state: "interrupted", result: %{"status" => "interrupted"})

    needs_attention(battle, "restart_requires_inspection")
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
    next = Enum.find(tasks(battle.id), &(&1.state != "completed"))
    context = Map.merge(battle.context, Map.take(result, ~w(head native_battle)))

    update(battle,
      context: context,
      current_task_id: if(next, do: next.task_id),
      stage: if(next, do: "prepare_worktree", else: "final_checks")
    )
  end

  defp advance(battle, %Attempt{stage: "summary"}, result) do
    battle =
      update(battle,
        state: "completed",
        context: Map.merge(battle.context, result_context(result))
      )

    record(battle, "completed")
    battle
  end

  defp advance(battle, attempt, result) do
    if task = current_task(battle) do
      context = Map.merge(task.context, result_context(result))

      context =
        if(attempt.stage == "prepare_worktree",
          do: Map.drop(context, ~w(candidate_sha native_candidate checks)),
          else: context
        )

      state = projection(@next[attempt.stage])
      update(task, state: state, context: context)
    end

    context =
      if(is_nil(attempt.task_id),
        do: Map.merge(battle.context, result_context(result)),
        else: battle.context
      )

    update(battle, stage: Map.fetch!(@next, attempt.stage), context: context)
  end

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

  defp review_verdict?(attempt, %{"status" => "completed"}) do
    context =
      if(attempt.task_id, do: attempt.request["task_context"], else: attempt.request["context"])

    checks?(attempt, context["checks"])
  end

  defp review_verdict?(_, _), do: true

  defp provider_identity?(attempt, provider) do
    role = attempt.request["role"]

    expected = %{
      "request_id" => attempt.id,
      "requested_model" => role["model"],
      "observed_model" => role["model"],
      "effort" => role["effort"],
      "access" => if(attempt.stage == "implementor", do: "write", else: "read")
    }

    Map.take(provider, Map.keys(expected)) == expected
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

  defp bound?(attempt, result) when is_map(result) do
    Map.keys(result) -- @result_fields == [] and
      Map.take(result, @envelope) == Map.take(attempt.request, @envelope) and
      match?({:ok, _}, Jason.encode(result)) and byte_size(Jason.encode!(result)) <= 131_072
  end

  defp bound?(_, _), do: false
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
