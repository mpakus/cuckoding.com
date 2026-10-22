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

  def read_stages(%{"version" => 3, "columns" => columns}),
    do: Enum.filter(columns, &custom_key?(&1["key"]))

  def read_stages(_), do: []

  def custom_key?("step_" <> id), do: match?({:ok, ^id}, Ecto.UUID.cast(id))
  def custom_key?(_), do: false

  def configure(key, arena_id, tabula_id, expected, team_id, names, steps) do
    with {:ok, key} <- Ecto.UUID.cast(key),
         {:ok, arena_id} <- Ecto.UUID.cast(arena_id),
         {:ok, tabula_id} <- Ecto.UUID.cast(tabula_id),
         true <- is_integer(expected) and expected >= 0 and is_integer(team_id),
         true <- valid_names?(names) and valid_steps?(steps, names) do
      core = Enum.map(@columns, &Map.put(&1, "name", String.trim(names[&1["key"]])))
      {before, after_steps} = Enum.split(core, 2)

      payload = %{
        "arena_id" => arena_id,
        "tabula_id" => tabula_id,
        "team_revision_id" => team_id,
        "definition" => %{
          "version" => 3,
          "execution" => "arena-loop-v2",
          "columns" =>
            before ++
              Enum.map(steps, &Map.update!(&1, "name", fn name -> String.trim(name) end)) ++
              after_steps
        }
      }

      save_command(key, expected, payload, "save_workflow")
    else
      _ -> {:error, "invalid_workflow"}
    end
  end

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

      save_command(key, expected, payload, "save_workflow_labels")
    else
      _ -> {:error, "invalid_workflow"}
    end
  end

  defp save_command(key, expected, payload, kind) do
    result = Repo.transaction(fn -> command(key, expected, payload, kind) end, mode: :immediate)
    if match?({:ok, _}, result), do: Foundation.broadcast()

    case result do
      {:ok, %Command{state: "completed"}} ->
        {:ok, Repo.get_by!(WorkflowRevision, command_id: key)}

      {:ok, %Command{result: reason}} ->
        {:error, reason}

      error ->
        error
    end
  end

  defp command(key, expected, payload, kind) do
    case Repo.get(Command, key) do
      nil ->
        persist(key, expected, payload, kind)

      %Command{kind: ^kind, expected_revision: ^expected, payload: ^payload} = c ->
        c

      _ ->
        Repo.rollback(:key_conflict)
    end
  end

  defp persist(key, expected, payload, kind) do
    board = Repo.get_by(Tabula, id: payload["tabula_id"], arena_id: payload["arena_id"])
    previous = if board, do: current(board)
    reason = rejection(board, previous, expected, payload)

    command =
      Repo.insert!(%Command{
        id: key,
        kind: kind,
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
      is_nil(board) ->
        "scope_missing"

      previous.revision != expected ->
        "stale_workflow"

      not supported?(previous.definition) ->
        "unsupported_workflow"

      not team_matches?(board, payload) ->
        "stale_team"

      read_stages(previous.definition) != [] and payload["definition"]["version"] != 3 ->
        "unsupported_workflow"

      previous.definition["columns"] == payload["definition"]["columns"] ->
        "workflow_unchanged"

      true ->
        blocker(board)
    end
  end

  defp supported?(%{"version" => version, "columns" => columns})
       when version in [1, 2, 3] and is_list(columns),
       do:
         Enum.map(
           Enum.reject(columns, &custom_key?(&1["key"])),
           &Map.take(&1, ~w(key role))
         ) ==
           Enum.map(@columns, &Map.take(&1, ~w(key role)))

  defp supported?(_), do: false

  defp team_matches?(board, %{"team_revision_id" => id, "definition" => definition}) do
    team = TeamAssignments.assigned(board)

    ids =
      for role <- team.definition["roles"],
          role["id"] not in ~w(speculator implementor secutor summa_rudis),
          do: role["id"]

    team.id == id and Enum.all?(read_stages(definition), &(&1["role"] in ids))
  end

  defp team_matches?(_, _), do: true

  defp valid_steps?(steps, names) when is_list(steps) and length(steps) <= 4 do
    Enum.all?(steps, fn step ->
      is_map(step) and Enum.sort(Map.keys(step)) == ~w(key name role) and
        custom_key?(step["key"]) and
        match?({:ok, _}, Ecto.UUID.cast(step["role"])) and valid_name?(step["name"])
    end) and
      length(Enum.uniq_by(steps, & &1["key"])) == length(steps) and
      length(Enum.uniq_by(steps, & &1["role"])) == length(steps) and
      unique_labels?(Map.values(names) ++ Enum.map(steps, & &1["name"]))
  end

  defp valid_steps?(_, _), do: false

  defp unique_labels?(values),
    do:
      length(Enum.uniq_by(values, &(&1 |> String.trim() |> String.downcase()))) == length(values)

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
