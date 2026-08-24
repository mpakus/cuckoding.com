defmodule AgentDesk.Env do
  @moduledoc """
  Desktop PATH bootstrap.

  Finder-launched macOS apps inherit a stripped PATH, so Homebrew/npm CLIs like
  `codex` are invisible until we merge the login-shell PATH and common bin dirs.
  """

  @spec bootstrap!() :: :ok
  def bootstrap! do
    System.put_env("PATH", merge_path([login_path(), System.get_env("PATH") | extra_dirs()]))
    :ok
  end

  @spec extra_dirs() :: [String.t()]
  def extra_dirs do
    home = System.user_home()

    [
      "/opt/homebrew/bin",
      "/opt/homebrew/sbin",
      "/usr/local/bin",
      "/usr/bin",
      "/bin",
      home && Path.join(home, ".local/bin"),
      home && Path.join(home, ".cargo/bin"),
      home && Path.join(home, ".npm-global/bin"),
      home && Path.join(home, ".volta/bin"),
      home && Path.join(home, ".asdf/shims"),
      home && Path.join(home, ".bun/bin"),
      home && Path.join(home, "Library/pnpm")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&File.dir?/1)
  end

  @spec merge_path([String.t() | nil]) :: String.t()
  def merge_path(parts) when is_list(parts) do
    parts
    |> Enum.flat_map(&split_path/1)
    |> Enum.uniq()
    |> Enum.join(":")
  end

  defp split_path(nil), do: []
  defp split_path(""), do: []

  defp split_path(part) when is_binary(part) do
    part
    |> String.split(":")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp login_path do
    if Application.get_env(:agent_desk, :inherit_login_path, false) do
      read_login_path()
    else
      ""
    end
  end

  defp read_login_path do
    shell = System.get_env("SHELL") || "/bin/zsh"

    if File.regular?(shell) do
      task =
        Task.async(fn ->
          System.cmd(shell, ["-l", "-c", "printf %s \"$PATH\""], stderr_to_stdout: true)
        end)

      case Task.yield(task, 2_000) || Task.shutdown(task, :brutal_kill) do
        {:ok, {path, 0}} -> path
        _ -> ""
      end
    else
      ""
    end
  end
end
