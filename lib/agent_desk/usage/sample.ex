defmodule AgentDesk.Usage.Sample do
  @moduledoc """
  One recorded provider usage sample. Token counts are integers, never floats.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.Agents.Session
  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "usage_samples" do
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :total_tokens, :integer, default: 0
    field :cost_cents, :integer
    field :model, :string

    belongs_to :project, Project
    belongs_to :agent_session, Session

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(sample, attrs) do
    sample
    |> cast(attrs, [
      :id,
      :project_id,
      :agent_session_id,
      :input_tokens,
      :output_tokens,
      :total_tokens,
      :cost_cents,
      :model
    ])
    |> validate_required([
      :project_id,
      :agent_session_id,
      :input_tokens,
      :output_tokens,
      :total_tokens
    ])
    |> validate_number(:input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:output_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:total_tokens, greater_than_or_equal_to: 0)
    |> validate_length(:model, max: 120)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:agent_session_id)
  end
end
