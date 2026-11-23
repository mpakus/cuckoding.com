defmodule Boss.Projects.ImplementerPoolItem do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @runners ~w(codex claude cursor opencode)

  schema "project_implementer_pool" do
    field :project_id, :integer
    field :member_id, :integer
    field :agent_id, :string
    field :model_id, :string
    field :reasoning_effort, :string
    field :binding_tag, :string
    field :position, :integer, default: 0
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :project_id,
      :member_id,
      :agent_id,
      :model_id,
      :reasoning_effort,
      :binding_tag,
      :position
    ])
    |> validate_required([:project_id, :agent_id, :binding_tag])
    |> validate_inclusion(:agent_id, @runners)
    |> validate_length(:model_id, max: 160)
    |> validate_length(:reasoning_effort, max: 32)
    |> validate_length(:binding_tag, max: 180)
  end
end
