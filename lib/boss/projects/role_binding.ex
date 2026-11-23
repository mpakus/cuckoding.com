defmodule Boss.Projects.RoleBinding do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(reviewer implementer analytic)
  @runners ~w(codex claude cursor opencode)

  schema "project_role_bindings" do
    field :project_id, :integer
    field :role_kind, :string
    field :member_id, :integer
    field :agent_id, :string
    field :model_id, :string
    field :reasoning_effort, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(binding, attrs) do
    binding
    |> cast(attrs, [
      :project_id,
      :role_kind,
      :member_id,
      :agent_id,
      :model_id,
      :reasoning_effort
    ])
    |> validate_required([:project_id, :role_kind, :agent_id])
    |> validate_inclusion(:role_kind, @roles)
    |> validate_inclusion(:agent_id, @runners)
    |> validate_length(:model_id, max: 160)
    |> validate_length(:reasoning_effort, max: 32)
    |> unique_constraint([:project_id, :role_kind])
  end
end
