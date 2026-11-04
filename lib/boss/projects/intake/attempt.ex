defmodule Boss.Projects.Intake.Attempt do
  use Ecto.Schema
  @primary_key {:id, :string, autogenerate: false}

  schema "project_intake_attempts" do
    belongs_to :request, Boss.Projects.Intake.Request, type: :string
    field :number, :integer
    field :previous_attempt_id, :string
    field :source_base, :string
    field :model_profile, :map
    field :status, :string, default: "running"
    field :receipt, :map, default: %{}
    timestamps(type: :utc_datetime_usec)
  end
end
