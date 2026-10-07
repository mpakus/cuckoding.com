defmodule Cuckoding.Dispatcher do
  @moduledoc "One supervised dispatcher; SQLite owns the queue and expiring claims."
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
    send(self(), :tick)
    {:ok, nil}
  end

  @impl true
  def handle_info(:updated, state), do: {:noreply, state}
  def handle_info({port, _}, state) when is_port(port), do: {:noreply, state}

  def handle_info(:tick, state) do
    case Cuckoding.Foundation.claim() do
      {:ok, %{state: "running"} = command} ->
        result = execute(command)
        Cuckoding.Foundation.finish(command, result)

      _ ->
        :ok
    end

    Process.send_after(self(), :tick, 500)
    {:noreply, state}
  end

  defp execute(%{kind: "discover_tools"}), do: Cuckoding.Tools.discover()

  defp execute(%{kind: "probe_codex"} = command) do
    if Cuckoding.Foundation.workspace().revision == command.expected_revision do
      directory = Cuckoding.Storage.probe_directory!(command.id, command.attempts)

      Cuckoding.Codex.probe(command.payload, directory, fn ->
        Cuckoding.Foundation.probe_active?(command)
      end)
    else
      %{}
    end
  rescue
    _ -> %{"status" => "launch_failed"}
  end

  defp execute(%{kind: "inspect_codex"} = command) do
    if Cuckoding.Foundation.workspace().revision == command.expected_revision do
      directory = Cuckoding.Storage.codex_profile!()

      Cuckoding.Codex.inspect_connection(command.payload, directory, fn ->
        Cuckoding.Foundation.probe_active?(command)
      end)
    else
      %{}
    end
  rescue
    _ -> %{"status" => "launch_failed"}
  end
end
