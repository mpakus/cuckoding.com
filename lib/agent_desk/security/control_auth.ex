defmodule AgentDesk.Security.ControlAuth do
  @moduledoc """
  Per-launch authorization for the loopback desktop control plane.

  A bootstrap bearer is accepted once and exchanged for a signed Phoenix
  session. Only token verifiers are retained after startup.
  """

  use GenServer

  import Plug.Conn, only: [configure_session: 2, put_session: 3]

  @session_key "control_authorization"
  @minimum_token_bytes 32

  @type mode :: :launch_token | :development | :test

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec consume_bootstrap(String.t()) :: {:ok, String.t()} | {:error, :unauthorized}
  def consume_bootstrap(token) when is_binary(token) do
    GenServer.call(__MODULE__, {:consume_bootstrap, token})
  end

  def consume_bootstrap(_token), do: {:error, :unauthorized}

  @spec readiness_proof() :: {:ok, String.t()} | {:error, :unavailable}
  def readiness_proof do
    GenServer.call(__MODULE__, :readiness_proof)
  end

  @spec authorized_session?(map()) :: boolean()
  def authorized_session?(session) when is_map(session) do
    binding = Map.get(session, @session_key) || Map.get(session, :control_authorization)
    authorized_binding?(binding)
  end

  def authorized_session?(_session), do: false

  @spec session_binding(map()) :: {:ok, String.t()} | {:error, :unauthorized}
  def session_binding(session) when is_map(session) do
    binding = Map.get(session, @session_key) || Map.get(session, :control_authorization)

    if authorized_binding?(binding) do
      {:ok, binding}
    else
      {:error, :unauthorized}
    end
  end

  def session_binding(_session), do: {:error, :unauthorized}

  @spec authorized_binding?(term()) :: boolean()
  def authorized_binding?(binding) when is_binary(binding) do
    GenServer.call(__MODULE__, {:authorized_binding?, binding})
  end

  def authorized_binding?(_binding), do: false

  @spec put_authorized_session(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def put_authorized_session(conn, binding) when is_binary(binding) do
    conn
    |> configure_session(renew: true)
    |> put_session(@session_key, binding)
  end

  @doc false
  @spec authorize_conn_for_test(Plug.Conn.t()) :: Plug.Conn.t()
  def authorize_conn_for_test(conn) do
    case GenServer.call(__MODULE__, :test_binding) do
      {:ok, binding} -> put_authorized_session(conn, binding)
      {:error, :not_test_mode} -> raise "control test session requested outside test mode"
    end
  end

  @doc false
  @spec reset_bootstrap_for_test(String.t()) :: :ok
  def reset_bootstrap_for_test(token) when is_binary(token) do
    case GenServer.call(__MODULE__, {:reset_bootstrap_for_test, token}) do
      :ok -> :ok
      {:error, :not_test_mode} -> raise "control bootstrap reset requested outside test mode"
    end
  end

  @doc false
  @spec rotate_binding_for_test() :: :ok
  def rotate_binding_for_test do
    case GenServer.call(__MODULE__, :rotate_binding_for_test) do
      :ok -> :ok
      {:error, :not_test_mode} -> raise "control binding rotation requested outside test mode"
    end
  end

  @doc false
  @spec mode() :: mode()
  def mode, do: GenServer.call(__MODULE__, :mode)

  @impl true
  def init(_opts) do
    mode = configured_mode()
    token = bootstrap_token!(mode)
    test_binding = if mode == :test, do: random_token()

    System.delete_env("AGENTDESK_CONTROL_TOKEN")
    System.delete_env("AGENTDESK_DEV_BOOTSTRAP_TOKEN")

    {:ok,
     %{
       mode: mode,
       token_hash: token && verifier(token),
       binding_hash: test_binding && verifier(test_binding),
       test_binding: test_binding
     }}
  end

  @impl true
  def handle_call({:consume_bootstrap, token}, _from, %{token_hash: expected} = state)
      when is_binary(expected) do
    if secure_equal?(verifier(token), expected) do
      binding = state.test_binding || random_token()

      {:reply, {:ok, binding}, %{state | token_hash: nil, binding_hash: verifier(binding)}}
    else
      {:reply, {:error, :unauthorized}, state}
    end
  end

  def handle_call({:consume_bootstrap, _token}, _from, state) do
    {:reply, {:error, :unauthorized}, state}
  end

  def handle_call(:readiness_proof, _from, %{token_hash: token_hash} = state)
      when is_binary(token_hash) do
    {:reply, {:ok, Base.encode16(token_hash, case: :lower)}, state}
  end

  def handle_call(:readiness_proof, _from, state) do
    {:reply, {:error, :unavailable}, state}
  end

  def handle_call({:authorized_binding?, binding}, _from, state) do
    {:reply, secure_equal?(verifier(binding), state.binding_hash), state}
  end

  def handle_call(:test_binding, _from, %{mode: :test} = state) do
    {:reply, {:ok, state.test_binding}, state}
  end

  def handle_call(:test_binding, _from, state) do
    {:reply, {:error, :not_test_mode}, state}
  end

  def handle_call({:reset_bootstrap_for_test, token}, _from, %{mode: :test} = state) do
    {:reply, :ok, %{state | token_hash: verifier(token)}}
  end

  def handle_call({:reset_bootstrap_for_test, _token}, _from, state) do
    {:reply, {:error, :not_test_mode}, state}
  end

  def handle_call(:rotate_binding_for_test, _from, %{mode: :test} = state) do
    binding = random_token()
    {:reply, :ok, %{state | test_binding: binding, binding_hash: verifier(binding)}}
  end

  def handle_call(:rotate_binding_for_test, _from, state) do
    {:reply, {:error, :not_test_mode}, state}
  end

  def handle_call(:mode, _from, state), do: {:reply, state.mode, state}

  defp configured_mode do
    :agent_desk
    |> Application.fetch_env!(:control_auth)
    |> Keyword.fetch!(:mode)
  end

  defp bootstrap_token!(:test), do: random_token()

  defp bootstrap_token!(:launch_token) do
    System.get_env("AGENTDESK_CONTROL_TOKEN")
    |> validate_token!("AGENTDESK_CONTROL_TOKEN")
  end

  defp bootstrap_token!(:development) do
    config = Application.fetch_env!(:agent_desk, :control_auth)

    (System.get_env("AGENTDESK_CONTROL_TOKEN") ||
       System.get_env("AGENTDESK_DEV_BOOTSTRAP_TOKEN") ||
       config[:bootstrap_token])
    |> validate_token!("AGENTDESK_DEV_BOOTSTRAP_TOKEN")
  end

  defp bootstrap_token!(mode) do
    raise ArgumentError, "unsupported control authorization mode: #{inspect(mode)}"
  end

  defp validate_token!(token, _name)
       when is_binary(token) and byte_size(token) >= @minimum_token_bytes,
       do: token

  defp validate_token!(_token, name) do
    raise """
    #{name} must contain at least #{@minimum_token_bytes} bytes.
    Browser-only development must set AGENTDESK_DEV_BOOTSTRAP_TOKEN explicitly
    and open /control/bootstrap?token=<value>.
    """
  end

  defp random_token do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp verifier(value), do: :crypto.hash(:sha256, value)

  defp secure_equal?(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) do
    Plug.Crypto.secure_compare(left, right)
  end

  defp secure_equal?(_left, _right), do: false
end
