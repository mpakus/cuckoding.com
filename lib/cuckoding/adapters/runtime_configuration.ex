defmodule Cuckoding.Adapters.RuntimeConfiguration do
  @moduledoc "Validates machine-local settings for selectable agent runtimes."

  @runtimes ~w(codex claude_code)

  def options, do: [{"Codex", "codex"}, {"Claude Code", "claude_code"}]

  def validate(attrs) when is_map(attrs) do
    with {:ok, runtime} <- runtime(attrs["runtime"]),
         {:ok, executable} <- executable(attrs["executable_path"]),
         {:ok, helper} <- helper(runtime, attrs["api_key_helper"]) do
      settings =
        %{"executable_path" => executable}
        |> maybe_put("api_key_helper", helper)

      {:ok, %{runtime: runtime, settings: settings}}
    end
  end

  defp runtime(runtime) when runtime in @runtimes, do: {:ok, runtime}
  defp runtime(_runtime), do: {:error, :unsupported_runtime}

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

  defp helper("codex", _path), do: {:ok, nil}
  defp helper("claude_code", path), do: executable(path)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
