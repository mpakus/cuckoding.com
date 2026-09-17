defmodule Cuckoding.Repo.Migrations.CreateLeases do
  use Ecto.Migration

  def change do
    create table(:leases, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :resource_type, :string,
        null: false,
        check: %{name: "resource_type_is_present", expr: "length(resource_type) > 0"}

      add :resource_id, :string,
        null: false,
        check: %{name: "resource_id_is_present", expr: "length(resource_id) > 0"}

      add :owner_id, :string,
        null: false,
        check: %{name: "owner_id_is_present", expr: "length(owner_id) > 0"}

      add :token_hash, :string,
        null: false,
        check: %{name: "token_hash_has_sha256_length", expr: "length(token_hash) = 64"}

      add :acquired_at, :utc_datetime_usec, null: false
      add :heartbeat_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec,
        null: false,
        check: %{name: "lease_expiry_follows_acquisition", expr: "expires_at > acquired_at"}

      add :released_at, :utc_datetime_usec
      add :release_reason, :string,
        check: %{
          name: "lease_release_is_consistent",
          expr:
            "(released_at IS NULL AND release_reason IS NULL) OR " <>
              "(released_at IS NOT NULL AND release_reason IN ('released', 'expired'))"
        }

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:leases, [:resource_type, :resource_id],
             where: "released_at IS NULL",
             name: :leases_one_active_resource_index
           )

    create index(:leases, [:expires_at], where: "released_at IS NULL")
    create index(:leases, [:owner_id], where: "released_at IS NULL")
  end
end
