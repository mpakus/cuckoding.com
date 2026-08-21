defmodule AgentDesk.Roles.Role do
  @moduledoc """
  User-defined agent role and prompt template for one project.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  @profiles ~w(default observer restricted)

  schema "agent_roles" do
    field :name, :string
    field :description, :string, default: ""
    field :prompt, :string, default: ""
    field :permission_profile, :string, default: "default"
    field :skills, :map, default: %{}

    belongs_to :project, Project

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(role, attrs) do
    role
    |> cast(attrs, [
      :id,
      :project_id,
      :name,
      :description,
      :prompt,
      :permission_profile,
      :skills
    ])
    |> update_change(:name, &normalize_name/1)
    |> validate_required([:project_id, :name, :permission_profile])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:description, max: 500)
    |> validate_length(:prompt, max: 8_000)
    |> validate_inclusion(:permission_profile, @profiles)
    |> validate_format(:name, ~r/^[a-z0-9][a-z0-9_-]*$/)
    |> validate_exclusion(:name, ~w(password token secret credential api_key))
    |> unique_constraint([:project_id, :name])
    |> foreign_key_constraint(:project_id)
  end

  defp normalize_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
  end

  defp normalize_name(other), do: other
end
