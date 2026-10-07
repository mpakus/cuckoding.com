defmodule Cuckoding.Execution.StartupReconciler do
  @moduledoc """
  Completes one reconciliation pass before later supervision children can schedule work.
  """

  use GenServer

  alias Cuckoding.Execution.Reconciler

  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)
  def summary, do: GenServer.call(__MODULE__, :summary)

  @impl true
  def init(options) do
    with {:ok, summary} <- Reconciler.run(options),
         :ok <- Cuckoding.Execution.BoardControl.reopen_admission() do
      {:ok, summary}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:summary, _from, summary), do: {:reply, summary, summary}
end
