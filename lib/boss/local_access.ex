defmodule Boss.LocalAccess do
  @moduledoc "Exchanges a short-lived terminal token for a browser session. Secrets stay in memory."
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def exchange(token, server \\ __MODULE__), do: GenServer.call(server, {:exchange, token})
  def valid_session?(session, server \\ __MODULE__), do: GenServer.call(server, {:valid, session})

  @doc "Issue a new one-use token from the local IEx console; existing browser sessions remain valid."
  def new_token(server \\ __MODULE__), do: GenServer.call(server, :new_token)

  @impl true
  def init(opts) do
    token = Keyword.get_lazy(opts, :token, &random_token/0)
    ttl = Keyword.get(opts, :ttl_ms, 600_000)
    if Keyword.get(opts, :announce, false), do: announce(token)
    {:ok, %{token_hash: hash(token), expires_at: now() + ttl, ttl: ttl, session: random_token()}}
  end

  @impl true
  def handle_call({:exchange, token}, _from, state) do
    if now() < state.expires_at and matches?(hash(token), state.token_hash) do
      {:reply, {:ok, state.session}, %{state | token_hash: nil}}
    else
      {:reply, :error, state}
    end
  end

  def handle_call({:valid, session}, _from, state) do
    {:reply, matches?(session, state.session), state}
  end

  def handle_call(:new_token, _from, state) do
    token = random_token()
    {:reply, token, %{state | token_hash: hash(token), expires_at: now() + state.ttl}}
  end

  @impl true
  def format_status(status), do: Map.put(status, :state, :redacted)

  defp matches?(left, right) when is_binary(left) and is_binary(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp matches?(_, _), do: false
  defp hash(token) when is_binary(token), do: :crypto.hash(:sha256, token)
  defp hash(_), do: nil
  defp now, do: System.monotonic_time(:millisecond)
  defp random_token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  defp announce(token) do
    url = Application.fetch_env!(:boss, BossWeb.Endpoint)[:url]

    IO.puts(
      "\nOpen http://127.0.0.1:#{url[:port]}/unlock and enter this one-use token (10 minutes):\n#{token}\n"
    )
  end
end
