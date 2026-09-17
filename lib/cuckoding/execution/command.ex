defmodule Cuckoding.Execution.Command do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @states ~w(pending running succeeded failed)
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "commands" do
    field :idempotency_key, :string
    field :kind, :string
    field :target_type, :string
    field :target_id, :string
    field :payload, :map
    field :state, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :max_attempts, :integer, default: 3
    field :not_before, :utc_datetime_usec
    field :last_error, :string
    field :result, :map
    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def create_changeset(command, attrs) do
    command
    |> cast(attrs, [
      :idempotency_key,
      :kind,
      :target_type,
      :target_id,
      :payload,
      :state,
      :attempts,
      :max_attempts,
      :not_before,
      :last_error,
      :result
    ])
    |> validate_required([
      :idempotency_key,
      :kind,
      :target_type,
      :target_id,
      :payload,
      :state,
      :attempts,
      :max_attempts,
      :not_before
    ])
    |> validate_inclusion(:state, @states)
    |> validate_number(:attempts, greater_than_or_equal_to: 0)
    |> validate_number(:max_attempts, greater_than: 0)
    |> unique_constraint(:idempotency_key)
  end

  def state_changeset(command, attrs) do
    command
    |> cast(attrs, [:state, :attempts, :not_before, :last_error, :result])
    |> validate_required([:state, :attempts, :max_attempts, :not_before])
    |> validate_inclusion(:state, @states)
    |> validate_number(:attempts,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: command.max_attempts
    )
  end
end
