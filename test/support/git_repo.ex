defmodule AgentDesk.GitRepo do
  @moduledoc false

  def tmp_repo!(prefix \\ "agentdesk") do
    root =
      Path.join(
        System.tmp_dir!(),
        "#{prefix}-#{System.system_time(:microsecond)}-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)
    git!(root, ["init", "-b", "main"])
    git!(root, ["config", "user.email", "test@agentdesk.test"])
    git!(root, ["config", "user.name", "AgentDesk Test"])
    File.write!(Path.join(root, "README.md"), "fixture\n")
    git!(root, ["add", "-f", "README.md"])
    git!(root, ["-c", "commit.gpgsign=false", "commit", "-m", "init"])
    root
  end

  def add_file!(root, name, contents) when is_binary(name) and is_binary(contents) do
    File.write!(Path.join(root, name), contents)
    git!(root, ["add", "-f", name])
    git!(root, ["-c", "commit.gpgsign=false", "commit", "-m", "add #{name}"])
    root
  end

  def set_origin!(root, url) when is_binary(url) do
    env =
      Enum.reject(System.get_env(), fn {key, _value} -> String.starts_with?(key, "GIT_") end)

    case System.cmd("git", ["-C", root, "remote", "get-url", "origin"],
           env: env,
           stderr_to_stdout: true
         ) do
      {_, 0} -> git!(root, ["remote", "set-url", "origin", url])
      _ -> git!(root, ["remote", "add", "origin", url])
    end

    root
  end

  defp git!(root, args) do
    env =
      Enum.reject(System.get_env(), fn {key, _value} -> String.starts_with?(key, "GIT_") end)

    case System.cmd("git", ["-C", root | args], env: env, stderr_to_stdout: true) do
      {_, 0} = result ->
        result

      {output, status} ->
        raise "git #{Enum.join(args, " ")} failed (#{status}): #{output}"
    end
  end
end
