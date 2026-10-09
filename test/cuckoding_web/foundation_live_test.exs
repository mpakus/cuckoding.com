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

  test "unauthenticated users cannot mount; setup persists through reconnect", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/locked"}}} = live(conn, "/")
    signed = sign_in(conn)
    assert {:ok, view, html} = live(signed, "/settings")
    assert html =~ "Your starting lineup."
    assert html =~ "Not checked"
    view |> element("button", "Check setup") |> render_click()
    assert Foundation.pending?()
    {:ok, claim} = Foundation.claim()

    {:ok, _} =
      Foundation.finish(claim, %{"rtk" => %{"status" => "found", "path" => "/test/bin/rtk"}})

    assert render(view) =~ "/test/bin/rtk"
    assert has_element?(view, "#tool-location-rtk[phx-mounted*=ignore_attrs]")
    assert {:ok, _, html} = live(signed, "/settings")
    assert html =~ "Found"
    assert html =~ "/test/bin/rtk"
  end

  test "expired browser authority cannot mutate even on an existing live connection", %{
    conn: conn
  } do
    {:ok, view, _} = conn |> sign_in() |> live("/settings")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> element("button", "Check setup") |> render_click()
    assert_redirect(view, "/locked")
    refute Foundation.pending?()
  end

  test "public pages expose keyboard navigation and honest empty state", %{conn: conn} do
    {:ok, view, html} = conn |> sign_in() |> live("/")
    assert has_element?(view, "a[href='#main']", "Skip to content")
    assert html =~ "Foundation preview"
    assert has_element?(view, "a[href='/settings']", "Check your setup")
    refute html =~ "Start battle"
  end

  test "expired authority cannot receive live workspace updates", %{conn: conn} do
    {:ok, view, _} = conn |> sign_in() |> live("/settings")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    Foundation.broadcast()
    assert_redirect(view, "/locked")
  end

  test "Codex requires explicit consent and preserves entered paths through updates", %{
    conn: conn
  } do
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/settings")
    assert has_element?(view, "label[for='codex-path']", "Codex executable")
    assert has_element?(view, "input[name='confirmed'][required]")
    view |> form("#codex-check", path: "/bin/sh") |> render_change()
    Foundation.broadcast()
    assert has_element?(view, "#codex-path[value='/bin/sh']")
    view |> form("#codex-check", path: "/bin/sh", confirmed: "true") |> render_change()
    assert has_element?(view, "input[name='confirmed'][checked]")
    view |> form("#codex-check", path: "/bin/ls", confirmed: "true") |> render_change()
    refute has_element?(view, "input[name='confirmed'][checked]")
    view |> form("#codex-check", path: "/bin/sh") |> render_submit()
    assert render(view) =~ "Confirm that you trust this executable"
    refute Foundation.pending_probe()
    view |> form("#codex-check", path: "/bin/sh", confirmed: "true") |> render_submit()
    assert Foundation.pending_probe()
    assert has_element?(view, "button", "Cancel check")
    view |> element("button", "Cancel check") |> render_click()
    assert render(view) =~ "Check cancelled."
    assert {:ok, _, html} = live(signed, "/settings")
    assert html =~ "Check cancelled."
  end

  test "private connection observation is consented, cancellable and survives reconnect", %{
    conn: conn
  } do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, "/bin/sh", true)
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "0.146.0"})
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/settings")
    view |> form("#connection-check") |> render_submit()
    assert render(view) =~ "Confirm the private profile check"
    refute Foundation.pending_probe("inspect_codex")
    view |> form("#connection-check", profile_confirmed: "true") |> render_submit()
    assert has_element?(view, "button", "Cancel connection check")
    view |> element("button", "Cancel connection check") |> render_click()
    assert render(view) =~ "Connection check cancelled."
    view |> form("#connection-check", profile_confirmed: "true") |> render_submit()
    {:ok, claim} = Foundation.claim()

    Foundation.finish(claim, %{
      "status" => "checked",
      "authorization" => "not_connected",
      "catalog_status" => "not_requested"
    })

    assert render(view) =~ "Not signed in to Cuckoding"
    assert {:ok, _, html} = live(signed, "/settings")
    assert html =~ "Not signed in to Cuckoding"
    assert has_element?(view, "#codex-login button", "Sign in with ChatGPT")
    assert html =~ "repository tasks are not enabled"

    connection = %{
      "status" => "checked",
      "authorization" => "chatgpt",
      "catalog_status" => "fresh",
      "fetched_at" => "2020-01-01T00:00:00Z",
      "models" => [
        %{
          "name" => "Test",
          "model" => "test",
          "efforts" => ["medium"],
          "input_modalities" => ["text"]
        }
      ]
    }

    Foundation.workspace() |> Ecto.Changeset.change(connection: connection) |> Repo.update!()
    assert {:ok, view, _} = live(signed, "/settings")
    assert has_element?(view, "#codex-models summary", "1 cached models · stale")
    assert has_element?(view, "#codex-models[phx-mounted*=ignore_attrs]")
  end

  test "profile checkboxes survive clock and unrelated updates and can be unchecked", %{
    conn: conn
  } do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, "/bin/sh", true)
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "0.146.0"})
    {:ok, view, _} = conn |> sign_in() |> live("/settings")

    for {form_id, field} <- [
          {"codex-login", :auth_confirmed},
          {"codex-logout", :auth_confirmed},
          {"connection-check", :profile_confirmed}
        ] do
      view |> form("##{form_id}", %{field => "true"}) |> render_change()
      send(view.pid, :clock)
      Foundation.broadcast()
      assert has_element?(view, "##{form_id} input[type=checkbox][checked]")
      view |> form("##{form_id}") |> render_change(%{field => nil})
      send(view.pid, :clock)
      refute has_element?(view, "##{form_id} input[type=checkbox][checked]")
    end

    refute Foundation.pending?()
  end

  test "profile consent resets on setup changes, rejects recovered forms and is session guarded",
       %{conn: conn} do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, "/bin/sh", true)
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "0.146.0"})
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/settings")

    forms = [
      {"codex-login", :auth_confirmed},
      {"codex-logout", :auth_confirmed},
      {"connection-check", :profile_confirmed}
    ]

    for {id, field} <- forms, do: view |> form("##{id}", %{field => "true"}) |> render_change()
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 1, "/bin/sh", true)
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "0.146.0"})

    for {id, field} <- forms do
      refute has_element?(view, "##{id} input[type=checkbox][checked]")
      view |> form("##{id}", %{field => "true"}) |> render_change(%{"revision" => "1"})
      refute has_element?(view, "##{id} input[type=checkbox][checked]")
      view |> form("##{id}", %{field => "true"}) |> render_submit(%{"revision" => "1"})
      refute Foundation.pending?()

      view
      |> form("##{id}", %{field => "true"})
      |> render_change(%{"consent_key" => Ecto.UUID.generate()})

      refute has_element?(view, "##{id} input[type=checkbox][checked]")

      view
      |> form("##{id}", %{field => "true"})
      |> render_submit(%{"consent_key" => Ecto.UUID.generate()})

      refute Foundation.pending?()
    end

    view |> form("#codex-login", auth_confirmed: "true") |> render_change()
    {:ok, again, _} = live(signed, "/settings")
    refute has_element?(again, "#codex-login input[type=checkbox][checked]")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> form("#codex-login", auth_confirmed: "true") |> render_submit()
    assert_redirect(view, "/locked")
    refute Foundation.pending?()
  end

  test "each profile action consumes consent without authorizing another action", %{conn: conn} do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, "/bin/sh", true)
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "0.146.0"})
    {:ok, view, _} = conn |> sign_in() |> live("/settings")

    for {id, field, kind} <- [
          {"codex-login", :auth_confirmed, "login_codex"},
          {"codex-logout", :auth_confirmed, "logout_codex"},
          {"connection-check", :profile_confirmed, "inspect_codex"}
        ] do
      view |> form("##{id}", %{field => "true"}) |> render_change()
      view |> form("##{id}") |> render_submit()
      command = Foundation.pending_probe(kind)
      assert command
      refute has_element?(view, "##{id} input[type=checkbox][checked]")
      Foundation.cancel_probe(command.id)
      render(view)
      view |> form("##{id}") |> render_submit()
      refute Foundation.pending?()
    end
  end

  test "model selection resets usage consent and completion survives reconnect", %{conn: conn} do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, "/bin/sh", true)
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "0.146.0"})
    {:ok, _} = Foundation.inspect_codex(Ecto.UUID.generate(), 1, true)
    {:ok, claim} = Foundation.claim()

    models =
      for id <- ["model-a", "model-b"] do
        %{
          "id" => id,
          "model" => id,
          "name" => id,
          "efforts" => ["low"],
          "default_effort" => "low",
          "input_modalities" => ["text"],
          "default" => false
        }
      end

    Foundation.finish(claim, %{
      "status" => "checked",
      "authorization" => "chatgpt",
      "catalog_status" => "fresh",
      "models" => models
    })

    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/settings")
    assert has_element?(view, "label[for='model-id']", "Model")
    view |> form("#model-check", model_id: "model-a") |> render_change()
    view |> form("#model-check", model_id: "model-a", model_confirmed: "true") |> render_change()
    assert has_element?(view, "input[name='model_confirmed'][checked]")
    {:ok, _} = Foundation.inspect_codex(Ecto.UUID.generate(), 2, true)
    {:ok, refresh} = Foundation.claim()

    Foundation.finish(refresh, %{
      "status" => "checked",
      "authorization" => "chatgpt",
      "catalog_status" => "fresh",
      "models" => models
    })

    refute has_element?(view, "input[name='model_confirmed'][checked]")
    assert has_element?(view, "#model-id option[value='model-a'][selected]")
    view |> form("#model-check", model_id: "model-a", model_confirmed: "true") |> render_change()
    view |> form("#model-check", model_id: "model-b", model_confirmed: "true") |> render_change()
    refute has_element?(view, "input[name='model_confirmed'][checked]")
    Foundation.broadcast()
    assert has_element?(view, "#model-id option[value='model-b'][selected]")
    view |> form("#model-check", model_id: "model-b") |> render_submit()
    assert render(view) =~ "Confirm the model check and possible provider usage"
    refute Foundation.pending?()
    view |> form("#model-check", model_id: "model-b", model_confirmed: "true") |> render_submit()
    assert has_element?(view, "#model-check-progress", "model-b")
    {:ok, claim} = Foundation.claim()

    Foundation.finish(claim, %{
      "status" => "passed",
      "requested_model" => "model-b",
      "observed_model" => "model-b",
      "effort" => "low",
      "thread_id" => Ecto.UUID.generate(),
      "turn_id" => Ecto.UUID.generate(),
      "grant" => "scratch-read-only-v1",
      "elapsed_ms" => 17
    })

    assert has_element?(view, "#model-check-result", "Runtime model: model-b")
    assert {:ok, again, _} = live(signed, "/settings")
    assert has_element?(again, "#model-check-result", "Runtime model: model-b")
    again |> form("#model-check", model_id: "model-a", model_confirmed: "true") |> render_submit()
    {:ok, claim} = Foundation.claim()
    again |> element("button", "Cancel model check") |> render_click()
    assert has_element?(again, "#model-check-progress button[disabled]", "Stopping")
    Foundation.finish(claim, %{"status" => "cancelled"})
    assert render(again) =~ "Model check cancelled"
    refute has_element?(again, "#model-check-result", "Runtime model:")
  end

  test "sign-in links require live authority, survive reconnect and vanish on cancellation", %{
    conn: conn
  } do
    Cuckoding.Codex.init_login_links()
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, "/bin/sh", true)
    {:ok, version} = Foundation.claim()
    Foundation.finish(version, %{"status" => "supported", "version" => "0.146.0"})
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, "/settings")
    view |> form("#codex-login") |> render_submit()
    assert render(view) =~ "Confirm the private-profile"
    refute Foundation.pending?()
    view |> form("#codex-login", auth_confirmed: "true") |> render_submit()
    {:ok, claim} = Foundation.claim()
    assert :ok = Foundation.login_waiting(claim)
    url = "https://auth.openai.com/oauth/authorize?state=fixture-link-canary"
    Cuckoding.Codex.put_login_link(claim.id, url)
    Foundation.broadcast()
    local = "/codex/login/" <> claim.id
    assert has_element?(view, "#codex-login-link[href='#{local}'][rel='noopener noreferrer']")
    refute render(view) =~ "fixture-link-canary"
    assert {:ok, reconnected, _} = live(signed, "/settings")
    assert has_element?(reconnected, "#codex-login-link")
    assert get(conn, local) |> response(401)
    assert get(signed, "/codex/login/invalid") |> response(410)
    assert get(signed, local) |> redirected_to() == url
    view |> element("button", "Cancel account operation") |> render_click()
    refute has_element?(view, "#codex-login-link")
    assert has_element?(view, "#codex-auth-progress button[disabled]", "Stopping")
    assert get(signed, local) |> response(410)
    Foundation.finish(claim, %{"status" => "cancelled"})
    assert render(view) =~ "Account operation cancelled"
    refute view |> element("#connection-result") |> render() =~ "0 ms"
    refute view |> element("#connection-result") |> render() =~ "The saved catalog is stale"
    refute Foundation.pending?()
    assert has_element?(view, "#codex-logout input[required]")
  end
end
