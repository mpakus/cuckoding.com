defmodule Cuckoding.Knowledge.Publication do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "knowledge_publications" do
    field :candidate_id, :binary_id
    field :project_id, :binary_id
    field :knowledge_item_id, :binary_id
    field :approval_id, :binary_id
    field :previous_publication_id, :binary_id
    field :action, :string
    field :version, :integer
    field :content_hash, :string
    field :content, :string
    field :actor, :string
    field :reason, :string
    field :recorded_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(publication, attrs) do
    publication
    |> cast(attrs, [
      :id,
      :candidate_id,
      :project_id,
      :knowledge_item_id,
      :approval_id,
      :previous_publication_id,
      :action,
      :version,
      :content_hash,
      :content,
      :actor,
      :reason,
      :recorded_at
    ])
    |> validate_required([
      :id,
      :candidate_id,
      :project_id,
      :knowledge_item_id,
      :approval_id,
      :action,
      :version,
      :content_hash,
      :content,
      :actor,
      :reason,
      :recorded_at
    ])
    |> validate_inclusion(:action, ~w(publish revoke rollback))
    |> validate_number(:version, greater_than: 0)
    |> validate_length(:actor, min: 1, max: 100)
    |> validate_length(:reason, min: 1, max: 1_000)
    |> validate_length(:content, max: 1_048_576)
    |> validate_format(:content_hash, ~r/^[0-9a-f]{64}$/)
    |> foreign_key_constraint(:candidate_id)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:knowledge_item_id)
    |> foreign_key_constraint(:approval_id)
    |> foreign_key_constraint(:previous_publication_id)
    |> unique_constraint(:approval_id)
    |> unique_constraint([:knowledge_item_id, :version])
    |> unique_constraint(:candidate_id,
      name: :knowledge_publications_one_publish_per_candidate_index
    )
  end
end

defmodule Cuckoding.Knowledge.SkillPackage do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "skill_packages" do
    field :knowledge_item_id, :binary_id
    field :publication_id, :binary_id
    field :name, :string
    field :version, :string
    field :file_path, :string
    field :manifest_json, :map
    field :content_hash, :string
    field :published_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(package, attrs) do
    package
    |> cast(attrs, [
      :id,
      :knowledge_item_id,
      :publication_id,
      :name,
      :version,
      :file_path,
      :manifest_json,
      :content_hash,
      :published_at
    ])
    |> validate_required([
      :id,
      :knowledge_item_id,
      :publication_id,
      :name,
      :version,
      :file_path,
      :manifest_json,
      :content_hash,
      :published_at
    ])
    |> validate_format(:name, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    |> validate_length(:name, max: 64)
    |> validate_format(:version, ~r/^\d+\.\d+\.\d+$/)
    |> validate_format(:content_hash, ~r/^[0-9a-f]{64}$/)
    |> foreign_key_constraint(:knowledge_item_id)
    |> foreign_key_constraint(:publication_id)
    |> unique_constraint([:name, :version])
    |> unique_constraint(:publication_id)
  end
end
