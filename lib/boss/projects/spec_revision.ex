defmodule Boss.Projects.SpecRevision do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  alias Boss.Repo

  schema "spec_revisions" do
    belongs_to :spec, Boss.Projects.Spec
    field :number, :integer
    field :relative_path, :string
    field :content_hash, :string
    field :original_text, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def latest(spec_id) do
    Repo.one(
      from r in __MODULE__, where: r.spec_id == ^spec_id, order_by: [desc: r.number], limit: 1
    )
  end

  def file_source(nil), do: nil

  def file_source(revision) do
    if rework_links?() do
      Repo.one(
        from d in "spec_rework_revisions",
          join: source in __MODULE__,
          on: source.id == d.source_revision_id,
          where: d.revision_id == ^revision.id,
          select: source
      ) || revision
    else
      revision
    end
  end

  def file_observations do
    if rework_links?() do
      from r in __MODULE__,
        left_join: d in "spec_rework_revisions",
        on: d.revision_id == r.id,
        where: is_nil(d.revision_id)
    else
      __MODULE__
    end
  end

  # Before this migration, rework wrote back to the working file.
  defp rework_links? do
    Repo.query!(
      "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE name='spec_rework_revisions' AND type='table')"
    ).rows == [[1]]
  end

  def source_changeset(attrs) do
    changeset = cast(%__MODULE__{}, attrs, [:original_text], empty_values: [])
    text = get_field(changeset, :original_text)

    if is_binary(text) and String.valid?(text) and byte_size(text) <= 1_048_576 and
         not String.contains?(text, <<0>>) do
      put_change(
        changeset,
        :content_hash,
        Base.encode16(:crypto.hash(:sha256, text), case: :lower)
      )
    else
      add_error(
        changeset,
        :original_text,
        "must be UTF-8 text of at most 1 MiB without NUL bytes"
      )
    end
  end
end
