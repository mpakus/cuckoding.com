defmodule AgentDesk.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    AgentDesk.Env.bootstrap!()
    AgentDesk.Storage.ensure_data_root!()
    AgentDesk.Security.Loopback.assert!()

    children =
      [
        ExTauri.ShutdownManager,
        AgentDeskWeb.Telemetry,
        AgentDesk.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:agent_desk, :ecto_repos), skip: skip_migrations?()},
        {Phoenix.PubSub, name: AgentDesk.PubSub},
        AgentDesk.Security.ControlAuth,
        AgentDesk.Circuit,
        {Registry, keys: :unique, name: AgentDesk.ProjectRegistry},
        {Registry, keys: :unique, name: AgentDesk.SessionRegistry},
        {Registry, keys: :unique, name: AgentDesk.ProviderSupervisorRegistry},
        {Registry, keys: :unique, name: AgentDesk.HubRegistry},
        {Registry, keys: :unique, name: AgentDesk.A2ASupervisorRegistry},
        {Registry, keys: :unique, name: AgentDesk.WorktreeRegistry},
        {Registry, keys: :unique, name: AgentDesk.WorktreeSupervisorRegistry},
        {Registry, keys: :unique, name: AgentDesk.SearchRegistry},
        {Registry, keys: :unique, name: AgentDesk.SearchSupervisorRegistry},
        AgentDesk.Projects.Supervisor,
        AgentDeskWeb.Endpoint
      ] ++ xerj_children()

    opts = [strategy: :one_for_one, name: AgentDesk.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AgentDeskWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp xerj_children do
    if AgentDesk.Search.adapter() == AgentDesk.Search.Xerj do
      [AgentDesk.Search.Xerj.Process]
    else
      []
    end
  end

  defp skip_migrations? do
    System.get_env("RELEASE_NAME") == nil
  end
end
