defmodule CuckodingWeb.SessionController do
  use CuckodingWeb, :controller
  alias Cuckoding.ShellAuth

  def open(conn, %{"token" => token} = params) do
    case ShellAuth.exchange(token) do
      {:ok, session} ->
        path = if params["view"] in ["/settings", "/about"], do: params["view"], else: "/"

        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:session_id, session.token)
        |> put_session(:expires_at, session.expires_at)
        |> redirect(to: path)

      _ ->
        conn
        |> put_status(401)
        |> text("This link expired. Open Cuckoding from its menu bar icon.")
    end
  end

  def open(conn, _), do: conn |> put_status(401) |> text("Open Cuckoding from its menu bar icon.")

  # The provider URL never enters LiveView assigns, request params or persistent state.
  def codex_login(conn, %{"id" => id}) do
    if ShellAuth.valid_session?(get_session(conn, :session_id)) do
      case Cuckoding.Foundation.login_redirect(id) do
        url when is_binary(url) ->
          redirect(conn, external: url)

        _ ->
          conn |> put_status(410) |> text("This sign-in link expired. Return to Agents & roles.")
      end
    else
      locked(conn, %{})
    end
  end

  def locked(conn, _),
    do:
      conn
      |> put_status(401)
      |> text("Your session ended. Open Cuckoding from its menu bar icon.")
end
