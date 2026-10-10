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
    {:ok, roster, _} = live(signed, "/settings")
    assert has_element?(roster, "#agent-codex", "Codex")
    assert has_element?(roster, "a[href='/settings/new']", "Add agent")
    {:ok, view, _} = live(signed, "/settings/new")

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
    {:ok, wizard, _} = follow_redirect(result, signed, "/settings/#{cursor.id}")
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
    {:ok, view, _} = live(signed, "/settings/#{id}")
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
    {:ok, other, _} = live(signed, "/settings/codex")
    refute has_element?(other, "#agent-progress")
    Foundation.cancel_probe(claim.id)
    assert get(signed, "/codex/login/#{claim.id}") |> response(410)
    Foundation.finish(claim, %{"status" => "cancelled"})
    assert Repo.get!(Cuckoding.Command, claim.id).state == "cancelled"
  end

  defp model(id),
    do: %{"id" => id, "model" => id, "name" => id, "default" => true, "hidden" => false}
end
