defmodule CuckodingWeb.TeamLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Cuckoding.{BrowserToken, Foundation, Repo, Team}

  test "shared application chrome can load a digested favicon", %{conn: conn} do
    name = "favicon-test-#{Ecto.UUID.generate()}.svg"
    path = Application.app_dir(:cuckoding, "priv/static/#{name}")
    source = Application.app_dir(:cuckoding, "priv/static/favicon.svg")
    File.cp!(source, path)
    on_exit(fn -> File.rm!(path) end)
    response = get(conn, "/#{name}")
    assert response(response, 200) == File.read!(source)
    assert get_resp_header(response, "content-type") == ["image/svg+xml"]
    assert conn |> Map.put(:host, "evil.test") |> get("/#{name}") |> response(403)
  end

  test "team editing requires a live browser session", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/locked"}}} = live(conn, "/team")
    {:ok, view, _} = conn |> sign_in() |> live("/team")
    render_change(view, "change", %{"roles" => %{"speculator" => %{"name" => "Draft"}}})
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    render_submit(view, "save", %{"roles" => %{}})
    assert_redirect(view, "/locked")
    assert Team.current().id == 1
  end

  test "keyboard form saves and reconnects; live updates preserve text and disclosures", %{
    conn: conn
  } do
    signed = sign_in(conn)
    {:ok, view, html} = live(signed, "/team")
    assert html =~ "Cast your roles."
    assert has_element?(view, "a[href='/team'][aria-current='page']")
    assert has_element?(view, "label[for='instructions-speculator']")
    assert has_element?(view, "section#role-speculator .role-binding select#agent-speculator")
    assert has_element?(view, "#role-options-speculator[phx-mounted*=ignore_attrs]:not([open])")
    assert has_element?(view, "#setup-journey li[aria-current=step]", "Roles")
    assert has_element?(view, "#team-next[href='/arenas']", "Next: Choose Arena")
    assert has_element?(view, "button[type='submit'][disabled]", "Save team")

    view
    |> form("#team-form",
      roles: %{speculator: %{name: "Planner", instructions: "Read docs first"}}
    )
    |> render_change()

    refute has_element?(view, "#team-next")

    Foundation.broadcast()
    assert has_element?(view, "#name-speculator[value='Planner']")
    assert has_element?(view, "#instructions-speculator", "Read docs first")
    view |> form("#team-form") |> render_submit()
    assert render(view) =~ "Team saved · revision 2"
    assert {:ok, again, _} = live(signed, "/team")
    assert has_element?(again, "#name-speculator[value='Planner']")
    assert has_element?(again, "#team-revision-1", "Speculator")
    refute Foundation.pending?()
  end

  test "recovered browser forms retain the original revision guard", %{conn: conn} do
    {:ok, _} = Team.save(Ecto.UUID.generate(), 1, Team.editable(Team.current()))
    {:ok, view, _} = conn |> sign_in() |> live("/team")

    render_change(view, "change", %{
      "base_revision" => "1",
      "roles" => %{"speculator" => %{"name" => "Recovered draft"}}
    })

    view |> form("#team-form") |> render_submit()
    assert render(view) =~ "A newer team was saved"
    assert has_element?(view, "#name-speculator[value='Recovered draft']")
    assert Team.current().id == 2
    render_submit(view, "save", %{"base_revision" => %{}, "roles" => %{}})
    assert render(view) =~ "Use unique role names"
  end

  test "Team repair retains its exact board through Save and explicit review", %{conn: conn} do
    %{board: board} = Cuckoding.PlanningFixtures.planning_fixture()
    signed = sign_in(conn)
    path = "/team?arena=#{board.arena_id}&tabula=#{board.id}"
    target = "/arenas/#{board.arena_id}/tabulae/#{board.id}#board-team"
    assigned = Cuckoding.TeamAssignments.assigned(board)
    {:ok, view, _} = live(signed, path)
    assert has_element?(view, "#team-board-context", board.name)
    assert has_element?(view, "#team-next[href='#{target}']", "Review team")
    view |> form("#team-form", roles: %{speculator: %{name: "Board planner"}}) |> render_change()
    Foundation.broadcast()
    assert has_element?(view, "#team-board-context", board.name)
    refute has_element?(view, "#team-next")
    view |> form("#team-form") |> render_submit()
    assert Cuckoding.TeamAssignments.assigned(board) == assigned
    assert has_element?(view, "#team-next[href='#{target}']", "Review team")
    result = view |> element("#team-next") |> render_click()
    {:ok, arena, _} = follow_redirect(result, signed)
    assert has_element?(arena, "#tabula-title", board.name)
    refute has_element?(arena, "#scope-team-form input[type=checkbox]")
    arena |> form("#scope-team-form") |> render_submit()
    assert Cuckoding.TeamAssignments.assigned(board).id == Team.current().id
    refute Foundation.pending?()
  end

  test "invalid, foreign or external Team context cannot choose a board or redirect", %{
    conn: conn
  } do
    %{board: board} = Cuckoding.PlanningFixtures.planning_fixture()
    signed = sign_in(conn)

    for query <- [
          "arena=bad&tabula=bad",
          "arena=#{Ecto.UUID.generate()}&tabula=#{board.id}",
          "return_to=https%3A%2F%2Fforeign.invalid",
          "arena[]=bad&tabula[]=bad"
        ] do
      {:ok, view, _} = live(signed, "/team?" <> query)
      refute has_element?(view, "#team-board-context")
      assert has_element?(view, "#team-next[href='/arenas']")
    end

    refute Foundation.pending?()
  end

  test "Save preserves an explicitly submitted agent/model pair and flags incomplete drafts", %{
    conn: conn
  } do
    Cuckoding.PlanningFixtures.planning_fixture()
    {:ok, view, _} = conn |> sign_in() |> live("/team")
    assert has_element?(view, "#team-incomplete", "Implementor, Secutor, Summa Rudis")

    roles =
      Map.new(
        Team.editable(Team.current()),
        &{&1["id"], %{"agent" => "codex", "model_id" => "test-id"}}
      )

    render_submit(view, "save", %{"roles" => roles})

    refute has_element?(view, "#team-error")
    refute has_element?(view, "#team-incomplete")
    assert Enum.all?(Team.current().definition["roles"], &(&1["model"] == "test-model"))
    assert has_element?(view, "#model-secutor option[value='test-id'][selected]")

    render_change(view, "change", %{"roles" => %{"secutor" => %{"agent" => ""}}})
    assert has_element?(view, "#model-secutor option[value=''][selected]")
    assert has_element?(view, "#team-incomplete", "Secutor")
    view |> form("#team-form") |> render_submit()
    assert has_element?(view, "#team-incomplete", "cannot run yet")

    render_submit(view, "save", %{
      "roles" => %{"secutor" => %{"agent" => "codex", "model_id" => "forged"}}
    })

    assert has_element?(view, "#team-error", "needs a current agent connection and model catalog")
    assert Enum.find(Team.current().definition["roles"], &(&1["id"] == "secutor"))["agent"] == ""
  end

  test "native form unused-field markers do not reject agent selection", %{conn: conn} do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, "/bin/sh", true)
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "0.146.0"})
    {:ok, view, _} = conn |> sign_in() |> live("/team")

    render_change(view, "change", %{
      "roles" => %{
        "speculator" => %{
          "name" => "Speculator",
          "instructions" => "Keep this text",
          "agent" => "codex",
          "_unused_name" => "",
          "_unused_instructions" => ""
        }
      }
    })

    refute has_element?(view, "#team-error")
    assert has_element?(view, "#agent-speculator option[value='codex'][selected]")
    refute has_element?(view, "#model-speculator[disabled]")
    view |> form("#team-form") |> render_submit()
    assert hd(Team.editable(Team.current()))["agent"] == "codex"
    assert hd(Team.editable(Team.current()))["instructions"] == "Keep this text"
  end

  test "stale editors keep drafts, errors and explicit discard confirmation", %{conn: conn} do
    {:ok, view, _} = conn |> sign_in() |> live("/team")
    view |> form("#team-form", roles: %{speculator: %{name: "My draft"}}) |> render_change()
    {:ok, _} = Team.save(Ecto.UUID.generate(), 1, Team.editable(Team.current()))
    assert render(view) =~ "Revision 2 is now saved"
    view |> form("#team-form") |> render_submit()
    assert has_element?(view, "[role='alert']", "A newer team was saved")
    Foundation.broadcast()
    assert has_element?(view, "#name-speculator[value='My draft']")
    view |> element("button", "Reload saved") |> render_click()
    assert render(view) =~ "Discard your unsaved draft"
    view |> element("button", "Keep editing") |> render_click()
    assert has_element?(view, "#name-speculator[value='My draft']")
    view |> element("button", "Reload saved") |> render_click()
    view |> element("button", "Discard draft and reload") |> render_click()
    assert has_element?(view, "#name-speculator[value='Speculator']")
    refute has_element?(view, "#team-error")
  end

  test "custom removal is confirmed and malformed client fields do not crash or save", %{
    conn: conn
  } do
    {:ok, view, _} = conn |> sign_in() |> live("/team")
    view |> element("button", "Add role") |> render_click()
    assert render(view) =~ "Custom · planning only · read-only"
    html = render(view)
    [_, id] = Regex.run(~r/id="name-([0-9a-f-]{36})"/, html)
    render_submit(view, "save", %{"roles" => %{id => %{"name" => "Research"}}})
    assert length(Team.editable(Team.current())) == 5
    view |> element("button[phx-value-id='#{id}']") |> render_click()
    view |> form("#team-form") |> render_submit()
    assert render(view) =~ "Confirm removal of saved custom roles"
    assert length(Team.editable(Team.current())) == 5
    view |> form("#team-form", confirm_removal: "true") |> render_submit()
    assert length(Team.editable(Team.current())) == 4
    render_submit(view, "save", %{"roles" => %{"speculator" => %{"name" => %{}}}})
    assert render(view) =~ "Use unique role names"
    assert Team.current().id == 3
  end
end
