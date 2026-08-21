defmodule AgentDesk.GitRepo do
  @moduledoc false

  def tmp_repo!(prefix \\ "agentdesk") do
    root =
      Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    {_, 0} = System.cmd("git", ["init"], cd: root, stderr_to_stdout: true)

    root
  end
end
