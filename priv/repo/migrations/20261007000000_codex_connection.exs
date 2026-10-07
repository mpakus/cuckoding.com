defmodule Cuckoding.Repo.Migrations.CodexConnection do
  use Ecto.Migration
  def up do
    alter table(:workspace) do
      add :connection, :map, null: false, default: %{}
    end
  end
  def down, do: raise("forward-only migration; restore a verified backup")
end
