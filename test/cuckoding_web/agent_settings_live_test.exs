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
      agent: %{
        label: "Shared Codex",
        adapter_key: "codex",
        executable_path: "/usr/bin/true",
        model_choice: "gpt-6-astra"
      }
    )
    |> render_submit()

    [account] = Cuckoding.Adapters.list_provider_accounts()
    assert account.capabilities_json["settings"]["model"] == "gpt-6-astra"
    assert has_element?(view, "#agent-#{account.id}", "Sign in once")
    assert has_element?(view, "#agent-command-#{account.id} input[readonly][data-copy-source]")
    assert has_element?(view, "#agent-command-#{account.id} button[data-copy-button]", "Copy")

    Cuckoding.Adapters.record_provider_failure(
      account.id,
      :authorization_check,
      :unsupported_version,
      account.capabilities_json
    )

    assert has_element?(view, "#agent-#{account.id} details", "Recent agent errors (1)")
    assert has_element?(view, "#agent-#{account.id}", "code unsupported_version")

    {:ok, home} = Cuckoding.Adapters.SharedProfile.prepare(account.id, "codex")
    File.write!(Path.join(home, "auth.json"), "{}")
    File.chmod!(Path.join(home, "auth.json"), 0o600)

    Cuckoding.Adapters.record_provider_status(account.id, "authenticated", nil, %{
      "status" => "available",
      "models" => [
        %{"id" => "gpt-6-astra", "label" => "Astra"},
        %{"id" => "gpt-5.6-sol", "label" => "Sol"}
      ]
    })

    assert has_element?(view, "#agent-#{account.id}", "Connected")
    assert has_element?(view, "#agent-#{account.id}", "Available models: 2")
    assert has_element?(view, "#agent-#{account.id} details:not([open])")
    assert has_element?(view, "#agent-impact-#{account.id}", "1 saved agent uses")
    assert has_element?(view, "#agent-impact-#{account.id}", "not assigned")

    assert has_element?(
             view,
             "#agent-#{account.id} button[data-confirm]",
             "Disconnect shared sign-in"
           )

    view |> element("#agent-#{account.id} button", "Edit agent") |> render_click()
    refute has_element?(view, "#agent-form[data-confirm]")
    assert has_element?(view, "#agent-form button[data-confirm]", "Save agent")
    assert has_element?(view, "select[name='agent[model_choice]'] option[value='gpt-5.6-sol']")
    view |> form("#agent-form", agent: %{label: "Renamed Codex"}) |> render_submit()
    renamed = Cuckoding.Adapters.get_provider_account(account.id)
    assert renamed.label == "Renamed Codex"
    assert get_in(renamed.capabilities_json, ["model_catalog", "models"]) |> length() == 2
    assert length(Cuckoding.Adapters.list_provider_accounts()) == 1
    {:ok, reopened, _html} = live(conn, ~p"/settings/agents")
    assert has_element?(reopened, "#agent-#{account.id}", "Connected")

    reopened |> form("#agent-form", agent: %{model_choice: "custom"}) |> render_change()

    reopened
    |> form("#agent-form",
      agent: %{
        label: "Codex Coder",
        executable_path: "/usr/bin/true",
        model_choice: "custom",
        model: "other-model"
      }
    )
    |> render_submit()

    agents = Cuckoding.Adapters.list_provider_accounts()
    second = Enum.find(agents, &(&1.label == "Codex Coder"))
    assert second.authorization_account_id == account.id
    assert second.capabilities_json["settings"]["model"] == "other-model"
    assert has_element?(reopened, "#agent-#{second.id}", "Connected")
    assert has_element?(reopened, "#agent-impact-#{account.id}", "2 saved agents use")

    assert has_element?(
             reopened,
             "#agent-#{second.id} a[href='#agent-#{account.id}']",
             "Manage shared sign-in"
           )

    refute has_element?(reopened, "#agent-command-#{second.id}")
    Cuckoding.Adapters.record_provider_status(account.id, "authentication_required")
    assert has_element?(reopened, "#agent-#{second.id}", "Sign-in required")
    {:ok, refreshed, _html} = live(conn, ~p"/settings/agents")
    assert has_element?(refreshed, "#agent-#{second.id}", "other-model")
    refreshed |> element("#agent-#{second.id} button", "Edit agent") |> render_click()

    assert has_element?(
             refreshed,
             "select[name='agent[model_choice]'] option[value='custom'][selected]"
           )

    refreshed |> form("#agent-form", agent: %{model: "changed-model"}) |> render_submit()

    assert Cuckoding.Adapters.get_provider_account(second.id).authorization_account_id ==
             account.id
  end
end
