defmodule CuckodingWeb.AgentSettingsLiveTest do
  use CuckodingWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "finds an installed runtime, keeps manual edits and locks saved setup", %{conn: conn} do
    root =
      Path.join(System.tmp_dir!(), "cuckoding-agent-detect-#{System.unique_integer([:positive])}")

    executable = Path.join(root, ".local/bin/codex")
    File.mkdir_p!(Path.dirname(executable))
    File.write!(executable, "#!/bin/sh\nexit 0\n")
    File.chmod!(executable, 0o700)
    previous = Map.take(System.get_env(), ["PATH", "CUCKODING_RUNTIME_HOME"])
    System.put_env(%{"PATH" => "/usr/bin:/bin", "CUCKODING_RUNTIME_HOME" => root})

    on_exit(fn ->
      System.delete_env("CUCKODING_RUNTIME_HOME")
      System.put_env(previous)
      File.rm_rf!(root)
    end)

    {:ok, view, _html} = live(conn, ~p"/settings/agents")
    view |> form("#agent-form", agent: %{label: "Detected Codex"}) |> render_submit()

    assert has_element?(
             view,
             "input[name='agent[executable_path]'][value='#{executable}']:not([readonly])"
           )

    assert render(view) =~ "Codex Desktop"

    view |> form("#agent-form", agent: %{executable_path: "/usr/bin/true"}) |> render_change()
    view |> form("#agent-form", agent: %{authorization_account_id: "new"}) |> render_change()
    assert has_element?(view, "input[name='agent[executable_path]'][value='/usr/bin/true']")
    view |> element("#detect-runtime") |> render_click()
    assert has_element?(view, "input[name='agent[executable_path]'][value='#{executable}']")
    assert has_element?(view, "#agent-status", "Found an installed executable")

    view |> form("#agent-form", agent: %{executable_path: "/usr/bin/true"}) |> render_submit()
    [account] = Cuckoding.Adapters.list_provider_accounts()
    assert account.capabilities_json["settings"]["executable_path"] == "/usr/bin/true"
    refute has_element?(view, "#detect-runtime")
    render_click(view, "detect_runtime")

    assert has_element?(
             view,
             "input[name='agent[executable_path]'][value='/usr/bin/true'][readonly]"
           )
  end

  test "failed discovery keeps a manually entered path", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/agents")

    view
    |> form("#agent-form", agent: %{adapter_key: "custom_agent", label: "My tool"})
    |> render_change()

    view |> form("#agent-form") |> render_submit()
    view |> form("#agent-form", agent: %{executable_path: "/usr/bin/true"}) |> render_change()
    view |> element("#detect-runtime") |> render_click()
    assert has_element?(view, "#agent-status", "No executable found")
    assert has_element?(view, "input[name='agent[executable_path]'][value='/usr/bin/true']")
  end

  test "found executables still receive a clear unsupported-version error", %{conn: conn} do
    root =
      Path.join(
        System.tmp_dir!(),
        "cuckoding-agent-version-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    executable = Path.join(root, "codex")
    File.write!(executable, "#!/bin/sh\necho 'codex-cli 0.155.0-alpha.16.3'\n")
    File.chmod!(executable, 0o700)
    {:ok, view, _html} = live(conn, ~p"/settings/agents")
    view |> form("#agent-form", agent: %{label: "Newer Codex"}) |> render_submit()

    assert render(view) =~
             "Supported CLI version: #{Cuckoding.Adapters.Codex.supported_version()}"

    view |> form("#agent-form", agent: %{executable_path: executable}) |> render_submit()
    view |> element("#agent-form button", "Check sign-in and fetch models") |> render_click()
    render_async(view, 5_000)
    assert has_element?(view, "#agent-error", "version is not supported")
    refute has_element?(view, "li[aria-current=step]", "3. Model")
  end

  test "wizard verifies sign-in and fetches model reasoning levels", %{conn: conn} do
    root =
      Path.join(System.tmp_dir!(), "cuckoding-agent-wizard-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    executable = Path.join(root, "codex")

    File.write!(executable, """
    #!/bin/sh
    if [ "$1" = "--version" ]; then
      echo 'codex-cli 0.146.0'
    elif [ "$3" = "login" ]; then
      echo 'Logged in using ChatGPT'
    elif [ "$3" = "app-server" ]; then
      read _initialize
      read _initialized
      read _list
      printf '%s\\n' '{"id":2,"result":{"data":[{"id":"gpt-6-astra","displayName":"Astra","isDefault":true,"supportedReasoningEfforts":[{"reasoningEffort":"low"},{"reasoningEffort":"high"}]}]}}'
    fi
    """)

    File.chmod!(executable, 0o700)
    {:ok, view, _html} = live(conn, ~p"/settings/agents")

    view
    |> form("#agent-form", agent: %{label: "Wizard Codex", adapter_key: "codex"})
    |> render_submit()

    view |> form("#agent-form", agent: %{executable_path: executable}) |> render_submit()

    [account] = Cuckoding.Adapters.list_provider_accounts()
    {:ok, home} = Cuckoding.Adapters.SharedProfile.prepare(account.id, "codex")
    File.write!(Path.join(home, "auth.json"), "{}")
    File.chmod!(Path.join(home, "auth.json"), 0o600)

    view |> element("#agent-form button", "Check sign-in and fetch models") |> render_click()
    render_async(view, 5_000)

    assert has_element?(view, "li[aria-current=step]", "3. Model")
    assert has_element?(view, "select[name='agent[model_choice]'] option[value='gpt-6-astra']")
    assert has_element?(view, "select[name='agent[reasoning_effort]'] option[value='high']")
  end

  test "setup-only runtime can return from authorization to model", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/agents")

    view
    |> form("#agent-form", agent: %{label: "Local OpenCode", adapter_key: "opencode"})
    |> render_submit()

    view |> form("#agent-form", agent: %{executable_path: "/usr/bin/true"}) |> render_submit()

    assert has_element?(view, "li[aria-current=step]", "3. Model")
    view |> element("#agent-form button", "Back") |> render_click()
    assert has_element?(view, "#agent-form button", "Continue to model")
    view |> element("#agent-form button", "Continue to model") |> render_click()
    assert has_element?(view, "li[aria-current=step]", "3. Model")
  end

  test "manages a shared agent independently of projects with live status", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/agents")
    assert has_element?(view, "nav a[aria-current=page]", "Agents")
    assert has_element?(view, "#profile-sharing", "provider history")
    refute has_element?(view, "input[name='agent[api_key_helper]']")

    view
    |> form("#agent-form",
      agent: %{
        label: "Shared Codex",
        adapter_key: "codex"
      }
    )
    |> render_submit()

    assert has_element?(view, "li[aria-current=step]", "2. Authorization")

    view
    |> form("#agent-form", agent: %{executable_path: "/usr/bin/true"})
    |> render_submit()

    [account] = Cuckoding.Adapters.list_provider_accounts()
    assert account.capabilities_json["settings"]["model"] == nil
    assert has_element?(view, "#wizard-agent-command-#{account.id} button[data-copy-button]")
    refute has_element?(view, "#agent-#{account.id}")

    Cuckoding.Adapters.record_provider_failure(
      account.id,
      :authorization_check,
      :unsupported_version,
      account.capabilities_json
    )

    {:ok, home} = Cuckoding.Adapters.SharedProfile.prepare(account.id, "codex")
    File.write!(Path.join(home, "auth.json"), "{}")
    File.chmod!(Path.join(home, "auth.json"), 0o600)

    Cuckoding.Adapters.record_provider_status(account.id, "authenticated", nil, %{
      "status" => "available",
      "models" => [
        %{
          "id" => "gpt-6-astra",
          "label" => "Astra",
          "reasoning_efforts" => ["low", "high"],
          "is_default" => true
        },
        %{"id" => "gpt-5.6-sol", "label" => "Sol", "reasoning_efforts" => ["low"]}
      ]
    })

    assert has_element?(view, "#agent-form button", "Continue to model")
    view |> element("#agent-form button", "Continue to model") |> render_click()
    assert has_element?(view, "li[aria-current=step]", "3. Model")
    assert has_element?(view, "select[name='agent[reasoning_effort]'] option[value='high']")

    view
    |> form("#agent-form", agent: %{model_choice: "gpt-6-astra", reasoning_effort: "high"})
    |> render_submit()

    assert Cuckoding.Adapters.get_provider_account(account.id).capabilities_json["settings"] == %{
             "executable_path" => "/usr/bin/true",
             "model" => "gpt-6-astra",
             "reasoning_effort" => "high"
           }

    assert has_element?(view, "#agent-#{account.id}", "Connected")
    assert has_element?(view, "#agent-command-#{account.id} input[readonly][data-copy-source]")
    assert has_element?(view, "#agent-command-#{account.id} button[data-copy-button]", "Copy")
    assert has_element?(view, "#agent-#{account.id} details", "Recent agent errors (1)")
    assert has_element?(view, "#agent-#{account.id}", "code unsupported_version")
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

    reopened
    |> form("#agent-form", agent: %{label: "Codex Coder", adapter_key: "codex"})
    |> render_submit()

    reopened
    |> form("#agent-form", agent: %{executable_path: "/usr/bin/true"})
    |> render_submit()

    assert has_element?(reopened, "li[aria-current=step]", "3. Model")
    reopened |> form("#agent-form", agent: %{model_choice: "custom"}) |> render_change()

    reopened
    |> form("#agent-form",
      agent: %{
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
