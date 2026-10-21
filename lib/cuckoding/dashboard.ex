defmodule Cuckoding.Dashboard do
  @moduledoc "Bounded read-only dashboard projections; observations never authorize work."
  import Ecto.Query

  alias Cuckoding.{
    AgentConnection,
    Arena,
    Command,
    DraftTask,
    Event,
    Repo,
    Tabula,
    TeamAssignments
  }

  alias Cuckoding.Battles.{Attempt, Battle, Task}
  @page_size 20
  @provider_commands ~w(probe_codex inspect_codex login_codex logout_codex
    check_codex_model check_codex_isolation probe_cursor inspect_cursor login_cursor logout_cursor)
  @repository_commands ~w(inspect_arena_git init_arena_git preview_arena_git commit_arena_git
    worktree_arena_git inspect_worktree_arena_git preview_documents accept_spec)
  @setup_commands @provider_commands ++
                    @repository_commands ++
                    ~w(discover_tools disconnect_agent choose_arena_folder plan_tabula)

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

  def board(arena_id, tabula_id) do
    with %Tabula{} = board <- scoped_board(arena_id, tabula_id) do
      battle =
        Repo.one(
          from b in Battle,
            where: b.arena_id == ^arena_id and b.tabula_id == ^board.id,
            order_by: [desc: b.inserted_at, desc: b.id],
            limit: 1
        )

      {total, completed} =
        if battle,
          do: Map.get(task_counts([battle.id]), battle.id, {0, 0}),
          else: {Map.get(draft_counts([board.id]), board.id, 0), 0}

      team = TeamAssignments.assigned(board).definition["roles"]

      %{
        total: total,
        completed: completed,
        battle_id: battle && battle.id,
        team: public_team(team)
      }
    end
  end

  defp public_team(roles) do
    ids =
      Enum.map(roles, & &1["agent"])
      |> Enum.filter(&match?({:ok, _}, Ecto.UUID.cast(&1)))

    names =
      Repo.all(from a in AgentConnection, where: a.id in ^ids, select: {a.id, a.name})
      |> Map.new()
      |> Map.put("codex", "Codex")

    Enum.map(roles, fn role ->
      role
      |> Map.take(~w(name agent model_id))
      |> Map.put("agent_name", names[role["agent"]] || "Unassigned")
    end)
  end

  def work(arena_id \\ nil, tabula_id \\ nil) do
    scope =
      if is_nil(arena_id) and is_nil(tabula_id),
        do: :global,
        else: scoped_board(arena_id, tabula_id)

    if scope do
      rows =
        (battle_workers(scope) ++ setup_work(scope))
        |> Enum.sort_by(&{DateTime.to_unix(&1.started_at, :microsecond), &1.id})

      %{rows: Enum.take(rows, @page_size), more?: length(rows) > @page_size}
    else
      %{rows: [], more?: false}
    end
  end

  defp scoped_board(arena_id, tabula_id) do
    with {:ok, arena_id} <- Ecto.UUID.cast(arena_id),
         {:ok, tabula_id} <- Ecto.UUID.cast(tabula_id) do
      Repo.one(from b in Tabula, where: b.arena_id == ^arena_id and b.id == ^tabula_id)
    else
      _ -> nil
    end
  end

  def workers, do: battle_workers(:global)

  defp battle_workers(scope) do
    query =
      from a in Attempt,
        join: b in Battle,
        on: a.battle_id == b.id,
        join: arena in Arena,
        on: arena.id == b.arena_id,
        where: a.state == "running",
        order_by: [asc: a.inserted_at, asc: a.id],
        limit: ^(@page_size + 1),
        select: %{
          id: a.id,
          arena_id: arena.id,
          arena_name: arena.name,
          tabula_id: b.tabula_id,
          stage: a.stage,
          state: a.state,
          started_at: a.inserted_at,
          agent_id: nil,
          binding: type(fragment("json_extract(?, '$.role')", a.request), :map)
        }

    query =
      if scope == :global,
        do: query,
        else: where(query, [_, b], b.arena_id == ^scope.arena_id and b.tabula_id == ^scope.id)

    Repo.all(query)
    |> Enum.map(
      &Map.update!(&1, :binding, fn binding ->
        Map.take(binding || %{}, ~w(name kind agent_name model))
      end)
    )
  end

  defp setup_work(scope) do
    query =
      from c in Command,
        left_join: agent in AgentConnection,
        on: agent.id == fragment("json_extract(?, '$.agent_id')", c.payload),
        left_join: arena in Arena,
        on: arena.id == fragment("json_extract(?, '$.arena_id')", c.payload),
        left_join: board in Tabula,
        on:
          board.id == fragment("json_extract(?, '$.tabula_id')", c.payload) and
            board.arena_id == arena.id,
        where: c.state in ~w(pending running cancelling) and c.kind in ^@setup_commands,
        order_by: [asc: c.inserted_at, asc: c.id],
        limit: ^(@page_size + 1),
        select: %{
          id: c.id,
          stage: c.kind,
          state: c.state,
          started_at: c.inserted_at,
          arena_id: arena.id,
          arena_name: arena.name,
          tabula_id: board.id,
          agent_id: fragment("json_extract(?, '$.agent_id')", c.payload),
          agent_name: agent.name,
          kind: fragment("json_extract(?, '$.kind')", c.payload),
          model: fragment("json_extract(?, '$.model')", c.payload),
          role: fragment("json_extract(?, '$.role.name')", c.payload)
        }

    query =
      if scope == :global,
        do: query,
        else:
          where(
            query,
            [c],
            fragment("json_extract(?, '$.arena_id')", c.payload) == ^scope.arena_id and
              (fragment("json_extract(?, '$.tabula_id')", c.payload) == ^scope.id or
                 (is_nil(fragment("json_extract(?, '$.tabula_id')", c.payload)) and
                    c.kind in ^@repository_commands))
          )

    Repo.all(query) |> Enum.map(&setup_row/1)
  end

  defp setup_row(row) do
    provider =
      cond do
        row.stage == "plan_tabula" ->
          row.kind

        row.stage in @provider_commands ->
          if String.contains?(row.stage, "cursor"), do: "cursor", else: "codex"

        true ->
          nil
      end

    legacy? = provider == "codex" and is_nil(row.agent_id)

    row
    |> Map.drop([:agent_name, :kind, :model, :role])
    |> Map.put(:agent_id, if(legacy?, do: "codex", else: row.agent_id))
    |> Map.put(:binding, %{
      "name" => row.role,
      "kind" => provider,
      "agent_name" => if(legacy?, do: "Codex", else: row.agent_name),
      "model" => row.model
    })
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
