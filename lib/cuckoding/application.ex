defmodule Cuckoding.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Cuckoding.Repo,
      Cuckoding.Execution.StartupReconciler,
      {Registry, keys: :unique, name: Cuckoding.RunRegistry},
      Cuckoding.Execution.RunSupervisors,
      {DynamicSupervisor, strategy: :one_for_one, name: Cuckoding.Execution.ProcessWorkers},
      {Phoenix.PubSub, name: Cuckoding.PubSub},
      CuckodingWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Cuckoding.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    CuckodingWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
