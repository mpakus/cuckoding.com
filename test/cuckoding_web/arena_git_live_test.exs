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
end
