defmodule Cuckoding.Knowledge.RetrievalToken do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "knowledge_retrieval_tokens" do
    field :run_id, :binary_id
    field :stage_attempt_id, :binary_id
    field :project_id, :binary_id
    field :token_hash, :string
    field :expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [:id, :run_id, :stage_attempt_id, :project_id, :token_hash, :expires_at])
    |> validate_required([:id, :run_id, :stage_attempt_id, :project_id, :token_hash, :expires_at])
    |> validate_format(:token_hash, ~r/^[0-9a-f]{64}$/)
    |> foreign_key_constraint(:run_id)
    |> foreign_key_constraint(:stage_attempt_id)
    |> foreign_key_constraint(:project_id)
    |> unique_constraint(:token_hash)
  end
end

defmodule Cuckoding.Knowledge.Retrieval do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "knowledge_retrievals" do
    field :run_id, :binary_id
    field :stage_attempt_id, :binary_id
    field :backend_key, :string
    field :namespace, :string
    field :query_hash, :string
    field :hit_count, :integer
    field :context_bytes, :integer
    field :selected_ids_json, :map
    field :occurred_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(retrieval, attrs) do
    retrieval
    |> cast(attrs, [
      :id,
      :run_id,
      :stage_attempt_id,
      :backend_key,
      :namespace,
      :query_hash,
      :hit_count,
      :context_bytes,
      :selected_ids_json,
      :occurred_at
    ])
    |> validate_required([
      :id,
      :run_id,
      :stage_attempt_id,
      :backend_key,
      :namespace,
      :query_hash,
      :hit_count,
      :context_bytes,
      :selected_ids_json,
      :occurred_at
    ])
    |> validate_format(:query_hash, ~r/^[0-9a-f]{64}$/)
    |> validate_number(:hit_count, greater_than_or_equal_to: 0)
    |> validate_number(:context_bytes, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:run_id)
    |> foreign_key_constraint(:stage_attempt_id)
  end
end

defmodule Cuckoding.Knowledge.Usage do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(injected retrieved cited accepted contradicted)
  @primary_key {:id, :binary_id, autogenerate: false}
  schema "knowledge_usages" do
    field :knowledge_item_id, :binary_id
    field :item_version, :integer
    field :run_id, :binary_id
    field :stage_attempt_id, :binary_id
    field :kind, :string
    field :event_key_hash, :string
    field :evidence_json, :map
    field :occurred_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def create_changeset(usage, attrs) do
    usage
    |> cast(attrs, [
      :id,
      :knowledge_item_id,
      :item_version,
      :run_id,
      :stage_attempt_id,
      :kind,
      :event_key_hash,
      :evidence_json,
      :occurred_at
    ])
    |> validate_required([
      :id,
      :knowledge_item_id,
      :item_version,
      :run_id,
      :stage_attempt_id,
      :kind,
      :event_key_hash,
      :evidence_json,
      :occurred_at
    ])
    |> validate_inclusion(:kind, @kinds)
    |> validate_number(:item_version, greater_than: 0)
    |> validate_format(:event_key_hash, ~r/^[0-9a-f]{64}$/)
    |> foreign_key_constraint(:knowledge_item_id)
    |> foreign_key_constraint(:run_id)
    |> foreign_key_constraint(:stage_attempt_id)
    |> unique_constraint(:event_key_hash)
  end
end
