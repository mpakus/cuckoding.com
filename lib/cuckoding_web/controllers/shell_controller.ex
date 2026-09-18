defmodule CuckodingWeb.ShellController do
  use CuckodingWeb, :controller

  alias Cuckoding.Diagnostics
  alias Cuckoding.Security.Audit
  alias Cuckoding.Shell
  alias Cuckoding.Shell.Auth
  alias Cuckoding.Updates

  plug CuckodingWeb.LoopbackOnly

  def open(conn, %{"token" => token}) do
    if Auth.consume_browser_token(token) do
      conn
      |> put_session(:browser_authenticated, true)
      |> redirect(to: safe_next(conn.params["next"]))
    else
      reject(conn, "auth.browser_token_rejected")
    end
  end

  def open(conn, _params), do: reject(conn, "auth.browser_token_rejected")

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

  def diagnostics(conn, _params) do
    with true <- shell?(conn),
         {:ok, path} <- Diagnostics.export() do
      json(conn, %{path: path, contents: Diagnostics.contents()})
    else
      false -> unauthorized(conn)
      {:error, _reason} -> conn |> put_status(:conflict) |> json(%{error: "diagnostics_failed"})
    end
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

  def prepare_update(conn, params) do
    with true <- shell?(conn),
         version when is_binary(version) <- params["version"],
         schema_change when is_boolean(schema_change) <- Map.get(params, "schema_change", true),
         {:ok, attempt} <- Updates.prepare(version, schema_change) do
      json(conn, %{attempt_id: attempt.id, status: attempt.state})
    else
      false -> unauthorized(conn)
      _other -> conn |> put_status(:conflict) |> json(%{error: "update_prepare_blocked"})
    end
  end

  def update_installing(conn, %{"attempt_id" => attempt_id}) do
    with true <- shell?(conn),
         {:ok, attempt} <- Updates.mark_installing(attempt_id) do
      json(conn, %{attempt_id: attempt.id, status: attempt.state})
    else
      false -> unauthorized(conn)
      _other -> conn |> put_status(:conflict) |> json(%{error: "update_not_prepared"})
    end
  end

  def update_installing(conn, _params),
    do: conn |> put_status(:bad_request) |> json(%{error: "invalid_update"})

  def update_failed(conn, %{"attempt_id" => attempt_id, "reason" => reason})
      when is_binary(reason) do
    with true <- shell?(conn),
         {:ok, attempt} <- Updates.mark_failed(attempt_id, reason) do
      json(conn, %{attempt_id: attempt.id, status: attempt.state})
    else
      false -> unauthorized(conn)
      _other -> conn |> put_status(:conflict) |> json(%{error: "update_failure_not_recorded"})
    end
  end

  def update_failed(conn, _params),
    do: conn |> put_status(:bad_request) |> json(%{error: "invalid_update"})

  def update_healthy(conn, _params) do
    with true <- shell?(conn),
         {:ok, attempt} <- Updates.mark_healthy_pending() do
      json(conn, %{attempt_id: attempt.id, status: attempt.state})
    else
      false -> unauthorized(conn)
      {:error, :update_not_pending} -> json(conn, %{status: "no_pending_update"})
      _other -> conn |> put_status(:conflict) |> json(%{error: "update_health_failed"})
    end
  end

  def unauthorized(conn, _params \\ %{}),
    do: reject(conn, "auth.authorization_rejected")

  defp reject(conn, event_type) do
    _audit = Audit.record(event_type, conn.method, conn.request_path, 401)
    conn |> put_status(:unauthorized) |> text("unauthorized")
  end

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
