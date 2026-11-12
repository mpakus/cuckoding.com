defmodule Boss.Agents.DetectorTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias Boss.Agents.Detector

  @secret "private-api-key-SENTINEL-do-not-retain"

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-detector-test-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "observes only advertised capabilities and configured credentials", %{root: root} do
    detector = detector(root)
    assert {:ok, results} = Detector.scan(detector)
    codex = agent(results, :codex)
    claude = agent(results, :claude)
    assert codex.version == "0.146.0"
    assert claude.version == "2.1.142"

    for agent <- [codex, claude] do
      assert agent.probe_status == :ok
      assert agent.auth_status == :configured
      assert agent.errors == []

      assert agent.capabilities == %{
               headless: :advertised,
               streaming: :advertised,
               session_resume: :advertised,
               structured_output: :advertised,
               approval_support: :advertised,
               usage_reporting: :unknown
             }

      refute inspect(agent) =~ @secret
    end

    invocations = File.read!(Path.join(root, "calls"))
    assert invocations =~ "codex|login status"
    assert invocations =~ "claude|auth status --json"
    refute invocations =~ "exec --json"
    cwd = File.read!(Path.join(root, "cwd")) |> String.trim()
    refute cwd == root
    refute File.exists?(cwd)
  end

  test "missing and unsupported installations do not run help or auth", %{root: root} do
    unsupported = fixture(root, :codex, %{"--version" => {"unrelated-tool 1.2.3", 0}})
    detector = detector_with(executables: %{codex: unsupported, claude: nil})
    assert {:ok, results} = Detector.scan(detector)
    codex = agent(results, :codex)
    claude = agent(results, :claude)
    assert codex.probe_status == :unsupported
    assert codex.version == nil
    assert codex.errors == [%{stage: :version, reason: :unrecognized}]
    assert claude.probe_status == :missing
    assert claude.path == nil
    assert claude.auth_status == :unknown

    assert Enum.all?(
             [:cursor, :hermes, :pi, :opencode],
             &(agent(results, &1).probe_status == :missing)
           )

    assert File.read!(Path.join(root, "calls")) == "codex|--version\n"
  end

  test "Codex's nonfatal PATH-alias warning does not mask version or local sign-in", %{root: root} do
    warning =
      "WARNING: proceeding, even though we could not create PATH aliases: " <> @secret

    path =
      fixture(root, :codex, %{
        "--version" => {warning <> "\ncodex-cli 0.166.0", 0},
        "login status" => {warning <> "\nLogged in using ChatGPT", 0}
      })

    detector = detector_with(executables: %{codex: path})
    assert {:ok, result} = Detector.scan_agent(:codex, detector)
    assert %{probe_status: :ok, version: "0.166.0", auth_status: :configured, errors: []} = result
    refute inspect(result) =~ @secret
  end

  test "auxiliary help failure keeps a detected CLI and its independently reported sign-in", %{
    root: root
  } do
    path = fixture(root, :codex, %{"exec --help" => {@secret, 2}})
    detector = detector_with(executables: %{codex: path})
    assert {:ok, result} = Detector.scan_agent(:codex, detector)

    assert %{
             probe_status: :ok,
             auth_status: :configured,
             errors: [%{stage: :help, reason: :exit_status}]
           } = result

    assert result.capabilities.streaming == :unknown
  end

  test "recognizes Pi's multiline help and Hermes argparse options and version labels", %{
    root: root
  } do
    pi =
      fixture(root, :pi, %{
        "--no-extensions --help" =>
          {"pi - AI coding assistant\n\e[1mUsage:\e[0m\n  pi [options] [messages...]\n" <>
             "\e[1mOptions:\e[0m\n  --print, -p\n  --mode <mode> text, json, or rpc\n" <>
             "  --resume, -r\n", 0}
      })

    hermes =
      fixture(root, :hermes, %{
        "--version" =>
          {"Hermes Agent v2026.11.10 (2026.11.10) · upstream a1b2c3d4\nPython: 3.11.14", 0},
        "--help" =>
          {"usage: hermes [-h] [-z PROMPT] <command>\n" <>
             "options:\n  -z PROMPT, --oneshot PROMPT  Run once\n  -r SESSION, --resume SESSION\n",
           0}
      })

    detector = detector_with(executables: %{pi: pi, hermes: hermes})
    assert {:ok, results} = Detector.scan(detector)

    assert %{
             probe_status: :ok,
             capabilities: %{
               headless: :advertised,
               streaming: :advertised,
               session_resume: :advertised
             }
           } = agent(results, :pi)

    assert %{
             probe_status: :ok,
             version: "2026.11.10",
             capabilities: %{headless: :advertised, session_resume: :advertised}
           } = agent(results, :hermes)

    assert File.read!(Path.join(root, "calls")) =~ "pi|--no-extensions --help"
  end

  test "unavailable platform never launches installed executables", %{root: root} do
    detector = detector(root, os_type: {:win32, :nt})
    assert {:ok, agents} = Detector.scan(detector)
    assert Enum.all?(agents, &(&1.probe_status == :unsupported))
    refute File.exists?(Path.join(root, "calls"))
  end

  test "failed and malformed version output is not reflected", %{root: root} do
    for output <- [@secret, "codex-cli 0.146.0\n" <> @secret, "codex-cli " <> @secret, <<255>>] do
      executable = fixture(root, :codex, %{"--version" => {output, 0}})
      detector = detector_with(executables: %{codex: executable})
      assert {:ok, results} = Detector.scan(detector)
      agent = agent(results, :codex)
      assert agent.probe_status == :unsupported
      assert agent.version == nil
      refute inspect(agent) =~ @secret
    end

    executable = fixture(root, :claude, %{"--version" => {@secret, 9}})
    detector = detector_with(executables: %{claude: executable})

    assert {:ok, results} = Detector.scan(detector)

    assert %{probe_status: :failed, errors: [%{stage: :version, reason: :exit_status}]} =
             agent(results, :claude)
  end

  test "help failure preserves recognized version but cannot claim capabilities", %{root: root} do
    executable = fixture(root, :codex, %{"--help" => {@secret, 7}})
    detector = detector_with(executables: %{codex: executable})
    assert {:ok, results} = Detector.scan(detector)
    agent = agent(results, :codex)
    assert agent.version == "0.146.0"
    assert agent.probe_status == :failed
    assert Enum.all?(agent.capabilities, fn {_, status} -> status == :unknown end)
    assert agent.auth_status == :unknown
    assert agent.errors == [%{stage: :help, reason: :exit_status}]
    refute inspect(agent) =~ @secret
  end

  test "successful help distinguishes absent flags and does not invent an auth command", %{
    root: root
  } do
    executable =
      fixture(root, :codex, %{
        "--help" => {"Usage: codex [OPTIONS]\nOptions:\n  --help  Print help", 0}
      })

    detector = detector_with(executables: %{codex: executable})
    assert {:ok, results} = Detector.scan(detector)
    agent = agent(results, :codex)
    assert agent.probe_status == :ok
    assert agent.auth_status == :unknown
    assert agent.capabilities.headless == :not_advertised
    assert agent.capabilities.streaming == :not_advertised
    assert agent.capabilities.usage_reporting == :unknown
    assert File.read!(Path.join(root, "calls")) == "codex|--version\ncodex|--help\n"
  end

  test "signed out is explicit, conflicting or malformed auth is unknown", %{root: root} do
    cases = [
      {:codex, "login status", "Not logged in", 1, :not_configured},
      {:codex, "login status", "Logged in using ChatGPT", 1, :unknown},
      {:codex, "login status", "Logged in using an API key - " <> @secret, 0, :configured},
      {:codex, "login status",
       "API key configured - " <>
         @secret <>
         "\nAuthentication is checked when you send a request.", 0, :configured},
      {:codex, "login status", "API key configured - " <> @secret, 0, :unknown},
      {:codex, "login status", "Logged in using workload identity", 0, :configured},
      {:codex, "login status", "Logged in using access token", 0, :configured},
      {:codex, "login status", "Logged in using ChatGPT\nNot logged in", 0, :unknown},
      {:claude, "auth status --json", ~s({"loggedIn":false}), 1, :not_configured},
      {:claude, "auth status --json", ~s({"loggedIn":true}), 1, :unknown},
      {:claude, "auth status --json", ~s({"loggedIn":false}), 0, :unknown},
      {:claude, "auth status --json", ~s({"loggedIn":"true","token":"#{@secret}"}), 0, :unknown},
      {:claude, "auth status --json", @secret, 9, :unknown}
    ]

    for {id, command, output, code, expected} <- cases do
      executable = fixture(root, id, %{command => {output, code}})
      detector = detector_with(executables: %{id => executable})
      assert {:ok, agents} = Detector.scan(detector)
      agent = Enum.find(agents, &(&1.id == id))
      assert agent.auth_status == expected
      assert agent.probe_status == :ok
      refute inspect(agent) =~ @secret
      assert agent.errors == [] == (expected != :unknown)
    end
  end

  test "output limit and probe timeout kill only the owned direct child", %{root: root} do
    for {script, opts, expected} <- [
          {"printf '%s' #{shell_quote(String.duplicate("s", 1025))}; exec /bin/sleep 30",
           [output_limit: 1024], :output_limit},
          {"exec /bin/sleep 30", [probe_timeout_ms: 100], :timeout}
        ] do
      executable = sleeper(root, script)
      detector = detector_with([executables: %{codex: executable}] ++ opts)
      task = Task.async(fn -> Detector.scan(detector) end)
      pid = wait_for_pid(root)
      assert {:ok, results} = Task.await(task)
      agent = agent(results, :codex)
      assert agent.errors == [%{stage: :version, reason: expected}]
      assert_stopped(pid)
      File.rm!(Path.join(root, "pid"))
    end
  end

  test "one active scan, caller death cleans child and allows immediate repeat", %{root: root} do
    executable = sleeper(root, "exec /bin/sleep 30")
    detector = detector_with(executables: %{codex: executable})
    owner = spawn(fn -> Detector.scan(detector) end)
    pid = wait_for_pid(root)
    cwd = File.read!(Path.join(root, "cwd")) |> String.trim()
    assert Bitwise.band(File.stat!(cwd).mode, 0o777) == 0o700
    assert {:error, :busy} = Detector.scan(detector)
    Process.exit(owner, :kill)
    assert_stopped(pid)
    fixture(root, :codex, %{}) |> File.cp!(executable)
    assert {:ok, results} = Detector.scan(detector)
    agent = agent(results, :codex)
    assert agent.probe_status == :ok
  end

  test "whole scan has an independent deadline and shutdown cleans child", %{root: root} do
    short_root = Path.join(root, "short-deadline")
    File.mkdir!(short_root)

    short_detector =
      detector_with(
        executables: %{codex: sleeper(short_root, "exec /bin/sleep 30")},
        probe_timeout_ms: 1000,
        scan_timeout_ms: 100
      )

    # The real deadline may expire before the child can write its startup marker.
    short_scan = Task.async(fn -> Detector.scan(short_detector) end)
    assert {:error, :unavailable} = Task.await(short_scan)
    assert :sys.get_state(short_detector).active == nil

    detector = detector_with(executables: %{codex: sleeper(root, "exec /bin/sleep 30")})
    task = Task.async(fn -> Detector.scan(detector) end)
    pid = wait_for_pid(root)
    %{active: %{monitor: monitor, scan_timer: timer}} = :sys.get_state(detector)
    assert Process.cancel_timer(timer) != false
    send(detector, {:scan_timeout, monitor})
    assert {:error, :unavailable} = Task.await(task)
    assert_stopped(pid)

    File.rm!(Path.join(root, "pid"))
    owner = spawn(fn -> Detector.scan(detector) end)
    pid = wait_for_pid(root)
    GenServer.stop(detector)
    assert_stopped(pid)
    Process.exit(owner, :kill)
  end

  test "status and abnormal shutdown logs redact transient auth bytes", %{root: root} do
    executable =
      fixture(root, :codex, %{
        "login status" =>
          {:script,
           "printf '%s' #{shell_quote(@secret)}; echo $$ > #{shell_quote(Path.join(root, "pid"))}; exec /bin/sleep 30"}
      })

    detector = detector_with(executables: %{codex: executable})
    owner = spawn(fn -> Detector.scan(detector) end)
    pid = wait_for_pid(root)
    refute inspect(:sys.get_status(detector), limit: :infinity) =~ @secret
    log = capture_log(fn -> GenServer.stop(detector, :fixture_failure) end)
    refute log =~ @secret
    assert_stopped(pid)
    Process.exit(owner, :kill)
  end

  test "rapid completed scans do not reuse old port messages or retain output", %{root: root} do
    detector = detector(root)

    for _ <- 1..5 do
      assert {:ok, results} = Detector.scan(detector)
      assert agent(results, :codex).probe_status == :ok
      assert agent(results, :claude).probe_status == :ok
      assert :sys.get_state(detector).active == nil
    end
  end

  test "absent server returns unavailable" do
    assert {:error, :unavailable} = Detector.scan(:missing_boss_detector)
  end

  test "descriptive prose is not a flag or subcommand declaration", %{root: root} do
    executable =
      fixture(root, :codex, %{
        "--help" =>
          {"Usage: codex [OPTIONS]\nDo not use --ask-for-approval here.\n  exec and login are described elsewhere.\nOptions:\n  --help  See docs for --ask-for-approval\n",
           0}
      })

    detector = detector_with(executables: %{codex: executable})
    assert {:ok, results} = Detector.scan(detector)
    agent = agent(results, :codex)
    assert agent.capabilities.headless == :not_advertised
    assert agent.capabilities.approval_support == :not_advertised
    assert File.read!(Path.join(root, "calls")) == "codex|--version\ncodex|--help\n"
  end

  test "contradictory duplicate JSON status fields are unknown", %{root: root} do
    for output <- [~s({"loggedIn":false,"loggedIn":true}), ~s({"loggedIn":true,"loggedIn":false})] do
      executable = fixture(root, :claude, %{"auth status --json" => {output, 0}})
      detector = detector_with(executables: %{claude: executable})
      assert {:ok, results} = Detector.scan(detector)
      agent = agent(results, :claude)
      assert agent.auth_status == :unknown
      assert agent.errors == [%{stage: :auth, reason: :unrecognized}]
    end
  end

  test "non-executable file produces a fixed spawn error", %{root: root} do
    path = Path.join(root, "not-executable")
    File.write!(path, @secret)
    File.chmod!(path, 0o600)
    detector = detector_with(executables: %{codex: path})
    assert {:ok, results} = Detector.scan(detector)
    agent = agent(results, :codex)
    assert agent.probe_status == :failed
    assert agent.errors == [%{stage: :version, reason: :spawn_failed}]
  end

  test "streaming enum evidence belongs to the output-format declaration", %{root: root} do
    for {help, expected} <- [
          {"Usage: claude [options]\nOptions:\n  --output-format <format> text, json\n\nNotes:\n  stream-json is unsupported",
           :not_advertised},
          {"Usage: claude [options]\nOptions:\n  --output-format <format> Output format:\n      text, json, stream-json\n  --help Print help",
           :advertised}
        ] do
      executable = fixture(root, :claude, %{"--help" => {help, 0}})
      detector = detector_with(executables: %{claude: executable})
      assert {:ok, results} = Detector.scan(detector)
      agent = agent(results, :claude)
      assert agent.capabilities.streaming == expected
    end
  end

  test "recognizes desktop agents from their own help without retaining account text", %{
    root: root
  } do
    detector =
      detector_with(
        executables: %{
          cursor: fixture(root, :cursor, %{}),
          hermes: fixture(root, :hermes, %{}),
          pi: fixture(root, :pi, %{}),
          opencode: fixture(root, :opencode, %{})
        }
      )

    assert {:ok, results} = Detector.scan(detector)
    cursor = agent(results, :cursor)
    assert cursor.version == "2026.09.15-d2fe57e"
    assert cursor.probe_status == :ok
    assert cursor.auth_status == :configured
    assert cursor.capabilities.headless == :advertised
    assert cursor.capabilities.streaming == :advertised
    assert cursor.capabilities.session_resume == :advertised
    assert cursor.capabilities.structured_output == :not_advertised
    assert cursor.capabilities.approval_support == :advertised
    assert cursor.capabilities.usage_reporting == :unknown
    refute inspect(cursor) =~ @secret

    hermes = agent(results, :hermes)
    assert hermes.version == "0.20.0"
    assert hermes.auth_status == :unknown
    assert hermes.capabilities.headless == :advertised
    assert hermes.capabilities.approval_support == :advertised
    refute File.read!(Path.join(root, "calls")) =~ "hermes|status"

    pi = agent(results, :pi)
    assert pi.version == "1.0.2"
    assert pi.auth_status == :unknown
    assert pi.capabilities.streaming == :advertised
    refute File.read!(Path.join(root, "calls")) =~ "print-api-key"

    opencode = agent(results, :opencode)
    assert opencode.version == "1.18.30"
    assert opencode.probe_status == :ok
    assert opencode.auth_status == :unknown
    assert opencode.capabilities.headless == :advertised
    assert opencode.capabilities.streaming == :advertised
    assert opencode.capabilities.session_resume == :advertised
    assert opencode.capabilities.approval_support == :advertised
    refute File.read!(Path.join(root, "calls")) =~ "auth list"

    stale_json =
      Jason.encode!(%{
        "status" => "authenticated",
        "isAuthenticated" => true,
        "message" => "Logged in (unable to fetch user details)"
      })

    stale_cursor = fixture(root, :cursor, %{"status --format json" => {stale_json, 0}})

    detector2 = detector_with(executables: %{cursor: stale_cursor})
    assert {:ok, results2} = Detector.scan(detector2)
    assert agent(results2, :cursor).auth_status == :stale
  end

  defp detector(root, opts \\ []) do
    detector_with(
      [executables: %{codex: fixture(root, :codex, %{}), claude: fixture(root, :claude, %{})}] ++
        opts
    )
  end

  defp agent(results, id), do: Enum.find(results, &(&1.id == id))

  defp detector_with(opts) do
    start_supervised!(Supervisor.child_spec({Detector, [name: nil] ++ opts}, id: make_ref()))
  end

  defp fixture(root, id, overrides) do
    responses =
      case id do
        :codex ->
          %{
            "--version" => {"codex-cli 0.146.0", 0},
            "--help" =>
              {"Codex CLI\nUsage: codex [OPTIONS]\nCommands:\n  exec  Run non-interactively\n  login Manage login\nOptions:\n  --ask-for-approval POLICY",
               0},
            "exec --help" =>
              {"Usage: codex exec [OPTIONS]\nCommands:\n  resume Resume session\nOptions:\n  --json\n  --output-schema FILE",
               0},
            "login --help" =>
              {"Usage: codex login [OPTIONS]\nCommands:\n  status Show status", 0},
            "login status" => {"Logged in using ChatGPT", 0}
          }

        :claude ->
          %{
            "--version" => {"2.1.142 (Claude Code)", 0},
            "--help" =>
              {"Usage: claude [options]\nOptions:\n  --print\n  --output-format <format> text, json, stream-json\n  --json-schema SCHEMA\n  --resume ID\n  --permission-mode MODE\nCommands:\n  auth Manage authentication",
               0},
            "auth --help" =>
              {"Usage: claude auth [options]\nCommands:\n  status [options] Show authentication status",
               0},
            "auth status --help" =>
              {"Usage: claude auth status [options]\nOptions:\n  --json Output JSON", 0},
            "auth status --json" => {~s({"loggedIn":true,"email":"#{@secret}"}), 0}
          }

        :cursor ->
          %{
            "--version" => {"2026.09.15-d2fe57e", 0},
            "--help" =>
              {"Usage: agent [options] [command]\nOptions:\n  -p, --print                  Print responses\n  --output-format <format>     text | json | stream-json\n  --resume [chatId]            Select a session\n  -f, --force                  Force allow commands\nCommands:\n  login                        Authenticate\n  status|whoami [options]      View authentication status\n  resume                       Resume the latest chat session",
               0},
            "status --help" =>
              {"Usage: agent status|whoami [options]\nOptions:\n  --format <format>  Output format (choices: \"text\", \"json\")",
               0},
            "status --format json" =>
              {~s({"status":"authenticated","isAuthenticated":true,"userInfo":{"email":"#{@secret}"}}),
               0}
          }

        :hermes ->
          %{
            "--version" => {"Hermes Agent v0.20.0 (2026.8.3)\nPython: 3.11.14", 0},
            "--help" =>
              {"usage: hermes [options] <command>\nOptions:\n  --resume ID\n  --query TEXT\n  --yolo\nCommands:\n  auth",
               0}
          }

        :pi ->
          %{
            "--version" => {"1.0.2", 0},
            "--no-extensions --help" =>
              {"Usage: pi [options]\nOptions:\n  -p, --print\n  --mode <mode> text, json, rpc\n  --approve\nCommands:\n  auth",
               0}
          }

        :opencode ->
          %{
            "--version" => {"1.18.30", 0},
            "--help" =>
              {"Commands:\n  opencode run [message..]     run opencode with a message\nOptions:\n  -c, --continue      continue the last session\n      --auto          auto-approve permissions",
               0},
            "run --help" =>
              {"opencode run [message..]\nOptions:\n      --format       format: default (formatted) or json (raw JSON events)\n  -c, --continue     continue the last session",
               0}
          }
      end

    cases =
      Map.merge(responses, overrides)
      |> Enum.map_join("\n", fn {args, response} ->
        body =
          case response do
            {:script, script} -> script
            {output, code} -> "printf '%s\\n' #{shell_quote(output)}; exit #{code}"
          end

        "#{shell_quote(args)}) #{body} ;;"
      end)

    path = Path.join(root, Atom.to_string(id))

    File.write!(
      path,
      "#!/bin/sh\nprintf '%s|%s\\n' '#{id}' \"$*\" >> #{shell_quote(Path.join(root, "calls"))}\npwd > #{shell_quote(Path.join(root, "cwd"))}\ncase \"$*\" in\n#{cases}\n*) exit 97 ;;\nesac\n"
    )

    File.chmod!(path, 0o700)
    path
  end

  defp sleeper(root, body) do
    path = Path.join(root, "sleeper")

    File.write!(
      path,
      "#!/bin/sh\npwd > #{shell_quote(Path.join(root, "cwd"))}\necho $$ > #{shell_quote(Path.join(root, "pid"))}\n#{body}\n"
    )

    File.chmod!(path, 0o700)
    path
  end

  defp shell_quote(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"

  defp wait_for_pid(root, attempts \\ 200)

  defp wait_for_pid(root, attempts) when attempts > 0 do
    case File.read(Path.join(root, "pid")) do
      {:ok, value} when value != "" ->
        String.trim(value) |> String.to_integer()

      _ ->
        Process.sleep(5)
        wait_for_pid(root, attempts - 1)
    end
  end

  defp wait_for_pid(_, 0), do: flunk("Probe did not start")

  defp assert_stopped(pid, attempts \\ 200)

  defp assert_stopped(pid, attempts) when attempts > 0 do
    case System.cmd("/bin/kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_, 0} ->
        Process.sleep(5)
        assert_stopped(pid, attempts - 1)

      _ ->
        :ok
    end
  end

  defp assert_stopped(_, 0), do: flunk("Owned probe survived cleanup")
end
