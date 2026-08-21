defmodule AgentDesk.Search.Memory do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "search_memories" do
    field :namespace, :string
    field :text, :string
    field :metadata, :map, default: %{}

    belongs_to :project, Project

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [:id, :project_id, :namespace, :text, :metadata])
    |> validate_required([:project_id, :namespace, :text])
    |> validate_length(:text, max: 8_000)
    |> validate_length(:namespace, max: 200)
  end
end
