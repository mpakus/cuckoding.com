defmodule Cuckoding.Adapters.RuntimeConfiguration do
  @moduledoc "Validates machine-local settings for selectable agent runtimes."

  alias Cuckoding.Adapters.CursorAgent
  alias Cuckoding.Adapters.OpenCode

  @options [
    {"Codex", "codex"},
    {"Claude Code", "claude_code"},
    {"Cursor Agent", "cursor_agent"},
    {"OpenCode", "opencode"},
    {"Custom Agent", "custom_agent"}
  ]
  @runtimes Enum.map(@options, &elem(&1, 1))

  def options, do: @options

  # Do not present guessed models as provider availability.
  def models(_runtime), do: []

  def default_executable("codex"), do: discover_executable(["codex"])
  def default_executable("claude_code"), do: discover_executable(["claude"])
  def default_executable("cursor_agent"), do: discover_executable(["cursor-agent", "agent"])
  def default_executable("opencode"), do: discover_executable(["opencode"])
  def default_executable("custom_agent"), do: ""
  def default_executable(_runtime), do: ""

  def warning("cursor_agent"), do: CursorAgent.warning()
  def warning("opencode"), do: OpenCode.warning()

  def warning("custom_agent"),
    do:
      "Custom Agent can be saved as a project connection, but runs remain blocked until a compatible adapter is implemented and reviewed."

  def warning(_runtime), do: nil

  def validate(attrs) when is_map(attrs) do
    with {:ok, runtime} <- runtime(attrs["runtime"]),
         {:ok, executable} <- executable(attrs["executable_path"]),
         {:ok, helper} <- helper(runtime, attrs["api_key_helper"]),
         {:ok, model} <- model(attrs["model"]),
         {:ok, reasoning_effort} <- reasoning_effort(runtime, attrs["reasoning_effort"]) do
      settings =
        %{"executable_path" => executable}
        |> maybe_put("api_key_helper", helper)
        |> maybe_put("model", model)
        |> maybe_put("reasoning_effort", reasoning_effort)

      {:ok, %{runtime: runtime, settings: settings}}
    end
  end

  defp runtime(runtime) when runtime in @runtimes, do: {:ok, runtime}
  defp runtime(_runtime), do: {:error, :unsupported_runtime}

  defp model(value) when value in [nil, ""], do: {:ok, nil}

  defp model(value) when is_binary(value) do
    if byte_size(value) <= 128 and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.:\/-]*\z/, value),
      do: {:ok, value},
      else: {:error, :invalid_model}
  end

  defp model(_value), do: {:error, :invalid_model}

  defp reasoning_effort(_runtime, value) when value in [nil, ""], do: {:ok, nil}

  defp reasoning_effort("codex", value)
       when value in ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"],
       do: {:ok, value}

  defp reasoning_effort(_runtime, _value), do: {:error, :invalid_reasoning_effort}

  defp discover_executable(names) do
    roots =
      [
        System.user_home() && Path.join(System.user_home(), ".local/bin"),
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin"
      ]
      |> Enum.reject(&is_nil/1)

    Enum.find_value(names, &System.find_executable/1) ||
      Enum.find_value(for(root <- roots, name <- names, do: Path.join(root, name)), "", fn path ->
        if match?({:ok, _}, executable(path)), do: path
      end)
  end

  defp executable(path) when is_binary(path) do
    expanded = Path.expand(path)

    if Path.type(path) == :absolute do
      case File.stat(expanded) do
        {:ok, %{type: :regular, mode: mode}} when Bitwise.band(mode, 0o111) != 0 ->
          {:ok, expanded}

        _other ->
          {:error, :invalid_runtime_executable}
      end
    else
      {:error, :invalid_runtime_executable}
    end
  end

  defp executable(_path), do: {:error, :invalid_runtime_executable}

  defp helper("claude_code", path), do: executable(path)
  defp helper(_runtime, _path), do: {:ok, nil}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
