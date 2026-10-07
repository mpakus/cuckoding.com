defmodule Cuckoding.Repo.Migrations.CodexReadiness do
  use Ecto.Migration

  def up do
    alter table(:workspace) do
      add :codex, :map, null: false, default: %{}
    end

    alter table(:commands) do
      add :payload, :map, null: false, default: %{}
    end
  end

  def down, do: raise("forward-only migration; restore a verified backup")
end
