defmodule CuckodingWeb.ShellController do
  use CuckodingWeb, :controller
  alias Cuckoding.ShellAuth
  plug :require_shell when action in [:open, :status, :quit]

  def bootstrap(conn, _) do
    case ShellAuth.bootstrap(bearer(conn)) do
      {:ok, token} -> json(conn, %{token: token})
      _ -> send_resp(conn, 401, "Unauthorized")
    end
  end

  def open(conn, _), do: json(conn, %{token: ShellAuth.handoff()})
  def status(conn, _), do: json(conn, %{status: "ready", version: "0.1.0"})

  def quit(conn, _) do
    Cuckoding.Foundation.record("shell.quit_requested")

    unless Application.get_env(:cuckoding, :testing) do
      Task.start(fn ->
        Process.sleep(100)
        System.stop(0)
      end)
    end

    conn |> put_status(202) |> json(%{status: "stopping"})
  end

  defp require_shell(conn, _) do
    if ShellAuth.authorize(bearer(conn)) == :ok,
      do: conn,
      else: conn |> send_resp(401, "Unauthorized") |> halt()
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end
end
