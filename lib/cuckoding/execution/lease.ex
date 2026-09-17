defmodule Cuckoding.Execution.Lease do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "leases" do
    field :resource_type, :string
    field :resource_id, :string
    field :owner_id, :string
    field :token_hash, :string
    field :acquired_at, :utc_datetime_usec
    field :heartbeat_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :released_at, :utc_datetime_usec
    field :release_reason, :string
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def create_changeset(lease, attrs) do
    lease
    |> cast(attrs, [
      :resource_type,
      :resource_id,
      :owner_id,
      :token_hash,
      :acquired_at,
      :heartbeat_at,
      :expires_at
    ])
    |> validate_required([
      :resource_type,
      :resource_id,
      :owner_id,
      :token_hash,
      :acquired_at,
      :heartbeat_at,
      :expires_at
    ])
    |> validate_length(:resource_type, min: 1)
    |> validate_length(:resource_id, min: 1)
    |> validate_length(:owner_id, min: 1)
    |> validate_length(:token_hash, is: 64)
    |> unique_constraint([:resource_type, :resource_id],
      name: :leases_one_active_resource_index
    )
    |> unique_constraint([:resource_type, :resource_id],
      name: :leases_resource_type_resource_id_index
    )
  end

  def update_changeset(lease, attrs) do
    cast(lease, attrs, [:heartbeat_at, :expires_at, :released_at, :release_reason])
  end
end
