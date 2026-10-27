defmodule Boss.Deliveries.Step do
  use Ecto.Schema
  @primary_key {:id, :string, autogenerate: false}
  schema "delivery_steps" do
    belongs_to :delivery, Boss.Deliveries.Delivery, type: :string
    field :number, :integer
    field :kind, :string
    field :cycle, :integer
    field :input, :map, default: %{}
    field :receipt, :map, default: %{}
    field :status, :string, default: "running"
    field :project_id, :integer, virtual: true
    timestamps(type: :utc_datetime_usec)
  end
end
