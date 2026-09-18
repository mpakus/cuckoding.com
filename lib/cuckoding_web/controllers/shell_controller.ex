defmodule CuckodingWeb.ShellController do
  use CuckodingWeb, :controller

  alias Cuckoding.Shell
  alias Cuckoding.Shell.Auth

  plug CuckodingWeb.LoopbackOnly

  def open(conn, %{"token" => token}) do
    if Auth.consume_browser_token(token) do
      conn
      |> put_session(:browser_authenticated, true)
      |> redirect(to: safe_next(conn.params["next"]))
    else
      unauthorized(conn)
    end
  end

  def open(conn, _params), do: unauthorized(conn)

  def bootstrap(conn, _params) do
    with {:ok, token} <- bearer(conn),
         {:ok, shell} <- Auth.bootstrap(token) do
      json(conn, %{shell_token: shell})
    else
      _other -> unauthorized(conn)
    end
  end

  def token(conn, _params) do
    with {:ok, shell} <- bearer(conn),
         {:ok, token} <- Auth.browser_token(shell) do
      json(conn, %{token: token, expires_in: 60})
    else
      _other -> unauthorized(conn)
    end
  end

  def status(conn, _params) do
    if shell?(conn), do: json(conn, Shell.status()), else: unauthorized(conn)
  end

  def shutdown(conn, _params) do
    with true <- shell?(conn),
         :ok <- Shell.shutdown() do
      stop_callback =
        Application.get_env(:cuckoding, :shell_stop_callback, &System.stop/1)

      Task.start(fn ->
        Process.sleep(100)
        stop_callback.(0)
      end)

      json(conn, %{status: "stopping"})
    else
      false -> unauthorized(conn)
      {:error, _reason} -> conn |> put_status(:conflict) |> json(%{error: "shutdown_blocked"})
    end
  end

  def unauthorized(conn, _params \\ %{}),
    do: conn |> put_status(:unauthorized) |> text("unauthorized")

  defp shell?(conn) do
    case bearer(conn) do
      {:ok, token} -> Auth.shell?(token)
      :error -> false
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _other -> :error
    end
  end

  defp safe_next("/settings/plugins"), do: "/settings/plugins"
  defp safe_next(_next), do: "/"
end
