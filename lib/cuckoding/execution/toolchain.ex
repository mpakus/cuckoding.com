defmodule Cuckoding.Execution.Toolchain do
  @moduledoc "Metadata-only discovery of native developer tools; no shell profiles or personal HOME."

  @names ~w(node npm pnpm yarn bun mix elixir erl bundle ruby cargo rustc uv python python3 git)
  @companions %{
    "npm" => ["node"],
    "pnpm" => ["node"],
    "yarn" => ["node"],
    "mix" => ["elixir", "erl"],
    "elixir" => ["erl"],
    "bundle" => ["ruby"],
    "cargo" => ["rustc"]
  }
  @system_path "/usr/bin:/bin:/usr/sbin:/sbin"

  def catalog(options \\ []) do
    home =
      Keyword.get(options, :home, System.get_env("CUCKODING_RUNTIME_HOME") || System.user_home())

    path = Keyword.get(options, :path, System.get_env("PATH", ""))

    system =
      Keyword.get(options, :system_dirs, ~w(/opt/homebrew/bin /usr/local/bin /usr/bin /bin))

    installed =
      if home do
        [".local/bin", ".bun/bin", ".npm-global/bin"]
        |> Enum.map(&Path.join(home, &1))
        |> Kernel.++(versioned_bins(home))
      else
        []
      end

    roots =
      (String.split(path, ":", trim: true) ++ system ++ installed)
      |> Enum.filter(&(Path.type(&1) == :absolute and Path.basename(&1) == "bin"))
      |> Enum.uniq()

    Map.new(@names, fn name ->
      candidates =
        roots
        |> Enum.map(&Path.join(&1, name))
        |> Enum.filter(&native_executable?/1)
        |> Enum.take(20)

      {name, candidates}
    end)
  end

  defp versioned_bins(home) do
    # Bounded installer layouts, not a recursive home scan. Selection is visible
    # in planning and Run; personal version-manager configuration is never loaded.
    for pattern <- [
          ".volta/tools/image/node/*/bin",
          ".asdf/installs/*/*/bin",
          ".local/share/mise/installs/*/*/bin",
          ".rvm/rubies/*/bin",
          ".rbenv/versions/*/bin",
          ".pyenv/versions/*/bin",
          ".rustup/toolchains/*/bin"
        ],
        path <- home |> Path.join(pattern) |> Path.wildcard() |> Enum.sort(:desc) |> Enum.take(20),
        do: path
  end

  def resolve(program, catalog) when is_binary(program) do
    candidates = catalog[Path.basename(program)] || []
    path = if Path.basename(program) == program, do: List.first(candidates), else: program

    if path in candidates, do: {:ok, path}, else: {:error, :goal_toolchain_unavailable}
  end

  def snapshot(commands, catalog \\ catalog()) do
    paths = commands |> Enum.map(fn %{"command" => [path | _]} -> path end) |> Enum.uniq()
    primary = Map.new(paths, &{Path.basename(&1), &1})

    with true <- map_size(primary) == length(paths),
         {:ok, tools} <- companions(primary, catalog),
         {:ok, files} <- file_records(tools) do
      {:ok, %{"tools" => files}}
    else
      false -> {:error, :goal_toolchain_unavailable}
      error -> error
    end
  end

  def environment(%{"tools" => files}) do
    paths = files |> Enum.map(&Path.dirname(&1["path"])) |> Enum.uniq()
    %{"PATH" => Enum.join(paths ++ [@system_path], ":")}
  end

  def environment(nil), do: %{}

  defp companions(primary, catalog) do
    Enum.reduce_while(primary, {:ok, primary}, fn {name, path}, {:ok, tools} ->
      case add_companions(name, path, tools, catalog) do
        {:ok, tools} -> {:cont, {:ok, tools}}
        error -> {:halt, error}
      end
    end)
  end

  defp add_companions(name, path, tools, catalog) do
    Enum.reduce_while(@companions[name] || [], {:ok, tools}, fn name, {:ok, tools} ->
      sibling = Path.join(Path.dirname(path), name)

      selected =
        tools[name] ||
          if(native_executable?(sibling), do: sibling, else: List.first(catalog[name] || []))

      if selected,
        do: {:cont, {:ok, Map.put(tools, name, selected)}},
        else: {:halt, {:error, :goal_toolchain_unavailable}}
    end)
  end

  def current?(%{"tools" => files}) when is_list(files) and files != [] do
    Enum.all?(files, fn file -> record(file["name"], file["path"]) == {:ok, file} end)
  end

  def current?(_), do: false
  def version_args("erl"), do: ["-version"]
  def version_args(_), do: ["--version"]

  defp file_records(tools) do
    tools
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn {name, path}, {:ok, records} ->
      case record(name, path) do
        {:ok, file} -> {:cont, {:ok, records ++ [file]}}
        error -> {:halt, error}
      end
    end)
  end

  defp record(name, path) do
    with true <- native_executable?(path),
         {:ok, stat} <- File.stat(path, time: :posix) do
      {:ok,
       %{
         "name" => name,
         "path" => path,
         "size" => stat.size,
         "mtime" => stat.mtime,
         "inode" => stat.inode
       }}
    else
      _ -> {:error, :goal_toolchain_unavailable}
    end
  end

  defp native_executable?(path) when is_binary(path) do
    not shim?(path, 0) and Path.type(path) == :absolute and not String.contains?(path, ":") and
      case File.stat(path) do
        {:ok, %{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o111) != 0
        _ -> false
      end
  end

  defp native_executable?(_), do: false

  defp shim?(_path, depth) when depth >= 8, do: true

  defp shim?(path, depth) do
    Enum.any?(~w(/shims/ /.volta/bin/ /.cargo/bin/), &String.contains?(path, &1)) or
      case File.read_link(path) do
        {:ok, target} -> shim?(Path.expand(target, Path.dirname(path)), depth + 1)
        _ -> false
      end
  end
end
