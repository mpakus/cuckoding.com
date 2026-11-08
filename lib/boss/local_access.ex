defmodule Boss.LocalAccess do
  @moduledoc "Exchanges a terminal token or remembered browser credential for a local session."
  use GenServer

  @remember_seconds 30 * 24 * 60 * 60

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def exchange(token, server \\ __MODULE__),
    do: GenServer.call(server, {:exchange, hash(token), false})

  def remember(token, server \\ __MODULE__),
    do: GenServer.call(server, {:exchange, hash(token), true})

  def restore(credential, server \\ __MODULE__)

  def restore(credential, server) when is_binary(credential) and byte_size(credential) == 43,
    do: GenServer.call(server, {:restore, hash(credential)})

  def restore(_credential, _server), do: :error

  def valid_session?(session, server \\ __MODULE__), do: GenServer.call(server, {:valid, session})

  @doc "Revoke automatic unlock. Already connected sessions continue for this run."
  def forget_browser(server \\ __MODULE__), do: GenServer.call(server, :forget_browser)

  @doc "Issue a new one-use token from the local IEx console; existing browser sessions remain valid."
  def new_token(server \\ __MODULE__), do: GenServer.call(server, :new_token)

  @impl true
  def init(opts) do
    token = Keyword.get_lazy(opts, :token, &random_token/0)
    ttl = Keyword.get(opts, :ttl_ms, 600_000)
    path = if directory = opts[:data_dir], do: Path.join(directory, ".remembered-browser")
    if Keyword.get(opts, :announce, false), do: announce(token)

    {:ok,
     %{
       token_hash: hash(token),
       expires_at: now() + ttl,
       ttl: ttl,
       session: random_token(),
       remember_path: path,
       remembered: load_remembered(path)
     }}
  end

  @impl true
  def handle_call({:exchange, digest, remember?}, _from, state) do
    if now() < state.expires_at and matches?(digest, state.token_hash) do
      exchange_valid_token(state, remember?)
    else
      {:reply, :error, state}
    end
  end

  def handle_call({:restore, digest}, _from, state) do
    result =
      with {expires_at, saved_digest} <- state.remembered,
           true <- System.os_time(:second) < expires_at,
           true <- matches?(digest, saved_digest) do
        {:ok, state.session}
      else
        _ -> :error
      end

    {:reply, result, state}
  end

  def handle_call({:valid, session}, _from, state) do
    {:reply, matches?(session, state.session), state}
  end

  def handle_call(:new_token, _from, state) do
    token = random_token()
    {:reply, token, %{state | token_hash: hash(token), expires_at: now() + state.ttl}}
  end

  def handle_call(:forget_browser, _from, %{remember_path: nil} = state), do: {:reply, :ok, state}

  def handle_call(:forget_browser, _from, state) do
    case File.rm(state.remember_path) do
      result when result in [:ok, {:error, :enoent}] ->
        {:reply, :ok, %{state | remembered: nil}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  defp exchange_valid_token(state, false) do
    {:reply, {:ok, state.session}, %{state | token_hash: nil}}
  end

  defp exchange_valid_token(state, true) do
    credential = random_token()
    expires_at = System.os_time(:second) + @remember_seconds
    digest = hash(credential)

    case save_remembered(state.remember_path, <<expires_at::64, digest::binary>>) do
      :ok ->
        {:reply, {:ok, state.session, credential, @remember_seconds},
         %{state | token_hash: nil, remembered: {expires_at, digest}}}

      {:error, _} ->
        {:reply, {:error, :remember_failed}, state}
    end
  end

  defp load_remembered(nil), do: nil

  defp load_remembered(path) do
    with {:ok, %{type: :regular, size: 40}} <- File.lstat(path),
         {:ok, <<expires_at::64, digest::binary-size(32)>>} <- File.read(path) do
      {expires_at, digest}
    else
      _ -> nil
    end
  end

  defp save_remembered(nil, _record), do: {:error, :no_data_directory}

  defp save_remembered(path, record) do
    scratch = path <> "." <> random_token()

    with {:ok, file} <- File.open(scratch, [:write, :binary, :exclusive]) do
      try do
        written = IO.binwrite(file, record)
        closed = File.close(file)

        with :ok <- written, :ok <- closed, :ok <- File.chmod(scratch, 0o600) do
          File.rename(scratch, path)
        end
      after
        File.rm(scratch)
      end
    end
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
