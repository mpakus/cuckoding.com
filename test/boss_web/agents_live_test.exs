defmodule BossWeb.AgentsLiveTest do
  use BossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  defmodule Detector do
    use GenServer
    def start_link(owner), do: GenServer.start_link(__MODULE__, owner, name: __MODULE__)
    def init(owner), do: {:ok, owner}
    def scan, do: GenServer.call(__MODULE__, :scan, :infinity)

    def handle_call(:scan, from, owner) do
      send(owner, {:scan, from})
      {:noreply, owner}
    end
  end

  defmodule FakeDiscovery do
    def fetch(:codex, _path) do
      {:ok,
       [
         %{
           "id" => "gpt-6.1-sol",
           "name" => "GPT-6.1 Sol",
           "reasoning" => true,
           "reasoning_efforts" => ["medium", "high", "xhigh"],
           "default_effort" => "high",
           "context_window" => 500_000,
           "billing" => "subscription_or_api",
           "pricing" => %{
             "input" => 2.0,
             "output" => 10.0,
             "cached_input" => 0.1,
             "unit" => "1M tokens"
           }
         },
         %{"id" => "plain-model", "name" => "Plain model", "billing" => "api"}
       ]}
    end

    def fetch(:claude, _path) do
      {:ok, Boss.Agents.ModelDiscovery.claude_models(["low", "medium", "high", "xhigh"])}
    end

    def fetch(:cursor, _path) do
      {:ok,
       [
         %{
           "id" => "gemini-4-carbon",
           "name" => "Gemini 4 Carbon",
           "reasoning" => true,
           "reasoning_efforts" => ["low", "medium", "high"],
           "default_effort" => "high",
           "billing" => "subscription_or_api",
           "pricing" => %{"input" => 1.25, "output" => 10.0, "unit" => "1M tokens"}
         },
         %{
           "id" => "claude-sonnet-4-thinking",
           "name" => "Claude Sonnet Thinking",
           "reasoning" => true,
           "reasoning_efforts" => ["low", "medium", "high"],
           "default_effort" => "high",
           "billing" => "subscription_or_api",
           "pricing" => %{"input" => 3.0, "output" => 15.0, "unit" => "1M tokens"}
         }
       ]}
    end

    def fetch(agent, _) when agent in [:pi, :hermes, :opencode] do
      {:ok,
       [
         %{
           "id" => "provider/#{agent}-model",
           "name" => "Configured #{agent} model",
           "billing" => if(agent == :opencode, do: "free", else: "api"),
           "pricing" =>
             if(agent == :opencode,
               do: %{"input" => 0.0, "output" => 0.0, "unit" => "1M tokens"},
               else: nil
             )
         }
       ]}
    end
  end

  defmodule FakeAuthorizer do
    def authorize(_id, :terminal), do: {:ok, :terminal_opened}

    def verify_and_fetch(id) do
      {:ok, models} = FakeDiscovery.fetch(id, "/tools/#{id}")

      saved =
        Boss.Agents.Detections.save_agent(%{
          id: id,
          name: Atom.to_string(id),
          path: "/tools/#{id}",
          version: "1.2.3",
          probe_status: :ok,
          auth_status: :configured,
          capabilities: %{},
          errors: [],
          models: models
        })

      {:ok, saved}
    end

    def fetch_models(id), do: verify_and_fetch(id)
  end

  setup %{conn: conn} do
    previous = Application.fetch_env(:boss, :agent_detector)
    prev_disc = Application.fetch_env(:boss, :agent_model_discovery)
    prev_auth = Application.fetch_env(:boss, :agent_authorizer)
    Application.put_env(:boss, :agent_detector, Detector)
    Application.put_env(:boss, :agent_model_discovery, FakeDiscovery)
    Application.put_env(:boss, :agent_authorizer, FakeAuthorizer)
    start_supervised!({Detector, self()})

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:boss, :agent_detector, value)
        :error -> Application.delete_env(:boss, :agent_detector)
      end

      case prev_disc do
        {:ok, value} -> Application.put_env(:boss, :agent_model_discovery, value)
        :error -> Application.delete_env(:boss, :agent_model_discovery)
      end

      case prev_auth do
        {:ok, value} -> Application.put_env(:boss, :agent_authorizer, value)
        :error -> Application.delete_env(:boss, :agent_authorizer)
      end
    end)

    conn = %{conn | host: "127.0.0.1", port: 4002}
    %{conn: conn}
  end

  test "loopback navigation and rendering never start a probe and expose + Connect agent panel",
       %{conn: conn} do
    foreign =
      %{build_conn() | host: "127.0.0.1", port: 4002}
      |> put_req_header("origin", "https://evil.example")

    assert response(get(foreign, "/agents"), 403) == "Forbidden"
    assert html_response(get(conn, "/agents"), 200) =~ "Agents &amp; Roles"
    home = conn |> get("/") |> html_response(200) |> LazyHTML.from_document()

    assert home |> LazyHTML.query("nav a[href='/agents']") |> LazyHTML.text() |> String.trim() ==
             "Agents"

    {:ok, view, _} = live(conn, "/agents")
    assert has_element?(view, "#connected-agents-empty")
    assert has_element?(view, "#connect-agent-panel")

    for {id, url, cmd} <- [
          {"codex", "https://developers.openai.com/codex/cli", "codex login"},
          {"claude", "https://code.claude.com/docs/en/setup", "claude auth login"},
          {"cursor", "https://cursor.com/docs/cli/overview", "agent login"},
          {"opencode", "https://opencode.ai/docs/cli/", "opencode auth login"},
          {"hermes", "https://hermes-agent.nousresearch.com/docs/getting-started/installation",
           "hermes model"},
          {"pi", "https://pi.dev/docs/latest/quickstart", "pi, then /login"}
        ] do
      view |> element("#pick-agent-#{id}") |> render_click()
      assert has_element?(view, "#agent-#{id}", "Not checked")
      assert has_element?(view, "#agent-#{id} a[href='#{url}']")
      assert has_element?(view, "#agent-#{id} code", cmd)
    end

    refute has_element?(view, "#agents-checked-at")
    refute has_element?(view, "#create-role")
    refute has_element?(view, "button", "Start")
    refute_receive {:scan, _}
  end

  test "explicit detection shows connected agents immediately and keeps unauthorized CLI in connect panel",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/agents")
    view |> element("#detect-agents") |> render_click()
    assert_receive {:scan, from}
    assert has_element?(view, "#detect-agents[disabled]")
    assert has_element?(view, "#agents-status[role='status']", "Detecting")
    render_click(view, "detect")
    refute_receive {:scan, _}
    GenServer.reply(from, {:ok, rows()})
    render_async(view, 2_000)

    refute has_element?(view, "#detect-agents[disabled]")
    assert has_element?(view, "#connected-agent-codex", "Authorized")
    assert has_element?(view, "#connected-agent-codex", "/tools/codex")
    assert has_element?(view, "#connected-agent-codex", "v1.2.3")
    refute has_element?(view, "#connected-agent-claude")

    view |> element("#manage-agent-codex") |> render_click()
    assert has_element?(view, "#agent-codex", "CLI metadata recognized")
    assert has_element?(view, "#agent-codex", "CLI reports credentials configured")
    assert has_element?(view, "#agent-codex [data-capability='headless']", "Advertised")
    assert has_element?(view, "#agent-codex [data-capability='streaming']", "Not advertised")
    assert has_element?(view, "#agent-codex [data-capability='usage_reporting']", "Unknown")

    view |> element("#pick-agent-claude") |> render_click()
    assert has_element?(view, "#agent-claude", "CLI reports no credentials configured")
    assert has_element?(view, "#agents-checked-at[datetime]")
    assert has_element?(view, "#agents-help", "does not verify provider access")
    refute render(view) =~ "Ready to run"
  end

  test "missing, unsupported and failed probes show fixed messages without raw diagnostics", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/agents")
    [codex, claude] = rows()

    detect(view, [
      %{codex | path: nil, version: nil, probe_status: :missing, auth_status: :unknown},
      %{
        claude
        | path: "/tools/<script>literal</script>",
          version: nil,
          probe_status: :unsupported,
          auth_status: :unknown,
          errors: [
            %{stage: :version, reason: :unrecognized, output: "PRIVATE_RAW_OUTPUT"},
            %{stage: :auth, reason: :unsupported}
          ]
      }
    ])

    if not has_element?(view, "#connect-agent-panel") do
      view |> element("#open-connect-agent") |> render_click()
    end

    view |> element("#pick-agent-codex") |> render_click()
    assert has_element?(view, "#agent-codex", "Not found on PATH")

    view |> element("#pick-agent-claude") |> render_click()
    assert has_element?(view, "#agent-claude", "CLI metadata unsupported")
    assert has_element?(view, "#agent-claude", "Version check returned unrecognized output")
    assert has_element?(view, "#agent-claude", "Sign-in check is not supported")
    refute render(view) =~ "PRIVATE_RAW_OUTPUT"
    refute has_element?(view, "#agent-claude script")

    detect(view, [
      %{
        codex
        | probe_status: :failed,
          errors: [%{stage: :help, reason: :timeout}, %{stage: :auth, reason: :output_limit}]
      },
      claude
    ])

    view |> element("#pick-agent-codex") |> render_click()
    assert has_element?(view, "#agent-codex", "Detection incomplete")
    assert has_element?(view, "#agent-codex", "Help check timed out")
    assert has_element?(view, "#agent-codex", "Sign-in check exceeded its output limit")
  end

  test "global failure preserves the last completed scan and permits retry", %{conn: conn} do
    {:ok, view, _} = live(conn, "/agents")
    detect(view, rows())
    checked_at = render(element(view, "#agents-checked-at"))

    for {reason, message} <- [
          {:busy, "Another detection is running"},
          {:unavailable, "Agent detection is unavailable"},
          {:cancelled, "Detection was interrupted"}
        ] do
      view |> element("#detect-agents") |> render_click()
      assert_receive {:scan, from}
      GenServer.reply(from, {:error, reason})
      render_async(view, 2_000)
      assert has_element?(view, "#agents-error[role='alert']", message)
      assert has_element?(view, "#agents-error", "Showing the last completed scan")
      assert has_element?(view, "#connected-agent-codex", "v1.2.3")
      assert render(element(view, "#agents-checked-at")) == checked_at
      refute has_element?(view, "#detect-agents[disabled]")
    end

    detect(view, rows())
    refute has_element?(view, "#agents-error")
    assert has_element?(view, "#agents-status", "Detection complete")
  end

  test "3 standard roles support multiple Agent + Model bindings, model toggles, and billing/price badges",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/agents")
    roles = Map.new(Boss.Agents.Roles.standard_list(), &{&1.kind, &1})
    assert Map.keys(roles) |> Enum.sort() == ["analytic", "implementer", "reviewer"]
    refute has_element?(view, "#create-role")

    reviewer = roles["reviewer"]
    implementer = roles["implementer"]
    analytic = roles["analytic"]

    assert has_element?(view, "#role-#{reviewer.id}-purpose", "verifies tasks directly")
    assert has_element?(view, "#role-#{implementer.id}-purpose", "Writes code and tests")
    assert has_element?(view, "#role-#{analytic.id}-purpose", "Brain that orchestrates")

    [codex, claude] = rows()
    cursor = %{codex | id: :cursor, name: "Cursor Agent", path: "/tools/agent"}
    opencode = %{codex | id: :opencode, name: "OpenCode", path: "/tools/opencode"}
    detect(view, [codex, claude, cursor, opencode])

    # Models show price and API vs Subscription billing badges
    assert has_element?(view, "#agent-models-codex", "GPT-6.1 Sol")
    assert has_element?(view, "#agent-models-codex", "$2 in · $10 out / 1M")
    assert has_element?(view, "#agent-models-codex", "Subscription / API")
    assert has_element?(view, "#agent-models-opencode", "Free (Included)")
    assert has_element?(view, "#agent-models-opencode", "$0 / 1M")

    # Unauthorized Claude can be authorized and verified from + Connect agent panel
    if not has_element?(view, "#connect-agent-panel") do
      view |> element("#open-connect-agent") |> render_click()
    end

    view |> element("#pick-agent-claude") |> render_click()
    view |> element("#authorize-claude") |> render_click()
    render_async(view, 2_000)
    assert has_element?(view, "#agent-notice-claude", "Opened login in macOS Terminal")

    view |> element("#verify-auth-claude") |> render_click()
    render_async(view, 2_000)
    assert has_element?(view, "#connected-agent-claude", "Authorized")
    assert has_element?(view, "#agent-models-claude", "Claude Opus 4.6")

    # Toggle a model off -> excluded from role model dropdown; toggle back on -> restored
    render_click(view, "toggle_model", %{
      "agent" => "codex",
      "model_id" => "plain-model",
      "enabled" => "false"
    })

    refute has_element?(view, "#role-reviewer-model option[value='plain-model']")

    # Reviewer, Implementer, and Analytic AUTO-SAVE immediately on select change (no submit click!)
    view
    |> form("#role-bind-form-reviewer", %{
      "role_kind" => "reviewer",
      "agent" => "cursor"
    })
    |> render_change()

    assert has_element?(view, "#role-saved-reviewer", "Auto-saved")
    assert has_element?(view, "#role-#{reviewer.id}", "Reviews:CursorGemini4Carbon·high")

    # Add a second Reviewer binding and auto-save its effort on change
    view |> element("#add-binding-reviewer") |> render_click()
    [_, second_reviewer] = Boss.Agents.Roles.bindings_for("reviewer")

    view
    |> form("#role-binding-#{second_reviewer.id}", %{
      "binding_id" => to_string(second_reviewer.id),
      "role_kind" => "reviewer",
      "agent" => "codex",
      "model_id" => "gpt-6.1-sol",
      "reasoning_effort" => "xhigh"
    })
    |> render_change()

    refute has_element?(
             view,
             "#binding-model-#{second_reviewer.id} option[value='plain-model']"
           )

    # Implementer auto-saves on change
    view
    |> form("#role-bind-form-implementer", %{
      "role_kind" => "implementer",
      "agent" => "opencode"
    })
    |> render_change()

    assert has_element?(view, "#role-saved-implementer", "Auto-saved")

    # Analytic auto-saves on change, then editing the bound row directly auto-saves the model change
    view
    |> form("#role-bind-form-analytic", %{
      "role_kind" => "analytic",
      "agent" => "claude"
    })
    |> render_change()

    [analytic_binding] = Boss.Agents.Roles.bindings_for("analytic")

    view
    |> form("#role-binding-#{analytic_binding.id}", %{
      "binding_id" => to_string(analytic_binding.id),
      "role_kind" => "analytic",
      "agent" => "claude",
      "model_id" => "claude-opus-4-6",
      "reasoning_effort" => "high"
    })
    |> render_change()

    assert has_element?(view, "#role-saved-analytic", "Auto-saved")
    assert has_element?(view, "#role-#{reviewer.id}", "Reviews:CursorGemini4Carbon·high")
    assert has_element?(view, "#role-#{reviewer.id}", "Reviews:CodexGPT6.1Sol·xhigh")
    assert has_element?(view, "#role-#{implementer.id}", "Implementer:OpenCodeOpencodeModel")
    assert has_element?(view, "#role-#{analytic.id}", "Analytic:ClaudeOpus4.6·high")

    # Reload /agents: detections, model toggles, and auto-saved role bindings persist
    {:ok, reloaded, _} = live(conn, "/agents")
    refute_receive {:scan, _}
    assert has_element?(reloaded, "#role-#{reviewer.id}", "Reviews:CursorGemini4Carbon·high")
    assert has_element?(reloaded, "#role-#{reviewer.id}", "Reviews:CodexGPT6.1Sol·xhigh")
    assert has_element?(reloaded, "#role-#{implementer.id}", "Implementer:OpenCodeOpencodeModel")
    assert has_element?(reloaded, "#role-#{analytic.id}", "Analytic:ClaudeOpus4.6·high")

    refute has_element?(
             reloaded,
             "#binding-model-#{second_reviewer.id} option[value='plain-model']"
           )
  end

  test "an async exit becomes a sanitized retryable error", %{conn: conn} do
    {:ok, view, _} = live(conn, "/agents")
    detect(view, rows())
    view |> element("#detect-agents") |> render_click()
    assert_receive {:scan, {pid, _}}
    monitor = Process.monitor(pid)

    :sys.replace_state(view.pid, fn state ->
      %{state | socket: Phoenix.LiveView.cancel_async(state.socket, :detect, :kill)}
    end)

    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    render_async(view, 2_000)
    assert has_element?(view, "#agents-error", "Detection was interrupted")
    assert has_element?(view, "#connected-agent-codex", "v1.2.3")
    refute has_element?(view, "#detect-agents[disabled]")
  end

  defp detect(view, rows) do
    view |> element("#detect-agents") |> render_click()
    assert_receive {:scan, from}
    GenServer.reply(from, {:ok, rows})
    render_async(view, 2_000)
  end

  defp rows do
    for {id, name, auth} <- [
          {:codex, "Codex", :configured},
          {:claude, "Claude Code", :not_configured}
        ] do
      %{
        id: id,
        name: name,
        path: "/tools/#{id}",
        version: "1.2.3",
        probe_status: :ok,
        auth_status: auth,
        capabilities: %{
          headless: :advertised,
          streaming: :not_advertised,
          session_resume: :advertised,
          structured_output: :unknown,
          approval_support: :advertised,
          usage_reporting: :unknown
        },
        errors: []
      }
    end
  end
end
