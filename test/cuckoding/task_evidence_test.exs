defmodule Cuckoding.TaskEvidenceTest do
  use Cuckoding.DataCase
  alias Cuckoding.Battles.{Attempt, Battle, Evidence, Task}
  alias Cuckoding.{Command, DashboardFixtures, Event, Tabulae}

  test "check feedback text stays private and the storage fence rejects other shapes" do
    f = DashboardFixtures.fixture("completed")

    attempt =
      Repo.insert!(%Attempt{
        id: Ecto.UUID.generate(),
        battle_id: f.battle.id,
        task_id: f.task.task_id,
        stage: "checks",
        state: "completed",
        claim_token: Ecto.UUID.generate(),
        deadline_at: f.battle.deadline_at,
        request: %{},
        result: %{
          "check_feedback" => [
            %{
              "check_id" => "check",
              "excerpt" => "PRIVATE_TEST_OUTPUT",
              "excerpt_bytes" => 19,
              "excerpt_sha256" => String.duplicate("a", 64),
              "request_id" => "PRIVATE_REQUEST"
            }
          ]
        }
      })

    page = Evidence.attempts(f.arena.id, f.board.id, f.task.task_id, f.battle.id, nil)

    assert hd(page.rows).result["check_feedback"] == [
             %{
               "check_id" => "check",
               "excerpt_bytes" => 19,
               "excerpt_sha256" => String.duplicate("a", 64)
             }
           ]

    {:ok, export} = Evidence.export(f.arena.id, f.board.id, f.task.task_id, f.battle.id)
    refute export =~ "PRIVATE_"

    for rows <- [%{}, [%{}, %{}]] do
      assert_raise Exqlite.Error, ~r/invalid check feedback shape/, fn ->
        Repo.query!("UPDATE battle_attempts SET result=? WHERE id=?", [
          Jason.encode!(%{"check_feedback" => rows}),
          attempt.id
        ])
      end
    end
  end

  test "execution scope binds Arena, board, draft and selected battle without fallback" do
    f = DashboardFixtures.fixture("completed")
    other = DashboardFixtures.fixture("completed")
    {:ok, board} = Tabulae.create(Ecto.UUID.generate(), f.arena.id, "Other board")
    count = {Repo.aggregate(Command, :count), Repo.aggregate(Event, :count)}
    assert Evidence.run(f.arena.id, f.board.id, f.task.task_id).battle_id == f.battle.id
    assert Evidence.run(other.arena.id, f.board.id, f.task.task_id) == nil
    assert Evidence.run(f.arena.id, board.id, f.task.task_id) == nil
    assert Evidence.run(f.arena.id, f.board.id, other.task.task_id) == nil
    assert Evidence.run(f.arena.id, f.board.id, f.task.task_id, other.battle.id) == nil
    assert Evidence.run("invalid", f.board.id, f.task.task_id) == nil
    assert Evidence.earlier(f.arena.id, f.board.id, f.task.task_id, nil) == nil
    assert Evidence.earlier(f.arena.id, f.board.id, f.task.task_id, "invalid") == nil
    assert Evidence.earlier(f.arena.id, f.board.id, f.task.task_id, other.battle.id) == nil

    assert Evidence.attempts(f.arena.id, f.board.id, f.task.task_id, other.battle.id, nil).rows ==
             []

    assert count == {Repo.aggregate(Command, :count), Repo.aggregate(Event, :count)}
  end

  test "earlier executions retain frozen criteria and use deterministic ordering" do
    f = DashboardFixtures.fixture("completed")
    now = DateTime.add(f.battle.inserted_at, 1)

    newer =
      f.battle
      |> Map.from_struct()
      |> Map.take(~w(arena_id tabula_id fingerprint snapshot state stage deadline_at)a)
      |> Map.merge(%{id: Ecto.UUID.generate(), inserted_at: now, updated_at: now})
      |> then(&Repo.insert!(struct!(Battle, &1)))

    Repo.insert!(%Task{
      id: Ecto.UUID.generate(),
      battle_id: newer.id,
      task_id: f.task.task_id,
      position: 0,
      snapshot: %{
        "revision" => 2,
        "criteria" => "New frozen checks",
        "private" => "hidden",
        "verification" => [
          %{
            "profile" => "mix-test",
            "directory" => "backend",
            "timeout_seconds" => 60,
            "private" => "hidden"
          }
        ]
      },
      state: "skipped"
    })

    run = Evidence.run(f.arena.id, f.board.id, f.task.task_id)
    assert run.battle_id == newer.id

    assert run.snapshot == %{
             "revision" => 2,
             "criteria" => "New frozen checks",
             "verification" => [
               %{"profile" => "mix-test", "directory" => "backend", "timeout_seconds" => 60}
             ]
           }

    assert run.task_state == "skipped"
    older = Evidence.earlier(f.arena.id, f.board.id, f.task.task_id, run.battle_id)
    assert older.battle_id == f.battle.id
    assert Evidence.earlier(f.arena.id, f.board.id, f.task.task_id, older.battle_id) == nil
  end

  test "attempt pages retain public review, file and check evidence, never private envelopes" do
    f = DashboardFixtures.fixture("completed")

    for i <- 1..23 do
      Repo.insert!(%Attempt{
        id: Ecto.UUID.generate(),
        battle_id: f.battle.id,
        task_id: f.task.task_id,
        role: "secutor",
        stage: "secutor",
        state: "expired",
        claim_token: Ecto.UUID.generate(),
        request: %{
          "role" => %{"name" => "Judge", "model" => "exact-model", "private" => "hidden"}
        },
        result: %{
          "summary" => "Review #{i}",
          "feedback" => "Repair this check",
          "candidate_sha" => String.duplicate("a", 40),
          "cleanup_verified" => true,
          "private" => "hidden",
          "provider" => %{
            "requested_model" => "exact-model",
            "observed_model" => "actual-model",
            "thoughts" => "hidden",
            "tools" => [
              %{
                "tool" => "read_file",
                "path" => "lib/app.ex",
                "status" => "completed",
                "raw" => "hidden"
              }
            ],
            "changes" => [%{"path" => "lib/app.ex", "sha256" => String.duplicate("b", 64)}]
          },
          "checks" => [
            %{"id" => "check", "status" => "failed", "exit_code" => 1, "raw" => "hidden"}
          ]
        },
        deadline_at: f.battle.deadline_at,
        inserted_at: DateTime.add(f.battle.inserted_at, i)
      })
    end

    page = Evidence.attempts(f.arena.id, f.board.id, f.task.task_id, f.battle.id, nil)
    assert length(page.rows) == 20
    assert page.more?
    assert hd(page.rows).result["summary"] == "Review 23"
    assert hd(page.rows).binding == %{"name" => "Judge", "model" => "exact-model"}

    assert hd(page.rows).result["checks"] == [
             %{"id" => "check", "status" => "failed", "exit_code" => 1}
           ]

    assert hd(page.rows).result["provider"]["tools"] == [
             %{"tool" => "read_file", "path" => "lib/app.ex", "status" => "completed"}
           ]

    refute inspect(page) =~ "hidden"
    refute inspect(page) =~ "claim_token"

    newest = Repo.get!(Attempt, hd(page.rows).id)

    Repo.insert!(%{
      newest
      | id: Ecto.UUID.generate(),
        claim_token: Ecto.UUID.generate(),
        inserted_at: DateTime.add(newest.inserted_at, 1),
        result: Map.put(newest.result, "summary", "Arrived while reading")
    })

    older =
      Evidence.attempts(f.arena.id, f.board.id, f.task.task_id, f.battle.id, List.last(page.rows))

    assert length(older.rows) == 3
    refute older.more?
    assert MapSet.disjoint?(MapSet.new(page.rows, & &1.id), MapSet.new(older.rows, & &1.id))
    assert Evidence.attempts(f.arena.id, f.board.id, f.task.task_id, f.battle.id, -1).rows == []
  end
end
