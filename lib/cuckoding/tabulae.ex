defmodule Cuckoding.Tabulae do
  @moduledoc "Arena-scoped boards and revisioned manual drafts. No execution authority."
  import Ecto.Query

  alias Cuckoding.{
    Arena,
    Command,
    DraftTask,
    DraftTaskRevision,
    Foundation,
    Planning,
    Repo,
    Tabula,
    TeamAssignments
  }

  @fields ~w(title description criteria column)
  @columns [
    %{"key" => "specs", "name" => "Specs", "role" => "speculator"},
    %{"key" => "todo", "name" => "ToDo", "role" => "summa_rudis"},
    %{"key" => "in_process", "name" => "In Process", "role" => "implementor"},
    %{"key" => "review", "name" => "Review", "role" => "secutor"},
    %{"key" => "completed", "name" => "Completed", "role" => nil}
  ]

  def arena(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(Arena, id)
      _ -> nil
    end
  end

  def list(arena_id),
    do: Repo.all(from b in Tabula, where: b.arena_id == ^arena_id, order_by: b.inserted_at)

  def get(arena_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(Tabula, id: id, arena_id: arena_id) |> Repo.preload(:team_revision)
      _ -> nil
    end
  end

  def tasks(tabula_id) do
    Repo.all(
      from t in DraftTask,
        join: r in DraftTaskRevision,
        on: r.task_id == t.id and r.revision == t.revision,
        where: t.tabula_id == ^tabula_id,
        order_by: t.inserted_at,
        select: {t, r.content}
    )
    |> Enum.map(fn {task, content} ->
      %{task | depends_on: Map.get(content, "depends_on", [])}
    end)
  end

  def history(tabula_id, task_id) do
    Repo.all(
      from r in DraftTaskRevision,
        join: t in DraftTask,
        on: r.task_id == t.id,
        where: t.tabula_id == ^tabula_id and t.id == ^task_id,
        order_by: [desc: r.revision],
        limit: 5
    )
  end

  def content(task),
    do: Map.new(@fields ++ ["depends_on"], &{&1, Map.fetch!(task, String.to_existing_atom(&1))})

  def create(key, arena_id, name) do
    with {:ok, key} <- Ecto.UUID.cast(key),
         {:ok, arena_id} <- Ecto.UUID.cast(arena_id),
         true <- text?(name, 1, 80, false) do
      payload = %{"arena_id" => arena_id, "name" => String.trim(name)}
      command(key, "create_tabula", 0, payload)
    else
      _ -> {:error, "invalid_board"}
    end
  end

  def save(key, arena_id, tabula_id, task_id, expected, attrs) do
    with {:ok, key} <- Ecto.UUID.cast(key),
         {:ok, arena_id} <- Ecto.UUID.cast(arena_id),
         {:ok, tabula_id} <- Ecto.UUID.cast(tabula_id),
         {:ok, task_id} <- Ecto.UUID.cast(task_id),
         true <- is_integer(expected) and expected >= 0,
         true <- valid_content?(attrs) do
      payload = %{
        "arena_id" => arena_id,
        "tabula_id" => tabula_id,
        "task_id" => task_id,
        "content" => attrs
      }

      command(key, "save_draft", expected, payload)
    else
      _ -> {:error, "invalid_task"}
    end
  end

  def import_proposal(key, arena_id, tabula_id, proposal_id, index) do
    with {:ok, key} <- Ecto.UUID.cast(key),
         {:ok, arena_id} <- Ecto.UUID.cast(arena_id),
         {:ok, tabula_id} <- Ecto.UUID.cast(tabula_id),
         {:ok, proposal_id} <- Ecto.UUID.cast(proposal_id),
         true <- is_integer(index) and index in 0..5 do
      command(key, "import_plan_task", 0, %{
        "arena_id" => arena_id,
        "tabula_id" => tabula_id,
        "task_id" => key,
        "proposal_id" => proposal_id,
        "index" => index
      })
    else
      _ -> {:error, "invalid_proposal"}
    end
  end

  def imported(tabula_id) do
    Repo.all(
      from c in Command,
        where:
          c.kind == "import_plan_task" and c.state == "completed" and
            fragment("json_extract(?, '$.tabula_id')", c.payload) == ^tabula_id,
        select: c.payload
    )
    |> MapSet.new(&{&1["proposal_id"], &1["index"]})
  end

  defp proposal_task(payload) do
    command = Repo.get(Command, payload["proposal_id"])

    if (command && command.payload["arena_id"] == payload["arena_id"]) and
         command.payload["tabula_id"] == payload["tabula_id"] do
      if proposal = Planning.proposal(command), do: Enum.at(proposal["tasks"], payload["index"])
    end
  end

  defp command(id, kind, expected, payload) do
    result =
      Repo.transaction(
        fn ->
          case Repo.get(Command, id) do
            nil -> persist(id, kind, expected, payload)
            %Command{kind: ^kind, expected_revision: ^expected, payload: ^payload} = c -> c
            _ -> Repo.rollback(:key_conflict)
          end
        end,
        mode: :immediate
      )

    if match?({:ok, _}, result), do: Foundation.broadcast()

    case result do
      {:ok, %Command{state: "completed", kind: "create_tabula"}} ->
        {:ok, Repo.get_by!(Tabula, command_id: id)}

      {:ok, %Command{state: "completed"}} ->
        {:ok, Repo.get_by!(DraftTaskRevision, command_id: id)}

      {:ok, %Command{result: reason}} ->
        {:error, reason}

      error ->
        error
    end
  end

  defp persist(id, kind, expected, payload) do
    reason = rejection(kind, expected, payload)

    command =
      Repo.insert!(%Command{
        id: id,
        kind: kind,
        payload: payload,
        expected_revision: expected,
        state: if(reason, do: "rejected", else: "completed"),
        result: reason
      })

    if reason do
      Foundation.record("#{kind}.rejected", %{"reason" => reason}, id)
    else
      write(kind, id, expected, payload)
    end

    command
  end

  defp rejection("create_tabula", _, payload) do
    if Repo.get(Arena, payload["arena_id"]) == nil, do: "scope_missing"
  end

  defp rejection("import_plan_task", _, payload) do
    cond do
      is_nil(get(payload["arena_id"], payload["tabula_id"])) or is_nil(proposal_task(payload)) ->
        "invalid_proposal"

      MapSet.member?(imported(payload["tabula_id"]), {payload["proposal_id"], payload["index"]}) ->
        "already_imported"

      Repo.get(DraftTask, payload["task_id"]) != nil ->
        "invalid_proposal"

      true ->
        nil
    end
  end

  defp rejection("save_draft", expected, payload) do
    board = Repo.get_by(Tabula, id: payload["tabula_id"], arena_id: payload["arena_id"])
    task = Repo.get(DraftTask, payload["task_id"])

    cond do
      board == nil or (task != nil and task.tabula_id != board.id) ->
        "scope_missing"

      (task && task.revision) != if(expected == 0, do: nil, else: expected) ->
        "stale_task"

      true ->
        stage_rejection(payload["content"]) || dependency_rejection(payload)
    end
  end

  defp stage_rejection(%{"column" => "specs"}), do: nil

  defp stage_rejection(%{"column" => "todo"} = content) do
    if Enum.any?(~w(description criteria), &(String.trim(content[&1]) == "")),
      do: "criteria_required"
  end

  defp stage_rejection(_), do: "stage_unavailable"

  defp dependency_rejection(payload) do
    # ponytail: load the board graph per save; query reachable edges if boards outgrow memory.
    graph = Map.new(tasks(payload["tabula_id"]), &{&1.id, &1.depends_on})
    id = payload["task_id"]
    dependencies = Map.get(payload["content"], "depends_on", Map.get(graph, id, []))

    cond do
      Enum.any?(dependencies, &(&1 == id or not Map.has_key?(graph, &1))) ->
        "invalid_dependencies"

      reaches?(dependencies, id, graph, MapSet.new()) ->
        "dependency_cycle"

      true ->
        nil
    end
  end

  defp reaches?([], _, _, _), do: false
  defp reaches?([id | _], id, _, _), do: true

  defp reaches?([id | rest], target, graph, visited) do
    if MapSet.member?(visited, id),
      do: reaches?(rest, target, graph, visited),
      else: reaches?(Map.get(graph, id, []) ++ rest, target, graph, MapSet.put(visited, id))
  end

  defp write("create_tabula", id, _, payload) do
    arena = Repo.get!(Arena, payload["arena_id"])

    board =
      Repo.insert!(%Tabula{
        arena_id: arena.id,
        team_revision_id: TeamAssignments.assigned(arena).id,
        command_id: id,
        name: payload["name"],
        definition: %{"version" => 1, "execution" => "disabled", "columns" => @columns},
        inserted_at: DateTime.utc_now()
      })

    Foundation.record(
      "tabula.created",
      %{
        "arena_id" => arena.id,
        "tabula_id" => board.id,
        "team_revision" => board.team_revision_id
      },
      id
    )
  end

  defp write("import_plan_task", id, expected, payload) do
    content = Map.put(proposal_task(payload), "column", "specs")
    write("save_draft", id, expected, Map.put(payload, "content", content))

    Foundation.record(
      "planning.task_imported",
      Map.take(payload, ~w(tabula_id task_id proposal_id index)),
      id
    )
  end

  defp write("save_draft", id, expected, payload) do
    attrs = Map.new(@fields, &{String.to_existing_atom(&1), payload["content"][&1]})
    previous = Repo.get(DraftTask, payload["task_id"])
    task = previous || %DraftTask{id: payload["task_id"], tabula_id: payload["tabula_id"]}

    content =
      Map.put_new_lazy(payload["content"], "depends_on", fn ->
        if previous do
          Repo.get_by!(DraftTaskRevision, task_id: task.id, revision: previous.revision).content
          |> Map.get("depends_on", [])
        else
          []
        end
      end)

    task
    |> Ecto.Changeset.change(Map.put(attrs, :revision, expected + 1))
    |> Repo.insert_or_update!()

    Repo.insert!(%DraftTaskRevision{
      task_id: task.id,
      command_id: id,
      revision: expected + 1,
      content: content,
      inserted_at: DateTime.utc_now()
    })

    Foundation.record(
      "draft.saved",
      %{
        "task_id" => task.id,
        "tabula_id" => task.tabula_id,
        "revision" => expected + 1,
        "from" => if(previous, do: previous.column),
        "to" => attrs.column,
        "depends_on" => content["depends_on"]
      },
      id
    )
  end

  defp valid_content?(attrs) when is_map(attrs) do
    Enum.sort(Map.keys(Map.delete(attrs, "depends_on"))) == Enum.sort(@fields) and
      valid_dependencies?(Map.get(attrs, "depends_on", [])) and
      text?(attrs["title"], 1, 120, false) and text?(attrs["description"], 0, 8_000, true) and
      text?(attrs["criteria"], 0, 4_000, true) and text?(attrs["column"], 1, 32, false)
  end

  defp valid_content?(_), do: false

  defp valid_dependencies?(ids) when is_list(ids) do
    length(ids) <= 16 and length(Enum.uniq(ids)) == length(ids) and
      Enum.all?(ids, &(is_binary(&1) and byte_size(&1) == 36 and Ecto.UUID.cast(&1) == {:ok, &1}))
  end

  defp valid_dependencies?(_), do: false

  defp text?(value, min, max, multiline) when is_binary(value) do
    byte_size(value) <= max * 4 and String.valid?(value) and
      String.length(value) in min..max and (min == 0 or String.trim(value) != "") and
      not Regex.match?(
        if(multiline, do: ~r/[\x00-\x08\x0B-\x1F\x7F]/, else: ~r/[\x00-\x1F\x7F]/),
        value
      )
  end

  defp text?(_, _, _, _), do: false
end
