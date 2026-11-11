defmodule Boss.Agents.Metadata do
  @moduledoc false

  @capabilities ~w(headless streaming session_resume structured_output approval_support usage_reporting)a

  @catalog [
    %{id: :codex, name: "Codex", executable: "codex"},
    %{id: :claude, name: "Claude Code", executable: "claude"},
    %{id: :cursor, name: "Cursor Agent", executable: "agent"},
    %{id: :hermes, name: "Hermes", executable: "hermes"},
    %{id: :pi, name: "Pi", executable: "pi"},
    %{id: :opencode, name: "OpenCode", executable: "opencode"}
  ]

  def catalog, do: @catalog
  def ids, do: Enum.map(@catalog, & &1.id)
  def review_runners, do: ~w(codex claude cursor)
  def review_runner?(id) when is_binary(id), do: id in review_runners()
  def review_runner?(_), do: false

  def find_executable(:cursor) do
    System.find_executable("agent") || System.find_executable("cursor-agent")
  end

  def find_executable(id) do
    System.find_executable(Enum.find(@catalog, &(&1.id == id)).executable)
  end

  def new(id, path) do
    %{
      id: id,
      name: Enum.find(@catalog, &(&1.id == id)).name,
      path: path,
      version: nil,
      probe_status: if(path, do: :unsupported, else: :missing),
      auth_status: :unknown,
      capabilities: Map.new(@capabilities, &{&1, :unknown}),
      errors: []
    }
  end

  def argv(_, :version), do: ["--version"]
  def argv(_, :help), do: ["--help"]
  def argv(:codex, :exec_help), do: ["exec", "--help"]
  def argv(:codex, :auth_help), do: ["login", "--help"]
  def argv(:codex, :auth), do: ["login", "status"]
  def argv(:claude, :auth_help), do: ["auth", "--help"]
  def argv(:claude, :auth_status_help), do: ["auth", "status", "--help"]
  def argv(:claude, :auth), do: ["auth", "status", "--json"]
  def argv(:cursor, :status_help), do: ["status", "--help"]
  def argv(:cursor, :auth), do: ["status", "--format", "json"]
  def argv(:opencode, :run_help), do: ["run", "--help"]

  def consume(agent, step, output, code) do
    cond do
      not String.valid?(output) or String.contains?(output, <<0>>) ->
        {failure(agent, step, :unrecognized), []}

      step != :auth and code != 0 ->
        {failure(agent, step, :exit_status), []}

      true ->
        interpret(agent, step, String.trim(output), code)
    end
  end

  def failure(agent, step, reason) do
    stage =
      if step in [:auth, :auth_help, :auth_status_help],
        do: :auth,
        else: if(step == :version, do: :version, else: :help)

    status =
      cond do
        stage == :auth -> agent.probe_status
        reason == :unrecognized -> :unsupported
        true -> :failed
      end

    %{agent | probe_status: status, errors: agent.errors ++ [%{stage: stage, reason: reason}]}
  end

  defp interpret(agent, :version, output, _) do
    line =
      if agent.id == :hermes,
        do: output |> String.split(~r/\r?\n/, parts: 2) |> hd(),
        else: output

    case version(agent.id, line) do
      {:ok, version} -> {%{agent | version: version}, [:help]}
      :error -> {failure(agent, :version, :unrecognized), []}
    end
  end

  defp interpret(agent, :auth, output, code) do
    case auth(agent.id, output, code) do
      :unknown -> {failure(agent, :auth, :unrecognized), []}
      status -> {%{agent | auth_status: status}, []}
    end
  end

  defp interpret(agent, step, output, _) do
    if help_identity?(agent, step, output) and
         Regex.match?(~r/^(?:Options|Commands|Positionals):\r?$/m, output) do
      help(agent, step, output)
    else
      {failure(agent, step, :unrecognized), []}
    end
  end

  defp version(:codex, output) do
    case Regex.run(~r/\Acodex-cli ([0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4})\z/, output) do
      [_, version] -> {:ok, version}
      _ -> :error
    end
  end

  defp version(:claude, output) do
    case Regex.run(~r/\A([0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}) \(Claude Code\)\z/, output) do
      [_, version] -> {:ok, version}
      _ -> :error
    end
  end

  defp version(:cursor, output) do
    case Regex.run(~r/\A(\d{4}\.\d{2}\.\d{2}-[0-9a-f]{7,40})\z/, output) do
      [_, version] -> {:ok, version}
      _ -> :error
    end
  end

  defp version(:hermes, output) do
    case Regex.run(
           ~r/\AHermes Agent v(\d{1,4}\.\d{1,4}\.\d{1,4}) \(\d{4}\.\d{1,2}\.\d{1,2}\)\z/,
           output
         ) do
      [_, version] -> {:ok, version}
      _ -> :error
    end
  end

  defp version(id, output) when id in [:pi, :opencode] do
    case Regex.run(~r/\A(\d{1,4}\.\d{1,4}\.\d{1,4})\z/, output) do
      [_, version] -> {:ok, version}
      _ -> :error
    end
  end

  defp help(%{id: :codex} = agent, :help, output) do
    exec? = command?(output, "exec")

    caps =
      Map.merge(agent.capabilities, %{
        headless: advertised(exec?),
        approval_support: advertised(flag?(output, "--ask-for-approval")),
        streaming: if(exec?, do: :unknown, else: :not_advertised),
        session_resume: if(exec?, do: :unknown, else: :not_advertised),
        structured_output: if(exec?, do: :unknown, else: :not_advertised)
      })

    steps =
      if(exec?, do: [:exec_help], else: []) ++
        if(command?(output, "login"), do: [:auth_help], else: [])

    {%{agent | probe_status: :ok, capabilities: caps}, steps}
  end

  defp help(%{id: :codex} = agent, :exec_help, output) do
    caps =
      Map.merge(agent.capabilities, %{
        streaming: advertised(flag?(output, "--json")),
        session_resume: advertised(command?(output, "resume")),
        structured_output: advertised(flag?(output, "--output-schema"))
      })

    {%{agent | capabilities: caps}, []}
  end

  defp help(%{id: :claude} = agent, :help, output) do
    caps =
      Map.merge(agent.capabilities, %{
        headless: advertised(flag?(output, "--print")),
        streaming:
          advertised(String.contains?(flag_block(output, "--output-format") || "", "stream-json")),
        session_resume: advertised(flag?(output, "--resume")),
        structured_output: advertised(flag?(output, "--json-schema")),
        approval_support: advertised(flag?(output, "--permission-mode"))
      })

    {%{agent | probe_status: :ok, capabilities: caps},
     if(command?(output, "auth"), do: [:auth_help], else: [])}
  end

  defp help(agent, :auth_help, output) do
    next = if agent.id == :codex, do: :auth, else: :auth_status_help
    {agent, if(command?(output, "status"), do: [next], else: [])}
  end

  defp help(%{id: :cursor} = agent, :help, output) do
    format = flag_block(output, "--output-format") || ""

    caps =
      Map.merge(agent.capabilities, %{
        headless: advertised(flag?(output, "--print")),
        streaming: advertised(String.contains?(format, "stream-json")),
        session_resume: advertised(flag?(output, "--resume") or command?(output, "resume")),
        structured_output:
          advertised(flag?(output, "--output-schema") or flag?(output, "--json-schema")),
        approval_support: advertised(flag?(output, "--force") or flag?(output, "--sandbox"))
      })

    {%{agent | probe_status: :ok, capabilities: caps},
     if(command?(output, "status"), do: [:status_help], else: [])}
  end

  defp help(%{id: :cursor} = agent, :status_help, output) do
    format = flag_block(output, "--format") || ""
    {agent, if(String.contains?(format, "json"), do: [:auth], else: [])}
  end

  defp help(%{id: :hermes} = agent, :help, output) do
    caps =
      Map.merge(agent.capabilities, %{
        headless: advertised(flag?(output, "--query")),
        streaming: :not_advertised,
        session_resume: advertised(flag?(output, "--resume") or flag?(output, "--continue")),
        structured_output: :not_advertised,
        approval_support: advertised(flag?(output, "--yolo"))
      })

    {%{agent | probe_status: :ok, capabilities: caps}, []}
  end

  defp help(%{id: :pi} = agent, :help, output) do
    mode = flag_block(output, "--mode") || ""

    caps =
      Map.merge(agent.capabilities, %{
        headless: advertised(flag?(output, "--print")),
        streaming: advertised(String.contains?(mode, "json")),
        session_resume: :not_advertised,
        structured_output: :not_advertised,
        approval_support: advertised(flag?(output, "--approve"))
      })

    {%{agent | probe_status: :ok, capabilities: caps}, []}
  end

  defp help(%{id: :opencode} = agent, :help, output) do
    run? = command?(output, "run")

    caps =
      Map.merge(agent.capabilities, %{
        headless: advertised(run?),
        streaming: if(run?, do: :unknown, else: :not_advertised),
        session_resume: advertised(flag?(output, "--continue") or flag?(output, "--session")),
        structured_output: :not_advertised,
        approval_support: advertised(flag?(output, "--auto"))
      })

    {%{agent | probe_status: :ok, capabilities: caps}, if(run?, do: [:run_help], else: [])}
  end

  defp help(%{id: :opencode} = agent, :run_help, output) do
    format = flag_block(output, "--format") || ""

    caps =
      Map.merge(agent.capabilities, %{
        streaming: advertised(String.contains?(format, "stream-json")),
        session_resume:
          advertised(
            agent.capabilities.session_resume == :advertised or flag?(output, "--continue")
          )
      })

    {%{agent | capabilities: caps}, []}
  end

  defp help(agent, :auth_status_help, output),
    do: {agent, if(flag?(output, "--json"), do: [:auth], else: [])}

  defp help_identity?(%{id: :opencode}, :run_help, output),
    do: Regex.match?(~r/^opencode run(?:\s|$)/m, output)

  defp help_identity?(agent, _step, output) do
    Regex.match?(~r/^[Uu]sage: #{Regex.escape(usage_name(agent))}(?:\s|$)/m, output) or
      (agent.id == :opencode and Regex.match?(~r/^ {2,}opencode(?:\s|$)/m, output))
  end

  defp usage_name(%{id: :cursor}), do: "agent"
  defp usage_name(%{id: id}), do: Atom.to_string(id)

  defp auth(:codex, "Not logged in", 1), do: :not_configured
  defp auth(:codex, "Logged in using ChatGPT", 0), do: :configured

  defp auth(:codex, output, 0) do
    if Regex.match?(~r/\ALogged in using an API key(?: - [^\r\n]+)?\z/, output),
      do: :configured,
      else: :unknown
  end

  defp auth(:cursor, output, 0) do
    case Jason.decode(output, objects: :ordered_objects) do
      {:ok, %Jason.OrderedObject{values: values}} ->
        case {
          Enum.filter(values, fn {key, _} -> key == "isAuthenticated" end),
          Enum.filter(values, fn {key, _} -> key == "status" end)
        } do
          {[{"isAuthenticated", true}], [{"status", "authenticated"}]} -> :configured
          _ -> :unknown
        end

      _ ->
        :unknown
    end
  end

  defp auth(:cursor, _, _), do: :unknown

  defp auth(:claude, output, code) do
    case Jason.decode(output, objects: :ordered_objects) do
      {:ok, %Jason.OrderedObject{values: values}} ->
        case {Enum.filter(values, fn {key, _} -> key == "loggedIn" end), code} do
          {[{"loggedIn", true}], 0} -> :configured
          {[{"loggedIn", false}], 1} -> :not_configured
          _ -> :unknown
        end

      _ ->
        :unknown
    end
  end

  defp auth(_, _, _), do: :unknown
  defp advertised(true), do: :advertised
  defp advertised(false), do: :not_advertised

  defp command?(output, command) do
    Enum.any?(
      section(output, "Commands"),
      &Regex.match?(~r/^ {2,}(?:opencode\s+)?#{Regex.escape(command)}(?:\s|\[|\||$)/, &1)
    )
  end

  defp flag?(output, flag), do: flag_block(output, flag) != nil

  defp flag_block(output, flag) do
    lines =
      Enum.drop_while(
        section(output, "Options"),
        &(not Regex.match?(~r/^ {2,}(?:-[A-Za-z?],?\s+)?#{Regex.escape(flag)}(?:\s|=|,|$)/, &1))
      )

    case lines do
      [line | rest] ->
        indent = byte_size(line) - byte_size(String.trim_leading(line))

        continuation =
          Enum.take_while(rest, &String.starts_with?(&1, String.duplicate(" ", indent + 1)))

        Enum.join([line | continuation], "\n")

      [] ->
        nil
    end
  end

  defp section(output, name) do
    output
    |> String.split(~r/\r?\n/)
    |> Enum.drop_while(&(&1 != name <> ":"))
    |> Enum.drop(1)
    |> Enum.take_while(&(&1 == "" or String.starts_with?(&1, " ")))
  end
end
