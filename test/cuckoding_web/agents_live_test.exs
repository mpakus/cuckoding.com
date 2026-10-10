defmodule CuckodingWeb.AgentsLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Cuckoding.{Agents, Foundation, Repo, Team}

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
    wizard |> form("#connection-check") |> render_submit(%{"consent_key" => "recovered"})
    refute Foundation.pending?()
    wizard |> form("#connection-check") |> render_submit()
    {:ok, claim} = Foundation.claim()
    assert claim.payload["agent_id"] == cursor.id
    assert claim.kind == "inspect_cursor"

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

      view |> form("#connection-check") |> render_submit()
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
