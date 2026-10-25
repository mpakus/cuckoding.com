defmodule Boss.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    server? = Phoenix.Endpoint.server?(:boss, BossWeb.Endpoint)

    children = [
      {Boss.DataDirectory, directory: Application.fetch_env!(:boss, :data_dir)},
      BossWeb.Telemetry,
      Boss.Repo,
      {Ecto.Migrator, repos: [Boss.Repo]},
      {Boss.LocalAccess, announce: server?},
      {Phoenix.PubSub, name: Boss.PubSub},
      BossWeb.Endpoint
    ]

    # Losing directory ownership must stop every later child before reacquiring it.
    Supervisor.start_link(children, strategy: :rest_for_one, name: Boss.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    BossWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
