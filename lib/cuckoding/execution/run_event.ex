defmodule Cuckoding.Execution.RunEvent do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "run_events" do
    field :run_id, :string
    field :sequence, :integer
    field :event_type, :string
    field :public_summary, :string
    field :payload, :map
    field :occurred_at, :utc_datetime_usec
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:run_id, :sequence, :event_type, :public_summary, :payload, :occurred_at])
    |> validate_required([
      :run_id,
      :sequence,
      :event_type,
      :public_summary,
      :payload,
      :occurred_at
    ])
    |> validate_number(:sequence, greater_than: 0)
    |> unique_constraint([:run_id, :sequence])
  end
end
