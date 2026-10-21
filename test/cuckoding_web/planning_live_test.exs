defmodule CuckodingWeb.PlanningLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  import Cuckoding.PlanningFixtures
  alias Cuckoding.{Foundation, Planning, Tabulae}
  setup do: planning_fixture()

  test "another saved role is optional, clears consent and preserves text before creating tasks",
       %{conn: conn, board: board} do
    %{role: role, board: board} = add_planning_role(board)
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{board.arena_id}/tabulae/#{board.id}")
    assert has_element?(view, "#planning-role-select option[value=speculator][selected]")
    view |> form("#draft-form", title: "Keep this manual draft") |> render_change()
    view |> form("#documents-form", paths: "docs/plan.md") |> render_submit()
    {:ok, source} = Foundation.claim()
    Foundation.finish(source, document_receipt())
    view |> form("#planning-form", brief: "Keep this plan", confirmed: "true") |> render_change()
    view |> form("#planning-role-form", role_id: role["id"]) |> render_change()
    assert has_element?(view, "#planning-role-select option[value='#{role["id"]}'][selected]")
    assert has_element?(view, "#planning-brief", "Keep this plan")
    refute has_element?(view, "#planning-form input[name=confirmed][checked]")
    Foundation.broadcast()
    assert has_element?(view, "#draft-title-input[value='Keep this manual draft']")
    assert has_element?(view, "#planning-role-select option[value='#{role["id"]}'][selected]")
    view |> form("#planning-form", confirmed: "true") |> render_submit()
    command = hd(Planning.history(board.id))
    assert command.payload["role"]["id"] == role["id"]
    assert command.payload["document_preview_id"] == source.id
    assert hd(command.payload["documents"])["text"] == "# Selected plan\nBuild a small feature."
    assert has_element?(view, "#plan-#{command.id} h3", "Researcher")
  end

  test "a foreign role cannot silently select Speculator and expired role controls are guarded",
       %{conn: conn, board: board} do
    %{role: role, board: board} = add_planning_role(board)
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{board.arena_id}/tabulae/#{board.id}")
    view |> form("#planning-role-form", role_id: role["id"]) |> render_change()
    view |> element("#planning-role-form") |> render_change(%{"role_id" => Ecto.UUID.generate()})
    assert has_element?(view, "#planning-role-select option[value='#{role["id"]}'][selected]")
    assert has_element?(view, "#planning-error", "Choose a saved role")
    assert Planning.history(board.id) == []
    Cuckoding.Repo.update_all(Cuckoding.BrowserToken, set: [expires_at: 0])
    view |> form("#planning-role-form", role_id: "speculator") |> render_change()
    assert_redirect(view, "/locked")
  end

  test "removing the selected role leaves an unavailable choice and clears consent without losing the brief",
       %{conn: conn, board: board} do
    alias Cuckoding.{Team, TeamAssignments}
    %{role: role, board: board} = add_planning_role(board)
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{board.arena_id}/tabulae/#{board.id}")
    view |> form("#planning-role-form", role_id: role["id"]) |> render_change()
    view |> form("#planning-form", brief: "Keep this work", confirmed: "true") |> render_change()
    team = Team.current()

    {:ok, team} =
      Team.save(
        Ecto.UUID.generate(),
        team.id,
        Enum.reject(Team.editable(team), &(&1["id"] == role["id"])),
        true
      )

    {:ok, _} =
      TeamAssignments.adopt(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        TeamAssignments.assigned(board).id,
        team.id,
        true
      )

    assert has_element?(
             view,
             "#planning-role-select option[selected][disabled]",
             "Selected role unavailable"
           )

    assert has_element?(view, "#planning-brief", "Keep this work")
    refute has_element?(view, "#planning-form input[name=confirmed][checked]")
    assert has_element?(view, "#planning-form button[disabled]")
    assert Planning.history(board.id) == []
  end

  test "the Cursor Speculator uses the same consented Create tasks dialog and retains drafts", %{
    conn: conn,
    board: board
  } do
    %{agent: agent, board: board} = cursor_speculator(board)
    signed = sign_in(conn)
    path = "/arenas/#{board.arena_id}/tabulae/#{board.id}"
    {:ok, view, _} = live(signed, path)
    refute has_element?(view, "#brief-planning .notice", "Choose a connected")
    view |> form("#draft-form", title: "Keep my manual draft") |> render_change()

    view
    |> form("#planning-form", brief: "Plan with Cursor", confirmed: "true")
    |> render_submit()

    command = hd(Planning.history(board.id))
    assert command.payload["agent_id"] == agent.id
    assert command.payload["kind"] == "cursor"
    assert has_element?(view, "#plan-#{command.id}", "Cursor · cursor-fixture")
    refute has_element?(view, "#plan-#{command.id}", "Codex · cursor-fixture")
    {:ok, claim} = Foundation.claim()

    assert {:ok, %{state: "completed"}} =
             Foundation.finish(claim, cursor_planning_receipt(command.id))

    task = hd(Tabulae.tasks(board.id))
    assert has_element?(view, "#column-specs #task-#{task.id}")
    assert has_element?(view, "#draft-title-input[value='Keep my manual draft']")
    assert has_element?(view, "#plan-#{command.id}", "Tasks created")
    {:ok, again, _} = live(signed, path)
    assert has_element?(again, "#column-specs #task-#{task.id}")
    assert Planning.history(board.id) |> length() == 1
  end

  test "expired sessions cannot launch component-targeted planning", %{conn: conn, board: board} do
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{board.arena_id}/tabulae/#{board.id}")
    Cuckoding.Repo.update_all(Cuckoding.BrowserToken, set: [expires_at: 0])
    view |> form("#planning-form", brief: "No authority", confirmed: "true") |> render_submit()
    assert_redirect(view, "/locked")
    assert Planning.history(board.id) == []
  end

  test "Create tasks saves cards automatically and preserves unrelated draft text on updates", %{
    conn: conn,
    board: board
  } do
    signed = sign_in(conn)
    path = "/arenas/#{board.arena_id}/tabulae/#{board.id}"
    {:ok, view, _} = live(signed, path)
    assert has_element?(view, "#brief-planning[phx-mounted*=ignore_attrs]")
    assert has_element?(view, "#planning-form button", "Create tasks")
    view |> form("#draft-form", title: "Unsaved manual task") |> render_change()
    view |> form("#planning-form", brief: "A small feature") |> render_submit()
    assert has_element?(view, "#planning-error", "confirm provider usage")
    view |> form("#planning-form", confirmed: "true") |> render_submit()
    command = hd(Planning.history(board.id))
    assert command.state == "pending"
    assert has_element?(view, "#plan-#{command.id}", "Codex · test-model")
    assert has_element?(view, "#plan-#{command.id} button", "Cancel planning")
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, planning_receipt(command.id))
    assert has_element?(view, "#plan-#{command.id}", "A proposed task")

    refute has_element?(view, "#plan-#{command.id} button", "Add to Specs")
    task = hd(Tabulae.tasks(board.id))
    assert has_element?(view, "#column-specs #task-#{task.id}")
    assert has_element?(view, "#draft-title-input[value='Unsaved manual task']")
    assert has_element?(view, "#planning-brief", "A small feature")
    assert has_element?(view, "#plan-#{command.id}", "Tasks created")
    {:ok, again, _} = live(signed, path)
    assert has_element?(again, "#plan-#{command.id}", "A proposed task")
    assert has_element?(again, "#column-specs #task-#{task.id}")
    assert has_element?(again, "#plan-#{command.id}", "Tasks created")
    assert length(Tabulae.tasks(board.id)) == 1
  end

  test "changed connection clears consent while retaining the brief; cancellation remains visible",
       %{conn: conn, board: board} do
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{board.arena_id}/tabulae/#{board.id}")
    view |> form("#planning-form", brief: "Keep this brief", confirmed: "true") |> render_change()
    connection = Map.put(Foundation.workspace().connection, "command_id", Ecto.UUID.generate())

    Foundation.workspace()
    |> Ecto.Changeset.change(connection: connection)
    |> Cuckoding.Repo.update!()

    Foundation.broadcast()
    refute has_element?(view, "#planning-form input[name=confirmed][checked]")
    assert has_element?(view, "#planning-brief", "Keep this brief")
    view |> form("#planning-form", confirmed: "true") |> render_submit()
    command = hd(Planning.history(board.id))
    {:ok, claim} = Foundation.claim()
    view |> element("#plan-#{command.id} button", "Cancel planning") |> render_click()
    assert has_element?(view, "#plan-#{command.id}", "cancelling")
    Foundation.finish(claim, planning_receipt(command.id))
    assert has_element?(view, "#plan-#{command.id}", "Planning cancelled")
    refute has_element?(view, "#plan-#{command.id}", "A proposed task")
  end

  test "document preview is local and selection changes clear consent without losing text", %{
    conn: conn,
    board: board
  } do
    signed = sign_in(conn)
    path = "/arenas/#{board.arena_id}/tabulae/#{board.id}"
    {:ok, view, _} = live(signed, path)
    view |> form("#draft-form", title: "Keep draft") |> render_change()
    view |> form("#planning-form", brief: "Keep brief", confirmed: "true") |> render_change()
    view |> form("#documents-form", paths: "docs/plan.md") |> render_change()
    refute has_element?(view, "#planning-form input[name=confirmed][checked]")
    view |> form("#documents-form", paths: "docs/plan.md") |> render_submit()
    assert Planning.history(board.id) == []
    assert has_element?(view, "#document-preview button", "Cancel preview")
    {:ok, claim} = Foundation.claim()

    Foundation.finish(
      claim,
      document_receipt("docs/plan.md", "<script>untrusted source</script>")
    )

    assert has_element?(view, "#document-preview pre", "<script>untrusted source</script>")
    refute has_element?(view, "#document-preview script")
    assert has_element?(view, "#document-preview details[phx-mounted*=ignore_attrs]")
    assert has_element?(view, "#planning-brief", "Keep brief")
    assert has_element?(view, "#draft-title-input[value='Keep draft']")
    view |> form("#planning-form", confirmed: "true") |> render_change()
    view |> element("button", "Use brief only") |> render_click()
    refute has_element?(view, "#planning-form input[name=confirmed][checked]")
    view |> element("button", "Use these snapshots") |> render_click()
    view |> form("#planning-form", confirmed: "true") |> render_submit()
    plan = hd(Planning.history(board.id))
    assert plan.payload["document_preview_id"] == claim.id
    assert length(plan.payload["documents"]) == 1
    {:ok, again, _} = live(signed, path)
    assert has_element?(again, "#document-preview", "Snapshots saved locally")
    assert has_element?(again, "#plan-#{plan.id} pre", "untrusted source")
    assert has_element?(again, "#document-selection", "Brief only")
  end

  test "expired component sessions cannot read selected documents", %{conn: conn, board: board} do
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{board.arena_id}/tabulae/#{board.id}")
    Cuckoding.Repo.update_all(Cuckoding.BrowserToken, set: [expires_at: 0])
    view |> form("#documents-form", paths: "docs/plan.md") |> render_submit()
    assert_redirect(view, "/locked")
    assert Cuckoding.PlanningDocuments.latest(board.id) == nil
  end

  test "folder read keeps drafts, reports limits, and sends snapshots only after consent", %{
    conn: conn,
    board: board
  } do
    signed = sign_in(conn)
    path = "/arenas/#{board.arena_id}/tabulae/#{board.id}"
    {:ok, view, _} = live(signed, path)
    view |> form("#draft-form", title: "Keep draft") |> render_change()
    view |> element("button", "Read project folder") |> render_click()
    assert Planning.history(board.id) == []
    assert has_element?(view, "#document-preview button", "Cancel preview")
    {:ok, claim} = Foundation.claim()

    receipt =
      folder_receipt()
      |> put_in(["scan", "visited"], 18)
      |> put_in(["scan", "limited"], true)
      |> put_in(["scan", "skipped"], %{"limit" => 2})

    Foundation.finish(claim, receipt)
    assert has_element?(view, "#folder-scan-summary", "16 source snapshots")
    assert has_element?(view, "#folder-scan-summary", "partial view")
    assert has_element?(view, "#draft-title-input[value='Keep draft']")
    refute has_element?(view, "#planning-form input[name=confirmed][checked]")
    view |> form("#planning-form", brief: "", confirmed: "true") |> render_submit()
    assert length(hd(Planning.history(board.id)).payload["documents"]) == 16
    {:ok, again, _} = live(signed, path)
    assert has_element?(again, "#folder-scan-summary", "16 source snapshots")
    assert has_element?(again, "#document-selection", "Brief only")
  end

  test "folder snapshots stay ready when the provider setup is unavailable", %{
    conn: conn,
    board: board
  } do
    Foundation.workspace()
    |> Ecto.Changeset.change(connection: %{})
    |> Cuckoding.Repo.update!()

    assert Planning.setup(board).token == nil
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{board.arena_id}/tabulae/#{board.id}")
    view |> element("button", "Read project folder") |> render_click()
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, folder_receipt())
    assert view |> element("#document-selection") |> render() =~ "Snapshots are ready locally"
    assert has_element?(view, "#planning-form button[disabled]", "Create tasks")
  end

  test "expired component sessions cannot scan the folder", %{conn: conn, board: board} do
    {:ok, view, _} = conn |> sign_in() |> live("/arenas/#{board.arena_id}/tabulae/#{board.id}")
    Cuckoding.Repo.update_all(Cuckoding.BrowserToken, set: [expires_at: 0])
    view |> element("button", "Read project folder") |> render_click()
    assert_redirect(view, "/locked")
    assert Cuckoding.PlanningDocuments.latest(board.id) == nil
  end

  test "linked suggestions show source snapshots, gate imports and retain original provenance", %{
    conn: conn,
    board: board
  } do
    claim = document_plan_fixture(board) |> legacy_plan_fixture()
    {:ok, _} = Foundation.finish(claim, linked_planning_receipt(claim.id))
    path = "/arenas/#{board.arena_id}/tabulae/#{board.id}"
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, path)
    view |> form("#draft-form", title: "Keep my manual draft") |> render_change()

    assert has_element?(
             view,
             "#proposal-#{claim.id}-1",
             "Prerequisites: Specify response"
           )

    assert has_element?(view, "#proposal-sources-#{claim.id}-1-0 pre", "Selected plan")
    view |> element("#proposal-#{claim.id}-1 button", "Add to Specs") |> render_click()
    assert has_element?(view, "#planning-error", "prerequisites to Specs first")
    assert Tabulae.tasks(board.id) == []
    view |> element("#proposal-#{claim.id}-0 button", "Add to Specs") |> render_click()
    view |> element("#proposal-#{claim.id}-1 button", "Add to Specs") |> render_click()
    [first, second] = Tabulae.tasks(board.id)
    assert second.depends_on == [first.id]
    assert has_element?(view, "#draft-title-input[value='Keep my manual draft']")
    {:ok, again, _} = live(signed, path)
    again |> element("button[aria-label='Edit Implement response']") |> render_click()
    assert has_element?(again, "#draft-source", "Original proposal sources")
    assert has_element?(again, "#draft-source-document-0", "docs/plan.md")
    assert has_element?(again, "#draft-source-document-0 pre", "Build a small feature")
    again |> form("#draft-form", title: "Edited implementation") |> render_submit()
    again |> element("button[aria-label='Edit Edited implementation']") |> render_click()
    assert has_element?(again, "#draft-source-document-0 pre", "Build a small feature")
    assert has_element?(again, "#draft-source[phx-mounted*=ignore_attrs]")
    Cuckoding.Repo.update_all(Cuckoding.BrowserToken, set: [expires_at: 0])
    again |> element("#proposal-#{claim.id}-2 button", "Add to Specs") |> render_click()
    assert_redirect(again, "/locked")
    assert length(Tabulae.tasks(board.id)) == 2
  end
end
