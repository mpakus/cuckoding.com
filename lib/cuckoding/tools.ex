defmodule Cuckoding.Tools do
  @moduledoc "Bounded executable metadata lookup. Found never means authorized."
  import Bitwise

  @names [
    {"rtk", ["rtk"]},
    {"codex", ["codex"]},
    {"claude", ["claude"]},
    {"cursor", ["cursor-agent", "agent"]},
    {"hermes", ["hermes"]}
  ]

  def desktop_codex do
    Enum.find(
      [
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "/Applications/Codex.app/Contents/Resources/codex"
      ],
      &executable?/1
    )
  end

  def discover(paths \\ directories()) do
    Map.new(@names, fn {key, names} ->
      candidates = for directory <- paths, name <- names, do: Path.join(directory, name)
      path = Enum.find(candidates, &executable?/1)

      {key, if(path, do: %{"status" => "found", "path" => path}, else: %{"status" => "missing"})}
    end)
  end

  defp executable?(path) do
    with :absolute <- Path.type(path),
         {:ok, %{type: :regular, mode: mode}} <- File.stat(path) do
      band(mode, 0o111) != 0
    else
      _ -> false
    end
  end

  defp directories do
    home = Application.get_env(:cuckoding, :discovery_home)

    personal =
      if home && Path.type(home) == :absolute do
        Enum.map(
          [".local/bin", ".volta/bin", ".npm-global/bin", ".bun/bin", ".asdf/shims"],
          &Path.join(home, &1)
        )
      else
        []
      end

    personal ++
      [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/Applications/Codex.app/Contents/Resources"
      ]
  end
end
