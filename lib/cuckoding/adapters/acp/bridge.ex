defmodule Cuckoding.Adapters.ACP.Bridge do
  @moduledoc "App-packaged, pinned ACP bridges. Never downloads or discovers a global bridge."

  @versions %{"codex" => "1.13.1+cuckoding.1", "claude" => "0.81.2+cuckoding.1"}

  def executable(name, options \\ []) when is_map_key(@versions, name) do
    root =
      Keyword.get(options, :bridge_directory) ||
        Application.app_dir(:cuckoding, "priv/agent_bridges")

    path = Path.join(root, "#{name}-acp")

    with {:ok, %{type: :regular, size: size}} when size <= 16_384 <-
           File.lstat(Path.join(root, "manifest.json")),
         {:ok, json} <- File.read(Path.join(root, "manifest.json")),
         {:ok, %{"schema" => 1, "bridges" => bridges}} <- Jason.decode(json),
         %{"version" => version, "sha256" => expected} <- bridges[name],
         true <- version == @versions[name],
         {:ok, %{type: :regular, size: size, mode: mode}} when size <= 268_435_456 <-
           File.lstat(path),
         true <- Bitwise.band(mode, 0o111) != 0 and Bitwise.band(mode, 0o022) == 0,
         {:ok, binary} <- File.read(path),
         true <- Base.encode16(:crypto.hash(:sha256, binary), case: :lower) == expected do
      {:ok, path}
    else
      {:error, :enoent} -> {:error, :acp_bridge_not_built}
      _ -> {:error, :acp_bridge_unverified}
    end
  end
end
