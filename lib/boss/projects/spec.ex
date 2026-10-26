defmodule Boss.Projects.Spec do
  use Ecto.Schema
  import Ecto.Changeset

  schema "specs" do
    belongs_to :project, Boss.Projects.Project
    field :identity_key, :string
    field :relative_path, :string
    field :missing, :boolean, default: false
    field :explicit_id, :string, virtual: true
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(project_id, attrs) do
    changeset =
      %__MODULE__{}
      |> cast(%{project_id: project_id}, [:project_id])
      |> cast(attrs, [:relative_path, :explicit_id], empty_values: [])
      |> validate_required([:project_id, :relative_path])
      |> validate_change(:relative_path, fn field, path ->
        if valid_path?(path),
          do: [],
          else: [{field, "must be a normalized relative Markdown path"}]
      end)
      |> validate_change(:explicit_id, fn field, id ->
        if String.valid?(id) and byte_size(id) in 1..200 and String.trim(id) == id and
             not String.contains?(id, [<<0>>, "\n", "\r"]),
           do: [],
           else: [{field, "must be a nonempty ID of at most 200 bytes"}]
      end)
      |> foreign_key_constraint(:project_id)
      |> unique_constraint(:identity_key, name: :specs_project_id_identity_key_index)
      |> unique_constraint(:relative_path, name: :specs_project_id_relative_path_index)

    if changeset.valid? do
      key =
        case get_field(changeset, :explicit_id) do
          nil -> "path:" <> get_field(changeset, :relative_path)
          id -> "id:" <> id
        end

      put_change(changeset, :identity_key, key)
    else
      changeset
    end
  end

  defp valid_path?(path) do
    String.valid?(path) and byte_size(path) <= 4096 and Path.type(path) == :relative and
      not String.contains?(path, [<<0>>, "\n", "\r", "\\"]) and
      Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", ".."])) and
      String.downcase(Path.extname(path)) == ".md"
  end
end
