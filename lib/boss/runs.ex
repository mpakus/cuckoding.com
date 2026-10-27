defmodule Boss.Runs do
  @moduledoc "Explicit manual attempts, independent of task approval and Done."
  import Ecto.Query
  alias Boss.{Repo, Tasks}
  alias Boss.Projects.{Project, Spec, SpecRevision}
  alias Boss.Runs.Run
  @active ~w(preparing launching running stopping)

  def active?(%Run{status: status}), do: status in @active
  def subscribe(project_id), do: Phoenix.PubSub.subscribe(Boss.PubSub, "runs:#{project_id}")

  def broadcast(run),
    do:
      Phoenix.PubSub.broadcast(
        Boss.PubSub,
        "runs:#{run.project_id}",
        {:run_changed, run.project_id}
      )

  def start(project_id, task_id, command_id, server \\ Boss.Runs.Manager),
    do: GenServer.call(server, {:start, project_id, task_id, command_id}, 10_000)

  def start_check(project_id, parent_id, command_id, text, server \\ Boss.Runs.Manager),
    do: GenServer.call(server, {:check, project_id, parent_id, command_id, text}, 10_000)

  def start_review(project_id, check_id, command_id, server \\ Boss.Runs.Manager),
    do: GenServer.call(server, {:review, project_id, check_id, command_id}, 10_000)

  # Stop bypasses the manager's DB work: only the live, project-scoped owner is signalled.
  def stop(project_id, run_id, registry \\ Boss.Runs.Active) do
    case :ets.lookup(registry, run_id) do
      [{^run_id, ^project_id, pid}] ->
        send(pid, :stop)
        :ok

      _ ->
        {:error, :not_running}
    end
  rescue
    ArgumentError -> {:error, :not_running}
  end

  def list(project_id, task_id) do
    recent =
      Repo.all(
        from r in Run,
          where: r.project_id == ^project_id and r.task_id == ^task_id,
          order_by: [desc: r.inserted_at, desc: r.id],
          limit: 10
      )

    # A review's source chain is review -> check -> Codex, at most two levels.
    Enum.reduce(1..2, recent, fn _, runs ->
      missing = Enum.uniq(Enum.map(runs, & &1.parent_run_id)) -- Enum.map(runs, & &1.id)

      parents =
        Repo.all(
          from r in Run,
            where:
              r.project_id == ^project_id and r.task_id == ^task_id and
                r.id in ^Enum.reject(missing, &is_nil/1),
            order_by: [desc: r.inserted_at, desc: r.id]
        )

      runs ++ parents
    end)
  end

  def get(project_id, id), do: Repo.get_by(Run, project_id: project_id, id: id)

  @doc false
  def replay(project_id, task_id, command_id) do
    if is_integer(project_id) and is_integer(task_id) and is_binary(command_id) and
         match?({:ok, _}, Ecto.UUID.cast(command_id)) do
      transaction(fn ->
        case Repo.get_by(Run, project_id: project_id, task_id: task_id, command_id: command_id) do
          %Run{adapter: "codex"} = run -> run
          %Run{} -> Repo.rollback(:idempotency_conflict)
          nil -> Repo.rollback(:busy)
        end
      end)
    else
      {:error, :invalid_command}
    end
  end

  @doc false
  def admit(project_id, task_id, command_id) do
    if is_integer(project_id) and is_integer(task_id) and is_binary(command_id) and
         match?({:ok, _}, Ecto.UUID.cast(command_id)) do
      transaction(fn ->
        case Repo.get_by(Run, task_id: task_id, command_id: command_id) do
          %Run{project_id: ^project_id, adapter: "codex"} = run ->
            {:existing, run}

          %Run{project_id: ^project_id} ->
            Repo.rollback(:idempotency_conflict)

          %Run{} ->
            Repo.rollback(:not_found)

          nil ->
            {task, _spec} =
              Repo.one(
                from t in Tasks.Task,
                  join: s in Spec,
                  on: s.id == t.spec_id,
                  where: t.id == ^task_id and s.project_id == ^project_id,
                  select: {t, s}
              ) || Repo.rollback(:not_found)

            unless task.state in ~w(new ready failed interrupted cancelled blocked needs_input),
              do: Repo.rollback(:task_unavailable)

            if Boss.Deliveries.Queue.pending?(task_id), do: Repo.rollback(:task_queued)

            if Boss.Deliveries.busy?() or
                 Repo.exists?(
                   from r in Run, where: r.status in ^@active or r.cleanup == "unknown"
                 ),
               do: Repo.rollback(:busy)

            case Tasks.Dependencies.check(project_id, task_id) do
              :ok -> :ok
              {:error, reason} -> Repo.rollback(reason)
            end

            run =
              Repo.insert!(%Run{
                id: Ecto.UUID.generate(),
                project_id: project_id,
                task_id: task_id,
                spec_revision_id: task.spec_revision_id,
                admitted_version: task.state_version,
                command_id: command_id
              })

            {:new, run}
        end
      end)
    else
      {:error, :invalid_command}
    end
  end

  @doc false
  def admit_check(project_id, parent_id, command_id, text, replay_only \\ false) do
    with true <-
           is_integer(project_id) and project_id > 0 and project_id <= 9_223_372_036_854_775_807,
         {:ok, _} <- Ecto.UUID.cast(parent_id),
         {:ok, _} <- Ecto.UUID.cast(command_id),
         {:ok, config, hash} <- Boss.Checks.Command.parse(text) do
      transaction(fn ->
        parent =
          Repo.get_by(Run, project_id: project_id, id: parent_id) || Repo.rollback(:not_found)

        case Repo.get_by(Run, task_id: parent.task_id, command_id: command_id) do
          %Run{
            adapter: "check",
            parent_run_id: ^parent_id,
            config_hash: ^hash,
            check_config: ^config
          } = saved ->
            {:existing, saved}

          %Run{} ->
            Repo.rollback(:idempotency_conflict)

          nil ->
            unless parent.adapter == "codex" and parent.status == "finished" and
                     parent.cleanup == "group_empty" and map_size(parent.workspace) > 0,
                   do: Repo.rollback(:source_unavailable)

            if Boss.Deliveries.Queue.pending?(parent.task_id), do: Repo.rollback(:task_queued)

            if replay_only or Boss.Deliveries.busy?() or
                 Repo.exists?(
                   from r in Run, where: r.status in ^@active or r.cleanup == "unknown"
                 ),
               do: Repo.rollback(:busy)

            task = Repo.get!(Tasks.Task, parent.task_id)

            unless task.state in ~w(new ready failed interrupted cancelled blocked needs_input),
              do: Repo.rollback(:task_unavailable)

            saved =
              Repo.insert!(%Run{
                id: Ecto.UUID.generate(),
                project_id: project_id,
                task_id: parent.task_id,
                spec_revision_id: parent.spec_revision_id,
                admitted_version: task.state_version,
                adapter: "check",
                parent_run_id: parent.id,
                command_id: command_id,
                check_config: config,
                config_hash: hash
              })

            {:new, saved}
        end
      end)
    else
      _ -> {:error, :invalid_command}
    end
  end

  @doc false
  def admit_review(project_id, check_id, command_id, replay_only \\ false) do
    with true <-
           is_integer(project_id) and project_id > 0 and project_id <= 9_223_372_036_854_775_807,
         {:ok, _} <- Ecto.UUID.cast(check_id),
         {:ok, _} <- Ecto.UUID.cast(command_id) do
      transaction(fn ->
        parent =
          Repo.get_by(Run, project_id: project_id, id: check_id) || Repo.rollback(:not_found)

        case Repo.get_by(Run, task_id: parent.task_id, command_id: command_id) do
          %Run{adapter: "review", parent_run_id: ^check_id} = saved ->
            {:existing, saved}

          %Run{} ->
            Repo.rollback(:idempotency_conflict)

          nil ->
            unless parent.adapter == "check" and parent.status == "finished" and
                     parent.cleanup == "group_empty" and is_binary(parent.candidate_commit) and
                     map_size(parent.workspace) > 0,
                   do: Repo.rollback(:source_unavailable)

            if Boss.Deliveries.Queue.pending?(parent.task_id), do: Repo.rollback(:task_queued)

            if replay_only or Boss.Deliveries.busy?() or
                 Repo.exists?(
                   from r in Run, where: r.status in ^@active or r.cleanup == "unknown"
                 ),
               do: Repo.rollback(:busy)

            task = Repo.get!(Tasks.Task, parent.task_id)

            unless task.state in ~w(new ready failed interrupted cancelled blocked needs_input),
              do: Repo.rollback(:task_unavailable)

            saved =
              Repo.insert!(%Run{
                id: Ecto.UUID.generate(),
                project_id: project_id,
                task_id: parent.task_id,
                spec_revision_id: parent.spec_revision_id,
                admitted_version: task.state_version,
                adapter: "review",
                parent_run_id: parent.id,
                command_id: command_id,
                check_config: parent.check_config,
                config_hash: parent.config_hash,
                candidate_commit: parent.candidate_commit,
                workspace: parent.workspace
              })

            {:new, saved}
        end
      end)
    else
      _ -> {:error, :invalid_command}
    end
  end

  @doc false
  def inputs(run),
    do: {Repo.get!(Project, run.project_id), Repo.get!(SpecRevision, run.spec_revision_id)}

  @doc false
  def update(id, attrs) do
    transaction(fn ->
      run = Repo.get(Run, id) || Repo.rollback(:not_found)
      unless active?(run), do: Repo.rollback(:already_finished)
      Repo.update!(Ecto.Changeset.change(run, attrs))
    end)
  end

  @doc false
  def reconcile do
    transaction(fn ->
      Repo.update_all(from(r in Run, where: r.status in ^@active),
        set: [
          status: "interrupted",
          cleanup: "unknown",
          reason:
            "Backend stopped before a final receipt. Workspace retained; no automatic restart.",
          finished_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        ]
      )
    end)
  end

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
