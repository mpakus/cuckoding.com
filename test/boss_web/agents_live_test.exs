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
           "pricing" => %{
             "input" => 2.0,
             "output" => 10.0,
             "cached_input" => 0.1,
             "unit" => "1M tokens"
           }
         },
         %{"id" => "plain-model", "name" => "Plain model"}
       ]}
    end

    def fetch(:claude, _path) do
      {:ok, Boss.Agents.ModelDiscovery.claude_models(["low", "medium", "high", "xhigh"])}
    end

    def fetch(:cursor, _path) do
      {:ok,
       [
         %{
           "id" => "claude-sonnet-4-thinking",
           "name" => "Claude Sonnet Thinking",
           "reasoning" => true,
           "reasoning_efforts" => ["low", "medium", "high"],
           "default_effort" => "high",
           "context_window" => nil,
           "pricing" => %{"input" => 3.0, "output" => 15.0, "unit" => "1M tokens"}
         }
       ]}
    end

    def fetch(agent, _) when agent in [:pi, :hermes, :opencode] do
      {:ok, [%{"id" => "provider/#{agent}-model", "name" => "Configured #{agent} model"}]}
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

    {:ok, session} = Boss.LocalAccess.exchange(Boss.LocalAccess.new_token())
    conn = %{conn | host: "127.0.0.1", port: 4002} |> init_test_session(local_session: session)
    %{conn: conn}
  end

  test "protected navigation and rendering never start a probe", %{conn: conn} do
    anonymous = %{build_conn() | host: "127.0.0.1", port: 4002}
    assert redirected_to(get(anonymous, "/agents")) == "/unlock"
    assert html_response(get(conn, "/agents"), 200) =~ "Detect agents"
    home = conn |> get("/") |> html_response(200) |> LazyHTML.from_document()

    assert home |> LazyHTML.query("nav a[href='/agents']") |> LazyHTML.text() |> String.trim() ==
             "Agents"

    {:ok, view, _} = live(conn, "/agents")
    assert has_element?(view, "#agent-codex", "Not checked")
    assert has_element?(view, "#agent-claude", "Not checked")
    assert has_element?(view, "#agent-cursor", "Not checked")
    assert has_element?(view, "#agent-hermes", "Not checked")
    assert has_element?(view, "#agent-pi", "Not checked")
    assert has_element?(view, "#agent-opencode", "Not checked")
    assert has_element?(view, "#agent-codex a[href='https://developers.openai.com/codex/cli']")
    assert has_element?(view, "#agent-claude a[href='https://code.claude.com/docs/en/setup']")
    assert has_element?(view, "#agent-cursor a[href='https://cursor.com/docs/cli/overview']")
    assert has_element?(view, "#agent-hermes code", "hermes model")
    assert has_element?(view, "#agent-pi code", "pi, then /login")
    assert has_element?(view, "#agent-opencode code", "opencode auth login")
    assert has_element?(view, "#agent-codex code", "codex login")
    assert has_element?(view, "#agent-claude code", "claude auth login")
    assert has_element?(view, "#agent-cursor code", "agent login")
    refute has_element?(view, "#agents-checked-at")
    refute has_element?(view, "button", "Start")
    refute_receive {:scan, _}
  end

  test "explicit detection allows one scan and distinguishes metadata from provider readiness", %{
    conn: conn
  } do
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
    assert has_element?(view, "#agent-codex", "CLI metadata recognized")
    assert has_element?(view, "#agent-codex", "CLI reports credentials configured")
    assert has_element?(view, "#agent-codex", "/tools/codex")
    assert has_element?(view, "#agent-codex", "1.2.3")
    assert has_element?(view, "#agent-codex [data-capability='headless']", "Advertised")
    assert has_element?(view, "#agent-codex [data-capability='streaming']", "Not advertised")
    assert has_element?(view, "#agent-codex [data-capability='usage_reporting']", "Unknown")
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

    assert has_element?(view, "#agent-codex", "Not found on PATH")
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
      assert has_element?(view, "#agent-codex", "1.2.3")
      assert render(element(view, "#agents-checked-at")) == checked_at
      refute has_element?(view, "#detect-agents[disabled]")
    end

    detect(view, rows())
    refute has_element?(view, "#agents-error")
    assert has_element?(view, "#agents-status", "Detection complete")
  end

  test "standard roles stay, connect only to detected-authorized models-agents, and persist detections across reloads",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/agents")
    roles = Map.new(Boss.Agents.Roles.list(), &{&1.kind, &1})
    reviewer = roles["reviewer"]
    implementer = roles["implementer"]
    analytic = roles["analytic"]

    assert has_element?(view, "#role-#{reviewer.id}-purpose", "Reviews specs and code")
    assert has_element?(view, "#role-#{implementer.id}-purpose", "Writes code and tests")
    assert has_element?(view, "#role-#{analytic.id}-purpose", "helps the Reviewer")
    refute has_element?(view, "#role-#{reviewer.id}-delete")

    # Before detection/authorization, roles cannot connect to undetected agents
    assert has_element?(view, "#role-#{reviewer.id}-empty-authorized")
    refute has_element?(view, "#role-#{reviewer.id}-agent-codex")

    # Detect: Codex & Cursor configured, Claude not_configured
    [codex, claude] = rows()
    cursor = %{codex | id: :cursor, name: "Cursor Agent", path: "/tools/agent"}
    detect(view, [codex, claude, cursor])

    # Supported models with pricing and reasoning are fetched for authorized agents
    assert has_element?(view, "#agent-models-codex", "GPT-6.1 Sol")
    assert has_element?(view, "#agent-models-codex", "$2.00 in · $10.00 out")
    assert has_element?(view, "#agent-models-codex", "medium · high · xhigh")

    # Unauthorized Claude shows authorization action and is excluded from role checkboxes
    assert has_element?(view, "#agent-auth-box-claude")
    refute has_element?(view, "#role-#{reviewer.id}-agent-claude")
    assert has_element?(view, "#role-#{reviewer.id}-agent-codex")
    assert has_element?(view, "#role-#{reviewer.id}-agent-cursor")

    view |> element("#authorize-claude") |> render_click()
    render_async(view, 2_000)
    assert has_element?(view, "#agent-claude", "Opened login in macOS Terminal")
    refute has_element?(view, "#role-#{reviewer.id}-agent-claude")

    view |> element("#verify-auth-claude") |> render_click()
    render_async(view, 2_000)
    assert has_element?(view, "#agent-models-claude", "Claude Opus 4.6")
    assert has_element?(view, "#role-#{reviewer.id}-agent-claude")

    for {role, agents} <- [{reviewer, ~w(claude cursor)}, {implementer, ~w(cursor codex)}],
        agent <- agents do
      view
      |> form("#role-#{role.id}-agents-#{agent}", %{assigned: "true"})
      |> render_change()
    end

    assert has_element?(view, "#role-#{reviewer.id}-agent-cursor[checked]")
    assert has_element?(view, "#role-#{implementer.id}-agent-cursor[checked]")

    view
    |> form("#role-#{implementer.id}-agents-codex", %{
      assigned: "true",
      model_id: "gpt-6.1-sol"
    })
    |> render_change(%{"_target" => ["model_id"]})

    view
    |> form("#role-#{implementer.id}-agents-codex", %{
      assigned: "true",
      model_id: "gpt-6.1-sol",
      reasoning_effort: "xhigh"
    })
    |> render_change(%{"_target" => ["reasoning_effort"]})

    render_change(view, "assign_role", %{
      "role_id" => to_string(implementer.id),
      "agent" => "cursor",
      "_target" => ["assigned"]
    })

    refute has_element?(view, "#role-#{implementer.id}-agent-cursor[checked]")
    assert has_element?(view, "#role-#{reviewer.id}-agent-cursor[checked]")

    assert has_element?(
             view,
             "#role-#{implementer.id}-model-codex option[value='gpt-6.1-sol'][selected]"
           )

    assert has_element?(
             view,
             "#role-#{implementer.id}-effort-codex option[value='xhigh'][selected]"
           )

    # Reload /agents in a fresh LiveView: saved detections, models, and role model bindings persist!
    {:ok, reloaded, _} = live(conn, "/agents")
    refute_receive {:scan, _}
    assert has_element?(reloaded, "#agents-checked-at[datetime]")
    assert has_element?(reloaded, "#agent-models-codex", "GPT-6.1 Sol")

    assert has_element?(
             reloaded,
             "#role-#{implementer.id}-model-codex option[value='gpt-6.1-sol'][selected]"
           )

    reloaded |> form("#create-role", %{name: "Planner"}) |> render_submit()
    planner = Enum.find(Boss.Agents.Roles.list(), &(&1.name == "Planner"))
    reloaded |> form("#role-#{planner.id}-name", %{name: "Architect"}) |> render_submit()
    assert has_element?(reloaded, "#role-#{planner.id}-name-input[value='Architect']")
    reloaded |> element("#role-#{planner.id}-delete") |> render_click()
    refute has_element?(reloaded, "#role-#{planner.id}")
    assert has_element?(reloaded, "#role-#{reviewer.id}-title", "Reviewer")
  end

  test "a custom role saves and reloads a model for each of the six agents", %{conn: conn} do
    {:ok, view, _} = live(conn, "/agents")
    [codex, claude] = rows()

    rows = [
      codex,
      %{claude | auth_status: :configured},
      %{codex | id: :cursor, path: "/tools/agent"}
      | for(id <- [:pi, :hermes, :opencode], do: %{codex | id: id, auth_status: :unknown})
    ]

    detect(view, rows)
    view |> form("#create-role", %{name: "Planner"}) |> render_submit()
    role = Enum.find(Boss.Agents.Roles.list(), &(&1.name == "Planner"))

    choices = [
      codex: "gpt-6.1-sol",
      cursor: "claude-sonnet-4-thinking",
      claude: "opus",
      pi: "provider/pi-model",
      hermes: "provider/hermes-model",
      opencode: "provider/opencode-model"
    ]

    for {agent, model} <- choices do
      view
      |> form("#role-#{role.id}-agents-#{agent}", %{assigned: "true"})
      |> render_change()

      view
      |> form("#role-#{role.id}-agents-#{agent}", %{assigned: "true", model_id: model})
      |> render_change(%{"_target" => ["model_id"]})
    end

    {:ok, reloaded, _} = live(conn, "/agents")

    for {agent, model} <- choices do
      assert has_element?(
               reloaded,
               "#role-#{role.id}-model-#{agent} option[value='#{model}'][selected]"
             )
    end
  end

  test "switching models clears an incompatible effort and preserves an unavailable member",
       %{conn: conn} do
    {:ok, view, _} = live(conn, "/agents")
    [codex, claude] = rows()
    detect(view, [codex, %{claude | auth_status: :configured}])
    {:ok, role} = Boss.Agents.Roles.create("Model testing")

    assert {:ok, _} =
             Boss.Agents.Roles.assign(role.id, ["codex", "claude"], %{
               "codex" => %{"model_id" => "gpt-6.1-sol", "reasoning_effort" => "high"},
               "claude" => %{"model_id" => "opus"}
             })

    detect(view, [codex, claude])

    view
    |> form("#role-#{role.id}-agents-codex", %{
      assigned: "true",
      model_id: "plain-model",
      reasoning_effort: "high"
    })
    |> render_change(%{"_target" => ["model_id"]})

    updated = Enum.find(Boss.Agents.Roles.list(), &(&1.id == role.id))

    assert updated.selections == %{
             "claude" => %{model_id: "opus", reasoning_effort: nil},
             "codex" => %{model_id: "plain-model", reasoning_effort: nil}
           }

    assert has_element?(view, "#role-#{role.id}-agents-claude", "Unavailable")
    Boss.Agents.Detections.save_models(:codex, [%{"id" => "replacement"}])
    {:ok, refreshed, _} = live(conn, "/agents")

    assert has_element?(
             refreshed,
             "#role-#{role.id}-model-codex option[value='plain-model'][selected][disabled]"
           )

    render_change(refreshed, "assign_role", %{
      "role_id" => to_string(role.id),
      "agent" => "claude",
      "_target" => ["assigned"]
    })

    updated = Enum.find(Boss.Agents.Roles.list(), &(&1.id == role.id))
    assert updated.selections == %{"codex" => %{model_id: "plain-model", reasoning_effort: nil}}
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
    assert has_element?(view, "#agent-codex", "1.2.3")
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
