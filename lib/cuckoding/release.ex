defmodule Cuckoding.Release do
  @moduledoc false

  @app :cuckoding

  def migrate do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _result, _apps} =
        Ecto.Migrator.with_repo(repo, fn repository ->
          Ecto.Migrator.run(repository, :up, all: true)
        end)
    end
  end
end
