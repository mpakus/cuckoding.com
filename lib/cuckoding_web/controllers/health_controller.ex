defmodule CuckodingWeb.HealthController do
  use CuckodingWeb, :controller

  def health(conn, _params) do
    health = Cuckoding.Health.snapshot()
    conn |> put_status(http_status(health.status)) |> json(health)
  end

  def status(conn, _params) do
    health = Cuckoding.Health.snapshot()

    conn
    |> put_status(http_status(health.status))
    |> json(%{health: health, configuration: Cuckoding.Config.safe_snapshot()})
  end

  defp http_status(:ok), do: :ok
  defp http_status(_status), do: :service_unavailable
end
