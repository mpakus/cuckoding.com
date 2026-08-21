defmodule AgentDesk.GitRepo do
  @moduledoc false

  def tmp_repo!(prefix \\ "agentdesk") do
    root =
      Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    {_, 0} = System.cmd("git", ["init"], cd: root, stderr_to_stdout: true)
    {_, 0} = System.cmd("git", ["config", "user.email", "test@agentdesk.test"], cd: root)
    {_, 0} = System.cmd("git", ["config", "user.name", "AgentDesk Test"], cd: root)
    File.write!(Path.join(root, "README.md"), "fixture\n")
    {_, 0} = System.cmd("git", ["add", "."], cd: root, stderr_to_stdout: true)
    {_, 0} = System.cmd("git", ["commit", "-m", "init"], cd: root, stderr_to_stdout: true)

    root
  end
end
