defmodule Boss.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    belongs_to :spec, Boss.Projects.Spec
    belongs_to :spec_revision, Boss.Projects.SpecRevision
    field :title, :string
    field :state, :string, default: "new"
    field :state_version, :integer, default: 0
    field :attention_reason, :string
    field :recovery_state, :string
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(spec, revision, attrs) do
    %__MODULE__{spec_id: spec.id, spec_revision_id: revision.id}
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> validate_length(:title, max: 200)
    |> unique_constraint(:spec_id)
    |> foreign_key_constraint(:spec_revision_id)
  end
end
