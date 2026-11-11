defmodule Boss.Agents.RoleMember do
  use Ecto.Schema
  import Ecto.Changeset
  alias Boss.Agents.Metadata

  schema "agent_role_members" do
    belongs_to :role, Boss.Agents.Role
    field :agent_id, :string
    field :model_id, :string
    field :reasoning_effort, :string
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:role_id, :agent_id, :model_id, :reasoning_effort])
    |> validate_required([:role_id, :agent_id])
    |> validate_inclusion(:agent_id, Enum.map(Metadata.ids(), &Atom.to_string/1))
    |> validate_length(:model_id, max: 160)
    |> validate_inclusion(:reasoning_effort, ~w(none low medium high xhigh max ultra))
    |> unique_constraint([:role_id, :agent_id])
  end
end
