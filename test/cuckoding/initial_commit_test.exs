defmodule Cuckoding.InitialCommitTest do
  use Cuckoding.DataCase
  alias Cuckoding.{ArenaGit, Command, Event, Foundation, GitPreview, LocalGit}
  import Cuckoding.DataCase, only: [arena_fixture: 0, preview_receipt: 0, preview_receipt: 1]

  defp observe(arena, paths \\ ["docs/plan.md"]) do
    {:ok, _} = ArenaGit.preview(Ecto.UUID.generate(), arena.id, paths)
    {:ok, claim} = Foundation.claim()
    {:ok, preview} = Foundation.finish(claim, preview_receipt(paths))
    preview
  end

  test "preview selection and exact consent are durable, idempotent and content-free" do
    arena = arena_fixture()
    key = Ecto.UUID.generate()
    assert {:ok, pending} = ArenaGit.preview(key, arena.id, ["docs/plan.md"])
    assert {:ok, ^pending} = ArenaGit.preview(key, arena.id, ["docs/plan.md"])
    assert {:error, :key_conflict} = ArenaGit.preview(key, arena.id, [])
    {:ok, claim} = Foundation.claim()
    receipt = Map.put(preview_receipt(), "raw", "PRIVATE_CONTENT_CANARY")
    {:ok, observed} = Foundation.finish(claim, receipt)
    assert ArenaGit.can_commit?(observed)

    assert {:error, "confirmation_required"} =
             ArenaGit.request(Ecto.UUID.generate(), arena.id, "commit", observed.id, false)

    key = Ecto.UUID.generate()
    {:ok, intent} = ArenaGit.request(key, arena.id, "commit", observed.id, true)
    assert intent.payload["preview"] == receipt["preview"]
    assert {:ok, ^intent} = ArenaGit.request(key, arena.id, "commit", observed.id, true)
    {:ok, claim} = Foundation.claim()
    Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")

    result = %{
      "status" => "committed",
      "head" => String.duplicate("c", 40),
      "tree" => String.duplicate("d", 40),
      "preview_id" => observed.id
    }

    assert {:ok, %{state: "completed", result: "committed"}} = Foundation.finish(claim, result)
    assert_receive :updated
    assert Foundation.workspace().revision == 0
    refute inspect(Repo.all(Command)) =~ "PRIVATE_CONTENT_CANARY"
    refute inspect(Repo.all(Event)) =~ "docs/plan.md"
    assert {:ok, nil} = Foundation.claim()
  end

  test "foreign, expired and superseded previews cannot authorize a commit" do
    arena = arena_fixture()
    preview = observe(arena)

    assert {:ok, %{result: "recheck_required"}} =
             ArenaGit.request(
               Ecto.UUID.generate(),
               arena_fixture().id,
               "commit",
               preview.id,
               true
             )

    refute ArenaGit.can_commit?(preview, DateTime.add(preview.updated_at, 300))

    Repo.update!(
      Ecto.Changeset.change(preview, updated_at: DateTime.add(DateTime.utc_now(), -301))
    )

    assert {:ok, %{result: "recheck_required"}} =
             ArenaGit.request(Ecto.UUID.generate(), arena.id, "commit", preview.id, true)

    previous = observe(arena)
    observe(arena, [])

    assert {:ok, %{result: "recheck_required"}} =
             ArenaGit.request(Ecto.UUID.generate(), arena.id, "commit", previous.id, true)
  end

  test "cancelled, interrupted and mismatched commit receipts never pass or replay" do
    arena = arena_fixture()
    observed = observe(arena, [])
    {:ok, command} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "commit", observed.id, true)
    {:ok, _} = Foundation.cancel_probe(command.id)
    assert Repo.get!(Command, command.id).state == "cancelled"
    assert {:ok, nil} = Foundation.claim()
    observed = observe(arena, [])
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "commit", observed.id, true)
    {:ok, claim} = Foundation.claim(1_000)
    assert {:ok, %{state: "failed", result: "interrupted"}} = Foundation.claim(3_601_000)
    assert {:error, :lost_claim} = Foundation.finish(claim, %{"status" => "committed"})
    assert {:ok, nil} = Foundation.claim(3_602_000)
    observed = observe(arena)
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "commit", observed.id, true)
    {:ok, claim} = Foundation.claim()

    foreign = %{
      "status" => "committed",
      "head" => String.duplicate("a", 40),
      "tree" => String.duplicate("b", 40),
      "preview_id" => Ecto.UUID.generate()
    }

    assert {:ok, %{state: "failed", result: "recheck_required"}} =
             Foundation.finish(claim, foreign)
  end

  test "closed bounded previews reject unsafe paths, wrong files and malformed receipts" do
    assert GitPreview.paths("") == {:ok, []}
    assert GitPreview.paths("docs/a, b.md\nrun.sh") == {:ok, ["docs/a, b.md", "run.sh"]}

    for path <- ["../x", "/x", ".git/config", ".env", "a//b", "a\\b", "id_rsa", "a.key", "a\0b"] do
      assert GitPreview.paths(path) == {:error, "invalid_selection"}
    end

    assert {:error, "invalid_selection"} = GitPreview.paths("x\nx")
    assert {:error, "invalid_selection"} = GitPreview.paths(String.duplicate("x", 4_001))
    refute GitPreview.valid_paths?(Enum.map(1..17, &to_string/1))

    assert LocalGit.normalize(%{"status" => "committed", "head" => "wrong"})["status"] ==
             "invalid_repository"

    for preview <- [
          put_in(preview_receipt(), ["preview", "files", Access.at(0), "bytes"], -1),
          put_in(preview_receipt(), ["preview", "files", Access.at(0), "sha256"], "raw-secret")
        ] do
      assert LocalGit.normalize(preview) == %{"status" => "invalid_repository"}
    end

    quoted = Enum.map(1..16, &(to_string(&1) <> String.duplicate("\"", 235)))
    assert LocalGit.normalize(preview_receipt(quoted)) == %{"status" => "invalid_repository"}

    arena = arena_fixture()
    {:ok, _} = ArenaGit.preview(Ecto.UUID.generate(), arena.id, ["docs/plan.md"])
    {:ok, claim} = Foundation.claim()
    assert {:ok, %{result: "recheck_required"}} = Foundation.finish(claim, preview_receipt([]))
    refute ArenaGit.can_commit?(ArenaGit.latest(arena.id))
  end
end
