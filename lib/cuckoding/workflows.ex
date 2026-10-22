defmodule Cuckoding.Workflows do
  @moduledoc "Immutable board workflow revisions; labels never grant execution authority."
  import Ecto.Query
  alias Cuckoding.{Battles, Command, Foundation, Repo, Tabula, TeamAssignments, WorkflowRevision}

  @columns [
    %{"key" => "specs", "name" => "Specs", "role" => "speculator"},
    %{"key" => "todo", "name" => "ToDo", "role" => "summa_rudis"},
    %{"key" => "in_process", "name" => "In Process", "role" => "implementor"},
    %{"key" => "review", "name" => "Review", "role" => "secutor"},
    %{"key" => "completed", "name" => "Completed", "role" => nil}
  ]

  def default_definition, do: %{"version" => 1, "execution" => "disabled", "columns" => @columns}
  def labels(definition), do: Map.new(definition["columns"], &{&1["key"], &1["name"]})
  def column_name(%Tabula{} = board, key), do: labels(board.definition)[key]

  def current(%Tabula{} = board) do
    Repo.one(
      from r in WorkflowRevision,
        where: r.tabula_id == ^board.id,
        order_by: [desc: r.revision],
        limit: 1
    ) ||
      %WorkflowRevision{
        tabula_id: board.id,
        revision: 0,
        definition: board.definition,
        inserted_at: board.inserted_at
      }
  end

  def project(%Tabula{} = board) do
    revision = current(board)
    %{board | definition: revision.definition, workflow_revision: revision.revision}
  end

  def history(tabula_id),
    do:
      Repo.all(
        from r in WorkflowRevision,
          where: r.tabula_id == ^tabula_id,
          order_by: [desc: r.revision],
          limit: 5
      )

  def blocker(board) do
    cond do
      TeamAssignments.busy?(board) -> "planning_active"
      Battles.locked?(board.id) -> "battle_active"
      true -> nil
    end
  end

  def save_labels(key, arena_id, tabula_id, expected, names) do
    with {:ok, key} <- Ecto.UUID.cast(key),
         {:ok, arena_id} <- Ecto.UUID.cast(arena_id),
         {:ok, tabula_id} <- Ecto.UUID.cast(tabula_id),
         true <- is_integer(expected) and expected >= 0 and valid_names?(names) do
      columns = Enum.map(@columns, &Map.put(&1, "name", String.trim(names[&1["key"]])))

      payload = %{
        "arena_id" => arena_id,
        "tabula_id" => tabula_id,
        "definition" => %{"version" => 2, "execution" => "arena-loop-v2", "columns" => columns}
      }

      result = Repo.transaction(fn -> command(key, expected, payload) end, mode: :immediate)
      if match?({:ok, _}, result), do: Foundation.broadcast()

      case result do
        {:ok, %Command{state: "completed"}} ->
          {:ok, Repo.get_by!(WorkflowRevision, command_id: key)}

        {:ok, %Command{result: reason}} ->
          {:error, reason}

        error ->
          error
      end
    else
      _ -> {:error, "invalid_workflow"}
    end
  end

  defp command(key, expected, payload) do
    case Repo.get(Command, key) do
      nil ->
        persist(key, expected, payload)

      %Command{kind: "save_workflow_labels", expected_revision: ^expected, payload: ^payload} = c ->
        c

      _ ->
        Repo.rollback(:key_conflict)
    end
  end

  defp persist(key, expected, payload) do
    board = Repo.get_by(Tabula, id: payload["tabula_id"], arena_id: payload["arena_id"])
    previous = if board, do: current(board)
    reason = rejection(board, previous, expected, payload)

    command =
      Repo.insert!(%Command{
        id: key,
        kind: "save_workflow_labels",
        expected_revision: expected,
        payload: payload,
        state: if(reason, do: "rejected", else: "completed"),
        result: reason
      })

    if is_nil(reason) do
      Repo.insert!(%WorkflowRevision{
        tabula_id: board.id,
        command_id: key,
        revision: expected + 1,
        definition: payload["definition"],
        inserted_at: DateTime.utc_now()
      })
    end

    Foundation.record(
      "workflow.#{command.state}",
      %{
        "arena_id" => payload["arena_id"],
        "tabula_id" => payload["tabula_id"],
        "previous_revision" => expected,
        "revision" => if(is_nil(reason), do: expected + 1),
        "reason" => reason
      },
      key
    )

    command
  end

  defp rejection(board, previous, expected, payload) do
    cond do
      is_nil(board) -> "scope_missing"
      previous.revision != expected -> "stale_workflow"
      not supported?(previous.definition) -> "unsupported_workflow"
      labels(previous.definition) == labels(payload["definition"]) -> "workflow_unchanged"
      true -> blocker(board)
    end
  end

  defp supported?(%{"version" => version, "columns" => columns})
       when version in [1, 2] and is_list(columns),
       do:
         Enum.map(columns, &Map.take(&1, ~w(key role))) ==
           Enum.map(@columns, &Map.take(&1, ~w(key role)))

  defp supported?(_), do: false

  defp valid_names?(names) when is_map(names) do
    values = Map.values(names)

    Enum.sort(Map.keys(names)) == Enum.sort(Enum.map(@columns, & &1["key"])) and
      Enum.all?(values, &valid_name?/1) and
      length(Enum.uniq_by(values, &(&1 |> String.trim() |> String.downcase()))) == 5
  end

  defp valid_names?(_), do: false

  defp valid_name?(name) when is_binary(name),
    do:
      byte_size(name) <= 160 and String.valid?(name) and String.length(name) in 1..40 and
        String.trim(name) != "" and not Regex.match?(~r/[\x00-\x1F\x7F]/, name)

  defp valid_name?(_), do: false
end
