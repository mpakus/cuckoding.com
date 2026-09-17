defmodule Cuckoding.Repo.Migrations.CreateSecretAccessAudits do
  use Ecto.Migration

  def change do
    create table(:secret_access_audits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :secret_ref, :string, null: false
      add :purpose, :string, null: false
      add :run_id, :binary_id
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:secret_access_audits, [:secret_ref, :occurred_at])
    create index(:secret_access_audits, [:run_id, :occurred_at])
  end
end
