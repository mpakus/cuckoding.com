defmodule Cuckoding.Dashboard do
  @moduledoc "Bounded read-only dashboard projections; observations never authorize work."
  import Ecto.Query
  alias Cuckoding.{Arena, Command, DraftTask, Event, Repo, Tabula}
  alias Cuckoding.Battles.{Attempt, Battle, Task}
  @page_size 20

  def arenas(page) when is_integer(page) and page >= 0 do
    rows =
      Repo.all(
        from a in Arena,
          order_by: [desc: a.inserted_at, desc: a.id],
          limit: ^(@page_size + 1),
          offset: ^(page * @page_size)
      )

    visible = Enum.take(rows, @page_size)
    ids = Enum.map(visible, & &1.id)
    latest = latest_battles(ids)
    boards = first_boards(ids)
    counts = task_counts(Enum.map(Map.values(latest), & &1.id))
    drafts = draft_counts(Enum.map(Map.values(boards), & &1.id))

    summaries =
      Enum.map(visible, fn arena ->
        battle = latest[arena.id]
        board = if battle, do: %{id: battle.tabula_id}, else: boards[arena.id]

        {total, completed} =
          if battle,
            do: Map.get(counts, battle.id, {0, 0}),
            else: {if(board, do: drafts[board.id] || 0, else: 0), 0}

        %{arena: arena, board: board, battle: battle, total: total, completed: completed}
      end)

    %{rows: summaries, more?: length(rows) > @page_size}
  end

  defp latest_battles(ids) do
    Repo.all(
      from b in Battle,
        as: :battle,
        where: b.arena_id in ^ids,
        where:
          not exists(
            from other in Battle,
              where:
                other.arena_id == parent_as(:battle).arena_id and
                  (other.inserted_at > parent_as(:battle).inserted_at or
                     (other.inserted_at == parent_as(:battle).inserted_at and
                        other.id > parent_as(:battle).id)),
              select: 1
          )
    )
    |> Map.new(&{&1.arena_id, &1})
  end

  defp first_boards(ids) do
    Repo.all(
      from b in Tabula,
        as: :board,
        where: b.arena_id in ^ids,
        where:
          not exists(
            from other in Tabula,
              where:
                other.arena_id == parent_as(:board).arena_id and
                  (other.inserted_at < parent_as(:board).inserted_at or
                     (other.inserted_at == parent_as(:board).inserted_at and
                        other.id < parent_as(:board).id)),
              select: 1
          )
    )
    |> Map.new(&{&1.arena_id, &1})
  end

  defp task_counts(ids) do
    Repo.all(
      from t in Task,
        where: t.battle_id in ^ids,
        group_by: t.battle_id,
        select:
          {t.battle_id,
           {count(t.id), sum(fragment("CASE WHEN ? = 'completed' THEN 1 ELSE 0 END", t.state))}}
    )
    |> Map.new()
  end

  defp draft_counts(ids) do
    Repo.all(
      from t in DraftTask,
        where: t.tabula_id in ^ids,
        group_by: t.tabula_id,
        select: {t.tabula_id, count(t.id)}
    )
    |> Map.new()
  end

  def workers do
    Repo.all(
      from a in Attempt,
        join: b in Battle,
        on: a.battle_id == b.id,
        join: arena in Arena,
        on: arena.id == b.arena_id,
        where: a.state == "running",
        order_by: a.inserted_at,
        limit: 2,
        select: %{
          id: a.id,
          arena_id: arena.id,
          arena_name: arena.name,
          tabula_id: b.tabula_id,
          stage: a.stage,
          started_at: a.inserted_at,
          binding: type(fragment("json_extract(?, '$.role')", a.request), :map)
        }
    )
    |> Enum.map(
      &Map.update!(&1, :binding, fn binding ->
        Map.take(binding || %{}, ~w(name kind agent_name model))
      end)
    )
  end

  def activity(arena_id \\ nil, before \\ nil) do
    if (is_nil(arena_id) or match?({:ok, _}, Ecto.UUID.cast(arena_id))) and
         (is_nil(before) or (is_integer(before) and before > 0)) do
      query =
        from e in Event,
          order_by: [desc: e.id],
          limit: ^(@page_size + 1),
          select: map(e, [:id, :kind, :occurred_at])

      query = if arena_id, do: scoped(query, arena_id), else: query

      query = if before, do: where(query, [e], e.id < ^before), else: query
      rows = Repo.all(query)
      %{rows: rows |> Enum.take(@page_size) |> Enum.reverse(), more?: length(rows) > @page_size}
    else
      %{rows: [], more?: false}
    end
  end

  defp scoped(query, arena_id) do
    boards = from b in Tabula, where: b.arena_id == ^arena_id, select: b.id

    commands =
      from c in Command,
        where: fragment("json_extract(?, '$.arena_id') = ?", c.payload, ^arena_id),
        select: c.id

    where(
      query,
      [e],
      fragment("json_extract(?, '$.arena_id') = ?", e.data, ^arena_id) or
        (is_nil(fragment("json_extract(?, '$.arena_id')", e.data)) and
           fragment("json_extract(?, '$.tabula_id')", e.data) in subquery(boards)) or
        (is_nil(fragment("json_extract(?, '$.arena_id')", e.data)) and
           is_nil(fragment("json_extract(?, '$.tabula_id')", e.data)) and
           e.command_id in subquery(commands))
    )
  end
end
