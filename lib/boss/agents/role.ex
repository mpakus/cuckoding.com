defmodule Boss.Agents.Role do
  use Ecto.Schema
  import Ecto.Changeset

  schema "agent_roles" do
    field :name, :string
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
  end

  defp trim(name) when is_binary(name), do: String.trim(name)
  defp trim(name), do: name
end
