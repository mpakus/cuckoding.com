defmodule AgentDesk.Search.Document do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "search_documents" do
    field :source, :string
    field :source_id, :string
    field :title, :string
    field :passage, :string
    field :path, :string
    field :content_hash, :string

    belongs_to :project, Project

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(doc, attrs) do
    doc
    |> cast(attrs, [
      :id,
      :project_id,
      :source,
      :source_id,
      :title,
      :passage,
      :path,
      :content_hash
    ])
    |> validate_required([:project_id, :source, :source_id, :title, :passage, :content_hash])
    |> unique_constraint([:project_id, :source, :source_id])
  end
end
