defmodule CuckodingWeb.ArenaGitLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Cuckoding.{ArenaGit, BrowserToken, Foundation, Repo}

  test "inspection, explicit initialization consent and reconnect preserve the public result", %{
    conn: conn
  } do
    arena = Cuckoding.DataCase.arena_fixture()
    signed = sign_in(conn)
    path = "/arenas/#{arena.id}"
    {:ok, view, _} = live(signed, path)
    refute has_element?(view, "#git-init-form")
    view |> element("button", "Inspect Git") |> render_click()
    assert render(view) =~ "Owner: you · system Git"
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "missing"})
    assert has_element?(view, "#git-init-form")
    view |> form("#git-init-form") |> render_submit()
    assert has_element?(view, "[role='alert']", "Confirm the displayed Git action")
    assert ArenaGit.latest(arena.id).kind == "inspect_arena_git"
    view |> form("#git-init-form", confirmed: "true") |> render_change()
    Foundation.broadcast()
    assert has_element?(view, "input[name='confirmed'][checked]")
    view |> form("#git-init-form", confirmed: "true") |> render_submit()
    refute has_element?(view, "#git-init-form")
    {:ok, claim} = Foundation.claim()
    assert claim.kind == "init_arena_git"
    Foundation.finish(claim, %{"status" => "initialized"})
    assert render(view) =~ "has no commits yet"
    {:ok, again, _} = live(signed, path)
    assert render(again) =~ "has no commits yet"
    assert has_element?(again, "#arena-git[phx-mounted*=ignore_attrs]")
    refute File.exists?(arena.path)
  end

  test "recovered consent cannot authorize a new inspection and cancellation stays explicit", %{
    conn: conn
  } do
    arena = Cuckoding.DataCase.arena_fixture()
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{arena.id}")

    for _ <- 1..2 do
      view |> element("button", "Inspect Git") |> render_click()
      {:ok, claim} = Foundation.claim()
      Foundation.finish(claim, %{"status" => "missing"})
    end

    render_submit(view, "init-git", %{
      "confirmed" => "true",
      "observation_id" => Ecto.UUID.generate()
    })

    assert ArenaGit.latest(arena.id).kind == "inspect_arena_git"
    refute has_element?(view, "input[name='confirmed'][checked]")
    view |> element("button", "Inspect Git") |> render_click()
    {:ok, claim} = Foundation.claim()
    view |> element("button", "Cancel Git operation") |> render_click()
    assert has_element?(view, "button[disabled]", "Cancel Git operation")
    Foundation.finish(claim, %{"status" => "missing"})
    assert render(view) =~ "will not be replayed"
    refute has_element?(view, "#git-init-form")
  end

  test "expired sessions cannot inspect or initialize Git", %{conn: conn} do
    arena = Cuckoding.DataCase.arena_fixture()
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{arena.id}")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    render_click(view, "inspect-git")
    assert_redirect(view, "/locked")
    assert ArenaGit.latest(arena.id) == nil
  end

  test "worktree confirmation is scoped, clears on update and survives reconnect as a receipt", %{
    conn: conn
  } do
    arena = Cuckoding.DataCase.arena_fixture()
    signed = sign_in(conn)
    path = "/arenas/#{arena.id}"
    {:ok, view, _} = live(signed, path)
    view |> element("button", "Inspect Git") |> render_click()
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "existing", "head" => String.duplicate("a", 40)})
    assert has_element?(view, "#worktree-form")
    view |> form("#worktree-form") |> render_submit()
    assert ArenaGit.worktrees(arena.id) == []
    view |> form("#worktree-form", confirmed: "true") |> render_change()
    Foundation.broadcast()
    assert has_element?(view, "#worktree-form input[checked]")

    render_submit(view, "prepare-worktree", %{
      "confirmed" => "true",
      "observation_id" => claim.id,
      "key" => Ecto.UUID.generate()
    })

    assert ArenaGit.worktrees(arena.id) == []
    view |> form("#worktree-form", confirmed: "true") |> render_change()
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect")
    {:ok, fresh} = Foundation.claim()
    Foundation.finish(fresh, %{"status" => "existing", "head" => String.duplicate("b", 40)})
    refute has_element?(view, "#worktree-form input[checked]")
    view |> form("#worktree-form", confirmed: "true") |> render_submit()
    {:ok, prepare} = Foundation.claim()
    assert prepare.kind == "worktree_arena_git"
    assert has_element?(view, "#worktree-form button[aria-disabled=true]:not([disabled])")
    view |> form("#worktree-form", confirmed: "true") |> render_submit()
    assert length(ArenaGit.worktrees(arena.id)) == 1
    assert render(view) =~ "no model"
    assert has_element?(view, "button", "Cancel preparation")

    Foundation.finish(prepare, %{
      "status" => "prepared",
      "key" => prepare.id,
      "head" => prepare.payload["head"],
      "path" => prepare.payload["worktree_path"],
      "device" => 1,
      "inode" => 2
    })

    assert has_element?(view, "#worktree-receipts", "checkout prepared")
    {:ok, again, _} = live(signed, path)
    assert has_element?(again, "#worktree-receipts", prepare.payload["worktree_path"])
    assert has_element?(again, "#worktree-setup[phx-mounted*=ignore_attrs]")
    refute has_element?(again, "#worktree-form input[checked]")
    again |> form("#worktree-form", confirmed: "true") |> render_submit()
    {:ok, pending} = Foundation.claim()
    again |> element("button", "Cancel preparation") |> render_click()
    assert has_element?(again, "button[disabled]", "Waiting for cleanup")
    Foundation.finish(pending, %{"status" => "prepared"})
    assert has_element?(again, "#worktree-receipts", "Nothing is retried")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    render_submit(again, "prepare-worktree", %{})
    assert_redirect(again, "/locked")
    assert length(ArenaGit.worktrees(arena.id)) == 2
  end

  test "worktree inspection is scoped, cancellable, durable and session guarded", %{conn: conn} do
    arena = Cuckoding.DataCase.arena_fixture()
    signed = sign_in(conn)
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect")
    {:ok, baseline} = Foundation.claim()
    Foundation.finish(baseline, %{"status" => "existing", "head" => String.duplicate("a", 40)})
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "worktree", baseline.id, true)
    {:ok, prepare} = Foundation.claim()

    Foundation.finish(prepare, %{
      "status" => "prepared",
      "key" => prepare.id,
      "head" => prepare.payload["head"],
      "path" => prepare.payload["worktree_path"],
      "device" => 1,
      "inode" => 2
    })

    {:ok, view, _} = live(signed, "/arenas/#{arena.id}")
    view |> element("button", "Inspect worktree") |> render_click()
    {:ok, claim} = Foundation.claim()
    assert claim.kind == "inspect_worktree_arena_git"
    assert has_element?(view, "button[aria-disabled=true]:not([disabled])", "Inspect worktree")
    assert has_element?(view, "#inspection-#{prepare.id}", "no model")
    view |> element("button", "Inspect worktree") |> render_click()
    assert ArenaGit.worktree_inspections(arena.id, [prepare])[prepare.id].id == claim.id
    render_click(view, "cancel-worktree-inspection", %{"id" => Ecto.UUID.generate()})
    assert Foundation.probe_active?(claim)

    Foundation.finish(
      claim,
      Map.put(claim.payload["preparation"], "status", "worktree_unchanged")
    )

    assert has_element?(view, "#inspection-#{prepare.id}", "raw tracked bytes matched")
    assert render(view) =~ "not permission to execute"
    {:ok, again, _} = live(signed, "/arenas/#{arena.id}")
    assert has_element?(again, "#inspection-#{prepare.id}", "raw tracked bytes matched")
    again |> element("button", "Inspect worktree") |> render_click()
    {:ok, cancel} = Foundation.claim()
    again |> element("button", "Cancel inspection") |> render_click()
    assert has_element?(again, "button[disabled]", "Cancel inspection")

    Foundation.finish(
      cancel,
      Map.put(cancel.payload["preparation"], "status", "worktree_unchanged")
    )

    assert has_element?(again, "#inspection-#{prepare.id}", "without a usable observation")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    again |> element("button", "Inspect worktree") |> render_click()
    assert_redirect(again, "/locked")
    assert ArenaGit.worktree_inspections(arena.id, [prepare])[prepare.id].id == cancel.id
  end
end
