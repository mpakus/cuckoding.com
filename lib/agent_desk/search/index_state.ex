defmodule AgentDesk.Search.IndexState do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "search_index_states" do
    field :status, :string, default: "idle"
    field :adapter, :string
    field :last_indexed_at, :utc_datetime_usec
    field :error, :string

    belongs_to :project, Project

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:id, :project_id, :status, :adapter, :last_indexed_at, :error])
    |> validate_required([:project_id, :status, :adapter])
    |> validate_inclusion(:status, ~w(idle indexing ready stale unavailable error))
    |> unique_constraint(:project_id)
  end
end
