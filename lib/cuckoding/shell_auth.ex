defmodule Cuckoding.ShellAuth do
  @moduledoc "Launch-scoped shell authority; browser tokens are hashed, expiring DB records."
  use GenServer
  import Ecto.Query
  alias Cuckoding.{BrowserToken, Foundation, Repo}
  @session_seconds 1_800
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def bootstrap(token), do: GenServer.call(__MODULE__, {:bootstrap, token})
  def authorize(token), do: GenServer.call(__MODULE__, {:authorize, token})
  def session_seconds, do: @session_seconds
  def digest(token), do: :crypto.hash(:sha256, token)
  def token, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

  @impl true
  def init(opts) do
    bootstrap =
      Keyword.get(opts, :bootstrap_hash, Application.get_env(:cuckoding, :bootstrap_hash))

    Application.delete_env(:cuckoding, :bootstrap_hash)

    unless Application.get_env(:cuckoding, :testing),
      do: Process.send_after(self(), :heartbeat, 5_000)

    {:ok, %{bootstrap: bootstrap, shell: nil, seen: System.monotonic_time(:second)}}
  end

  @impl true
  def handle_call({:bootstrap, token}, _from, state) do
    if matches?(token, state.bootstrap) do
      shell = token()
      Foundation.record("shell.authorized")

      {:reply, {:ok, shell},
       %{state | bootstrap: nil, shell: digest(shell), seen: System.monotonic_time(:second)}}
    else
      {:reply, {:error, :unauthorized}, state}
    end
  end

  def handle_call({:authorize, token}, _from, state) do
    if matches?(token, state.shell) do
      {:reply, :ok, %{state | seen: System.monotonic_time(:second)}}
    else
      {:reply, {:error, :unauthorized}, state}
    end
  end

  @impl true
  def handle_info(:heartbeat, state) do
    if System.monotonic_time(:second) - state.seen > 30 do
      Foundation.record("shell.disconnected")
      System.stop(0)
    end

    Process.send_after(self(), :heartbeat, 5_000)
    {:noreply, state}
  end

  defp matches?(token, expected)
       when is_binary(token) and is_binary(expected) and byte_size(token) <= 128,
       do: Plug.Crypto.secure_compare(digest(token), expected)

  defp matches?(_, _), do: false

  def handoff do
    value = token()
    now = System.system_time(:second)

    Repo.transaction(
      fn ->
        Repo.delete_all(from t in BrowserToken, where: t.expires_at <= ^now)
        Repo.insert!(%BrowserToken{digest: digest(value), kind: "handoff", expires_at: now + 60})
      end,
      mode: :immediate
    )

    value
  end

  def exchange(value) when is_binary(value) and byte_size(value) <= 128 do
    now = System.system_time(:second)
    hash = digest(value)

    Repo.transaction(
      fn ->
        {deleted, _} =
          Repo.delete_all(
            from t in BrowserToken,
              where: t.digest == ^hash and t.kind == "handoff" and t.expires_at > ^now
          )

        if deleted != 1, do: Repo.rollback(:unauthorized)
        session = token()
        expires = now + @session_seconds
        Repo.insert!(%BrowserToken{digest: digest(session), kind: "session", expires_at: expires})
        Foundation.record("browser.authorized")
        %{token: session, expires_at: expires}
      end,
      mode: :immediate
    )
  end

  def exchange(_), do: {:error, :unauthorized}

  def valid_session?(value) when is_binary(value) and byte_size(value) <= 128 do
    now = System.system_time(:second)
    hash = digest(value)

    Repo.exists?(
      from t in BrowserToken,
        where: t.digest == ^hash and t.kind == "session" and t.expires_at > ^now
    )
  end

  def valid_session?(_), do: false
end
