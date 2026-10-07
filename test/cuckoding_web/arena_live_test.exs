defmodule CuckodingWeb.ArenaLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Cuckoding.{Arenas, BrowserToken, Foundation, Repo, Team}

  setup do
    root = "/private/tmp/cuckoding-arena-ui-#{Ecto.UUID.generate()}"
    File.mkdir!(root)

    previous =
      for key <- [:discovery_home, :data_dir],
          into: %{},
          do: {key, Application.get_env(:cuckoding, key)}

    Application.put_env(:cuckoding, :discovery_home, "/Users/cuckoding-test")
    Application.put_env(:cuckoding, :data_dir, root <> "-data")

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if is_nil(value),
          do: Application.delete_env(:cuckoding, key),
          else: Application.put_env(:cuckoding, key, value)
      end)

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "native selection previews, preserves input and confirmation, then registers and reconnects",
       %{conn: conn, root: root} do
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/arenas")
    assert has_element?(view, "a[href='/arenas'][aria-current='page']")
    view |> element("button", "Choose folder…") |> render_click()
    assert render(view) =~ "macOS native dialog"
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "selected", "path" => root})
    assert has_element?(view, "#arena-form")
    assert render(view) =~ "No .git entry"
    view |> form("#arena-form", name: "My project") |> render_submit()
    assert render(view) =~ "confirm the displayed folder"
    Foundation.broadcast()
    assert has_element?(view, "#arena-name[value='My project']")
    assert has_element?(view, "[role='alert']")
    Team.save(Ecto.UUID.generate(), 1, Team.editable(Team.current()))
    assert has_element?(view, "#preview-team", "revision 1")
    assert has_element?(view, "#preview-team[phx-mounted*=ignore_attrs]")
    view |> form("#arena-form", confirmed: "true") |> render_submit()
    assert render(view) =~ "My project registered locally"
    refute has_element?(view, "#arena-form")
    assert {:ok, again, _} = live(signed, "/arenas")
    assert render(again) =~ "My project"
    assert hd(Arenas.list()).team_revision_id == 1
    assert File.ls!(root) == []
  end

  test "missing or expired browser sessions cannot select folders", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/locked"}}} = live(conn, "/arenas")
    {:ok, view, _} = conn |> sign_in() |> live("/arenas")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    render_click(view, "choose")
    assert_redirect(view, "/locked")
    assert Arenas.selection() == nil
  end

  test "cancel is accessible and stale recovered forms cannot confirm a different selection", %{
    conn: conn,
    root: root
  } do
    {:ok, view, _} = conn |> sign_in() |> live("/arenas")
    render_click(view, "choose")
    view |> element("button", "Cancel selection") |> render_click()
    assert render(view) =~ "Folder selection cancelled"
    render_click(view, "choose")
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "selected", "path" => root})

    render_submit(view, "register", %{
      "name" => "Recovered",
      "confirmed" => "true",
      "selection_id" => Ecto.UUID.generate()
    })

    assert Arenas.list() == []
    assert has_element?(view, "#arena-name[value='Recovered']")
    refute has_element?(view, "input[name='confirmed'][checked]")

    render_submit(view, "register", %{
      "name" => %{},
      "confirmed" => "true",
      "selection_id" => claim.id
    })

    assert Arenas.list() == []
  end
end
