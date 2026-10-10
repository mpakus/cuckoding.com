defmodule CuckodingWeb.FoundationLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Cuckoding.{BrowserToken, Foundation, Repo, ShellAuth}

  test "foreign hosts, origins, ports and shell callers are rejected", %{conn: conn} do
    assert conn |> Map.put(:host, "evil.test") |> get("/") |> response(403)
    assert conn |> Map.put(:port, 9000) |> get("/") |> response(403)
    assert conn |> put_req_header("origin", "https://evil.test") |> get("/") |> response(403)
    assert conn |> put_req_header("origin", "null") |> get("/") |> response(403)
    assert conn |> put_req_header("sec-fetch-site", "cross-site") |> get("/") |> response(403)
    assert conn |> post("/shell/open") |> response(401)
    refute CuckodingWeb.Boundary.allowed_origin?(URI.parse("http://127.0.0.1:9000"))
    assert CuckodingWeb.Boundary.allowed_origin?(URI.parse("http://127.0.0.1:4002"))
  end

  test "browser handoff is single-use and cannot redirect off-host", %{conn: conn} do
    handoff = ShellAuth.handoff()
    opened = get(conn, "/open", token: handoff, view: "https://evil.test")
    assert redirected_to(opened) == "/"
    assert get_resp_header(opened, "referrer-policy") == ["no-referrer"]
    assert get_resp_header(opened, "cache-control") == ["no-store"]
    assert get(conn, "/open", token: handoff) |> response(401)
    assert get(conn, "/open") |> response(401)
    assert get_session(opened, :session_id)
  end

  test "wizard has four steps, requires a live form and preserves the chosen executable", %{
    conn: conn
  } do
    assert {:error, {:redirect, %{to: "/locked"}}} = live(conn, "/settings")
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/settings/codex")
    assert has_element?(view, ".wizard-steps li", "Choose Agent")
    assert has_element?(view, ".wizard-steps li", "Connect and Authorize")
    assert has_element?(view, ".wizard-steps li", "Select models")
    assert has_element?(view, ".wizard-steps li", "Save")
    refute has_element?(view, "input[type=checkbox]")
    view |> form("#codex-check", path: "/bin/sh") |> render_change()
    send(view.pid, :clock)
    Foundation.broadcast()
    assert has_element?(view, "#codex-path[value='/bin/sh']")

    view
    |> form("#codex-check", path: "/bin/sh")
    |> render_submit(%{"consent_key" => "recovered"})

    refute Foundation.pending?()
    view |> form("#codex-check", path: "/bin/sh") |> render_submit()
    assert has_element?(view, "#agent-progress button", "Cancel")
    {:ok, probe} = Foundation.claim()
    Foundation.finish(probe, %{"status" => "supported", "version" => "0.146.0"})
    assert has_element?(view, "#wizard-connect")
    assert {:ok, again, _} = live(signed, "/settings/codex")
    assert has_element?(again, "#wizard-connect")
  end

  test "expired authority cannot submit or receive live updates", %{conn: conn} do
    {:ok, view, _} = conn |> sign_in() |> live("/settings/codex")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> form("#codex-check", path: "/bin/sh") |> render_submit()
    assert_redirect(view, "/locked")
    refute Foundation.pending?()
    {:ok, view, _} = conn |> sign_in() |> live("/settings/codex")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    Foundation.broadcast()
    assert_redirect(view, "/locked")
  end

  test "public pages expose keyboard navigation and honest empty state", %{conn: conn} do
    {:ok, view, html} = conn |> sign_in() |> live("/")
    assert has_element?(view, "a[href='#main']", "Skip to content")
    assert html =~ "Foundation preview"
    assert has_element?(view, "a[href='/settings']", "Check your setup")
    refute html =~ "Start battle"
  end

  test "an outdated executable observation resumes at Choose Agent", %{conn: conn} do
    version()
    workspace = Foundation.workspace()

    workspace
    |> Ecto.Changeset.change(codex: Map.put(workspace.codex, "path", "/missing/codex"))
    |> Repo.update!()

    {:ok, view, _} = conn |> sign_in() |> live("/settings/codex")
    assert has_element?(view, "#wizard-choose")
    refute has_element?(view, "#wizard-connect")
  end

  test "desktop executable choice is metadata only and pending probes can be cancelled", %{
    conn: conn
  } do
    {:ok, view, _} = conn |> sign_in() |> live("/settings/codex")
    render_click(view, "choose_desktop_codex")
    assert has_element?(view, "#codex-path[value='#{Cuckoding.Tools.desktop_codex() || ""}']")
    refute Foundation.pending?()
    view |> form("#codex-check", path: "/bin/sh") |> render_submit()
    view |> element("#agent-progress button", "Cancel") |> render_click()
    refute Foundation.pending?()
    assert render(view) =~ "Action cancelled"
  end

  test "fresh connection advances to models, hides login and keeps signout available", %{
    conn: conn
  } do
    version()
    {:ok, view, _} = conn |> sign_in() |> live("/settings/codex")
    assert has_element?(view, "#codex-login")
    view |> form("#connection-check") |> render_submit()
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, catalog())
    assert has_element?(view, "#wizard-models")
    view |> element("#wizard-models button", "Back") |> render_click()
    refute has_element?(view, "#codex-login")
    assert has_element?(view, "#codex-logout button", "Sign out of Codex")
    view |> form("#codex-logout") |> render_submit(%{"revision" => "1"})
    refute Foundation.pending?()
    view |> form("#codex-logout") |> render_submit()
    assert Foundation.pending_probe("logout_codex")
  end

  test "all advertised models can be selected, preserved, saved and used by Team", %{conn: conn} do
    connect()
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/settings/codex")
    for n <- 1..7, do: assert(has_element?(view, "#model-selection input[value='model-#{n}']"))
    assert render(view) =~ "additional model"
    view |> form("#model-selection", model_ids: ["model-1", "model-7"]) |> render_change()
    send(view.pid, :clock)
    Foundation.broadcast()
    assert has_element?(view, "#model-selection input[value='model-7'][checked]")
    view |> element("#wizard-models button", "Back") |> render_click()
    view |> element("#wizard-connect button", "Select models") |> render_click()
    assert has_element?(view, "#model-selection input[value='model-7'][checked]")
    view |> form("#model-selection", model_ids: ["model-7"]) |> render_change()
    refute has_element?(view, "#model-selection input[value='model-1'][checked]")
    view |> form("#model-selection", model_ids: ["model-7"]) |> render_submit()
    assert has_element?(view, "#wizard-save", "Save your agent")
    refute Foundation.saved_agent_models()
    view |> form("#save-models") |> render_submit()
    assert Foundation.saved_agent_models().payload["model_ids"] == ["model-7"]
    assert has_element?(view, "#wizard-save", "Your agent is saved")
    assert {:ok, again, _} = live(signed, "/settings/codex")
    assert has_element?(again, "#wizard-save", "Model 7")
    {:ok, team, _} = live(signed, "/team")
    team |> form("#team-form", roles: %{"speculator" => %{"agent" => "codex"}}) |> render_change()
    assert has_element?(team, "#model-speculator option[value='model-7']")
    refute has_element?(team, "#model-speculator option[value='model-1']")
    refute Foundation.pending?()
  end

  test "catalog refresh invalidates reviewed Save and test consent, but preserves model choices",
       %{conn: conn} do
    connect()
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/settings/codex")
    view |> form("#model-selection", model_ids: ["model-1"]) |> render_change()
    view |> form("#model-check", model_id: "model-1") |> render_change()
    view |> form("#model-check", model_id: "model-1", model_confirmed: "true") |> render_change()
    send(view.pid, :clock)
    Foundation.broadcast()
    assert has_element?(view, "input[name=model_confirmed][checked]")
    refresh()
    refute has_element?(view, "input[name=model_confirmed][checked]")
    assert has_element?(view, "#model-id option[value='model-1'][selected]")
    assert has_element?(view, "#model-selection input[value='model-1'][checked]")
    view |> form("#model-selection", model_ids: ["model-1"]) |> render_submit()
    refresh()
    view |> form("#save-models") |> render_submit()
    refute Foundation.saved_agent_models()
    assert has_element?(view, "#wizard-error", "Go back")
  end

  test "model testing is optional, consented, scoped and cancellable; public results persist", %{
    conn: conn
  } do
    connect()
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/settings/codex")
    view |> form("#model-check", model_id: "model-1") |> render_submit()
    refute Foundation.pending?()

    view
    |> form("#model-check", model_id: "model-1", model_confirmed: "true")
    |> render_submit(%{"consent_key" => "old"})

    refute Foundation.pending?()
    view |> form("#model-check", model_id: "model-1", model_confirmed: "true") |> render_submit()
    {:ok, claim} = Foundation.claim()
    assert has_element?(view, "#agent-progress", "model-1")

    Foundation.finish(claim, %{
      "status" => "passed",
      "requested_model" => "model-1",
      "observed_model" => "model-1",
      "effort" => "low",
      "thread_id" => Ecto.UUID.generate(),
      "turn_id" => Ecto.UUID.generate(),
      "grant" => "scratch-read-only-v1"
    })

    assert has_element?(view, "#model-check-result", "Model responded")
    assert {:ok, again, _} = live(signed, "/settings/codex")
    assert has_element?(again, "#model-check-result", "Model responded")
    again |> form("#model-check", model_id: "model-1", model_confirmed: "true") |> render_submit()
    {:ok, claim} = Foundation.claim()
    again |> element("#agent-progress button", "Cancel") |> render_click()
    assert has_element?(again, "#agent-progress button[disabled]")
    Foundation.finish(claim, %{"status" => "cancelled"})
    assert has_element?(again, "#model-check-result", "Model check cancelled")
    refute Foundation.pending?()
  end

  test "sign-in links require live authority, survive reconnect and vanish on cancellation", %{
    conn: conn
  } do
    Cuckoding.Codex.init_login_links()
    version()
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/settings/codex")
    view |> form("#codex-login") |> render_submit()
    {:ok, claim} = Foundation.claim()
    assert :ok = Foundation.login_waiting(claim)
    url = "https://auth.openai.com/oauth/authorize?state=fixture-link-canary"
    Cuckoding.Codex.put_login_link(claim.id, url)
    Foundation.broadcast()
    local = "/codex/login/" <> claim.id
    assert has_element?(view, "a[href='#{local}'][rel='noopener noreferrer']")
    refute render(view) =~ "fixture-link-canary"
    assert {:ok, reconnected, _} = live(signed, "/settings/codex")
    assert has_element?(reconnected, "a[href='#{local}']")
    assert get(conn, local) |> response(401)
    assert get(signed, "/codex/login/invalid") |> response(410)
    assert get(signed, local) |> redirected_to() == url
    view |> element("#agent-progress button", "Cancel") |> render_click()
    refute has_element?(view, "a[href='#{local}']")
    assert get(signed, local) |> response(410)
    Foundation.finish(claim, %{"status" => "cancelled"})
    refute Foundation.pending?()
  end

  defp version do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, "/bin/sh", true)
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "0.146.0"})
  end

  defp connect do
    version()
    refresh()
  end

  defp refresh do
    {:ok, _} =
      Foundation.inspect_codex(Ecto.UUID.generate(), Foundation.workspace().revision, true)

    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, catalog())
  end

  defp catalog do
    %{
      "status" => "checked",
      "authorization" => "chatgpt",
      "catalog_status" => "fresh",
      "models" =>
        for n <- 1..7 do
          %{
            "id" => "model-#{n}",
            "model" => "model-#{n}",
            "name" => "Model #{n}",
            "efforts" => ["low"],
            "default_effort" => "low",
            "default" => n == 1,
            "input_modalities" => ["text"],
            "hidden" => n > 3
          }
        end
    }
  end
end
