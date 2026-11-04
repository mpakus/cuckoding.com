defmodule Boss.Projects.Documentation.Conversion do
  use Ecto.Schema
  @primary_key {:id, :string, autogenerate: false}

  schema "project_documentation_conversions" do
    belongs_to :project, Boss.Projects.Project
    field :command_id, :string
    field :source_count, :integer
    field :root_path, :string
    field :git_common_dir, :string
    field :specs_path, :string
    field :base_branch, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
