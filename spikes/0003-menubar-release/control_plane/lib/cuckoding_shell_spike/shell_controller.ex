defmodule CuckodingShellSpike.ShellController do
  use Phoenix.Controller, formats: [:html, :json]

  alias CuckodingShellSpike.Auth

  def open(conn, %{"token" => token}) do
    if Auth.consume_browser_token(token) do
      next = safe_next(conn.params["next"])
      conn |> put_session(:browser_authenticated, true) |> redirect(to: next)
    else
      unauthorized(conn)
    end
  end

  def open(conn, _params), do: unauthorized(conn)

  def bootstrap(conn, _params) do
    with {:ok, token} <- bearer(conn), {:ok, shell} <- Auth.bootstrap(token) do
      json(conn, %{shell_token: shell})
    else
      _ -> unauthorized(conn)
    end
  end

  def token(conn, _params) do
    with {:ok, shell} <- bearer(conn), {:ok, token} <- Auth.browser_token(shell) do
      json(conn, %{token: token, expires_in: 60})
    else
      _ -> unauthorized(conn)
    end
  end

  def status(conn, _params) do
    if shell?(conn), do: json(conn, %{active_runs: 0, attention: 0}), else: unauthorized(conn)
  end

  def shutdown(conn, _params) do
    if shell?(conn) do
      Task.start(fn ->
        Process.sleep(100)
        System.stop(0)
      end)

      json(conn, %{status: "stopping"})
    else
      unauthorized(conn)
    end
  end

  def crash(conn, _params) do
    if shell?(conn) do
      Task.start(fn ->
        Process.sleep(100)
        :erlang.halt(42)
      end)

      json(conn, %{status: "crashing"})
    else
      unauthorized(conn)
    end
  end

  def unauthorized(conn), do: conn |> put_status(401) |> text("unauthorized")

  defp shell?(conn) do
    case bearer(conn) do
      {:ok, token} -> Auth.shell?(token)
      :error -> false
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> :error
    end
  end

  defp safe_next("/settings"), do: "/settings"
  defp safe_next(_), do: "/"
end
