defmodule Boss.Projects.SpecRevision do
  use Ecto.Schema
  import Ecto.Changeset

  schema "spec_revisions" do
    belongs_to :spec, Boss.Projects.Spec
    field :number, :integer
    field :relative_path, :string
    field :content_hash, :string
    field :original_text, :string
    timestamps(type: :utc_datetime_usec, updated_at: false)
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
