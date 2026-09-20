defmodule CuckodingWeb.AgentSettingsLiveTest do
  use CuckodingWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "manages a shared agent independently of projects with live status", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/agents")
    assert has_element?(view, "nav a[aria-current=page]", "Agents")
    assert has_element?(view, "#profile-sharing", "provider history")
    refute has_element?(view, "input[name='agent[api_key_helper]']")

    view
    |> form("#agent-form",
      agent: %{label: "Shared Codex", adapter_key: "codex", executable_path: "/usr/bin/true"}
    )
    |> render_submit()

    [account] = Cuckoding.Adapters.list_provider_accounts()
    assert has_element?(view, "#agent-#{account.id}", "Sign in once")
    assert has_element?(view, "#agent-command-#{account.id} input[readonly][data-copy-source]")
    assert has_element?(view, "#agent-command-#{account.id} button[data-copy-button]", "Copy")
    Cuckoding.Adapters.record_provider_status(account.id, "authenticated")
    assert has_element?(view, "#agent-#{account.id}", "Connected")
    assert has_element?(view, "#agent-#{account.id} details:not([open])")
    view |> element("#agent-#{account.id} button", "Edit agent") |> render_click()
    assert has_element?(view, "#agent-form[data-confirm]")
    view |> form("#agent-form", agent: %{label: "Renamed Codex"}) |> render_submit()
    assert Cuckoding.Adapters.get_provider_account(account.id).label == "Renamed Codex"
    assert length(Cuckoding.Adapters.list_provider_accounts()) == 1
    {:ok, reopened, _html} = live(conn, ~p"/settings/agents")
    assert has_element?(reopened, "#agent-#{account.id}", "Connected")
  end
end
