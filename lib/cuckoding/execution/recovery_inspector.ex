defmodule Cuckoding.Execution.RecoveryInspector do
  @moduledoc """
  Read-only boundary for verifying host resources during reconciliation.

  The Phase 3 local runner supplies the macOS implementation. Reconciliation never signals,
  adopts, deletes, or rewrites a host resource through this boundary.
  """

  @callback process_identity(pos_integer(), keyword()) ::
              {:ok, String.t()} | :gone | {:error, atom()}
  @callback port_owner(:inet.port_number(), keyword()) ::
              :free | {:ok, pos_integer(), String.t()} | {:error, atom()}
  @callback worktree_status(String.t(), String.t(), keyword()) ::
              :present | :missing | {:drift, atom()} | {:error, atom()}
end

defmodule Cuckoding.Execution.UnavailableRecoveryInspector do
  @moduledoc false
  @behaviour Cuckoding.Execution.RecoveryInspector

  @impl true
  def process_identity(_pid, _options), do: {:error, :inspector_unavailable}

  @impl true
  def port_owner(_port, _options), do: {:error, :inspector_unavailable}

  @impl true
  def worktree_status(_path, _base_sha, _options), do: {:error, :inspector_unavailable}
end
