defmodule Boss.Deliveries.ImplementerBinding do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:delivery_id, :string, autogenerate: false}
  @runners ~w(codex claude cursor opencode)

  schema "delivery_implementer_bindings" do
    field :project_id, :integer
    field :task_id, :integer
    field :member_id, :integer
    field :agent_id, :string
    field :model_id, :string
    field :reasoning_effort, :string
    field :binding_tag, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(binding, attrs) do
    binding
    |> cast(attrs, [
      :delivery_id,
      :project_id,
      :task_id,
      :member_id,
      :agent_id,
      :model_id,
      :reasoning_effort,
      :binding_tag
    ])
    |> validate_required([:delivery_id, :project_id, :task_id, :agent_id, :binding_tag])
    |> validate_inclusion(:agent_id, @runners)
    |> validate_length(:model_id, max: 160)
    |> validate_length(:reasoning_effort, max: 32)
    |> validate_length(:binding_tag, max: 180)
  end
end
