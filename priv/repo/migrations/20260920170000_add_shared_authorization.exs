defmodule Cuckoding.Repo.Migrations.AddSharedAuthorization do
  use Ecto.Migration

  def change do
    alter table(:provider_accounts) do
      add :authorization_account_id,
          references(:provider_accounts, type: :binary_id, on_delete: :restrict)
    end

    create index(:provider_accounts, [:authorization_account_id])
  end
end
