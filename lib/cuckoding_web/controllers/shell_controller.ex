defmodule CuckodingWeb.ShellController do
  use CuckodingWeb, :controller
  alias Cuckoding.{Battles, ShellAuth}
  plug :require_shell when action in [:open, :status, :quit]

  def bootstrap(conn, _) do
    case ShellAuth.bootstrap(bearer(conn)) do
      {:ok, token} -> json(conn, %{token: token})
      _ -> send_resp(conn, 401, "Unauthorized")
    end
  end

  def open(conn, _), do: json(conn, %{token: ShellAuth.handoff()})

  def status(conn, _) do
    json(conn, %{
      status: "ready",
      version: "0.1.0",
      idle_sleep: %{
        contract: "shell-lease-v1",
        requested: Battles.idle_sleep_requested?(),
        lease_seconds: ShellAuth.power_lease_seconds()
      }
    })
  end

  def quit(conn, _) do
    Cuckoding.Foundation.record("shell.quit_requested")

    unless Application.get_env(:cuckoding, :testing) do
      Process.send_after(ShellAuth, :shutdown, 100)
    end

    conn |> put_status(202) |> json(%{status: "stopping"})
  end

  defp require_shell(conn, _) do
    power =
      case get_req_header(conn, "x-cc-power-state") do
        [] -> nil
        [state] -> state
        _ -> :invalid
      end

    case ShellAuth.authorize(bearer(conn), power) do
      :ok -> conn
      {:error, :invalid_power_state} -> conn |> send_resp(400, "Invalid power state") |> halt()
      _ -> conn |> send_resp(401, "Unauthorized") |> halt()
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end
end
