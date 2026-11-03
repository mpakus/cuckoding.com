defmodule BossWeb.AccessController do
  use BossWeb, :controller

  def show(conn, _params), do: render(conn, :unlock, error: nil)

  def create(conn, params) do
    case Boss.LocalAccess.exchange(params["token"]) do
      {:ok, session} ->
        Plug.CSRFProtection.delete_csrf_token()

        conn
        |> configure_session(renew: true)
        |> clear_session()
        |> put_session(:local_session, session)
        |> redirect(to: ~p"/")

      :error ->
        conn
        |> put_status(:unauthorized)
        |> render(:unlock, error: "Token is invalid, expired or already used.")
    end
  end
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
