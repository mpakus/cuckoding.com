defmodule Cuckoding.ProjectChecksTest do
  use Cuckoding.DataCase
  import Cuckoding.DataCase, only: [arena_fixture: 0]
  alias Cuckoding.{CheckRevision, Command, Event, Foundation, ProjectChecks}

  defp check do
    %{
      "id" => Ecto.UUID.generate(),
      "name" => "Unit tests",
      "executable" => "mix",
      "arguments" => ["test", "--warnings-as-errors"],
      "directory" => ".",
      "timeout_seconds" => 300
    }
  end

  test "confirmed revisions are scoped, immutable, idempotent and never enter dispatch" do
    arena = arena_fixture()
    other = arena_fixture()
    checks = [check()]
    key = Ecto.UUID.generate()
    assert ProjectChecks.current(arena.id).revision == 0
    assert ProjectChecks.history(arena.id) == []
    original_workspace = Foundation.workspace()
    Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
    assert {:ok, first} = ProjectChecks.save(key, arena.id, 0, checks, true)
    assert_receive :updated
    assert first.revision == 1
    assert first.definition == %{"version" => 1, "execution" => "disabled", "checks" => checks}
    assert {:ok, ^first} = ProjectChecks.save(key, arena.id, 0, checks, true)
    assert {:error, :key_conflict} = ProjectChecks.save(key, other.id, 0, checks, true)
    assert ProjectChecks.current(other.id).revision == 0
    assert {:ok, nil} = Foundation.claim()
    assert Foundation.workspace() == original_workspace
    refute File.exists?(arena.path)

    assert {:error, "confirmation_required"} =
             ProjectChecks.save(Ecto.UUID.generate(), arena.id, 1, [], false)

    assert ProjectChecks.current(arena.id) == first
    assert {:ok, empty} = ProjectChecks.save(Ecto.UUID.generate(), arena.id, 1, [], true)
    assert empty.revision == 2
    assert ProjectChecks.history(arena.id) == [empty, first]
    assert Repo.get!(CheckRevision, first.id) == first
    assert {:error, _} = Repo.query("UPDATE check_revisions SET revision = 9")
    assert {:error, _} = Repo.query("DELETE FROM check_revisions")
    assert {:ok, ^first} = ProjectChecks.save(key, arena.id, 0, checks, true)
    refute inspect(Repo.all(Event)) =~ "--warnings-as-errors"

    assert Enum.any?(
             Repo.all(Event),
             &(&1.kind == "checks.completed" and &1.data["revision"] == 2)
           )
  end

  test "stale writers, key changes, foreign scopes and audit failure cannot replace saved checks" do
    arena = arena_fixture()
    checks = [check()]

    results =
      for _ <- 1..2 do
        Task.async(fn -> ProjectChecks.save(Ecto.UUID.generate(), arena.id, 0, checks, true) end)
      end
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert {:error, "stale_checks"} in results

    assert {:error, "checks_unchanged"} =
             ProjectChecks.save(Ecto.UUID.generate(), arena.id, 1, checks, true)

    assert {:error, "scope_missing"} =
             ProjectChecks.save(Ecto.UUID.generate(), Ecto.UUID.generate(), 0, checks, true)

    key = Ecto.UUID.generate()
    assert {:error, "stale_checks"} = ProjectChecks.save(key, arena.id, 0, [], true)
    assert {:error, "stale_checks"} = ProjectChecks.save(key, arena.id, 0, [], true)
    assert {:error, :key_conflict} = ProjectChecks.save(key, arena.id, 1, [], true)

    Repo.query!(
      "CREATE TEMP TRIGGER reject_check_event BEFORE INSERT ON events WHEN NEW.kind = 'checks.completed' BEGIN SELECT RAISE(ABORT, 'fixture failure'); END"
    )

    key = Ecto.UUID.generate()
    assert_raise Exqlite.Error, fn -> ProjectChecks.save(key, arena.id, 1, [], true) end
    assert Repo.get(Command, key) == nil
    assert ProjectChecks.current(arena.id).revision == 1
    Repo.query!("DROP TRIGGER reject_check_event")
  end

  test "declarations reject malformed authority, wrappers, traversal, controls and unbounded inputs" do
    arena = arena_fixture()
    c = check()

    invalid =
      [
        nil,
        %{},
        [nil],
        [Map.put(c, "grant", "all")],
        [Map.delete(c, "directory")],
        [c, c],
        [c, %{c | "id" => Ecto.UUID.generate(), "name" => " UNIT TESTS "}],
        Enum.map(1..9, fn i -> %{c | "id" => Ecto.UUID.generate(), "name" => "Check #{i}"} end)
      ] ++
        for {field, value} <- [
              {"id", "../escape"},
              {"id", <<0::128>>},
              {"id", String.upcase(c["id"])},
              {"name", " "},
              {"name", String.duplicate("a", 61)},
              {"name", "bad\nname"},
              {"executable", "rtk"},
              {"executable", "/usr/bin/mix"},
              {"executable", "mix test"},
              {"executable", "../mix"},
              {"executable", "$(mix)"},
              {"arguments", "test"},
              {"arguments", ["test\u0000"]},
              {"arguments", [""]},
              {"arguments", [String.duplicate("a", 257)]},
              {"arguments", Enum.to_list(1..17)},
              {"directory", "/tmp"},
              {"directory", "../outside"},
              {"directory", "app/../outside"},
              {"directory", "~/project"},
              {"directory", "app//test"},
              {"directory", "app\\test"},
              {"directory", ""},
              {"directory", <<255>>},
              {"directory", nil},
              {"timeout_seconds", 0},
              {"timeout_seconds", 1801},
              {"timeout_seconds", "300"}
            ],
            do: [Map.put(c, field, value)]

    count = Repo.aggregate(Command, :count)

    for checks <- invalid do
      assert {:error, "invalid_checks"} =
               ProjectChecks.save(Ecto.UUID.generate(), arena.id, 0, checks, true)
    end

    assert Repo.aggregate(Command, :count) == count
    assert ProjectChecks.history(arena.id) == []
  end

  test "argv is literal data, previews bind exact bytes, and schema sequences cannot skip" do
    arena = arena_fixture()

    c = %{
      check()
      | "arguments" => ["test", "a b", "$(touch canary)", "'quoted'", "--x=;"],
        "directory" => "apps/my app"
    }

    assert {:ok, preview} = ProjectChecks.preview([c])
    {:ok, changed} = ProjectChecks.preview([%{c | "timeout_seconds" => 301}])
    refute ProjectChecks.digest(preview) == ProjectChecks.digest(changed)
    assert {:ok, saved} = ProjectChecks.save(Ecto.UUID.generate(), arena.id, 0, [c], true)
    assert saved.definition == preview

    assert {:error, error} =
             Repo.query(
               "INSERT INTO check_revisions (arena_id, command_id, revision, definition, inserted_at) SELECT arena_id, command_id, 9, definition, inserted_at FROM check_revisions LIMIT 1"
             )

    assert Exception.message(error) =~ "invalid check revision"

    assert {:ok, nil} = Foundation.claim()
  end
end
