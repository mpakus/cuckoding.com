defmodule AgentDesk.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    AgentDesk.Storage.ensure_data_root!()

    children = [
      ExTauri.ShutdownManager,
      AgentDeskWeb.Telemetry,
      AgentDesk.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:agent_desk, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:agent_desk, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AgentDesk.PubSub},
      {Registry, keys: :unique, name: AgentDesk.ProjectRegistry},
      {Registry, keys: :unique, name: AgentDesk.SessionRegistry},
      AgentDesk.Projects.Supervisor,
      {DynamicSupervisor, name: AgentDesk.ProviderProcessSupervisor, strategy: :one_for_one},
      Supervisor.child_spec(
        {Task, fn -> AgentDesk.Projects.restore_on_boot() end},
        id: AgentDesk.Projects.Restorer,
        restart: :temporary
      ),
      AgentDeskWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: AgentDesk.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AgentDeskWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations? do
    System.get_env("RELEASE_NAME") == nil
  end
end
