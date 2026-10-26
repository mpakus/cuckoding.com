defmodule Boss.Tasks do
  import Ecto.Query
  alias Boss.Repo
  alias Boss.Tasks.{Event, Task, Transition}

  def get_task!(id), do: Repo.get!(Task, id)

  def list_events(task_id),
    do: Repo.all(from e in Event, where: e.task_id == ^task_id, order_by: e.version)

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
  Execution and evidence-producing transitions remain unavailable.
  """
  def transition(task_id, command) do
    if valid_command?(task_id, command) do
      command = Map.put_new(command, :reason, nil)

      Repo.transaction(
        fn ->
          case Repo.get_by(Event, task_id: task_id, command_id: command.command_id) do
            nil -> apply_transition(task_id, command)
            event -> replay(event, command)
          end
        end,
        mode: :immediate
      )
    else
      {:error, :invalid_command}
    end
  rescue
    _error in [Exqlite.Error, Ecto.ConstraintError, DBConnection.ConnectionError] ->
      {:error, :storage_error}
  end

  defp apply_transition(task_id, command) do
    task = Repo.get(Task, task_id) || Repo.rollback(:not_found)
    if task.state_version != command.expected_version, do: Repo.rollback(:stale_state)

    changes =
      case Transition.apply(task, command.action, command.reason) do
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
      Enum.all?(Map.keys(command), &(&1 in [:command_id, :expected_version, :action, :reason])) and
      valid_text?(id, 128) and valid_text?(action, 64) and
      (is_nil(command[:reason]) or valid_text?(command[:reason], 1000))
  end

  defp valid_command?(_, _), do: false

  defp valid_text?(value, limit),
    do:
      is_binary(value) and byte_size(value) <= limit and String.valid?(value) and
        String.trim(value) != "" and not String.contains?(value, <<0>>)
end
