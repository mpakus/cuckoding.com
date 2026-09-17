defmodule Cuckoding.FakeRecoveryInspector do
  @moduledoc false
  @behaviour Cuckoding.Execution.RecoveryInspector

  @impl true
  def process_identity(pid, options) do
    options |> Keyword.get(:processes, %{}) |> Map.get(pid, :gone)
  end

  @impl true
  def port_owner(port, options) do
    options |> Keyword.get(:ports, %{}) |> Map.get(port, :free)
  end

  @impl true
  def worktree_status(path, _base_sha, options) do
    options |> Keyword.get(:worktrees, %{}) |> Map.get(path, :missing)
  end
end
