defmodule CuckodingWeb.InitialCommitLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Cuckoding.{ArenaGit, BrowserToken, Foundation, Repo}

  defp unborn(arena) do
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect")
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "unborn"})
  end

  defp preview(view, paths \\ "docs/plan.md") do
    view |> form("#git-preview-form", paths: paths) |> render_submit()
    {:ok, claim} = Foundation.claim()

    {:ok, observed} =
      Foundation.finish(
        claim,
        Cuckoding.DataCase.preview_receipt(claim.payload["paths"])
      )

    observed
  end

  test "initial commit has an exact preview, separate confirmation and retained receipt", %{
    conn: conn
  } do
    arena = Cuckoding.DataCase.arena_fixture()
    unborn(arena)
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/arenas/#{arena.id}")
    observed = preview(view)
    assert has_element?(view, "#git-preview", "docs/plan.md")
    assert render(view) =~ "Cuckoding &lt;local@cuckoding.invalid&gt;"
    view |> form("#git-commit-form") |> render_submit()
    assert has_element?(view, "[role='alert']", "Confirm the displayed")
    assert ArenaGit.latest(arena.id).id == observed.id
    view |> form("#git-commit-form", commit_confirmed: "true") |> render_change()
    Foundation.broadcast()
    assert has_element?(view, "input[name='commit_confirmed'][checked]")
    view |> form("#git-commit-form", commit_confirmed: "true") |> render_submit()
    {:ok, claim} = Foundation.claim()
    assert claim.kind == "commit_arena_git"

    Foundation.finish(claim, %{
      "status" => "committed",
      "head" => String.duplicate("a", 40),
      "tree" => String.duplicate("b", 40),
      "preview_id" => observed.id
    })

    assert render(view) =~ "Initial local commit created"
    {:ok, again, _} = live(signed, "/arenas/#{arena.id}")
    assert render(again) =~ "Initial local commit created"
    refute has_element?(again, "#git-commit-form")
  end

  test "edited selection or recovered foreign consent cannot commit; empty preview is explicit",
       %{conn: conn} do
    arena = Cuckoding.DataCase.arena_fixture()
    unborn(arena)
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{arena.id}")
    previous = preview(view)
    view |> form("#git-preview-form", paths: "other.md") |> render_change()
    view |> form("#git-commit-form", commit_confirmed: "true") |> render_submit()
    assert ArenaGit.latest(arena.id).id == previous.id
    observed = preview(view, "")
    assert has_element?(view, "#git-preview", "Empty baseline")

    render_submit(view, "commit-git", %{
      "observation_id" => previous.id,
      "commit_confirmed" => "true"
    })

    assert ArenaGit.latest(arena.id).id == observed.id
    refute has_element?(view, "input[name='commit_confirmed'][checked]")
  end

  test "expired session refuses preview and commit", %{conn: conn} do
    arena = Cuckoding.DataCase.arena_fixture()
    unborn(arena)
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{arena.id}")
    observed = preview(view, "")
    assert has_element?(view, "#git-commit-form")
    Repo.update_all(BrowserToken, set: [expires_at: 0])

    render_submit(view, "commit-git", %{
      "observation_id" => observed.id,
      "commit_confirmed" => "true"
    })

    assert_redirect(view, "/locked")
    assert ArenaGit.latest(arena.id).id == observed.id
  end
end
