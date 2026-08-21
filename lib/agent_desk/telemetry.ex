defmodule AgentDesk.Telemetry do
  @moduledoc """
  Domain telemetry helpers. Event names stay stable for later adapters and dashboards.
  """

  @spec project_opened(Ecto.UUID.t()) :: :ok
  def project_opened(project_id) when is_binary(project_id) do
    :telemetry.execute([:agent_desk, :project, :opened], %{count: 1}, %{project_id: project_id})
  end

  @spec project_closed(Ecto.UUID.t()) :: :ok
  def project_closed(project_id) when is_binary(project_id) do
    :telemetry.execute([:agent_desk, :project, :closed], %{count: 1}, %{project_id: project_id})
  end
end
