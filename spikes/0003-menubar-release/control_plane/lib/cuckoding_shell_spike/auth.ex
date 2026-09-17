defmodule CuckodingShellSpike.Auth do
  use GenServer

  @token_ttl_seconds 60

  def start_link(_args), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def bootstrap(token), do: GenServer.call(__MODULE__, {:bootstrap, token})
  def browser_token(shell_token), do: GenServer.call(__MODULE__, {:browser_token, shell_token})
  def consume_browser_token(token), do: GenServer.call(__MODULE__, {:consume, token})
  def shell?(token), do: GenServer.call(__MODULE__, {:shell?, token})

  @impl true
  def init(_) do
    path = System.fetch_env!("CUCKODING_BOOTSTRAP_FILE")

    [_secret_key_base, bootstrap] =
      path |> File.read!() |> String.trim() |> String.split("\n", parts: 2)

    File.rm!(path)
    {:ok, %{bootstrap: bootstrap, shell: nil, browser: %{}}}
  end

  @impl true
  def handle_call({:bootstrap, token}, _from, %{bootstrap: bootstrap} = state) do
    if secure_equal?(token, bootstrap) do
      shell = token()
      {:reply, {:ok, shell}, %{state | bootstrap: nil, shell: shell}}
    else
      {:reply, :error, state}
    end
  end

  def handle_call({:browser_token, shell}, _from, state) do
    if secure_equal?(shell, state.shell) do
      token = token()
      expires_at = System.monotonic_time(:second) + @token_ttl_seconds
      {:reply, {:ok, token}, put_in(state.browser[token], expires_at)}
    else
      {:reply, :error, state}
    end
  end

  def handle_call({:consume, token}, _from, state) do
    {expires_at, browser} = Map.pop(state.browser, token)
    valid? = is_integer(expires_at) and expires_at >= System.monotonic_time(:second)
    {:reply, valid?, %{state | browser: browser}}
  end

  def handle_call({:shell?, token}, _from, state),
    do: {:reply, secure_equal?(token, state.shell), state}

  defp token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  defp secure_equal?(left, right) when is_binary(left) and is_binary(right),
    do: byte_size(left) == byte_size(right) and Plug.Crypto.secure_compare(left, right)

  defp secure_equal?(_, _), do: false
end
