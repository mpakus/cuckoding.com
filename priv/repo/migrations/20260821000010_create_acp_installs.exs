defmodule AgentDesk.Repo.Migrations.CreateAcpInstalls do
  use Ecto.Migration

  def change do
    create table(:acp_installs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :registry_id, :text, null: false
      add :name, :text, null: false
      add :version, :text
      add :status, :text, null: false, default: "installed"
      add :provider_key, :text, null: false, default: "acp"
      add :executable, :text
      add :args, {:array, :string}, default: []
      add :distribution, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:acp_installs, [:registry_id])
    create index(:acp_installs, [:status])
  end
end
