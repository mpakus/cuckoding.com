defmodule AgentDesk.Git do
  @moduledoc """
  Git repository probes used when opening a project.

  Destructive Git operations are not performed here.
  """

  @spec repository?(Path.t()) :: boolean()
  def repository?(path) when is_binary(path) do
    git_dir = Path.join(path, ".git")
    File.exists?(git_dir)
  end
end
