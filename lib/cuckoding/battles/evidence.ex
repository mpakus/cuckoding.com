defmodule Cuckoding.Battles.Evidence do
  @moduledoc "Bounded, scoped public task history; reading receipts never authorizes work."
  import Ecto.Query
  alias Cuckoding.Battles.{Attempt, Battle, Task}
  alias Cuckoding.{DraftTask, Repo, Tabula}
  @page_size 20
  @export_bytes 2 * 1024 * 1024

  def export(arena, board, task, battle, before \\ nil) do
    with true <- ids?([battle]),
         %{} = execution <- run(arena, board, task, battle),
         {:ok, cursor} <- export_cursor(battle, task, before) do
      page = attempts(arena, board, task, battle, cursor)

      body =
        Jason.encode_to_iodata!(%{
          format: "cuckoding-task-evidence-v1",
          exported_at: DateTime.utc_now(),
          scope: %{arena_id: arena, tabula_id: board, task_id: task, battle_id: battle},
          notice:
            "Public retained evidence, not completion proof or execution permission. " <>
              "Final review and recovery observations remain in Inspect battle.",
          execution: execution,
          attempts: page.rows,
          pagination: %{before: before, more: page.more?, page_size: @page_size}
        })

      if IO.iodata_length(body) <= @export_bytes,
        do: {:ok, IO.iodata_to_binary(body)},
        else: {:error, :too_large}
    else
      _ -> {:error, :not_found}
    end
  end

  defp export_cursor(_, _, nil), do: {:ok, nil}

  defp export_cursor(battle, task, id) do
    if ids?([id]) do
      case Repo.one(
             from a in Attempt,
               where: a.battle_id == ^battle and a.task_id == ^task and a.id == ^id,
               select: %{id: a.id, started_at: a.inserted_at}
           ) do
        nil -> {:error, :not_found}
        cursor -> {:ok, cursor}
      end
    else
      {:error, :not_found}
    end
  end

  def run(arena, board, task, battle \\ nil) do
    if ids?([arena, board, task]) and (is_nil(battle) or ids?([battle])) do
      query = scope(arena, board, task)
      query = if battle, do: where(query, [_, b], b.id == ^battle), else: query
      fetch_run(query)
    end
  end

  def earlier(arena, board, task, battle) do
    with true <- ids?([battle]),
         %{} = current <- run(arena, board, task, battle) do
      scope(arena, board, task)
      |> where(
        [_, b],
        b.inserted_at < ^current.started_at or
          (b.inserted_at == ^current.started_at and b.id < ^battle)
      )
      |> fetch_run()
    else
      _ -> nil
    end
  end

  def attempts(arena, board, task, battle, before) do
    if cursor?(before) and ids?([battle]) and run(arena, board, task, battle) do
      query =
        from a in Attempt,
          where: a.battle_id == ^battle and a.task_id == ^task

      query =
        if before do
          where(
            query,
            [a],
            a.inserted_at < ^before.started_at or
              (a.inserted_at == ^before.started_at and a.id < ^before.id)
          )
        else
          query
        end

      rows =
        Repo.all(
          from a in query,
            order_by: [desc: a.inserted_at, desc: a.id],
            limit: ^(@page_size + 1),
            select: %{
              id: a.id,
              state: a.state,
              stage: a.stage,
              role: a.role,
              started_at: a.inserted_at,
              result: a.result,
              binding: type(fragment("json_extract(?, '$.role')", a.request), :map)
            }
        )

      visible =
        rows
        |> Enum.take(@page_size)
        |> Enum.map(fn row ->
          row
          |> Map.update!(:binding, &Map.take(&1 || %{}, ~w(name kind agent_name model)))
          |> Map.update!(:result, &receipt/1)
        end)

      %{rows: visible, more?: length(rows) > @page_size}
    else
      %{rows: [], more?: false}
    end
  end

  defp scope(arena, board, task) do
    from t in Task,
      join: b in Battle,
      on: t.battle_id == b.id,
      join: d in DraftTask,
      on: t.task_id == d.id and d.tabula_id == b.tabula_id,
      join: tabula in Tabula,
      on: tabula.id == b.tabula_id and tabula.arena_id == b.arena_id,
      where: b.arena_id == ^arena and b.tabula_id == ^board and t.task_id == ^task
  end

  defp fetch_run(query) do
    row =
      Repo.one(
        from [t, b] in query,
          order_by: [desc: b.inserted_at, desc: b.id],
          limit: 1,
          select: %{
            battle_id: b.id,
            started_at: b.inserted_at,
            battle_state: b.state,
            task_state: t.state,
            review_round: t.review_round,
            snapshot: t.snapshot
          }
      )

    if row, do: Map.update!(row, :snapshot, &public_snapshot/1)
  end

  defp public_snapshot(snapshot) do
    visible =
      Map.take(snapshot, ~w(title description criteria criteria_sha256 revision depends_on))

    if Map.has_key?(snapshot, "verification"),
      do:
        Map.put(
          visible,
          "verification",
          public_list(snapshot["verification"], 4, ~w(profile directory timeout_seconds))
        ),
      else: visible
  end

  defp receipt(result) do
    provider = result["provider"] || %{}

    result
    |> Map.take(~w(status reason summary feedback head candidate_sha cleanup_verified))
    |> Map.put(
      "checks",
      public_list(
        result["checks"],
        8,
        ~w(id status exit_code stdout_sha256 stdout_bytes elapsed_ms cleanup_verified contract candidate_sha check_sha256 input_manifest_sha256 image_spec_sha256 intent_sha256 native_state vm_closed source_unchanged observed_stdout_bytes native_started admission_sha256)
      )
    )
    |> Map.put("provider", %{
      "requested_model" => provider["requested_model"],
      "observed_model" => provider["observed_model"],
      "tools" => public_list(provider["tools"], 64, ~w(tool status path sha256)),
      "changes" => public_list(provider["changes"], 64, ~w(path sha256))
    })
  end

  defp public_list(nil, _, _), do: []

  defp public_list(rows, limit, keys),
    do: rows |> Enum.take(limit) |> Enum.map(&Map.take(&1, keys))

  defp cursor?(nil), do: true
  defp cursor?(%{started_at: %DateTime{}, id: id}), do: ids?([id])
  defp cursor?(_), do: false
  defp ids?(ids), do: Enum.all?(ids, &match?({:ok, _}, Ecto.UUID.cast(&1)))
end
