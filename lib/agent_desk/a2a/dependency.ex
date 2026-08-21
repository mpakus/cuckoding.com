defmodule AgentDesk.A2A.Dependency do
  @moduledoc """
  Directed wait-edge: `task_id` cannot proceed until `depends_on_id` completes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias AgentDesk.A2A.Task
  alias AgentDesk.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "task_dependencies" do
    belongs_to :project, Project
    belongs_to :task, Task
    belongs_to :depends_on, Task

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [:id, :project_id, :task_id, :depends_on_id])
    |> validate_required([:project_id, :task_id, :depends_on_id])
    |> validate_not_self()
    |> unique_constraint([:task_id, :depends_on_id])
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:depends_on_id)
  end

  defp validate_not_self(changeset) do
    task_id = get_field(changeset, :task_id)
    depends_on_id = get_field(changeset, :depends_on_id)

    if is_binary(task_id) and task_id == depends_on_id do
      add_error(changeset, :depends_on_id, "cannot depend on itself")
    else
      changeset
    end
  end
end
