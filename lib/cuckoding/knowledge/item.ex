defmodule Cuckoding.Knowledge.Item do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(fact decision pattern recipe observation skill)
  @statuses ~w(candidate project global superseded revoked)
  @sync_states ~w(synced modified missing invalid)

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "knowledge_items" do
    field :scope, :string
    field :project_id, :binary_id
    field :kind, :string
    field :title, :string
    field :file_path, :string
    field :content_hash, :string
    field :observed_hash, :string
    field :sync_state, :string, default: "synced"
    field :revision_source, :string, default: "user"
    field :status, :string
    field :version, :integer
    field :confidence, :float
    field :valid_from, :utc_datetime_usec
    field :invalid_at, :utc_datetime_usec
    field :supersedes_id, :binary_id
    field :triggers_json, {:array, :string}, default: []
    field :evidence_json, :map
    field :produced_by_json, :map
    field :review_json, :map
    field :reviewed_by, :string
    field :reviewed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @metadata_fields [
    :kind,
    :title,
    :content_hash,
    :observed_hash,
    :status,
    :version,
    :confidence,
    :valid_from,
    :invalid_at,
    :supersedes_id,
    :triggers_json,
    :evidence_json,
    :produced_by_json,
    :review_json,
    :reviewed_by,
    :reviewed_at
  ]

  def create_changeset(item, attrs) do
    item
    |> cast(
      attrs,
      [:id, :scope, :project_id, :file_path, :sync_state, :revision_source] ++ @metadata_fields
    )
    |> validate_item()
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:supersedes_id)
    |> unique_constraint([:project_id, :file_path], name: :knowledge_items_project_path_index)
    |> unique_constraint(:file_path, name: :knowledge_items_global_path_index)
  end

  def observation_changeset(item, attrs) do
    item
    |> cast(attrs, [:observed_hash, :sync_state])
    |> validate_inclusion(:sync_state, @sync_states)
    |> validate_hash(:observed_hash)
  end

  def user_revision_changeset(item, attrs) do
    item
    |> cast(attrs, @metadata_fields)
    |> put_change(:sync_state, "synced")
    |> put_change(:revision_source, "user")
    |> validate_item()
    |> foreign_key_constraint(:supersedes_id)
  end

  def system_revision_changeset(item, attrs) do
    item
    |> cast(attrs, @metadata_fields)
    |> put_change(:sync_state, "synced")
    |> put_change(:revision_source, "system")
    |> validate_item()
    |> foreign_key_constraint(:supersedes_id)
  end

  defp validate_item(changeset) do
    changeset
    |> validate_required([
      :id,
      :scope,
      :kind,
      :title,
      :file_path,
      :content_hash,
      :sync_state,
      :revision_source,
      :status,
      :version,
      :confidence,
      :valid_from,
      :triggers_json,
      :evidence_json,
      :produced_by_json
    ])
    |> validate_inclusion(:scope, ~w(project global))
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:sync_state, @sync_states)
    |> validate_inclusion(:revision_source, ~w(system user))
    |> validate_length(:title, min: 1, max: 200)
    |> validate_number(:version, greater_than: 0)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_hash(:content_hash)
    |> validate_hash(:observed_hash)
    |> validate_scope()
    |> validate_validity()
    |> validate_supersession()
  end

  defp validate_hash(changeset, field) do
    validate_format(changeset, field, ~r/^[0-9a-f]{64}$/)
  end

  defp validate_scope(changeset) do
    case {get_field(changeset, :scope), get_field(changeset, :project_id),
          get_field(changeset, :status)} do
      {"project", project_id, status} when is_binary(project_id) and status != "global" ->
        changeset

      {"global", nil, status} when status in ~w(global superseded revoked) ->
        changeset

      _other ->
        add_error(changeset, :scope, "does not match its owner and status")
    end
  end

  defp validate_validity(changeset) do
    case {get_field(changeset, :valid_from), get_field(changeset, :invalid_at)} do
      {%DateTime{}, nil} ->
        changeset

      {%DateTime{} = from, %DateTime{} = until} ->
        if DateTime.compare(until, from) in [:eq, :gt],
          do: changeset,
          else: add_error(changeset, :invalid_at, "must not precede valid_from")

      _other ->
        changeset
    end
  end

  defp validate_supersession(changeset) do
    if get_field(changeset, :id) == get_field(changeset, :supersedes_id),
      do: add_error(changeset, :supersedes_id, "cannot reference itself"),
      else: changeset
  end
end
