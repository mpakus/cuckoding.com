defmodule Boss.Agents.Role do
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_roles" do
    field :name, :string
    field :kind, :string
    has_many :members, Boss.Agents.RoleMember
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name])
    |> update_change(:name, &trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 80)
    |> unique_constraint(:name)
    |> reject_standard()
  end

  def standard_changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :kind])
    |> validate_required([:name, :kind])
    |> validate_inclusion(:kind, ~w(reviewer implementer analytic))
    |> unique_constraint(:kind)
    |> unique_constraint(:name)
  end

  defp reject_standard(changeset) do
    if get_field(changeset, :kind),
      do: add_error(changeset, :name, "is a standard role"),
      else: changeset
  end

  defp trim(name) when is_binary(name), do: String.trim(name)
  defp trim(name), do: name
end
