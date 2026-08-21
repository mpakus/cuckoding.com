defmodule AgentDesk.A2A.Workflow do
  @moduledoc """
  Named reusable task graph for a project.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "workflow_templates" do
    field :name, :string
    field :description, :string, default: ""
    field :definition, :map, default: %{}

    belongs_to :project, Project

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:id, :project_id, :name, :description, :definition])
    |> validate_required([:project_id, :name, :definition])
    |> validate_length(:name, max: 120)
    |> validate_length(:description, max: 2000)
    |> validate_steps()
    |> foreign_key_constraint(:project_id)
  end

  defp validate_steps(changeset) do
    validate_change(changeset, :definition, fn :definition, definition ->
      steps = List.wrap(definition["steps"] || definition[:steps])

      cond do
        steps == [] ->
          [definition: "must include at least one step"]

        length(steps) > 20 ->
          [definition: "is limited to 20 steps"]

        true ->
          []
      end
    end)
  end
end
