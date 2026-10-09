defmodule Cuckoding.ArenaGitTest do
  use Cuckoding.DataCase
  alias Cuckoding.{ArenaGit, Command, Event, Foundation, LocalGit}
  import Cuckoding.DataCase, only: [arena_fixture: 0]

  setup do
    previous =
      for key <- [:data_dir, :discovery_home],
          into: %{},
          do: {key, Application.get_env(:cuckoding, key)}

    Application.put_env(:cuckoding, :data_dir, "/private/tmp/cuckoding-git-test-data")
    Application.put_env(:cuckoding, :discovery_home, "/Users/cuckoding-test")

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if value,
          do: Application.put_env(:cuckoding, key, value),
          else: Application.delete_env(:cuckoding, key)
      end)
    end)

    :ok
  end

  test "inspection and initialization are scoped, consented, idempotent and separate from setup revisions" do
    arena = arena_fixture()
    key = Ecto.UUID.generate()

    assert {:error, "confirmation_required"} =
             ArenaGit.request(key, arena.id, "inspect", Ecto.UUID.generate(), true)

    assert {:ok, pending} = ArenaGit.request(key, arena.id, "inspect")
    assert {:ok, ^pending} = ArenaGit.request(key, arena.id, "inspect")
    assert {:error, :key_conflict} = ArenaGit.request(key, arena_fixture().id, "inspect")

    assert {:error, "confirmation_required"} =
             ArenaGit.request(Ecto.UUID.generate(), arena.id, "init")

    {:ok, claim} = Foundation.claim()

    assert {:ok, observed} =
             Foundation.finish(claim, %{
               "status" => "missing",
               "elapsed_ms" => 50,
               "raw" => "fixture-secret"
             })

    assert ArenaGit.can_initialize?(observed)
    assert {:ok, ^observed} = ArenaGit.request(key, arena.id, "inspect")
    init_key = Ecto.UUID.generate()
    assert {:ok, init} = ArenaGit.request(init_key, arena.id, "init", observed.id, true)
    assert {:ok, ^init} = ArenaGit.request(init_key, arena.id, "init", observed.id, true)
    assert init.payload["path"] == arena.path
    assert init.payload["device"] == arena.device
    {:ok, claim} = Foundation.claim()
    Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")

    assert {:ok, completed} =
             Foundation.finish(claim, %{"status" => "initialized", "elapsed_ms" => 100})

    assert_receive :updated
    assert ArenaGit.latest(arena.id).id == completed.id
    refute ArenaGit.can_initialize?(completed)
    assert Foundation.workspace().revision == 0
    refute inspect(Repo.all(Event)) =~ arena.path
    refute inspect(Repo.all(Command)) =~ "fixture-secret"
    assert {:ok, nil} = Foundation.claim()
  end

  test "stale, foreign, missing and expired initialization observations are rejected" do
    arena = arena_fixture()
    other = arena_fixture()
    observed = inspect_missing(arena)

    assert {:ok, %{state: "rejected", result: "recheck_required"}} =
             ArenaGit.request(Ecto.UUID.generate(), other.id, "init", observed.id, true)

    assert {:ok, %{result: "arena_missing"}} =
             ArenaGit.request(Ecto.UUID.generate(), Ecto.UUID.generate(), "inspect")

    observed = inspect_missing(arena)
    refute ArenaGit.can_initialize?(observed, DateTime.add(observed.updated_at, 300))

    Repo.update!(
      Ecto.Changeset.change(observed, updated_at: DateTime.add(DateTime.utc_now(), -301))
    )

    assert {:ok, %{result: "recheck_required"}} =
             ArenaGit.request(Ecto.UUID.generate(), arena.id, "init", observed.id, true)

    previous = inspect_missing(arena)
    inspect_missing(arena)

    assert {:ok, %{result: "recheck_required"}} =
             ArenaGit.request(Ecto.UUID.generate(), arena.id, "init", previous.id, true)
  end

  test "cancellation and sleep-sized claim gaps never replay or accept late success" do
    arena = arena_fixture()
    observed = inspect_missing(arena)
    {:ok, pending} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "init", observed.id, true)
    Foundation.cancel_probe(pending.id)
    assert Repo.get!(Command, pending.id).state == "cancelled"
    assert {:ok, nil} = Foundation.claim()
    observed = inspect_missing(arena)
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "init", observed.id, true)
    {:ok, claim} = Foundation.claim(1_000)
    Foundation.cancel_probe(claim.id)
    assert Foundation.pending?()

    assert {:ok, %{state: "cancelled", result: "cancelled"}} =
             Foundation.finish(claim, %{"status" => "initialized"})

    assert {:error, :lost_claim} = Foundation.finish(claim, %{"status" => "initialized"})
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect")
    {:ok, claim} = Foundation.claim(1_000)
    assert {:ok, %{state: "failed", result: "interrupted"}} = Foundation.claim(3_601_000)
    assert {:ok, nil} = Foundation.claim(3_602_000)
    assert {:error, :lost_claim} = Foundation.finish(claim, %{"status" => "missing"})
    refute ArenaGit.can_initialize?(ArenaGit.latest(arena.id))
    assert Foundation.workspace().revision == 0
  end

  test "Git setup serializes with provider and other Arena operations" do
    arena = arena_fixture()
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect")

    assert {:ok, %{result: "setup_busy"}} =
             ArenaGit.request(Ecto.UUID.generate(), arena_fixture().id, "inspect")

    assert {:ok, %{result: "profile_busy"}} = Foundation.discover(Ecto.UUID.generate(), 0)
  end

  test "missing or changed folders refuse the helper and only closed receipts survive" do
    arena = arena_fixture()
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect")
    {:ok, claim} = Foundation.claim()
    assert ArenaGit.execute(claim) == %{"status" => "folder_changed"}

    assert LocalGit.normalize(%{"status" => "existing", "head" => "not a hash"}) == %{
             "status" => "invalid_repository"
           }

    assert LocalGit.normalize(%{"status" => "shell", "command" => "fixture-secret"}) == %{
             "status" => "unavailable"
           }

    assert {:ok, result} =
             Foundation.finish(claim, %{
               "status" => "existing",
               "head" => String.duplicate("a", 40),
               "elapsed_ms" => -1,
               "raw" => "fixture-secret"
             })

    assert result.payload["observation"] == %{
             "status" => "existing",
             "head" => String.duplicate("a", 40)
           }

    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect")
    {:ok, claim} = Foundation.claim()

    assert {:ok, %{result: "recheck_required"}} =
             Foundation.finish(claim, %{"status" => "initialized"})

    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect")
    {:ok, claim} = Foundation.claim()
    Foundation.cancel_probe(claim.id)

    assert {:ok, %{state: "failed", result: "cleanup_uncertain"}} =
             Foundation.finish(claim, %{"status" => "cleanup_uncertain"})
  end

  test "worktree consent freezes HEAD and path without changing the baseline observation" do
    arena = arena_fixture()
    observed = inspect_head(arena)
    assert ArenaGit.can_prepare?(observed)
    refute ArenaGit.can_prepare?(observed, DateTime.add(observed.updated_at, 300))
    key = Ecto.UUID.generate()

    assert {:error, "confirmation_required"} =
             ArenaGit.request(key, arena.id, "worktree", observed.id)

    assert {:ok, pending} = ArenaGit.request(key, arena.id, "worktree", observed.id, true)
    assert {:ok, ^pending} = ArenaGit.request(key, arena.id, "worktree", observed.id, true)
    assert pending.payload["head"] == observed.payload["observation"]["head"]
    assert pending.payload["worktree_path"] == ArenaGit.worktree_path(key)
    assert ArenaGit.latest(arena.id).id == observed.id
    {:ok, claim} = Foundation.claim()
    assert {:ok, done} = Foundation.finish(claim, worktree_receipt(claim))
    assert done.result == "prepared"
    assert hd(ArenaGit.worktrees(arena.id)).id == done.id
    assert ArenaGit.latest(arena.id).id == observed.id
    refute inspect(Repo.all(Event)) =~ "checkout"
    refute inspect(Repo.all(Command)) =~ "fixture-secret"
    assert {:ok, ^done} = ArenaGit.request(key, arena.id, "worktree", observed.id, true)
    assert {:ok, nil} = Foundation.claim()
  end

  test "worktrees reject foreign or stale observations and foreign native receipts" do
    arena = arena_fixture()
    previous = inspect_head(arena)

    assert {:ok, %{result: "recheck_required"}} =
             ArenaGit.request(
               Ecto.UUID.generate(),
               arena_fixture().id,
               "worktree",
               previous.id,
               true
             )

    observed = inspect_head(arena)

    assert {:ok, %{result: "recheck_required"}} =
             ArenaGit.request(Ecto.UUID.generate(), arena.id, "worktree", previous.id, true)

    for {field, value} <- [
          {"key", Ecto.UUID.generate()},
          {"head", String.duplicate("b", 40)},
          {"path", "/foreign/checkout"}
        ] do
      {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "worktree", observed.id, true)
      {:ok, claim} = Foundation.claim()

      assert {:ok, %{result: "recheck_required"}} =
               Foundation.finish(claim, Map.put(worktree_receipt(claim), field, value))
    end

    Repo.update!(
      Ecto.Changeset.change(observed, updated_at: DateTime.add(DateTime.utc_now(), -301))
    )

    assert {:ok, %{result: "recheck_required"}} =
             ArenaGit.request(Ecto.UUID.generate(), arena.id, "worktree", observed.id, true)
  end

  test "worktree cancellation holds ownership and expired receipts never become successful or replay" do
    arena = arena_fixture()
    observed = inspect_head(arena)

    {:ok, pending} =
      ArenaGit.request(Ecto.UUID.generate(), arena.id, "worktree", observed.id, true)

    Foundation.cancel_probe(pending.id)
    assert {:ok, nil} = Foundation.claim()
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "worktree", observed.id, true)
    {:ok, claim} = Foundation.claim()
    Foundation.cancel_probe(claim.id)
    assert Foundation.pending?()
    assert {:ok, %{state: "cancelled"}} = Foundation.finish(claim, worktree_receipt(claim))
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "worktree", observed.id, true)
    {:ok, expired} = Foundation.claim(1000)
    refute Foundation.probe_active?(expired)
    assert {:error, :lost_claim} = Foundation.finish(expired, worktree_receipt(expired))
    assert {:ok, %{result: "interrupted"}} = Foundation.claim(3_601_000)
    assert {:ok, nil} = Foundation.claim(3_602_000)
    assert {:error, :lost_claim} = Foundation.finish(expired, worktree_receipt(expired))

    assert Repo.get!(Command, expired.id).payload["worktree_path"] ==
             ArenaGit.worktree_path(expired.id)

    assert {:ok, _} =
             ArenaGit.request(Ecto.UUID.generate(), arena.id, "worktree", observed.id, true)

    {:ok, claim} = Foundation.claim()
    assert {:ok, %{result: "profile_busy"}} = Foundation.discover(Ecto.UUID.generate(), 0)
    Foundation.cancel_probe(claim.id)

    assert {:ok, %{state: "failed", result: "cleanup_uncertain"}} =
             Foundation.finish(claim, %{"status" => "cleanup_uncertain"})
  end

  test "worktree inspections freeze only this Arena's completed receipt and remain separate from baseline" do
    arena = arena_fixture()
    prepared = prepared_worktree(arena)
    baseline = ArenaGit.latest(arena.id)
    key = Ecto.UUID.generate()
    assert {:ok, pending} = ArenaGit.request(key, arena.id, "inspect_worktree", prepared.id)
    assert {:ok, ^pending} = ArenaGit.request(key, arena.id, "inspect_worktree", prepared.id)

    assert pending.payload["preparation"] ==
             Map.take(prepared.payload["observation"], ~w(key head path device inode))

    assert {:ok, %{result: "setup_busy"}} =
             ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect")

    {:ok, claim} = Foundation.claim()
    assert Foundation.probe_active?(claim)

    result =
      Map.merge(claim.payload["preparation"], %{
        "status" => "worktree_unchanged",
        "raw" => "INSPECTION_CANARY"
      })

    assert {:ok, done} = Foundation.finish(claim, result)
    assert done.state == "completed"
    assert {:ok, ^done} = ArenaGit.request(key, arena.id, "inspect_worktree", prepared.id)
    assert ArenaGit.worktree_inspections(arena.id, [prepared])[prepared.id].id == done.id
    assert ArenaGit.worktree_inspections(arena_fixture().id, [prepared])[prepared.id] == nil

    # The separate ordinary inspection above is rejected; the worktree inspection is never the baseline.
    refute ArenaGit.latest(arena.id).id in [prepared.id, done.id]
    assert baseline.kind == "inspect_arena_git"
    refute inspect(Repo.all(Command)) =~ "INSPECTION_CANARY"
    assert Repo.get!(Command, prepared.id) == prepared

    assert Repo.aggregate(
             from(e in Event,
               where: e.command_id == ^done.id and e.kind == "arena_git.completed"
             ),
             :count
           ) == 1

    for id <- [baseline.id, Ecto.UUID.generate()] do
      assert {:ok, %{state: "rejected", result: "recheck_required"}} =
               ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect_worktree", id)
    end

    assert {:ok, %{state: "rejected", result: "recheck_required"}} =
             ArenaGit.request(
               Ecto.UUID.generate(),
               arena_fixture().id,
               "inspect_worktree",
               prepared.id
             )

    assert {:error, "confirmation_required"} =
             ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect_worktree", "bad")
  end

  test "inspection refuses foreign and malformed receipts and preserves changed observations" do
    arena = arena_fixture()
    prepared = prepared_worktree(arena)

    for {field, value} <- [
          {"key", Ecto.UUID.generate()},
          {"head", String.duplicate("b", 40)},
          {"path", "/foreign"},
          {"device", 9},
          {"inode", 9}
        ] do
      {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect_worktree", prepared.id)
      {:ok, claim} = Foundation.claim()

      result =
        claim.payload["preparation"]
        |> Map.put("status", "worktree_unchanged")
        |> Map.put(field, value)

      assert {:ok, %{state: "failed", result: "recheck_required"}} =
               Foundation.finish(claim, result)
    end

    assert LocalGit.normalize(%{"status" => "worktree_unchanged"}) == %{
             "status" => "invalid_repository"
           }

    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect_worktree", prepared.id)
    {:ok, claim} = Foundation.claim()

    assert {:ok, %{state: "completed", result: "worktree_changed"}} =
             Foundation.finish(
               claim,
               Map.put(claim.payload["preparation"], "status", "worktree_changed")
             )

    assert ArenaGit.latest(arena.id).kind == "inspect_arena_git"
  end

  test "inspection cancellation and expiry retain receipt history without accepting late observations" do
    arena = arena_fixture()
    prepared = prepared_worktree(arena)

    {:ok, pending} =
      ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect_worktree", prepared.id)

    Foundation.cancel_probe(pending.id)
    assert {:ok, nil} = Foundation.claim()
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect_worktree", prepared.id)
    {:ok, claim} = Foundation.claim()
    Foundation.cancel_probe(claim.id)
    assert Foundation.pending?()

    assert {:ok, %{state: "cancelled"}} =
             Foundation.finish(
               claim,
               Map.put(claim.payload["preparation"], "status", "worktree_unchanged")
             )

    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect_worktree", prepared.id)
    {:ok, expired} = Foundation.claim(1000)
    refute Foundation.probe_active?(expired)
    assert {:error, :lost_claim} = Foundation.finish(expired, %{"status" => "worktree_unchanged"})
    assert {:ok, %{result: "interrupted"}} = Foundation.claim(3_601_000)
    assert {:ok, nil} = Foundation.claim(3_602_000)
    assert {:error, :lost_claim} = Foundation.finish(expired, %{"status" => "worktree_unchanged"})
    assert Repo.get!(Command, prepared.id) == prepared
  end

  defp prepared_worktree(arena) do
    observed = inspect_head(arena)
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "worktree", observed.id, true)
    {:ok, claim} = Foundation.claim()
    {:ok, prepared} = Foundation.finish(claim, worktree_receipt(claim))
    prepared
  end

  defp inspect_head(arena) do
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect")
    {:ok, claim} = Foundation.claim()

    {:ok, observed} =
      Foundation.finish(claim, %{"status" => "existing", "head" => String.duplicate("a", 40)})

    observed
  end

  defp worktree_receipt(claim),
    do: %{
      "status" => "prepared",
      "head" => claim.payload["head"],
      "key" => claim.id,
      "path" => claim.payload["worktree_path"],
      "device" => 1,
      "inode" => 42,
      "raw" => "fixture-secret"
    }

  defp inspect_missing(arena) do
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect")
    {:ok, claim} = Foundation.claim()
    {:ok, observed} = Foundation.finish(claim, %{"status" => "missing"})
    observed
  end
end
