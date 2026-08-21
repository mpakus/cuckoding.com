defmodule AgentDesk.Search.Xerj.Process do
  @moduledoc """
  Optional XERJ OS process bound to loopback. Failure never stops the project runtime.
  Never attaches to a XERJ node AgentDesk did not start.
  """

  use GenServer

  require Logger

  alias AgentDesk.Circuit
  alias AgentDesk.Search.Xerj.Discovery
  alias AgentDesk.Search.Xerj.HTTP
  alias AgentDesk.Storage

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec base_url() :: String.t()
  def base_url, do: "http://127.0.0.1:9200"

  @spec owned?() :: boolean()
  def owned? do
    case GenServer.whereis(__MODULE__) do
      nil -> false
      pid -> GenServer.call(pid, :owned?)
    end
  end

  @spec running?() :: boolean()
  def running? do
    match?({:ok, _}, HTTP.get(base_url() <> "/"))
  end

  @impl true
  def init(_opts) do
    cond do
      is_nil(Discovery.executable()) ->
        {:ok, %{port: nil, owned: false}}

      not Circuit.allow?("xerj") ->
        Logger.warning("XERJ circuit open; search stays unavailable")
        {:ok, %{port: nil, owned: false}}

      running?() ->
        Logger.warning("XERJ already listening on 127.0.0.1:9200; AgentDesk will not attach")
        {:ok, %{port: nil, owned: false}}

      true ->
        dir = Storage.xerj_dir()
        File.mkdir_p!(dir)
        port = open(Discovery.executable(), dir)
        {:ok, %{port: port, owned: true}}
    end
  end

  @impl true
  def handle_call(:owned?, _from, state), do: {:reply, state.owned == true, state}

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    if status != 0, do: Circuit.failure("xerj")
    {:noreply, %{state | port: nil, owned: false}}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{port: port}) when is_port(port) do
    if Port.info(port), do: Port.close(port)
    :ok
  rescue
    ArgumentError -> :ok
  end

  def terminate(_reason, _state), do: :ok

  defp open(exe, dir) do
    Port.open({:spawn_executable, exe}, [
      :binary,
      :exit_status,
      :use_stdio,
      {:args, ["--insecure", "--bind", "127.0.0.1", "--data-dir", dir]}
    ])
  end
end
