defmodule Cuckoding.Updates.Attempt do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "update_attempts" do
    field :from_version, :string
    field :to_version, :string
    field :schema_change, :boolean
    field :state, :string
    field :backup_path, :string
    field :backup_manifest_hash, :string
    field :active_run_ids_json, {:array, :string}, default: []
    field :failure_reason, :string
    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :id,
      :from_version,
      :to_version,
      :schema_change,
      :state,
      :backup_path,
      :backup_manifest_hash,
      :active_run_ids_json,
      :failure_reason
    ])
    |> validate_required([:id, :from_version, :to_version, :schema_change, :state])
    |> validate_inclusion(:state, ~w(preparing prepared installing healthy failed rolled_back))
    |> validate_length(:backup_manifest_hash, is: 64)
  end
end

defmodule Cuckoding.Updates.Event do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "update_events" do
    field :update_attempt_id, :binary_id
    field :event_type, :string
    field :command_key, :string
    field :details_json, :map, default: %{}
    field :occurred_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(event, attrs) do
    event
    |> cast(attrs, [
      :id,
      :update_attempt_id,
      :event_type,
      :command_key,
      :details_json,
      :occurred_at
    ])
    |> validate_required([:id, :update_attempt_id, :event_type, :command_key, :occurred_at])
    |> foreign_key_constraint(:update_attempt_id)
    |> unique_constraint(:command_key)
  end
end
