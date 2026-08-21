defmodule AgentDesk.Projects.Project do
  @moduledoc """
  A Git repository opened in AgentDesk.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "projects" do
    field :name, :string
    field :root_path, :string
    field :canonical_path, :string
    field :vcs_type, :string, default: "git"
    field :default_branch, :string
    field :settings, :map, default: %{}
    field :last_opened_at, :utc_datetime_usec
    field :open, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :root_path,
      :canonical_path,
      :vcs_type,
      :default_branch,
      :settings,
      :last_opened_at,
      :open
    ])
    |> validate_required([:name, :root_path, :canonical_path, :vcs_type])
    |> validate_inclusion(:vcs_type, ["git"])
    |> unique_constraint(:canonical_path)
  end
end
