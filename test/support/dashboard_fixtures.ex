defmodule Cuckoding.DashboardFixtures do
  @moduledoc false
  alias Cuckoding.Battles.{Battle, Task}
  alias Cuckoding.{Repo, Tabulae}

  def fixture(state \\ "running", snapshot \\ %{"title" => "Task"}) do
    arena = Cuckoding.DataCase.arena_fixture()
    {:ok, board} = Tabulae.create(Ecto.UUID.generate(), arena.id, "Beta")
    id = Ecto.UUID.generate()

    {:ok, _} =
      Tabulae.save(Ecto.UUID.generate(), arena.id, board.id, id, 0, %{
        "title" => "Task",
        "description" => "Build it",
        "criteria" => "Inspect it",
        "column" => "specs"
      })

    now = DateTime.utc_now()

    battle =
      Repo.insert!(%Battle{
        id: Ecto.UUID.generate(),
        arena_id: arena.id,
        tabula_id: board.id,
        snapshot: %{},
        fingerprint: String.duplicate("a", 64),
        state: state,
        stage: "implementor",
        deadline_at: DateTime.add(now, 100),
        inserted_at: now,
        updated_at: now
      })

    task =
      Repo.insert!(%Task{
        id: Ecto.UUID.generate(),
        battle_id: battle.id,
        task_id: id,
        position: 0,
        snapshot: snapshot,
        state: "completed"
      })

    %{arena: arena, board: board, battle: battle, task: task}
  end
end
