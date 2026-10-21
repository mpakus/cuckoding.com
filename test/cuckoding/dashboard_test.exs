defmodule Cuckoding.DashboardTest do
  use Cuckoding.DataCase
  alias Cuckoding.Battles.{Attempt, Battle}
  alias Cuckoding.{Command, Dashboard, Foundation, Tabulae}

  import Cuckoding.DashboardFixtures

  test "Arena summaries use the latest battle and frozen task progress with exact board links" do
    f = fixture("completed")
    {:ok, other} = Tabulae.create(Ecto.UUID.generate(), f.arena.id, "Later board")

    current =
      Repo.insert!(%Battle{
        id: Ecto.UUID.generate(),
        arena_id: f.arena.id,
        tabula_id: other.id,
        snapshot: %{},
        fingerprint: String.duplicate("b", 64),
        state: "needs_attention",
        reason: "cleanup_uncertain",
        stage: "admission",
        deadline_at: DateTime.add(DateTime.utc_now(), 100)
      })

    page = Dashboard.arenas(0)
    assert [row] = page.rows
    assert row.arena.id == f.arena.id
    assert row.board.id == other.id
    assert row.battle.id == current.id
    assert row.total == 0
    assert row.completed == 0
    refute page.more?
  end

  test "Arena pagination is bounded and does not duplicate rows" do
    for _ <- 1..23, do: Cuckoding.DataCase.arena_fixture()
    first = Dashboard.arenas(0)
    second = Dashboard.arenas(1)
    assert length(first.rows) == 20
    assert first.more?
    assert length(second.rows) == 3
    refute second.more?

    assert MapSet.disjoint?(
             MapSet.new(first.rows, & &1.arena.id),
             MapSet.new(second.rows, & &1.arena.id)
           )
  end

  test "active workers expose only public exact role binding fields" do
    f = fixture()

    binding = %{
      "name" => "Implementor",
      "kind" => "codex",
      "agent_name" => "Builder",
      "model" => "selected-model",
      "private" => "do not expose"
    }

    request = %{"role" => binding, "private" => "do not expose"}

    Repo.insert!(%Attempt{
      id: Ecto.UUID.generate(),
      battle_id: f.battle.id,
      task_id: f.task.task_id,
      stage: "implementor",
      role: "implementor",
      state: "running",
      claim_token: Ecto.UUID.generate(),
      request: request,
      deadline_at: f.battle.deadline_at
    })

    assert [worker] = Dashboard.workers()
    assert worker.arena_id == f.arena.id
    assert worker.tabula_id == f.board.id
    assert worker.binding == Map.take(binding, ~w(name kind agent_name model))
    refute Map.has_key?(worker, :request)
  end

  test "activity pages are chronological, scoped and metadata-only" do
    first = Ecto.UUID.generate()
    other = Ecto.UUID.generate()

    for i <- 1..45 do
      Foundation.record("battle.stage_finished", %{
        "arena_id" => first,
        "summary" => "private #{i}"
      })

      Foundation.record("battle.started", %{"arena_id" => other})
    end

    page = Dashboard.activity(first)
    assert length(page.rows) == 20
    assert page.more?
    ids = Enum.map(page.rows, & &1.id)
    assert ids == Enum.sort(ids)
    assert Enum.all?(page.rows, &(Map.keys(&1) |> Enum.sort() == [:id, :kind, :occurred_at]))
    older = Dashboard.activity(first, hd(page.rows).id)
    assert length(older.rows) == 20
    assert List.last(older.rows).id < hd(page.rows).id
    assert Enum.all?(older.rows, &(&1.kind == "battle.stage_finished"))
    assert Dashboard.activity("invalid").rows == []
    assert Dashboard.activity(other, 0).rows == []
  end

  test "Arena activity resolves board and command history without falling through foreign scopes" do
    f = fixture()
    other = fixture()

    command =
      Repo.insert!(%Command{
        id: Ecto.UUID.generate(),
        kind: "plan_brief",
        state: "completed",
        expected_revision: 0,
        payload: %{"arena_id" => f.arena.id}
      })

    Foundation.record("scope.direct", %{"arena_id" => f.arena.id})
    Foundation.record("scope.board", %{"tabula_id" => f.board.id})
    Foundation.record("scope.command", %{}, command.id)

    Foundation.record(
      "scope.foreign_arena",
      %{"arena_id" => other.arena.id, "tabula_id" => f.board.id},
      command.id
    )

    Foundation.record("scope.foreign_board", %{"tabula_id" => other.board.id}, command.id)
    kinds = Dashboard.activity(f.arena.id).rows |> Enum.map(& &1.kind)
    assert "scope.direct" in kinds
    assert "scope.board" in kinds
    assert "scope.command" in kinds
    refute "scope.foreign_arena" in kinds
    refute "scope.foreign_board" in kinds
  end
end
