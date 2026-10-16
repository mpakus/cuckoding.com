defmodule CuckodingWeb.AgentsLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Cuckoding.{Agents, Foundation, Repo, Team}

  test "new Cursor defaults need no typed name or path and discovery executes nothing", %{
    conn: conn
  } do
    root = "/private/tmp/cuckoding-agent-defaults-#{Ecto.UUID.generate()}"
    directory = Path.join(root, ".local/bin")
    File.mkdir_p!(directory)
    path = Path.join(directory, "cursor-agent")
    marker = Path.join(root, "executed")
    File.write!(path, "#!/bin/sh\ntouch #{marker}\n")
    File.chmod!(path, 0o700)
    previous = Application.get_env(:cuckoding, :discovery_home)
    Application.put_env(:cuckoding, :discovery_home, root)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cuckoding, :discovery_home, previous),
        else: Application.delete_env(:cuckoding, :discovery_home)

      File.rm_rf!(root)
    end)

    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/agents/new")
    assert has_element?(view, "#agent-name[type=text][value=Codex]")
    view |> form("#codex-check", agent: "cursor") |> render_change()
    assert has_element?(view, "#agent-name[value=Cursor]")
    assert has_element?(view, "#codex-path[value='#{path}']")
    refute has_element?(view, "#executable-details[open]")
    refute File.exists?(marker)
    refute Foundation.pending?()
    view |> form("#codex-check", name: "My planner", path: "/bin/sh") |> render_change()
    send(view.pid, :clock)
    assert has_element?(view, "#agent-name[value='My planner']")
    assert has_element?(view, "#codex-path[value='/bin/sh']")
    view |> form("#codex-check", agent: "codex") |> render_change()
    assert has_element?(view, "#agent-name[value='My planner']")

    {:ok, fresh, _} = live(signed, "/agents/new")
    fresh |> form("#codex-check", agent: "cursor") |> render_change()
    result = fresh |> form("#codex-check") |> render_submit()
    [cursor] = Agents.list()
    assert cursor.name == "Cursor"
    assert cursor.codex["path"] == nil
    {:ok, wizard, _} = follow_redirect(result, signed)
    {:ok, probe} = Foundation.claim()
    assert probe.payload["path"] == path
    Foundation.finish(probe, %{"status" => "supported", "version" => "2026.09.15-d2fe57e"})
    refute has_element?(wizard, "#connection-check")
    wizard |> form("#codex-login") |> render_submit()
    {:ok, login} = Foundation.claim()
    assert login.kind == "login_cursor"
    assert login.payload["agent_id"] == cursor.id

    Foundation.finish(login, %{
      "status" => "checked",
      "authorization" => "cursor",
      "catalog_status" => "fresh",
      "models" => [model("fixture-model")]
    })

    assert has_element?(wizard, "#wizard-models")
    refute File.exists?(marker)
  end

  test "signed-out Codex can disconnect and unassign after its executable changes", %{conn: conn} do
    ctx = Cuckoding.PlanningFixtures.planning_fixture()

    {:ok, _} =
      Foundation.inspect_codex(Ecto.UUID.generate(), Foundation.workspace().revision, true)

    {:ok, inspection} = Foundation.claim()

    Foundation.finish(inspection, %{
      "status" => "checked",
      "authorization" => "not_connected",
      "catalog_status" => "not_requested",
      "models" => []
    })

    File.rename!(ctx.path, ctx.path <> ".old")
    File.write!(ctx.path, "#!/bin/sh\nexit 1\n")
    File.chmod!(ctx.path, 0o700)
    assert {:error, :version_required} = Foundation.verified_executable()
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/agents")
    before = Team.current()
    view |> form("#disconnect-form-codex") |> render_submit(%{"key" => "recovered"})
    assert Team.current() == before
    view |> form("#disconnect-form-codex") |> render_submit()
    assert has_element?(view, "[role=status]", "Disconnected locally")
    assert has_element?(view, "[role=status]", "Provider sign-out was not attempted")
    assert has_element?(view, "#agent-codex button[disabled]", "Disconnected")
    assert hd(Team.current().definition["roles"])["agent"] == ""
    assert hd(Cuckoding.TeamAssignments.assigned(ctx.board).definition["roles"])["agent"] == ""
    assert {:ok, nil} = Foundation.claim()
    send(view.pid, :catalog_tick)
    assert has_element?(view, "[role=status]", "Disconnected locally")
    {:ok, reconnected, _} = live(signed, "/agents")
    assert has_element?(reconnected, "#agent-codex button[disabled]", "Disconnected")
  end

  test "roster Disconnect is scoped, guarded and unassigns only its named agent", %{conn: conn} do
    ctx = Cuckoding.PlanningFixtures.planning_fixture()

    {:ok, command} =
      Agents.add_and_probe(
        Ecto.UUID.generate(),
        Foundation.workspace().revision,
        "Writer",
        "cursor",
        "/bin/sh"
      )

    id = command.payload["agent_id"]
    {:ok, probe} = Foundation.claim()
    Foundation.finish(probe, %{"status" => "supported", "version" => "2026.09.15-d2fe57e"})

    {:ok, _} =
      Foundation.inspect_codex(Ecto.UUID.generate(), Foundation.workspace().revision, true, id)

    {:ok, claim} = Foundation.claim()

    Foundation.finish(claim, %{
      "status" => "checked",
      "authorization" => "cursor",
      "catalog_status" => "fresh",
      "models" => [model("writer-model")]
    })

    {:ok, _} =
      Foundation.save_agent_models(
        Ecto.UUID.generate(),
        Foundation.workspace().revision,
        Agents.get(id).connection["command_id"],
        ["writer-model"],
        id
      )

    roles =
      Team.editable(Team.current())
      |> List.update_at(1, &Map.merge(&1, %{"agent" => id, "model_id" => "writer-model"}))

    {:ok, team} = Team.save(Ecto.UUID.generate(), Team.current().id, roles)

    {:ok, _} =
      Cuckoding.TeamAssignments.adopt(
        Ecto.UUID.generate(),
        ctx.arena.id,
        ctx.board.id,
        ctx.board.team_revision_id,
        team.id,
        true
      )

    legacy = Agents.get("codex")
    {:ok, view, _} = conn |> sign_in() |> live("/agents")
    assert has_element?(view, "button[aria-label='Disconnect Writer']")
    assert has_element?(view, "dialog#disconnect-#{id}[phx-hook=Dialog]")
    view |> form("#disconnect-form-#{id}") |> render_submit(%{"key" => "old-form"})
    refute Foundation.pending?()
    assert Team.current() == team
    view |> form("#disconnect-form-#{id}") |> render_submit()
    assert has_element?(view, "[role=status]", "roles are now unassigned")
    assert Agents.get("codex") == legacy
    assert hd(Team.current().definition["roles"])["agent"] == "codex"
    assert Enum.at(Team.current().definition["roles"], 1)["agent"] == ""
    assigned = Cuckoding.TeamAssignments.assigned(ctx.board)
    assert hd(assigned.definition["roles"])["agent"] == "codex"
    assert Enum.at(assigned.definition["roles"], 1)["model_id"] == ""
    {:ok, logout} = Foundation.claim()
    assert logout.payload["agent_id"] == id
    assert logout.kind == "logout_cursor"
  end

  test "expired roster sessions cannot disconnect", %{conn: conn} do
    Cuckoding.PlanningFixtures.planning_fixture()
    {:ok, view, _} = conn |> sign_in() |> live("/agents")
    team = Team.current()
    Repo.update_all(Cuckoding.BrowserToken, set: [expires_at: 0])
    view |> form("#disconnect-form-codex") |> render_submit()
    assert_redirect(view, "/locked")
    refute Foundation.pending?()
    assert Team.current() == team
  end

  test "roster adds a named Cursor connection without replacing Codex and scopes recovered forms",
       %{conn: conn} do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, "/bin/sh", true)
    {:ok, probe} = Foundation.claim()
    Foundation.finish(probe, %{"status" => "supported", "version" => "0.146.0"})
    signed = sign_in(conn)
    {:ok, roster, _} = live(signed, "/agents")
    assert has_element?(roster, "#agent-codex", "Codex")
    assert has_element?(roster, "a[href='/agents/new']", "Add agent")
    {:ok, view, _} = live(signed, "/agents/new")

    view
    |> form("#codex-check", name: "Planner", agent: "cursor", path: "/bin/sh")
    |> render_change()

    assert has_element?(view, "#agent-choice option[value=cursor][selected]")
    assert has_element?(view, "#agent-name[value=Planner]")

    result =
      view
      |> form("#codex-check", name: "Planner", agent: "cursor", path: "/bin/sh")
      |> render_submit()

    [_, cursor] = Agents.list()
    {:ok, wizard, _} = follow_redirect(result, signed, "/agents/#{cursor.id}")
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "2026.09.15-d2fe57e"})
    assert has_element?(wizard, "#codex-login button", "Sign in with Cursor")
    assert Agents.get("codex").connection == %{}
    refute has_element?(wizard, "#connection-check")
    wizard |> form("#codex-login") |> render_submit(%{"consent_key" => "recovered"})
    refute Foundation.pending?()
    wizard |> form("#codex-login") |> render_submit()
    {:ok, claim} = Foundation.claim()
    assert claim.payload["agent_id"] == cursor.id
    assert claim.kind == "login_cursor"

    Foundation.finish(claim, %{
      "status" => "checked",
      "authorization" => "cursor",
      "catalog_status" => "fresh",
      "models" => [model("grok-fixture")]
    })

    assert has_element?(wizard, "#wizard-models")
    refute has_element?(wizard, "#model-diagnostic")
    wizard |> form("#model-selection", model_ids: ["grok-fixture"]) |> render_change()
    send(wizard.pid, :clock)
    assert has_element?(wizard, "#model-selection input[value='grok-fixture'][checked]")
    wizard |> form("#model-selection", model_ids: ["grok-fixture"]) |> render_submit()
    wizard |> form("#save-models") |> render_submit()
    assert has_element?(wizard, "#wizard-save .subtle", "Cursor · 1 selected models")
    assert Foundation.saved_agent_models(cursor.id).payload["model_ids"] == ["grok-fixture"]
    assert Foundation.saved_agent_models() == nil
    assert has_element?(roster, "#agent-#{cursor.id}", "1 selected models")
    {:ok, team, _} = live(signed, "/team")

    team
    |> form("#team-form", roles: %{"speculator" => %{"agent" => cursor.id}})
    |> render_change()

    assert has_element?(team, "#model-speculator option[value='grok-fixture']")
    refute has_element?(team, "#model-implementor option[value='grok-fixture']")

    team
    |> form("#team-form", roles: %{"speculator" => %{"model_id" => "grok-fixture"}})
    |> render_change()

    team |> form("#team-form") |> render_submit()
    assert hd(Team.current().definition["roles"])["agent"] == cursor.id
    team |> form("#team-form", roles: %{"speculator" => %{"agent" => "codex"}}) |> render_change()
    refute has_element?(team, "#model-speculator option[value='grok-fixture']")
  end

  test "Cursor's full variant catalog can be selected, saved and assigned to a role", %{
    conn: conn
  } do
    {:ok, command} = Agents.add_and_probe(Ecto.UUID.generate(), 0, "Cursor", "cursor", "/bin/sh")
    id = command.payload["agent_id"]
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "2026.09.15-d2fe57e"})
    {:ok, view, _} = conn |> sign_in() |> live("/agents/#{id}")
    view |> form("#codex-login") |> render_submit()
    {:ok, claim} = Foundation.claim()
    rows = for index <- 1..512, do: model("variant-#{index}")

    receipt =
      %{
        "status" => "checked",
        "authorization" => "cursor",
        "catalog_status" => "fresh",
        "models" => rows
      }
      |> Jason.encode!()
      |> Cuckoding.Cursor.normalize_connection()

    Foundation.finish(claim, receipt)
    assert has_element?(view, "#model-selection input[value='variant-512']")
    ids = Enum.map(rows, & &1["id"])
    view |> form("#model-selection", model_ids: ids) |> render_submit()
    view |> form("#save-models") |> render_submit()
    assert Foundation.saved_agent_models(id).payload["model_ids"] == Enum.sort(ids)
    assert length(Team.catalog(id).selectable_models) == 512

    roles =
      Team.editable(Team.current())
      |> List.update_at(0, &Map.merge(&1, %{"agent" => id, "model_id" => "variant-512"}))

    assert {:ok, _} = Team.save(Ecto.UUID.generate(), Team.current().id, roles)

    assert {:error, :invalid_models} =
             Foundation.save_agent_models(
               Ecto.UUID.generate(),
               Foundation.workspace().revision,
               Agents.get(id).connection["command_id"],
               ids ++ ["overflow"],
               id
             )
  end

  test "Cursor sign-in URL stays behind the session and cannot cross into another agent", %{
    conn: conn
  } do
    Cuckoding.Codex.init_login_links()
    {:ok, command} = Agents.add_and_probe(Ecto.UUID.generate(), 0, "Cursor", "cursor", "/bin/sh")
    id = command.payload["agent_id"]
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "2026.09.15-d2fe57e"})
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/agents/#{id}")
    view |> form("#codex-login") |> render_submit()
    {:ok, claim} = Foundation.claim()
    Foundation.login_waiting(claim)
    url = "https://cursor.com/loginDeepControl?uuid=private-fixture"
    Cuckoding.Codex.put_login_link(claim.id, url, "cursor")
    Foundation.broadcast()
    assert has_element?(view, "a[href='/codex/login/#{claim.id}']", "Continue at Cursor")
    refute render(view) =~ "private-fixture"
    assert redirected_to(get(signed, "/codex/login/#{claim.id}")) == url
    assert get(conn, "/codex/login/#{claim.id}") |> response(401)
    {:ok, other, _} = live(signed, "/agents/codex")
    refute has_element?(other, "#agent-progress")
    Foundation.cancel_probe(claim.id)
    assert get(signed, "/codex/login/#{claim.id}") |> response(410)
    Foundation.finish(claim, %{"status" => "cancelled"})
    assert Repo.get!(Cuckoding.Command, claim.id).state == "cancelled"
  end

  for kind <- ~w(codex cursor) do
    test "#{kind} keeps Next visible and recovers a failed catalog on the models step", %{
      conn: conn
    } do
      kind = unquote(kind)
      authorization = if kind == "codex", do: "chatgpt", else: "cursor"
      version = if kind == "codex", do: "0.146.0", else: "2026.09.15-d2fe57e"
      {:ok, command} = Agents.add_and_probe(Ecto.UUID.generate(), 0, "Planner", kind, "/bin/sh")
      id = command.payload["agent_id"]
      {:ok, claim} = Foundation.claim()
      Foundation.finish(claim, %{"status" => "supported", "version" => version})
      {:ok, view, _} = conn |> sign_in() |> live("/agents/#{id}")
      assert has_element?(view, "#connect-next[disabled]", "Next: Select models")
      assert has_element?(view, "#connect-next-hint", "Connect your account")
      render_click(view, "step", %{"step" => "3"})
      assert has_element?(view, "#wizard-connect")
      refute has_element?(view, "#wizard-models")

      view |> form("#codex-login") |> render_submit()
      assert has_element?(view, "#connect-next[disabled]")
      {:ok, claim} = Foundation.claim()

      Foundation.finish(claim, %{
        "status" => "checked",
        "authorization" => authorization,
        "catalog_status" => "failed"
      })

      assert has_element?(view, "#wizard-connect", "model list is unavailable or out of date")
      assert has_element?(view, "#connect-next:not([disabled])")
      commands = Repo.aggregate(Cuckoding.Command, :count)
      view |> element("#connect-next") |> render_click()
      assert has_element?(view, "#wizard-models")
      assert Repo.aggregate(Cuckoding.Command, :count) == commands
      assert has_element?(view, "#model-selection fieldset[disabled]")
      assert has_element?(view, "#model-selection button[disabled]", "Review selection")
      render_submit(view, "review_models", %{"model_ids" => ["invented-model"]})
      refute has_element?(view, "#wizard-save")
      send(view.pid, :clock)
      assert has_element?(view, "#wizard-models")

      view |> form("#models-refresh") |> render_submit(%{"consent_key" => "recovered"})
      refute Foundation.pending?()
      view |> form("#models-refresh") |> render_submit()
      assert has_element?(view, "#models-refresh button[disabled]")
      {:ok, claim} = Foundation.claim()
      assert claim.kind == "inspect_#{kind}"
      assert claim.payload["agent_id"] == id

      Foundation.finish(claim, %{
        "status" => "checked",
        "authorization" => authorization,
        "catalog_status" => "fresh",
        "models" => [model("fixture-model")]
      })

      refute has_element?(view, "#models-refresh")
      assert has_element?(view, "#model-selection input[value=fixture-model]")
      view |> form("#model-selection", model_ids: ["fixture-model"]) |> render_change()
      view |> element("#wizard-models button", "Back") |> render_click()
      view |> element("#connect-next") |> render_click()
      assert has_element?(view, "#model-selection input[value=fixture-model][checked]")
      view |> form("#model-selection", model_ids: ["fixture-model"]) |> render_submit()
      view |> form("#save-models") |> render_submit()
      assert Foundation.saved_agent_models(id).payload["model_ids"] == ["fixture-model"]
      refute Foundation.pending?()
    end
  end

  defp model(id),
    do: %{
      "id" => id,
      "model" => id,
      "name" => id,
      "default" => true,
      "hidden" => false,
      "efforts" => ["low"],
      "default_effort" => "low",
      "input_modalities" => ["text"]
    }
end
