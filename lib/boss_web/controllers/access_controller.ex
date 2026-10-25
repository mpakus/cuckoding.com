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
    <p class="text-sm font-semibold tracking-widest text-emerald-400">BOSS · LOCAL</p>
    <h1 class="mt-4 text-3xl font-semibold">Connect this browser</h1>
    <p class="mt-4 text-zinc-300">
      Enter the one-use token printed in the terminal where you started BOSS.
    </p>
    <form action={~p"/unlock"} method="post" class="mt-8 max-w-lg space-y-4">
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
        class="w-full rounded-md border border-zinc-600 bg-zinc-900 px-3 py-3 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400"
      />
      <p :if={@error} role="alert" class="text-sm text-red-300">{@error}</p>
      <button
        type="submit"
        class="rounded-md bg-emerald-400 px-5 py-3 font-semibold text-zinc-950 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400"
      >
        Connect browser
      </button>
    </form>
    <p class="mt-6 text-sm text-zinc-400">
      Tokens expire after 10 minutes. Restart BOSS to get a new token.
    </p>
    """
  end
end
