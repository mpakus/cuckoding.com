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

  def handle_info(:tick, state) do
    # This first command only reads metadata, so expired claims are safe to retry.
    # Side-effecting provider commands must add reconciliation before dispatch.
    case Cuckoding.Foundation.claim() do
      {:ok, %{state: "running"} = command} ->
        Cuckoding.Foundation.finish(command, Cuckoding.Tools.discover())

      _ ->
        :ok
    end

    Process.send_after(self(), :tick, 500)
    {:noreply, state}
  end
end
