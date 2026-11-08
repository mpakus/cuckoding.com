defmodule BossWeb.AccessController do
  use BossWeb, :controller

  @remember_cookie_options [path: "/unlock", http_only: true, same_site: "Strict"]

  def show(conn, _params) do
    case Boss.LocalAccess.restore(conn.req_cookies[remember_cookie(conn)]) do
      {:ok, session} -> connect_browser(conn, session)
      :error -> render(conn, :unlock, error: nil)
    end
  end

  def create(conn, params) do
    result =
      if params["remember"] == "true",
        do: Boss.LocalAccess.remember(params["token"]),
        else: Boss.LocalAccess.exchange(params["token"])

    case result do
      {:ok, session} ->
        connect_browser(conn, session)

      {:ok, session, credential, max_age} ->
        options = [max_age: max_age] ++ @remember_cookie_options

        conn
        |> put_resp_cookie(remember_cookie(conn), credential, options)
        |> connect_browser(session)

      {:error, :remember_failed} ->
        conn
        |> put_status(:service_unavailable)
        |> render(:unlock,
          error: "BOSS couldn’t remember this browser. Try again or leave the box unchecked."
        )

      :error ->
        conn
        |> put_status(:unauthorized)
        |> render(:unlock, error: "Token is invalid, expired or already used.")
    end
  end

  defp connect_browser(conn, session) do
    Plug.CSRFProtection.delete_csrf_token()

    conn
    |> put_resp_header("cache-control", "no-store")
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:local_session, session)
    |> redirect(to: ~p"/")
  end

  defp remember_cookie(conn), do: "_boss_remember_#{conn.port}"
end

defmodule BossWeb.AccessHTML do
  use BossWeb, :html

  def unlock(assigns) do
    ~H"""
    <header class="app-page-header max-w-2xl">
      <p class="app-eyebrow">Local access</p>
      <h1 class="app-page-title">Connect this browser</h1>
      <p class="app-page-description">
        Enter the one-use token printed in the terminal where you started BOSS.
      </p>
    </header>
    <form action={~p"/unlock"} method="post" class="app-panel max-w-lg space-y-4">
      <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
      <label for="token" class="block text-sm font-medium">One-use token</label>
      <input
        id="token"
        name="token"
        type="password"
        required
        autocomplete="off"
        spellcheck="false"
        autocapitalize="none"
        autofocus
        class="app-field w-full px-3 py-3"
      />
      <label class="flex items-center gap-2 text-sm font-medium">
        <input type="checkbox" name="remember" value="true" class="size-4" />
        Remember this browser for 30 days
      </label>
      <p :if={@error} role="alert" class="text-sm text-danger">{@error}</p>
      <button
        type="submit"
        class="app-button-primary px-5 py-3 font-semibold"
      >
        Connect browser
      </button>
    </form>
    <p class="mt-6 text-sm text-muted">
      Tokens expire after 10 minutes. Restart BOSS to get a new token.
    </p>
    """
  end
end
