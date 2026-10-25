defmodule Boss.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    server? = Phoenix.Endpoint.server?(:boss, BossWeb.Endpoint)

    children = [
      BossWeb.Telemetry,
      Boss.Repo,
      {Ecto.Migrator, repos: [Boss.Repo]},
      {Boss.LocalAccess, announce: server?},
      {Phoenix.PubSub, name: Boss.PubSub},
      Boss.FolderPicker,
      BossWeb.Endpoint
    ]

    with {:ok, lock} <- Boss.DataDirectory.acquire(Application.fetch_env!(:boss, :data_dir)) do
      case Supervisor.start_link(children, strategy: :one_for_one, name: Boss.Supervisor) do
        {:ok, supervisor} ->
          {:ok, supervisor, lock}

        {:error, reason} ->
          Boss.DataDirectory.release(lock)
          {:error, reason}
      end
    end
  end

  @impl true
  def stop(lock), do: Boss.DataDirectory.release(lock)

  @impl true
  def config_change(changed, _new, removed) do
    BossWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
