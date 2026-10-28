defmodule Boss.Deliveries.Autopilot do
  @moduledoc "Explicit frozen task selection, advanced through existing delivery evidence one task at a time."
  import Ecto.Query
  alias Boss.{Deliveries, Repo, Runs, Tasks}
  alias Boss.Deliveries.{AutopilotBatch, AutopilotItem, Delivery, Queue, Request}

  def start(project, command, tasks, text, reviewer, server \\ Boss.Runs.Manager),
    do:
      GenServer.call(server, {:autopilot_start, project, command, tasks, text, reviewer}, 10_000)

  def resume(project, id, version, server \\ Boss.Runs.Manager),
    do: GenServer.call(server, {:autopilot_resume, project, id, version}, 10_000)

  def pause(project, id, version), do: change(project, id, :pause, version)

  def cancel(project, id, version, registry \\ Boss.Runs.Active) do
    # The alias is registered before releasing the worker; Stop never waits for storage.
    Runs.stop(project, {:autopilot, id}, registry)
    result = change(project, id, :cancel, version)
    Runs.stop(project, {:autopilot, id}, registry)
    result
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

  def running?, do: Repo.exists?(from b in AutopilotBatch, where: b.status == "running")

  def owns_request?(id), do: Repo.get(AutopilotItem, id) != nil

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
          not Enum.any?(rows(batch.id), fn {_, r, d, _} ->
            r.status == "started" and d.status != "done"
          end)

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
  def admit(project, command, tasks, text, reviewer, owned \\ false) do
    with true <- is_integer(project) and project > 0 and reviewer in ["codex", "claude"],
         {:ok, _} <- Ecto.UUID.cast(command),
         true <-
           is_list(tasks) and length(tasks) in 1..256 and
             Enum.all?(tasks, &(is_integer(&1) and &1 > 0)) and Enum.uniq(tasks) == tasks,
         {:ok, config, hash} <- Boss.Checks.Command.parse(text) do
      transaction(fn ->
        case Repo.get_by(AutopilotBatch, project_id: project, command_id: command) do
          %{task_ids: ^tasks, check_config: ^config, config_hash: ^hash, reviewer: ^reviewer} =
              batch ->
            view(batch)

          %AutopilotBatch{} ->
            Repo.rollback(:idempotency_conflict)

          nil ->
            backlog =
              Repo.all(
                from t in Tasks.Task,
                  join: s in Boss.Projects.Spec,
                  on: s.id == t.spec_id,
                  where: s.project_id == ^project and not s.missing and t.state == "new",
                  select: t.id,
                  limit: 257
              )

            if length(backlog) > 256, do: Repo.rollback(:backlog_too_large)
            if Enum.sort(backlog) != Enum.sort(tasks), do: Repo.rollback(:backlog_changed)

            if owned or Deliveries.busy?() or
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
                reviewer: reviewer
              })

            Enum.with_index(tasks)
            |> Enum.each(fn {task, position} ->
              case Queue.admit(project, task, Ecto.UUID.generate(), text, reviewer) do
                {:ok, request} ->
                  Repo.insert!(%AutopilotItem{
                    request_id: request.id,
                    autopilot_id: batch.id,
                    position: position,
                    integration_command_id: Ecto.UUID.generate()
                  })

                {:error, reason} ->
                  Repo.rollback(reason)
              end
            end)

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

    if batch &&
         not Enum.any?(rows(batch.id), fn {_, r, d, _} ->
           r.status == "started" and d.status != "done"
         end) do
      project = Repo.get!(Boss.Projects.Project, batch.project_id)

      result =
        with {:ok, workspace} <- Boss.Agents.Workspace.plan(project, batch.id),
             do: Boss.Deliveries.Integration.preflight(project, batch.id, workspace.base_commit)

      {batch.id, result}
    else
      nil
    end
  end

  defp advance_batch(batch, preflight, cursor) do
    unless complete?(batch), do: Repo.rollback(:incomplete_autopilot)
    entries = rows(batch.id)
    unfinished = Enum.reject(entries, fn {_, _, d, _} -> d && d.status == "done" end)

    case unfinished do
      [] ->
        {:changed, view(save(batch, "completed", nil))}

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
            if Deliveries.active?(delivery),
              do: :waiting,
              else:
                block(
                  batch,
                  "Task stopped: " <>
                    (delivery.reason || delivery.status) <>
                    " Autopilot did not start another task."
                )

          nil ->
            start_next(batch, unfinished, preflight, cursor)
        end
    end
  end

  defp start_next(batch, entries, preflight, cursor) do
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
            {id, offset} when id == batch.id and is_integer(offset) -> offset
            _ -> 0
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
            {:waiting, {batch.id, count}}

          {:scanned, _} ->
            block(
              batch,
              "No selected task is ready. Resolve missing, unfinished or cyclic prerequisites, then start a fresh selection."
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
    items =
      for {item, request, delivery, title} <- rows(batch.id),
          do: %{
            position: item.position,
            task_id: request.task_id,
            title: title,
            request_id: request.id,
            request_status: request.status,
            delivery_id: request.delivery_id,
            delivery_status: if(delivery, do: delivery.status),
            spec_revision_id: request.spec_revision_id
          }

    batch |> Map.from_struct() |> Map.drop([:__meta__]) |> Map.put(:items, items)
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

  defp broadcast({:ok, %{project_id: _} = batch} = result) do
    unless Repo.in_transaction?(), do: Runs.broadcast(batch)
    result
  end

  defp broadcast({:ok, {:changed, batch}} = result) do
    Runs.broadcast(batch)
    result
  end

  defp broadcast(result), do: result

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
end
