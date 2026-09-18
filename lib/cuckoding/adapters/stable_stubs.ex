defmodule Cuckoding.Adapters.StableStub do
  @moduledoc false

  alias Cuckoding.Adapters.Types

  def capabilities do
    {:ok,
     %Types.Capabilities{
       structured_output?: false,
       native_resume?: false,
       cancellation?: false,
       usage?: false,
       mcp?: false,
       permission_modes: [],
       model_discovery?: false,
       instruction_files: [],
       skill_directories: []
     }}
  end

  def unavailable(warning),
    do: {:error, Types.Error.new(:adapter_unavailable, :availability, false, warning)}
end

defmodule Cuckoding.Adapters.CursorAgent do
  @moduledoc "Stable Cursor Agent stub blocked by observed global state and plugin leakage."
  @behaviour Cuckoding.Adapters.AgentAdapter

  alias Cuckoding.Adapters.StableStub
  alias Cuckoding.Adapters.Types

  @warning "Cursor Agent is unavailable: the verified CLI wrote user-global session state and started a user-global MCP process despite run-scoped configuration."

  def warning, do: @warning

  @impl true
  def probe(options) do
    runner = Keyword.get(options, :command_runner, &System.cmd/3)

    with {:ok, path} <- cursor_executable(options),
         {version, 0} <- runner.(path, ["--version"], stderr_to_stdout: true),
         {auth, 0} <- runner.(path, ["status", "--format", "json"], stderr_to_stdout: true),
         {:ok, %{"isAuthenticated" => authenticated?}} when is_boolean(authenticated?) <-
           Jason.decode(auth) do
      {:ok,
       %Types.Probe{
         adapter: "cursor_agent",
         path: path,
         version: String.trim(version),
         available?: false,
         authenticated?: authenticated?,
         status: "unsupported_global_state_isolation"
       }}
    else
      {:error, %Types.Error{} = error} -> {:error, error}
      _other -> {:error, Types.Error.new(:probe_failed, :provider, true)}
    end
  end

  @impl true
  def capabilities(_options), do: StableStub.capabilities()

  @impl true
  def render_config(_request, _options), do: StableStub.unavailable(@warning)
  @impl true
  def start(_request, _options), do: StableStub.unavailable(@warning)
  @impl true
  def send(_session, _input, _options), do: StableStub.unavailable(@warning)
  @impl true
  def pause(_session, _options), do: StableStub.unavailable(@warning)
  @impl true
  def resume(_subject, _checkpoint, _options), do: StableStub.unavailable(@warning)
  @impl true
  def recover(_session, _inspection, _options), do: StableStub.unavailable(@warning)
  @impl true
  def cancel(_session, _options), do: StableStub.unavailable(@warning)
  @impl true
  def inspect(_session, _options), do: StableStub.unavailable(@warning)
  @impl true
  def decode_event(_event, _options), do: StableStub.unavailable(@warning)
  @impl true
  def collect_usage(_session, _options), do: StableStub.unavailable(@warning)

  defp cursor_executable(options) do
    case Keyword.get(options, :path) || System.find_executable("cursor-agent") ||
           System.find_executable("agent") do
      path when is_binary(path) -> {:ok, Path.expand(path)}
      _other -> {:error, Types.Error.new(:not_installed, :availability, false)}
    end
  end
end

defmodule Cuckoding.Adapters.OpenCode do
  @moduledoc "Stable OpenCode stub used until a supported CLI and isolated runtime are verified."
  @behaviour Cuckoding.Adapters.AgentAdapter

  alias Cuckoding.Adapters.StableStub
  alias Cuckoding.Adapters.Types

  @warning "OpenCode is unavailable: the desktop app is installed, but no supported OpenCode CLI is on PATH and runtime isolation has not been verified."

  def warning, do: @warning

  @impl true
  def probe(options) do
    finder = Keyword.get(options, :find_executable, &System.find_executable/1)

    case Keyword.get(options, :path) || finder.("opencode") do
      nil ->
        {:ok,
         %Types.Probe{
           adapter: "opencode",
           available?: false,
           authenticated?: false,
           status: "cli_not_installed"
         }}

      path ->
        probe_cli(Path.expand(path), Keyword.get(options, :command_runner, &System.cmd/3))
    end
  end

  @impl true
  def capabilities(_options), do: StableStub.capabilities()

  @impl true
  def render_config(_request, _options), do: StableStub.unavailable(@warning)
  @impl true
  def start(_request, _options), do: StableStub.unavailable(@warning)
  @impl true
  def send(_session, _input, _options), do: StableStub.unavailable(@warning)
  @impl true
  def pause(_session, _options), do: StableStub.unavailable(@warning)
  @impl true
  def resume(_subject, _checkpoint, _options), do: StableStub.unavailable(@warning)
  @impl true
  def recover(_session, _inspection, _options), do: StableStub.unavailable(@warning)
  @impl true
  def cancel(_session, _options), do: StableStub.unavailable(@warning)
  @impl true
  def inspect(_session, _options), do: StableStub.unavailable(@warning)
  @impl true
  def decode_event(_event, _options), do: StableStub.unavailable(@warning)
  @impl true
  def collect_usage(_session, _options), do: StableStub.unavailable(@warning)

  defp probe_cli(path, runner) do
    case runner.(path, ["--version"], stderr_to_stdout: true) do
      {version, 0} ->
        {:ok,
         %Types.Probe{
           adapter: "opencode",
           path: path,
           version: String.trim(version),
           available?: false,
           authenticated?: false,
           status: "runtime_isolation_unverified"
         }}

      _other ->
        {:error, Types.Error.new(:probe_failed, :provider, true)}
    end
  end
end

defmodule Cuckoding.Adapters.Catalog do
  @moduledoc "User-visible runtime availability and selection policy."

  alias Cuckoding.Adapters.CursorAgent
  alias Cuckoding.Adapters.OpenCode

  def experimental_options do
    [
      option("cursor_agent", "Cursor Agent", CursorAgent.warning()),
      option("opencode", "OpenCode", OpenCode.warning())
    ]
  end

  defp option(key, label, warning) do
    %{key: key, label: label, selectable?: false, warning: warning}
  end
end
