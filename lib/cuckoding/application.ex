defmodule Cuckoding.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    if Application.get_env(:cuckoding, :testing) do
      database = Application.fetch_env!(:cuckoding, Cuckoding.Repo)[:database]
      Cuckoding.Storage.prepare!(Path.dirname(database))
    end

    children =
      [
        Cuckoding.Repo,
        Cuckoding.Database,
        {Phoenix.PubSub, name: Cuckoding.PubSub},
        Cuckoding.ShellAuth
      ] ++ dispatcher() ++ [CuckodingWeb.Endpoint, Cuckoding.Ready]

    Supervisor.start_link(children, strategy: :one_for_one, name: Cuckoding.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    CuckodingWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp dispatcher do
    if Application.get_env(:cuckoding, :dispatcher, true), do: [Cuckoding.Dispatcher], else: []
  end
end

defmodule Cuckoding.Database do
  @moduledoc "Migrations finish before authentication, dispatch or HTTP starts."
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_) do
    repo = Cuckoding.Repo
    migrations = Ecto.Migrator.migrations_path(repo)

    known =
      Path.wildcard(Path.join(migrations, "*.exs"))
      |> Enum.map(fn path ->
        {version, _} = path |> Path.basename() |> Integer.parse()
        version
      end)

    applied = Ecto.Migrator.migrated_versions(repo)

    if Enum.any?(applied, &(&1 not in known)),
      do: raise("database schema is newer than this application")

    Ecto.Migrator.run(repo, :up, all: true, log: false)
    repo.config()[:database] |> Path.dirname() |> Cuckoding.Storage.prepare!()
    {:ok, nil}
  end
end

defmodule Cuckoding.Ready do
  @moduledoc false
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  @impl true
  def init(_) do
    unless Application.get_env(:cuckoding, :testing) do
      {:ok, {{127, 0, 0, 1}, port}} = CuckodingWeb.Endpoint.server_info(:http)
      IO.puts("CCODING_READY " <> Jason.encode!(%{port: port, version: "0.1.0"}))
    end

    {:ok, nil}
  end
end
