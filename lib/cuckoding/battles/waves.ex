defmodule Cuckoding.Battles.Waves do
  @moduledoc "Two independent implementation lanes, followed by serialized review/integration."
  alias Cuckoding.Battles.{Attempt, Battle, ProviderClosure, Receipts, Task}
  alias Cuckoding.{Event, Repo}
  import Ecto.Query

  @pipeline ~w(prepare_worktree coordinator speculator implementor capture)
  @terminal ~w(completed skipped deferred)
  def policy, do: "parallel-waves-v1"
  def enabled?(snapshot), do: snapshot["parallelism"] == policy()
  def pipeline?(stage), do: stage in @pipeline

  def stage(task), do: task.context["lane_stage"]
  def active(tasks), do: Enum.filter(tasks, &(stage(&1) && &1.state not in @terminal))

  def view(%Battle{} = battle, %Attempt{task_id: nil}), do: battle

  def view(%Battle{} = battle, %Attempt{} = attempt),
    do: %{battle | current_task_id: attempt.task_id, stage: attempt.stage}

  def candidates(battle, tasks, running) do
    lanes = active(tasks)
    pipeline = Enum.filter(lanes, &pipeline?(stage(&1)))
    busy = Enum.map(running, & &1.task_id)

    eligible =
      cond do
        pipeline != [] -> Enum.reject(pipeline, &(&1.task_id in busy))
        running != [] -> []
        true -> Enum.take(lanes, 1)
      end

    Enum.map(eligible, fn task ->
      stage =
        if stage(task) in ~w(checks secutor integrate) and
             (task.context["native_candidate"]["base"] || task.context["preparation"]["head"]) !=
               battle.context["head"],
           do: "combine",
           else: stage(task)

      %{battle | current_task_id: task.task_id, stage: stage}
    end)
  end

  def backoff_origin(battle),
    do:
      if(enabled?(battle.snapshot) and battle.context["wave_failure_drain"] == true,
        do: "running",
        else: battle.state
      )

  def conflict?(attempt, result),
    do:
      enabled?(attempt.request["snapshot"]) and attempt.stage == "combine" and
        result["status"] == "failed" and result["reason"] == "candidate_conflict" and
        result["cleanup_verified"] == true

  def conflict_settled?(battle, attempt),
    do:
      enabled?(battle.snapshot) and attempt.id in (battle.context["combination_conflicts"] || []) and
        attempt.state == "failed" and conflict?(attempt, attempt.result)

  def control_attempt(battle, history),
    do:
      if(enabled?(battle.snapshot),
        do: Enum.find(Enum.reverse(history), &(&1.task_id == battle.current_task_id)),
        else: List.last(history)
      )

  def other_blocked?(battle, attempt),
    do:
      enabled?(battle.snapshot) and attempt.task_id != battle.current_task_id and
        Map.has_key?(battle.context["lane_blockers"] || %{}, attempt.task_id) and
        attempt.state == "failed" and attempt.result["cleanup_verified"] == true

  def failure_context(battle, reason) do
    if enabled?(battle.snapshot) and battle.state == "running" and
         reason != "late_result_rejected" and running?(battle.id),
       do: Map.put(battle.context, "wave_failure_drain", true),
       else: battle.context
  end

  def reject_receipt(battle, attempt, result) do
    transaction!()

    unless attempt.battle_id == battle.id and Receipts.bound?(attempt, result) and
             Receipts.rejected_payload_valid?(attempt, result),
           do: Repo.rollback(:invalid_result)

    state = if result["cleanup_verified"] == true, do: "cancelled", else: "interrupted"
    change(attempt, state: state, result: Map.put(result, "status", "cancelled"))

    event(battle, "wave_stage_rejected", %{
      "attempt_id" => attempt.id,
      "task_id" => attempt.task_id,
      "reported_status" => result["status"],
      "cleanup_verified" => result["cleanup_verified"] == true
    })

    battle
  end

  def interrupt(battle) do
    transaction!()

    running =
      Repo.all(
        from a in Attempt,
          where: a.battle_id == ^battle.id and a.state == "running",
          order_by: a.inserted_at
      )

    for attempt <- running,
        do: change(attempt, state: "interrupted", result: %{"status" => "interrupted"})

    providers = Enum.filter(running, &provider_inspection?(battle, &1))
    selected = List.first(providers) || List.first(running)

    battle =
      if selected,
        do: change(battle, current_task_id: selected.task_id, stage: selected.stage),
        else: battle

    {retain_provider_queue(battle, providers), selected}
  end

  defp provider_inspection?(battle, attempt),
    do:
      battle.state in ~w(running pausing stopping needs_attention) and not is_nil(attempt.role) and
        ProviderClosure.enabled?(battle.snapshot)

  defp retain_provider_queue(battle, []), do: battle

  defp retain_provider_queue(battle, [first | _] = providers) do
    context =
      battle.context
      |> Map.put("wave_provider_inspections", Enum.map(providers, & &1.id))
      |> Map.put("provider_closure_pending", first.id)

    change(battle, context: context)
  end

  def put_stage(context, battle, stage),
    do: if(enabled?(battle.snapshot), do: Map.put(context, "lane_stage", stage), else: context)

  # Called only by the durable owner inside its immediate write transaction.
  def activate(battle, final_stage) do
    transaction!()
    tasks = tasks(battle.id)
    remaining = Enum.reject(tasks, &(&1.state in @terminal))

    cond do
      active(tasks) != [] -> focus(battle, true)
      remaining == [] -> finish_tasks(battle, tasks, final_stage)
      true -> open_wave(battle, tasks)
    end
  end

  defp open_wave(battle, tasks) do
    completed = for task <- tasks, task.state == "completed", do: task.task_id

    ready =
      tasks
      |> Enum.filter(fn task ->
        task.state == "pending" and
          Enum.all?(task.snapshot["depends_on"] || [], &(&1 in completed))
      end)
      |> Enum.take(2)

    if ready == [], do: Repo.rollback(:invalid_dependencies)
    wave = (battle.context["wave"] || 0) + 1

    for task <- ready do
      change(task,
        state: "specs",
        context: Map.merge(task.context, %{"wave" => wave, "lane_stage" => "prepare_worktree"})
      )
    end

    battle = change(battle, context: Map.put(battle.context, "wave", wave))
    event(battle, "wave_started", %{"wave" => wave, "task_ids" => Enum.map(ready, & &1.task_id)})
    focus(battle, true)
  end

  defp finish_tasks(battle, tasks, final_stage) do
    if Enum.any?(tasks, &(&1.state == "completed")) do
      change(battle, current_task_id: nil, stage: final_stage)
    else
      battle = change(battle, state: "stopped", current_task_id: nil, reason: "all_tasks_skipped")
      event(battle, "stopped", %{"reason" => battle.reason})
      battle
    end
  end

  def focus(battle), do: focus(battle, false)

  defp focus(battle, accepted_transition?) do
    transaction!()
    tasks = tasks(battle.id)
    blockers = battle.context["lane_blockers"] || %{}

    selected = focused_task(battle, tasks, blockers, accepted_transition?)

    if selected do
      fields = [current_task_id: selected.task_id, stage: stage(selected)]

      fields =
        if blockers == %{}, do: fields, else: fields ++ [reason: blockers[selected.task_id]]

      change(battle, fields)
    else
      battle
    end
  end

  defp focused_task(battle, tasks, blockers, accepted_transition?) do
    case Map.fetch(battle.context, "provider_closure_pending") do
      {:ok, id} when is_binary(id) -> pending_provider_task(battle, tasks, id)
      {:ok, _} -> nil
      :error -> ordinary_focus(battle, tasks, blockers, accepted_transition?)
    end
  end

  defp pending_provider_task(battle, tasks, id) do
    case Repo.get_by(Attempt, id: id, battle_id: battle.id, state: "interrupted") do
      %Attempt{} = attempt ->
        Enum.find(tasks, &(&1.task_id == attempt.task_id and stage(&1) == attempt.stage))

      _ ->
        nil
    end
  end

  defp ordinary_focus(battle, tasks, blockers, accepted_transition?) do
    if not accepted_transition? and battle.state == "needs_attention" and blockers == %{},
      do: nil,
      else: Enum.find(tasks, &Map.has_key?(blockers, &1.task_id)) || List.first(active(tasks))
  end

  def block(battle, reason) do
    transaction!()

    context =
      if battle.current_task_id,
        do:
          Map.update(
            battle.context,
            "lane_blockers",
            %{battle.current_task_id => reason},
            fn old ->
              Map.put(old, battle.current_task_id, reason)
            end
          ),
        else: battle.context

    state = if running?(battle.id), do: "pausing", else: "needs_attention"
    battle |> change(state: state, context: context) |> focus()
  end

  def clear_block(battle, task_id), do: clear_blocks(battle, [task_id])

  def clear_blocks(battle, task_ids) do
    transaction!()
    blockers = Map.drop(battle.context["lane_blockers"] || %{}, task_ids)
    context = Map.put(battle.context, "lane_blockers", blockers)
    context = if blockers == %{}, do: Map.delete(context, "wave_failure_drain"), else: context
    state = if blockers == %{}, do: battle.state, else: "needs_attention"
    battle |> change(state: state, context: context) |> focus()
  end

  def advance_provider_queue(battle, completed_id) do
    if enabled?(battle.snapshot) and is_list(battle.context["wave_provider_inspections"]) do
      transaction!()

      unless List.first(battle.context["wave_provider_inspections"]) == completed_id,
        do: Repo.rollback(:invalid_recovery_queue)

      pending = List.delete(battle.context["wave_provider_inspections"], completed_id)
      context = Map.put(battle.context, "wave_provider_inspections", pending)

      next_provider_inspection(battle, pending, context)
    else
      battle
    end
  end

  defp next_provider_inspection(battle, [], context), do: change(battle, context: context)

  defp next_provider_inspection(battle, [id | _], context) do
    next =
      Repo.get_by(Attempt, id: id, battle_id: battle.id) || Repo.rollback(:invalid_recovery_queue)

    unless next.state == "interrupted" and not is_nil(next.role),
      do: Repo.rollback(:invalid_recovery_queue)

    change(battle,
      context: Map.put(context, "provider_closure_pending", id),
      current_task_id: next.task_id,
      stage: next.stage
    )
  end

  def blocked?(battle), do: map_size(battle.context["lane_blockers"] || %{}) > 0

  def running?(battle_id),
    do: Repo.exists?(from a in Attempt, where: a.battle_id == ^battle_id and a.state == "running")

  defp tasks(id), do: Repo.all(from t in Task, where: t.battle_id == ^id, order_by: t.position)
  defp change(record, fields), do: Repo.update!(Ecto.Changeset.change(record, fields))

  defp transaction! do
    unless Repo.in_transaction?(), do: raise("task waves require the battle transaction")
  end

  defp event(battle, kind, data) do
    Repo.insert!(%Event{
      kind: "battle." <> kind,
      data:
        Map.merge(
          %{
            "battle_id" => battle.id,
            "arena_id" => battle.arena_id,
            "tabula_id" => battle.tabula_id
          },
          data
        ),
      occurred_at: DateTime.utc_now()
    })
  end
end
