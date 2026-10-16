defmodule Cuckoding.ShellAuth do
  @moduledoc "Launch-scoped shell authority; browser tokens are hashed, expiring DB records."
  use GenServer
  import Ecto.Query
  alias Cuckoding.{BrowserToken, Foundation, Repo}
  @session_seconds 1_800
  @power_lease_seconds 15
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def bootstrap(token), do: GenServer.call(__MODULE__, {:bootstrap, token})
  def authorize(token, power \\ nil), do: GenServer.call(__MODULE__, {:authorize, token, power})
  def power_lease_seconds, do: @power_lease_seconds

  def power_status(sample \\ nil), do: GenServer.call(__MODULE__, {:power_status, sample})

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

    {:ok, %{bootstrap: bootstrap, shell: nil, seen: System.monotonic_time(:second), power: nil}}
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

  def handle_call({:authorize, token, power}, _from, state) do
    cond do
      not matches?(token, state.shell) ->
        {:reply, {:error, :unauthorized}, state}

      power not in [nil, "held", "released", "unavailable"] ->
        {:reply, {:error, :invalid_power_state}, state}

      true ->
        state = %{
          state
          | seen: System.monotonic_time(:second),
            power: observe_power(state.power, power)
        }

        {:reply, :ok, state}
    end
  end

  def handle_call({:power_status, sample}, _from, state) do
    report = state.power
    {wall, monotonic} = sample || {DateTime.utc_now(), System.monotonic_time(:millisecond)}

    elapsed =
      if report,
        do: [monotonic - report.seen, DateTime.diff(wall, report.observed_at, :millisecond)]

    age = if elapsed, do: max(0, div(Enum.max(elapsed), 1_000))

    {:reply,
     %{
       state: if(report, do: report.state, else: "unknown"),
       observed_at: if(report, do: report.observed_at),
       age_seconds: age,
       fresh:
         not is_nil(elapsed) and
           Enum.all?(elapsed, &(&1 >= 0 and &1 < @power_lease_seconds * 1_000))
     }, state}
  end

  defp observe_power(previous, nil), do: previous

  defp observe_power(previous, power) do
    if is_nil(previous) or previous.state != power do
      Foundation.record("shell.power_observed", %{
        "state" => power,
        "contract" => "shell-lease-v1",
        "lease_seconds" => @power_lease_seconds
      })

      Foundation.broadcast()
    end

    %{state: power, observed_at: DateTime.utc_now(), seen: System.monotonic_time(:millisecond)}
  end

  @impl true
  def handle_info(:shutdown, state) do
    unless Application.get_env(:cuckoding, :testing), do: System.stop(0)
    {:noreply, state}
  end

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
