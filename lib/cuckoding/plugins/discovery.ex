defmodule Cuckoding.Plugins.Discovery do
  @moduledoc "Discovers manifests and measures declared binary versions without invoking a shell."

  alias Cuckoding.Plugins.Manifest

  def scan(options \\ []) do
    finder = Keyword.get(options, :find_executable, &System.find_executable/1)
    runner = Keyword.get(options, :command_runner, &System.cmd/3)

    options
    |> directories()
    |> Enum.flat_map(fn {source, directory} -> manifest_paths(source, directory) end)
    |> Enum.reduce(%{manifests: [], errors: [], keys: MapSet.new()}, fn {source, path}, result ->
      case Manifest.load(path, source) do
        {:ok, manifest} -> add_manifest(result, manifest, finder, runner)
        {:error, reason} -> add_error(result, path, reason)
      end
    end)
    |> Map.delete(:keys)
    |> Map.update!(:manifests, &Enum.reverse/1)
    |> Map.update!(:errors, &Enum.reverse/1)
  end

  defp directories(options) do
    [
      {"bundled", Keyword.get(options, :bundled_dir, bundled_dir())},
      {"user", Keyword.get(options, :user_dir, user_dir())}
    ]
  end

  defp bundled_dir, do: Application.app_dir(:cuckoding, "priv/plugins")

  defp user_dir do
    Path.join([System.user_home!(), "Library", "Application Support", "Cuckoding", "plugins"])
  end

  defp manifest_paths(_source, nil), do: []

  defp manifest_paths(source, directory) do
    case File.ls(directory) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.flat_map(&manifest_path(source, directory, &1))

      {:error, :enoent} ->
        []

      {:error, reason} ->
        [{source, {:directory_error, directory, reason}}]
    end
  end

  defp manifest_path(source, directory, entry) do
    plugin_dir = Path.join(directory, entry)

    case File.lstat(plugin_dir) do
      {:ok, %{type: :directory}} -> [{source, Path.join(plugin_dir, "plugin.yml")}]
      _other -> []
    end
  end

  defp add_manifest(result, manifest, finder, runner) do
    key = manifest.data["key"]

    if MapSet.member?(result.keys, key) do
      add_error(result, manifest.path, {:duplicate_plugin_key, key})
    else
      detection = detect(manifest, finder, runner)

      result
      |> Map.update!(:keys, &MapSet.put(&1, key))
      |> Map.update!(:manifests, &[{manifest, detection} | &1])
    end
  end

  defp add_error(result, {:directory_error, directory, reason}, _ignored) do
    Map.update!(result, :errors, &[%{path: directory, reason: reason} | &1])
  end

  defp add_error(result, path, reason) do
    Map.update!(result, :errors, &[%{path: path, reason: reason} | &1])
  end

  defp detect(manifest, finder, runner) do
    manifest.data["detect"]["binaries"]
    |> Enum.map(&detect_binary(&1, finder, runner))
    |> detection_result()
  end

  defp detect_binary(binary, finder, runner) do
    case finder.(binary["name"]) do
      path when is_binary(path) -> run_version(path, binary, runner)
      _missing -> %{name: binary["name"], state: "missing", version: nil, path: nil}
    end
  end

  defp run_version(path, binary, runner) do
    argument = Enum.at(binary["version_command"], 1)

    try do
      case runner.(path, [argument], stderr_to_stdout: true) do
        {output, 0} ->
          version_result(path, binary, output)

        {_output, status} ->
          %{name: binary["name"], state: "unhealthy", version: nil, path: path, exit: status}
      end
    rescue
      error ->
        %{
          name: binary["name"],
          state: "unhealthy",
          version: nil,
          path: path,
          error: Exception.message(error)
        }
    end
  end

  defp version_result(path, binary, output) do
    case Regex.run(~r/\b\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\b/, output) do
      [version] ->
        state =
          if Version.compare(version, binary["min_version"]) in [:eq, :gt],
            do: "available",
            else: "version_mismatch"

        %{name: binary["name"], state: state, version: version, path: path}

      _no_version ->
        %{name: binary["name"], state: "unhealthy", version: nil, path: path}
    end
  end

  defp detection_result([]), do: %{health: "available", binaries: %{}, last_error: nil}

  defp detection_result(results) do
    health =
      cond do
        Enum.any?(results, &(&1.state == "missing")) -> "missing"
        Enum.any?(results, &(&1.state == "version_mismatch")) -> "version_mismatch"
        Enum.any?(results, &(&1.state == "unhealthy")) -> "unhealthy"
        true -> "available"
      end

    binaries = Map.new(results, &{&1.name, Map.drop(&1, [:name])})
    last_error = if health == "available", do: nil, else: detection_error(results)
    %{health: health, binaries: binaries, last_error: last_error}
  end

  defp detection_error(results) do
    results
    |> Enum.reject(&(&1.state == "available"))
    |> Enum.map_join(", ", &"#{&1.name}: #{&1.state}")
  end
end
