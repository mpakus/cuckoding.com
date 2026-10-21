defmodule Cuckoding.DashboardTest do
  use Cuckoding.DataCase
  alias Cuckoding.{AgentConnection, Command, Dashboard, Foundation, Tabulae}
  alias Cuckoding.Battles.{Attempt, Battle}

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

  test "work includes exact setup and planning bindings without private command content" do
    f = fixture()

    agent =
      Repo.insert!(%AgentConnection{id: Ecto.UUID.generate(), name: "My Cursor", kind: "cursor"})

    command =
      Repo.insert!(%Command{
        id: Ecto.UUID.generate(),
        kind: "plan_tabula",
        state: "running",
        expected_revision: 0,
        payload: %{
          "arena_id" => f.arena.id,
          "tabula_id" => f.board.id,
          "agent_id" => agent.id,
          "kind" => "cursor",
          "model" => "exact-alias",
          "role" => %{"name" => "Speculator", "instructions" => "hidden-instructions"},
          "brief" => "private-brief",
          "documents" => [%{"text" => "private-document"}],
          "login_url" => "private-url"
        }
      })

    login =
      Repo.insert!(%Command{
        id: Ecto.UUID.generate(),
        kind: "login_codex",
        state: "cancelling",
        expected_revision: 0,
        payload: %{"private" => "hidden-login"}
      })

    Repo.insert!(%Command{
      id: Ecto.UUID.generate(),
      kind: "plan_tabula",
      state: "completed",
      expected_revision: 0,
      payload: %{}
    })

    assert %{rows: rows, more?: false} = Dashboard.work()
    assert length(rows) == 2
    planning = Enum.find(rows, &(&1.id == command.id))

    assert planning.binding == %{
             "name" => "Speculator",
             "agent_name" => "My Cursor",
             "kind" => "cursor",
             "model" => "exact-alias"
           }

    assert planning.agent_id == agent.id
    assert planning.state == "running"
    assert Enum.find(rows, &(&1.id == login.id)).state == "cancelling"
    refute inspect(rows) =~ "private-"
    refute inspect(rows) =~ "hidden-"
    assert Dashboard.work(f.arena.id, f.board.id).rows == [planning]
  end

  test "board work rejects foreign scope and limits global activity" do
    f = fixture()
    other = fixture()

    for _ <- 1..23 do
      Repo.insert!(%Command{
        id: Ecto.UUID.generate(),
        kind: "inspect_arena_git",
        state: "pending",
        expected_revision: 0,
        payload: %{"arena_id" => f.arena.id}
      })
    end

    foreign =
      Repo.insert!(%Command{
        id: Ecto.UUID.generate(),
        kind: "plan_tabula",
        state: "running",
        expected_revision: 0,
        payload: %{"arena_id" => other.arena.id, "tabula_id" => f.board.id}
      })

    Repo.insert!(%Command{
      id: Ecto.UUID.generate(),
      kind: "future_unknown_command",
      state: "running",
      expected_revision: 0,
      payload: %{}
    })

    assert %{rows: rows, more?: true} = Dashboard.work()
    assert length(rows) == 20
    scoped = Dashboard.work(f.arena.id, f.board.id)
    assert length(scoped.rows) == 20
    refute Enum.any?(scoped.rows, &(&1.id == foreign.id))
    assert Dashboard.work(f.arena.id, other.board.id).rows == []
    assert Dashboard.work("invalid", f.board.id).rows == []
    assert Dashboard.work(f.arena.id, nil).rows == []
  end

  test "board summary uses only that board's latest frozen progress and saved team" do
    f = fixture()
    other = fixture()
    {:ok, empty} = Tabulae.create(Ecto.UUID.generate(), f.arena.id, "Empty board")
    before = Repo.aggregate(Command, :count)
    summary = Dashboard.board(f.arena.id, f.board.id)
    assert summary.total == 1
    assert summary.completed == 1
    assert summary.battle_id == f.battle.id

    assert Enum.all?(
             summary.team,
             &(Map.keys(&1) |> Enum.sort() == ~w(agent agent_name model_id name))
           )

    assert Dashboard.board(f.arena.id, empty.id).total == 0
    assert Dashboard.board(f.arena.id, other.board.id) == nil
    assert Dashboard.board("invalid", f.board.id) == nil
    assert Repo.aggregate(Command, :count) == before
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
