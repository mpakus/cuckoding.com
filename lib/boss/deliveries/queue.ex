defmodule Boss.Deliveries.Queue do
  @moduledoc "Durable explicit workflow requests; restart requires explicit resume."
  import Ecto.Query
  alias Boss.{Deliveries, Repo, Runs, Tasks}
  alias Boss.Deliveries.{Delivery, Request}
  alias Boss.Projects.Spec
  @pending ~w(queued paused)

  def enqueue(project, task, command, text, reviewer, server \\ Boss.Runs.Manager),
    do: GenServer.call(server, {:queue_enqueue, project, task, command, text, reviewer}, 10_000)

  def resume(project, id, server \\ Boss.Runs.Manager),
    do: GenServer.call(server, {:queue_resume, project, id}, 10_000)

  def list(project, task),
    do:
      Repo.all(
        from r in Request,
          where: r.project_id == ^project and r.task_id == ^task,
          order_by: [desc: r.inserted_at, desc: r.id],
          limit: 3
      )

  def pending?(task),
    do: Repo.exists?(from r in Request, where: r.task_id == ^task and r.status in ^@pending)

  @doc false
  def queued do
    Repo.all(
      from r in Request,
        where:
          r.status == "queued" and
            fragment("NOT EXISTS (SELECT 1 FROM autopilot_items a WHERE a.request_id=?)", r.id),
        order_by: [asc: r.inserted_at, asc: r.id],
        limit: 32
    )
  end

  @doc false
  def admit(project, task, command, text, reviewer) do
    with true <- valid_id?(project) and valid_id?(task) and reviewer in ["codex", "claude"],
         {:ok, _} <- Ecto.UUID.cast(command),
         {:ok, config, hash} <- Boss.Checks.Command.parse(text) do
      transaction(fn ->
        case Repo.get_by(Request, task_id: task, command_id: command) do
          %Request{
            project_id: ^project,
            check_config: ^config,
            config_hash: ^hash,
            reviewer: ^reviewer
          } = saved ->
            saved

          %Request{} ->
            Repo.rollback(:idempotency_conflict)

          nil ->
            if Repo.exists?(
                 from d in Delivery, where: d.task_id == ^task and d.command_id == ^command
               ),
               do: Repo.rollback(:idempotency_conflict)

            current =
              Repo.one(
                from t in Tasks.Task,
                  join: s in Spec,
                  on: s.id == t.spec_id,
                  where: t.id == ^task and s.project_id == ^project,
                  select: t
              ) || Repo.rollback(:not_found)

            if pending?(task), do: Repo.rollback(:task_queued)

            unless current.state in ~w(new failed cancelled blocked needs_input interrupted),
              do: Repo.rollback(:task_unavailable)

            if Repo.exists?(
                 from r in Runs.Run,
                   where:
                     r.task_id == ^task and
                       (r.status in ~w(preparing launching running stopping) or
                          r.cleanup == "unknown")
               ) or
                 Repo.exists?(
                   from d in Delivery,
                     where:
                       d.task_id == ^task and
                         (d.status in ~w(planning implementing testing reviewing integrating) or
                            d.cleanup == "unknown")
                 ),
               do: Repo.rollback(:busy)

            if Repo.aggregate(
                 from(r in Request,
                   where:
                     r.status in ^@pending and
                       fragment(
                         "NOT EXISTS (SELECT 1 FROM autopilot_items a WHERE a.request_id=?)",
                         r.id
                       )
                 ),
                 :count
               ) >= 32,
               do: Repo.rollback(:queue_full)

            Repo.insert!(%Request{
              id: Ecto.UUID.generate(),
              project_id: project,
              task_id: task,
              spec_revision_id: current.spec_revision_id,
              admitted_version: current.state_version,
              command_id: command,
              check_config: config,
              config_hash: hash,
              reviewer: reviewer
            })
        end
      end)
      |> broadcast_result()
    else
      _ -> {:error, :invalid_command}
    end
  end

  def cancel(project, id), do: change(project, id, :cancel)

  @doc false
  def resume_saved(project, id), do: change(project, id, :resume)

  defp change(project, id, action) do
    with true <- valid_id?(project), {:ok, _} <- Ecto.UUID.cast(id) do
      transaction(fn ->
        request = Repo.get_by(Request, project_id: project, id: id) || Repo.rollback(:not_found)

        if Boss.Deliveries.Autopilot.owns_request?(id), do: Repo.rollback(:autopilot_owned)

        case {action, request.status} do
          {:cancel, status} when status in @pending ->
            save!(request, status: "cancelled", reason: "Queued workflow cancelled.")

          {:cancel, "cancelled"} ->
            request

          {:cancel, "started"} ->
            Repo.rollback(:already_started)

          {:resume, "paused"} ->
            save!(request, status: "queued", reason: nil)

          {:resume, status} when status in ["queued", "started"] ->
            request

          _ ->
            Repo.rollback(:request_finished)
        end
      end)
      |> broadcast_result()
    else
      _ -> {:error, :invalid_command}
    end
  end

  @doc false
  def pause do
    transaction(fn ->
      Repo.all(
        from r in Request,
          where:
            r.status == "queued" and
              fragment("NOT EXISTS (SELECT 1 FROM autopilot_items a WHERE a.request_id=?)", r.id),
          limit: 32
      )
      |> Enum.map(
        &save!(&1,
          status: "paused",
          reason: "BOSS restarted. Resume this saved request to authorize its launch."
        )
      )
    end)
  end

  @doc false
  def claim(id), do: Deliveries.claim(id)

  @doc false
  def save!(request, attrs), do: request |> Ecto.Changeset.change(attrs) |> Repo.update!()

  defp broadcast_result({:ok, request} = result) do
    unless Repo.in_transaction?(), do: Runs.broadcast(request)
    result
  end

  defp broadcast_result(result), do: result

  defp valid_id?(n), do: is_integer(n) and n > 0 and n <= 9_223_372_036_854_775_807

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
