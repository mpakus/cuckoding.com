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

  @spec provider_started(Ecto.UUID.t(), String.t()) :: :ok
  def provider_started(session_id, provider) do
    :telemetry.execute(
      [:agent_desk, :provider, :started],
      %{count: 1},
      %{session_id: session_id, provider: provider}
    )
  end

  @spec provider_exited(Ecto.UUID.t(), integer()) :: :ok
  def provider_exited(session_id, status) do
    :telemetry.execute(
      [:agent_desk, :provider, :exited],
      %{count: 1, status: status},
      %{session_id: session_id}
    )
  end
end
