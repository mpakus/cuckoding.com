defmodule Boss.Tasks do
  import Ecto.Query
  alias Boss.Repo
  alias Boss.Projects.{Spec, SpecRevision}
  alias Boss.Tasks.{Event, Task, Transition}

  def get_task!(id), do: Repo.get!(Task, id)

  def list_events(task_id),
    do: Repo.all(from e in Event, where: e.task_id == ^task_id, order_by: e.version)

  @doc """
  Reads project-scoped task details in one snapshot, defaulting to the pinned source.
  Revision metadata is newest first; events are the latest 50, newest first.
  Source text is returned unchanged and must be displayed as plain text.
  """
  def get_details(project_id, task_id, revision_number \\ nil) do
    if valid_id?(project_id) and valid_id?(task_id) and
         (is_nil(revision_number) or valid_id?(revision_number)) do
      with_repo_transaction(
        fn -> read_details(project_id, task_id, revision_number) end,
        :deferred
      )
    else
      {:error, :not_found}
    end
  end

  @doc """
  Applies a named action and records its receipt in one transaction.

  Commands have atom keys: command_id (nonblank UTF-8, at most 128 bytes),
  expected_version (nonnegative integer), action (string), and optional reason
  (nonblank UTF-8, at most 1000 bytes). Unknown keys, including evidence, are
  rejected. Text is preserved exactly; an omitted reason is equivalent to nil.

  Returns {:ok, event}, including on an identical replay. The event describes
  that original transition, not the current task; read get_task!/1 for that.
  IDs are scoped to a task. Reusing an ID with different input conflicts.
  On :storage_error, retry the same command ID to reconcile an unknown outcome.
  Generic workflow edges remain closed. The producer-owned delivery_progress
  action accepts a delivery_id and derives progress from persisted evidence.
  Inside a caller's transaction, success is provisional until its outer commit;
  the outer transaction also determines the SQLite transaction mode.
  """
  def transition(task_id, command) do
    if valid_command?(task_id, command) do
      execute(task_id, Map.put_new(command, :reason, nil))
    else
      {:error, :invalid_command}
    end
  end

  defp execute(task_id, command) do
    with_repo_transaction(
      fn ->
        case Repo.get_by(Event, task_id: task_id, command_id: command.command_id) do
          nil -> apply_transition(task_id, command)
          event -> replay(event, command)
        end
      end,
      :immediate
    )
  end

  defp with_repo_transaction(operation, mode) do
    selector = Repo.get_dynamic_repo()
    repo = if is_atom(selector), do: Process.whereis(selector), else: selector

    if is_pid(repo) and Process.alive?(repo) do
      # Every query must use the same pool, even if its registered name restarts.
      Repo.put_dynamic_repo(repo)

      try do
        Repo.transaction(operation, mode: mode)
      rescue
        _error in [Exqlite.Error, Ecto.ConstraintError, DBConnection.ConnectionError] ->
          {:error, :storage_error}

        error in [ArgumentError, RuntimeError] ->
          if Process.alive?(repo),
            do: reraise(error, __STACKTRACE__),
            else: {:error, :storage_error}
      catch
        :exit, reason ->
          if Process.alive?(repo),
            do: :erlang.raise(:exit, reason, __STACKTRACE__),
            else: {:error, :storage_error}
      after
        Repo.put_dynamic_repo(selector)
      end
    else
      {:error, :storage_error}
    end
  end

  defp read_details(project_id, task_id, revision_number) do
    {task, spec} =
      Repo.one(
        from t in Task,
          join: s in Spec,
          on: t.spec_id == s.id,
          where: t.id == ^task_id and s.project_id == ^project_id,
          select: {t, s}
      ) || Repo.rollback(:not_found)

    pinned =
      Repo.get_by(SpecRevision, id: task.spec_revision_id, spec_id: spec.id) ||
        Repo.rollback(:not_found)

    latest =
      Repo.one(
        from r in SpecRevision, where: r.spec_id == ^spec.id, order_by: [desc: r.number], limit: 1
      ) || Repo.rollback(:not_found)

    selected =
      cond do
        is_nil(revision_number) or revision_number == pinned.number -> pinned
        revision_number == latest.number -> latest
        true -> Repo.get_by(SpecRevision, spec_id: spec.id, number: revision_number)
      end || Repo.rollback(:not_found)

    %{
      task: task,
      spec: spec,
      pinned_revision: pinned,
      latest_revision: latest,
      selected_revision: selected,
      revisions:
        Repo.all(
          from r in SpecRevision,
            where: r.spec_id == ^spec.id,
            order_by: [desc: r.number],
            select: %{number: r.number, inserted_at: r.inserted_at}
        ),
      events:
        Repo.all(
          from e in Event,
            where: e.task_id == ^task.id,
            order_by: [desc: e.version],
            limit: 50
        )
    }
  end

  defp valid_id?(id), do: is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807

  defp apply_transition(task_id, command) do
    task = Repo.get(Task, task_id) || Repo.rollback(:not_found)
    if task.state_version != command.expected_version, do: Repo.rollback(:stale_state)

    changes =
      case if(command.action == "delivery_progress",
             do: Boss.Deliveries.transition_changes(task, command),
             else: Transition.apply(task, command.action, command.reason)
           ) do
        {:ok, changes} -> changes
        {:error, reason} -> Repo.rollback(reason)
      end

    version = task.state_version + 1
    updates = Map.to_list(changes) ++ [state_version: version, updated_at: DateTime.utc_now()]

    query =
      from t in Task,
        where:
          t.id == ^task.id and t.state_version == ^task.state_version and t.state == ^task.state

    case Repo.update_all(query, set: updates) do
      {1, _} -> :ok
      {0, _} -> Repo.rollback(:stale_state)
    end

    case Repo.insert(%Event{
           task_id: task.id,
           spec_revision_id: task.spec_revision_id,
           command_id: command.command_id,
           version: version,
           action: command.action,
           from_state: task.state,
           to_state: changes.state,
           reason: command.reason
         }) do
      {:ok, event} -> event
      {:error, _} -> Repo.rollback(:storage_error)
    end
  end

  defp replay(event, command) do
    if event.version == command.expected_version + 1 and event.action == command.action and
         event.reason == command.reason do
      event
    else
      Repo.rollback(:idempotency_conflict)
    end
  end

  defp valid_command?(
         task_id,
         %{command_id: id, expected_version: version, action: action} = command
       ) do
    is_integer(task_id) and task_id > 0 and task_id <= 9_223_372_036_854_775_807 and
      is_integer(version) and version >= 0 and version < 9_223_372_036_854_775_807 and
      Enum.all?(
        Map.keys(command),
        &(&1 in [:command_id, :expected_version, :action, :reason, :delivery_id])
      ) and
      ((action == "delivery_progress" and match?({:ok, _}, Ecto.UUID.cast(command[:delivery_id])) and
          is_binary(id) and String.starts_with?(id, command.delivery_id <> ":") and
          is_nil(command[:reason])) or
         (action != "delivery_progress" and not Map.has_key?(command, :delivery_id))) and
      valid_text?(id, 128) and valid_text?(action, 64) and
      (is_nil(command[:reason]) or valid_text?(command[:reason], 1000))
  end

  defp valid_command?(_, _), do: false

  defp valid_text?(value, limit),
    do:
      is_binary(value) and byte_size(value) <= limit and String.valid?(value) and
        String.trim(value) != "" and not String.contains?(value, <<0>>)
end
