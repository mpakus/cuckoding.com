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

  setup %{conn: conn} do
    previous = Application.fetch_env(:boss, :agent_detector)
    Application.put_env(:boss, :agent_detector, Detector)
    start_supervised!({Detector, self()})

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:boss, :agent_detector, value)
        :error -> Application.delete_env(:boss, :agent_detector)
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
    {:ok, home, _} = live(conn, "/")
    assert has_element?(home, "a[href='/agents']", "Agents")
    {:ok, view, _} = live(conn, "/agents")
    assert has_element?(view, "#agent-codex", "Not checked")
    assert has_element?(view, "#agent-claude", "Not checked")
    assert has_element?(view, "#agent-codex a[href='https://developers.openai.com/codex/cli']")
    assert has_element?(view, "#agent-claude a[href='https://code.claude.com/docs/en/setup']")
    assert has_element?(view, "#agent-codex code", "codex login")
    assert has_element?(view, "#agent-claude code", "claude auth login")
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
