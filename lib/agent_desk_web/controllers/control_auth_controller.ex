defmodule AgentDeskWeb.ControlAuthController do
  use AgentDeskWeb, :controller

  alias AgentDesk.Security.ControlAuth

  def readiness(conn, _params) do
    case ControlAuth.readiness_proof() do
      {:ok, proof} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> text(proof)

      {:error, :unavailable} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_status(:service_unavailable)
        |> text("unavailable")
    end
  end

  def bootstrap(conn, %{"token" => token}) do
    case ControlAuth.consume_bootstrap(token) do
      {:ok, binding} ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> put_resp_header("referrer-policy", "no-referrer")
        |> ControlAuth.put_authorized_session(binding)
        |> redirect(to: ~p"/")

      {:error, :unauthorized} ->
        unauthorized(conn)
    end
  end

  def bootstrap(conn, _params), do: unauthorized(conn)

  def unauthorized(conn, _params), do: unauthorized(conn)

  defp unauthorized(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_status(:unauthorized)
    |> text("Desktop control authorization required.")
  end
end
